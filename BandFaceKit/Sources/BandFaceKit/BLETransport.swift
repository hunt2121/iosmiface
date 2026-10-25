// SPDX-License-Identifier: MIT
//
// Транспорт CoreBluetooth: сервіс FE95, запис у 0x005F без відповіді, сповіщення з 0x005E.
// Пару (bonding) не створюємо — захист дає шифрування протоколу.

#if canImport(CoreBluetooth)
import CoreBluetooth
import Foundation

public enum BandGATT {
    public static let service = CBUUID(string: "FE95")
    /// Браслет → телефон (підписка на сповіщення).
    public static let rx = CBUUID(string: "0000005E-0000-1000-8000-00805F9B34FB")
    /// Телефон → браслет (запис без відповіді).
    public static let tx = CBUUID(string: "0000005F-0000-1000-8000-00805F9B34FB")
    public static let namePrefix = "Xiaomi Smart Band 10"
}

public struct DiscoveredBand: Sendable, Hashable {
    public let identifier: UUID
    public let name: String
    /// true — знайдено серед уже підключених до системи (наприклад, через Mi Fitness).
    public let alreadyConnected: Bool
}

/// Одне з'єднання з браслетом. Усі виклики CoreBluetooth ідуть на власній послідовній черзі.
public final class BLEBandTransport: NSObject, BandTransport, @unchecked Sendable {
    private let queue = DispatchQueue(label: "BandFaceKit.ble")
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?

    private var poweredOnWaiters: [CheckedContinuation<Void, Error>] = []
    private var connectWaiter: CheckedContinuation<Void, Error>?
    private var writeWaiters: [CheckedContinuation<Void, Error>] = []
    private var scanHandler: ((DiscoveredBand) -> Void)?
    private var discovered: [UUID: CBPeripheral] = [:]

    /// Сюди надходять сповіщення з RX. Зазвичай — `session.receive`.
    public var onReceive: (@Sendable (Data) -> Void)?
    /// Викликається, коли з'єднання розірвалося.
    public var onDisconnect: (@Sendable (Error?) -> Void)?

    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    // MARK: - Пошук

