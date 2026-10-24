import Foundation
import CoreBluetooth

struct DiscoveredBand: Identifiable, Hashable {
    let id: UUID
    let name: String
    var rssi: Int
}

/// Bluetooth-шар: пошук, підключення, виявлення сервісів, черга запису з керуванням потоком.
/// Протокол Xiaomi живе в XiaomiProtocol.swift.
final class BLEManager: NSObject, ObservableObject {
    @Published var state: CBManagerState = .unknown
    @Published var devices: [DiscoveredBand] = []
    @Published var isScanning = false
    @Published var connectedID: UUID?
    @Published var connectedName: String?
    @Published var servicesReady = false
    @Published var log: [String] = []

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var active: CBPeripheral?
    private(set) var characteristics: [CBUUID: CBCharacteristic] = [:]
    private var pendingServiceDiscovery = 0

    /// Вхідні дані зі сповіщень (викликається на головному потоці).
    var onData: ((CBUUID, Data) -> Void)?
    /// Викликається при розриві з'єднання.
    var onDisconnect: (() -> Void)?

    // MARK: - Черга запису

    private struct PendingWrite {
        let characteristic: CBCharacteristic
        let data: Data
        var offset = 0
        let completion: (() -> Void)?
    }

    private var writeQueue: [PendingWrite] = []
    private var awaitingResponse = false
    private var responseCompletion: (() -> Void)?
    private var notifyCompletions: [CBUUID: (Bool) -> Void] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func addLog(_ text: String) {
        log.append(text)
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }

    // MARK: - Пошук і підключення

    func startScan() {
        guard central.state == .poweredOn else {
            addLog("Bluetooth вимкнено або недоступний")
            return
        }
        devices.removeAll()
        peripherals.removeAll()
        isScanning = true
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        addLog("Пошук пристроїв…")
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
    }

    func connect(_ id: UUID) {
        guard let p = peripherals[id] else { return }
        stopScan()
        active = p
        p.delegate = self
        addLog("Підключення до \(p.name ?? "?")…")
        central.connect(p, options: nil)
    }

    func disconnect() {
        if let p = active { central.cancelPeripheralConnection(p) }
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

    // MARK: - Запис

    /// Ставить дані в чергу. Дані розбиваються на фрагменти за MTU.
    /// `completion` викликається, коли всі фрагменти передано стеку Bluetooth.
    @discardableResult
    func enqueue(_ data: Data, to uuid: CBUUID, completion: (() -> Void)? = nil) -> Bool {
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
                    if let cb = item.completion { DispatchQueue.main.async { cb() } }
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
        writeQueue.removeAll()
        awaitingResponse = false
        responseCompletion = nil
        notifyCompletions.removeAll()
    }
}

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name
            ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
        guard let name, !name.isEmpty else { return }
        peripherals[peripheral.identifier] = peripheral
        let item = DiscoveredBand(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
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
        servicesReady = false
        characteristics.removeAll()
        resetTransfer()
        addLog("Підключено. Пошук сервісів…")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        addLog("Помилка підключення: \(error?.localizedDescription ?? "невідомо")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        addLog("Відключено\(error.map { ": \($0.localizedDescription)" } ?? "")")
        connectedID = nil
        connectedName = nil
        servicesReady = false
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
            addLog("Сервіс \(s.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            characteristics[c.uuid] = c
            addLog("  • \(c.uuid.uuidString) [\(describe(c.properties))]")
        }
        pendingServiceDiscovery -= 1
        if pendingServiceDiscovery <= 0 {
            servicesReady = true
            addLog("Виявлення сервісів завершено")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let cb = notifyCompletions.removeValue(forKey: characteristic.uuid) {
            cb(error == nil && characteristic.isNotifying)
        }
        if let error { addLog("Підписка \(characteristic.uuid.uuidString): \(error.localizedDescription)") }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let d = characteristic.value { onData?(characteristic.uuid, d) }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { addLog("Помилка запису: \(error.localizedDescription)") }
        awaitingResponse = false
        if let cb = responseCompletion {
            responseCompletion = nil
            DispatchQueue.main.async { cb() }
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
