import Foundation
import CoreBluetooth
import BandFaceKit

struct FoundBand: Identifiable, Hashable {
    let id: UUID
    let name: String
    var rssi: Int
}

/// Bluetooth-шар: пошук, підключення, виявлення сервісів, черга запису з керуванням потоком.
/// Протокол браслета — у бібліотеці BandFaceKit; цей клас для неї транспорт (BandTransport).
final class BLEManager: NSObject, ObservableObject {
    @Published var state: CBManagerState = .unknown
    @Published var devices: [FoundBand] = []
    @Published var isScanning = false
    @Published var connectedID: UUID?
    @Published var connectedName: String?
    @Published var servicesReady = false
    /// Іде підключення до запам'ятованого браслета
    @Published var isConnecting = false
    @Published var connectingName: String?
    @Published var log: [String] = []

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var active: CBPeripheral?
    private(set) var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var pendingServiceDiscovery = 0
    private let lastDeviceKey = "lastDeviceID"
    /// Користувач сам натиснув «Відключити» — до наступного запуску автоматично не підключаємося
    private var userDisconnected = false

    /// Вхідні дані зі сповіщень (викликається на головному потоці).
    var onData: ((CBUUID, Data) -> Void)?
    /// Викликається при розриві з'єднання.
    var onDisconnect: (() -> Void)?

    // MARK: - Черга запису

    private struct PendingWrite {
        let characteristic: CBCharacteristic
        let data: Data
        var offset = 0
        /// true — дані передано стеку Bluetooth, false — з'єднання розірвалося раніше.
        let completion: ((Bool) -> Void)?
    }

    private var writeQueue: [PendingWrite] = []
    private var awaitingResponse = false
    private var responseCompletion: ((Bool) -> Void)?
    private var notifyCompletions: [CBUUID: (Bool) -> Void] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func addLog(_ text: String) {
        log.append(text)
        if log.count > 3000 { log.removeFirst(log.count - 3000) }
    }

    /// Технічний запис — лише коли увімкнено «Детальний журнал».
    /// Текст обчислюється тільки тоді, коли він справді потрібен.
    func debug(_ text: @autoclosure () -> String) {
        if UserDefaults.standard.bool(forKey: "verboseLog") { addTimedLog(text()) }
    }

    /// Запис із часом (мілісекунди) — для детального журналу й режиму спостереження.
    func addTimedLog(_ text: String) {
        addLog(Self.timeFormatter.string(from: Date()) + " " + text)
    }

    /// Час у детальному журналі — щоб бачити, скільки триває кожен етап.
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    // MARK: - Пошук і підключення