    private func waitPoweredOn() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                switch self.central.state {
                case .poweredOn: continuation.resume()
                case .unsupported, .unauthorized, .poweredOff: continuation.resume(throwing: BandError.bluetoothUnavailable)
                default: self.poweredOnWaiters.append(continuation)
                }
            }
        }
    }

    /// Шукає браслети протягом `duration`. Спершу — серед підключених до системи за сервісом FE95
    /// (на iOS браслет, підключений через Mi Fitness, не рекламується), потім — скануванням.
    public func discover(for duration: Duration = .seconds(5)) async throws -> [DiscoveredBand] {
        try await waitPoweredOn()
        let collected = Collected()
        queue.sync {
            for p in self.central.retrieveConnectedPeripherals(withServices: [BandGATT.service]) {
                self.discovered[p.identifier] = p
                collected.add(DiscoveredBand(identifier: p.identifier, name: p.name ?? "Xiaomi band", alreadyConnected: true))
            }
            self.scanHandler = { collected.add($0) }
            self.central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
        try? await Task.sleep(for: duration)
        queue.sync {
            self.central.stopScan()
            self.scanHandler = nil
        }
        return collected.values
    }

    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [UUID: DiscoveredBand] = [:]
        private var order: [UUID] = []
        func add(_ band: DiscoveredBand) {
            lock.lock(); defer { lock.unlock() }
            if items[band.identifier] == nil { order.append(band.identifier) }
            if items[band.identifier]?.alreadyConnected != true { items[band.identifier] = band }
        }
        var values: [DiscoveredBand] {
            lock.lock(); defer { lock.unlock() }
            return order.compactMap { items[$0] }
        }
    }

    // MARK: - Підключення

    /// Підключається, знаходить характеристики і підписується на RX.
    public func connect(to identifier: UUID, timeout: Duration = .seconds(15)) async throws {
        try await waitPoweredOn()
        let peripheral: CBPeripheral = try queue.sync {
            if let p = discovered[identifier] { return p }
            if let p = central.retrievePeripherals(withIdentifiers: [identifier]).first { return p }
            throw BandError.notConnected
        }

        let timeoutTask = Task { [weak self] in
            try await Task.sleep(for: timeout)
            self?.finishConnect(.failure(BandError.timeout))
        }
        defer { timeoutTask.cancel() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.connectWaiter = continuation
                self.peripheral = peripheral
                peripheral.delegate = self
                self.central.connect(peripheral)
            }
        }
    }

    /// Відписується від RX і розриває з'єднання (щоб Mi Fitness знову міг підключитися).
    public func disconnect() {
        queue.async {
            guard let p = self.peripheral else { return }
            if let rx = self.rxCharacteristic, p.state == .connected {
                p.setNotifyValue(false, for: rx)
            }
            self.central.cancelPeripheralConnection(p)
        }
    }

    private func finishConnect(_ result: Result<Void, Error>) {
        queue.async {
            guard let waiter = self.connectWaiter else { return }
            self.connectWaiter = nil
            if case .failure = result, let p = self.peripheral {
                self.central.cancelPeripheralConnection(p)
            }
            waiter.resume(with: result)
        }
    }

    // MARK: - Запис

    public func write(_ frame: [UInt8]) async throws {
        let data = Data(frame)
        var offset = 0
        while offset < data.count {
            try await waitUntilCanWrite()
            let sent: Int = try queue.sync {
                guard let p = peripheral, p.state == .connected, let tx = txCharacteristic else {
                    throw BandError.notConnected
                }
                guard p.canSendWriteWithoutResponse else { return 0 }
                let maxLength = max(p.maximumWriteValueLength(for: .withoutResponse), 20)
                let end = min(offset + maxLength, data.count)
                p.writeValue(data.subdata(in: offset..<end), for: tx, type: .withoutResponse)
                return end - offset
            }
            offset += sent
        }
    }

    private func waitUntilCanWrite() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard let p = self.peripheral, p.state == .connected else {
                    continuation.resume(throwing: BandError.notConnected)
                    return
                }
                if p.canSendWriteWithoutResponse {
                    continuation.resume()
                } else {
                    self.writeWaiters.append(continuation)
                }
            }
        }
    }

    private func failEverything(_ error: Error) {
        let writers = writeWaiters
        writeWaiters.removeAll()
        writers.forEach { $0.resume(throwing: error) }
        if let waiter = connectWaiter {
            connectWaiter = nil
            waiter.resume(throwing: error)
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEBandTransport: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            let waiters = poweredOnWaiters
            poweredOnWaiters.removeAll()
            waiters.forEach { $0.resume() }
        case .unsupported, .unauthorized, .poweredOff:
            let waiters = poweredOnWaiters
            poweredOnWaiters.removeAll()
            waiters.forEach { $0.resume(throwing: BandError.bluetoothUnavailable) }
            failEverything(BandError.bluetoothUnavailable)
        default:
            break
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
        guard name.hasPrefix(BandGATT.namePrefix) else { return }
        discovered[peripheral.identifier] = peripheral
        scanHandler?(DiscoveredBand(identifier: peripheral.identifier, name: name, alreadyConnected: false))
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([BandGATT.service])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        failEverything(error ?? BandError.notConnected)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        txCharacteristic = nil
        rxCharacteristic = nil
        failEverything(BandError.disconnected)
        onDisconnect?(error)
    }
}

// MARK: - CBPeripheralDelegate

extension BLEBandTransport: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == BandGATT.service }) else {
            finishConnect(.failure(error ?? BandError.serviceNotFound))
            return
        }
        peripheral.discoverCharacteristics([BandGATT.rx, BandGATT.tx], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        let characteristics = service.characteristics ?? []
        guard error == nil,
              let rx = characteristics.first(where: { $0.uuid == BandGATT.rx }),
              let tx = characteristics.first(where: { $0.uuid == BandGATT.tx })
        else {
            finishConnect(.failure(error ?? BandError.characteristicNotFound))
            return
        }
        rxCharacteristic = rx
        txCharacteristic = tx
        // Для прийому достатньо підписки на RX.
        peripheral.setNotifyValue(true, for: rx)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BandGATT.rx else { return }
        if let error {
            finishConnect(.failure(error))
        } else if characteristic.isNotifying {
            finishConnect(.success(()))
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == BandGATT.rx, let value = characteristic.value else { return }
        onReceive?(value)
    }

    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        let waiters = writeWaiters
        writeWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

// MARK: - Зручний сценарій

extension WatchfaceInstaller {
    /// Підключається до браслета, встановлює циферблат і відключається.
    public func install(
        _ face: FaceFile,
        authKey: [UInt8],
        bandIdentifier: UUID,
        transport: BLEBandTransport = BLEBandTransport(),
        configuration: BandSession.Configuration = .init(),
        onPhase: (@Sendable (InstallPhase) -> Void)? = nil
    ) async throws {
        let session = BandSession(transport: transport, configuration: configuration)
        transport.onReceive = { session.receive($0) }
        transport.onDisconnect = { _ in Task { await session.connectionLost() } }
        try await transport.connect(to: bandIdentifier)
        defer { transport.disconnect() }
        try await install(face, authKey: authKey, session: session, onPhase: onPhase)
    }
}
#endif
