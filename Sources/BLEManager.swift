import Foundation
import CoreBluetooth

struct DiscoveredBand: Identifiable, Hashable {
    let id: UUID
    let name: String
    var rssi: Int
}

/// Bluetooth-шар: пошук, підключення, виявлення сервісів і характеристик.
/// Протокол Xiaomi (авторизація, шифрування, завантаження файлу) живе в XiaomiProtocol.swift.
final class BLEManager: NSObject, ObservableObject {
    @Published var state: CBManagerState = .unknown
    @Published var devices: [DiscoveredBand] = []
    @Published var isScanning = false
    @Published var connectedID: UUID?
    @Published var connectedName: String?
    @Published var log: [String] = []

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var active: CBPeripheral?
    private(set) var characteristics: [CBUUID: CBCharacteristic] = [:]

    /// Колбек для вхідних даних із характеристик (використовує протокольний шар).
    var onData: ((CBUUID, Data) -> Void)?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func addLog(_ text: String) {
        log.append(text)
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }

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

    @discardableResult
    func write(_ data: Data, to uuid: CBUUID, withResponse: Bool = false) -> Bool {
        guard let p = active, let c = characteristics[uuid] else { return false }
        p.writeValue(data, for: c, type: withResponse ? .withResponse : .withoutResponse)
        return true
    }

    func maxWriteLength() -> Int {
        active?.maximumWriteValueLength(for: .withoutResponse) ?? 20
    }

    func subscribe(to uuid: CBUUID) {
        guard let p = active, let c = characteristics[uuid] else { return }
        p.setNotifyValue(true, for: c)
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
        characteristics.removeAll()
        addLog("Підключено. Пошук сервісів…")
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        addLog("Помилка підключення: \(error?.localizedDescription ?? "невідомо")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        addLog("Відключено")
        connectedID = nil
        connectedName = nil
        active = nil
        characteristics.removeAll()
    }
}

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for s in peripheral.services ?? [] {
            addLog("Сервіс \(s.uuid.uuidString)")
            peripheral.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            characteristics[c.uuid] = c
            addLog("  • \(c.uuid.uuidString) [\(describe(c.properties))]")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let d = characteristic.value { onData?(characteristic.uuid, d) }
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