    func startScan() {
        guard central.state == .poweredOn else {
            addLog(String(localized: "Bluetooth вимкнено або недоступний"))
            return
        }
        devices.removeAll()
        peripherals.removeAll()
        // Пристрої, вже підключені до iPhone іншим застосунком (напр. Mi Fitness), не рекламуються
        for p in central.retrieveConnectedPeripherals(withServices: [BandGATT.service]) {
            peripherals[p.identifier] = p
            devices.append(FoundBand(id: p.identifier, name: (p.name ?? "?") + " " + String(localized: "(вже підключений до iPhone)"), rssi: 0))
            debug("Уже підключений до системи: \(p.name ?? "?")")
        }
        isScanning = true
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        addLog(String(localized: "Пошук пристроїв…"))
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    func connect(_ id: UUID) {
        guard let p = peripherals[id] else { return }
        userDisconnected = false
        start(p)
    }

    private func start(_ p: CBPeripheral) {
        stopScan()
        active = p
        p.delegate = self
        isConnecting = true
        connectingName = p.name
        addLog(String(localized: "Підключення до \(p.name ?? String(localized: "браслета"))…"))
        central.connect(p, options: nil)
    }

    /// `byUser`: користувач натиснув «Відключити» або «Скасувати».
    /// Відключення при згортанні застосунку — не від користувача, тож потім підключимося знову.
    func disconnect(byUser: Bool = true) {
        if byUser { userDisconnected = true }
        guard let p = active else { return }
        central.cancelPeripheralConnection(p)
        if connectedID == nil {
            // Підключення ще не відбулося — просто скасовуємо очікування
            active = nil
            isConnecting = false
            connectingName = nil
        }
    }

    /// Автоматичне підключення до браслета, з яким працювали минулого разу.
    func reconnectLast() {
        guard central.state == .poweredOn, active == nil, !userDisconnected,
              let raw = UserDefaults.standard.string(forKey: lastDeviceKey),
              let id = UUID(uuidString: raw),
              let p = central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        peripherals[id] = p
        start(p)
    }

    // MARK: - Сповіщення

    func subscribe(to uuid: CBUUID, completion: @escaping (Bool) -> Void) {
        guard let p = active, let c = characteristics[uuid] else {
            completion(false)
            return
        }
        if c.isNotifying {
            completion(true)
            return
        }
        notifyCompletions[uuid] = completion
        p.setNotifyValue(true, for: c)
    }

    func unsubscribe(from uuid: CBUUID) {
        guard let p = active, let c = characteristics[uuid], c.isNotifying else { return }
        p.setNotifyValue(false, for: c)
    }

    // MARK: - Запис

    /// Ставить дані в чергу. Дані розбиваються на фрагменти за MTU.
    /// `completion` викликається, коли всі фрагменти передано стеку Bluetooth.
    @discardableResult
    func enqueue(_ data: Data, to uuid: CBUUID, completion: ((Bool) -> Void)? = nil) -> Bool {
        guard active != nil, let c = characteristics[uuid], !data.isEmpty else { return false }
        writeQueue.append(PendingWrite(characteristic: c, data: data, completion: completion))
        pump()
        return true
    }

    private func pump() {
        guard let p = active else { return }
        while let item = writeQueue.first {
            let c = item.characteristic
            let noResponse = c.properties.contains(.writeWithoutResponse)

            if noResponse {
                guard p.canSendWriteWithoutResponse else { return }
            } else if awaitingResponse {
                return
            }

            let maxLen = max(20, p.maximumWriteValueLength(for: noResponse ? .withoutResponse : .withResponse))
            let end = min(item.offset + maxLen, item.data.count)
            let chunk = item.data.subdata(in: item.offset..<end)
            p.writeValue(chunk, for: c, type: noResponse ? .withoutResponse : .withResponse)
            writeQueue[0].offset = end

            let finished = end >= item.data.count
            if finished {
                writeQueue.removeFirst()
                if noResponse {
                    if let cb = item.completion { DispatchQueue.main.async { cb(true) } }
                } else {
                    responseCompletion = item.completion
                }
            }
            if !noResponse {
                awaitingResponse = true
                return
            }
        }
    }

    private func resetTransfer() {
        // Ті, хто чекає на запис, дізнаються, що він не відбувся
        let pending = writeQueue.compactMap(\.completion) + [responseCompletion].compactMap { $0 }
        let subscriptions = Array(notifyCompletions.values)
        writeQueue.removeAll()
        awaitingResponse = false
        responseCompletion = nil
        notifyCompletions.removeAll()
        pending.forEach { $0(false) }
        subscriptions.forEach { $0(false) }
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        if central.state == .poweredOn { reconnectLast() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        guard let name, !name.isEmpty else { return }
        // Показуємо лише пристрої Xiaomi (сервіс FE95 або відома назва), без навушників тощо
        let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:]
        let lower = name.lowercased()
        guard uuids.contains(BandGATT.service) || serviceData[BandGATT.service] != nil
                || lower.contains("xiaomi") || lower.contains("band") || lower.contains("redmi") else { return }
        peripherals[peripheral.identifier] = peripheral
        let item = FoundBand(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        if let i = devices.firstIndex(where: { $0.id == item.id }) {
            devices[i] = item
        } else {
            devices.append(item)
        }
        devices.sort { $0.rssi > $1.rssi }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedID = peripheral.identifier
        connectedName = peripheral.name
        isConnecting = false
        connectingName = nil
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: lastDeviceKey)
        servicesReady = false
        characteristics.removeAll()
        resetTransfer()
        addLog(String(localized: "Підключено"))
        debug("Макс. запис без відповіді: \(peripheral.maximumWriteValueLength(for: .withoutResponse)) байт")
        // Шукаємо лише сервіс Xiaomi — так підключення швидше
        peripheral.discoverServices([BandGATT.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        addLog(String(localized: "Помилка підключення: \(error?.localizedDescription ?? String(localized: "невідомо"))"))
        active = nil
        isConnecting = false
        connectingName = nil
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        addLog(String(localized: "Відключено") + (error.map { ": \($0.localizedDescription)" } ?? ""))
        connectedID = nil
        connectedName = nil
        servicesReady = false
        isConnecting = false
        connectingName = nil
        active = nil
        characteristics.removeAll()
        resetTransfer()
        onDisconnect?()
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let services = peripheral.services ?? []
        pendingServiceDiscovery = services.count
        if services.isEmpty { servicesReady = true }
        for s in services {
            debug("Сервіс \(s.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            characteristics[c.uuid] = c
            debug("  • \(c.uuid.uuidString) [\(describe(c.properties))]")
        }
        pendingServiceDiscovery -= 1
        if pendingServiceDiscovery <= 0 {
            servicesReady = true
            debug("Виявлення сервісів завершено")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let cb = notifyCompletions.removeValue(forKey: characteristic.uuid) {
            cb(error == nil)
        }
        if let error { debug("Підписка \(characteristic.uuid.uuidString): \(error.localizedDescription)") }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { addLog(String(localized: "Сповіщення \(characteristic.uuid.uuidString): \(error.localizedDescription)")) }
        if let d = characteristic.value { onData?(characteristic.uuid, d) }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { addLog(String(localized: "Помилка запису: \(error.localizedDescription)")) }
        awaitingResponse = false
        if let cb = responseCompletion {
            responseCompletion = nil
            DispatchQueue.main.async { cb(error == nil) }
        }
        pump()
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        pump()
    }

    private func describe(_ p: CBCharacteristicProperties) -> String {
        var r: [String] = []
        if p.contains(.read) { r.append("read") }
        if p.contains(.write) { r.append("write") }
        if p.contains(.writeWithoutResponse) { r.append("writeNR") }
        if p.contains(.notify) { r.append("notify") }
        if p.contains(.indicate) { r.append("indicate") }
        return r.joined(separator: ",")
    }
}

// MARK: - Транспорт для BandFaceKit

extension BLEManager: BandTransport, @unchecked Sendable {
    /// Надсилає цілий кадр у TX (0x5F) і чекає, поки всі його шматки прийме стек Bluetooth.
    /// Увесь стан класу живе на головному потоці.
    func write(_ frame: [UInt8]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                let queued = self.enqueue(Data(frame), to: BandGATT.tx) { sent in
                    if sent { continuation.resume() } else { continuation.resume(throwing: BandError.disconnected) }
                }
                if !queued { continuation.resume(throwing: BandError.notConnected) }
            }
        }
    }

    /// Вмикає або вимикає сповіщення характеристики й чекає підтвердження. true — успішно.
    @MainActor
    func setNotify(_ on: Bool, for uuid: CBUUID) async -> Bool {
        guard let p = active, let c = characteristics[uuid], c.properties.contains(.notify) else { return false }
        if c.isNotifying == on { return true }
        return await withCheckedContinuation { continuation in
            notifyCompletions.removeValue(forKey: uuid)?(false)
            notifyCompletions[uuid] = { continuation.resume(returning: $0) }
            debug("Сповіщення \(uuid.uuidString): \(on ? "увімкнути" : "вимкнути")")
            p.setNotifyValue(on, for: c)
        }
    }

    /// Підписка на сповіщення 5E і 5F (як Mi Fitness) — один раз на з'єднання.
    /// Не відписуємося між сесіями: якщо Mi Fitness теж підписаний (iOS будить його у фоні),
    /// відписка повертає помилку, і після неї iOS перестає доставляти нам сповіщення.
    /// Підписку iOS прибирає сама, коли застосунок відключається від браслета.
    @MainActor
    func subscribeBand() async -> Bool {
        let rx = await setNotify(true, for: BandGATT.rx)
        _ = await setNotify(true, for: BandGATT.tx)
        return rx
    }

    /// Розриває з'єднання застосунку з браслетом і встановлює його знову (до ~15 с).
    /// Mi Fitness від цього не страждає: iOS тримає фізичне з'єднання, поки воно потрібне іншим застосункам.
    @MainActor
    func reconnect() async -> Bool {
        guard connectedID != nil else { return false }
        disconnect(byUser: false)
        for _ in 0..<50 {
            if connectedID == nil { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        reconnectLast()
        for _ in 0..<150 {
            if connectedID != nil && servicesReady { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    var hasBandCharacteristics: Bool {
        characteristics[BandGATT.rx] != nil && characteristics[BandGATT.tx] != nil
    }
}
