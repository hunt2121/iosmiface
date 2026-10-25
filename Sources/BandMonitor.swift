import Foundation
import CoreBluetooth
import BandFaceKit

/// Пасивне спостереження за обміном браслета з іншим застосунком (Mi Fitness).
/// BandFace лише підписується на сповіщення 0x5E і нічого не надсилає браслету.
/// Вміст команд зашифровано ключами чужої сесії, тож видно лише структуру: типи кадрів,
/// номери, довжини, канали й підтвердження браслетом кадрів телефона.
@MainActor
final class BandMonitor: ObservableObject {
    @Published private(set) var isRunning = false
    private let ble: BLEManager
    private var parser = FrameParser()

    init(ble: BLEManager) {
        self.ble = ble
    }

    func start() async {
        guard !isRunning, ble.connectedID != nil, ble.hasBandCharacteristics else {
            ble.addLog(String(localized: "Спостереження: спершу підключіть браслет"))
            return
        }
        parser = FrameParser()
        ble.onData = { [weak self] uuid, data in
            guard uuid == BandGATT.rx else { return }
            Task { @MainActor in self?.handle(data) }
        }
        guard await ble.subscribeRX() else {
            ble.onData = nil
            ble.addLog(String(localized: "Спостереження: не вдалося підписатися на сповіщення"))
            return
        }
        isRunning = true
        ble.addTimedLog("MON старт: BandFace нічого не надсилає, лише слухає браслет")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        ble.onData = nil
        ble.unsubscribe(from: BandGATT.rx)
        ble.addTimedLog("MON стоп")
    }

    private func handle(_ data: Data) {
        for frame in parser.append([UInt8](data)) {
            switch frame.type {
            case .ack:
                // Браслет підтверджує кадр, який надіслав інший застосунок
                ble.addTimedLog("MON ← ack \(frame.sequence) (браслет отримав кадр телефона)")
            case .session:
                let code = frame.payload.first.map { "\($0)" } ?? "?"
                ble.addTimedLog("MON ← session code \(code), \(frame.payload.count) Б")
            case .data:
                guard frame.payload.count >= 2 else { continue }
                let channel = frame.payload[0] & 0x0F
                let opcode = frame.payload[1]
                let body = Array(frame.payload.dropFirst(2))
                var line = "MON ← data seq \(frame.sequence) flags \(frame.flags) ch \(channel) op \(opcode) \(body.count) Б"
                // Відкритий текст (автентифікація) можна розібрати
                if opcode == 1, channel == 1, let command = try? Command(body: body) {
                    line += " cmd \(command.name)"
                }
                ble.addTimedLog(line)
            }
        }
    }
}
