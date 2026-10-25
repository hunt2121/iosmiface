import Foundation
import CoreBluetooth
import UIKit

// Порт протоколу Xiaomi (BLE V2) із Gadgetbridge:
//   XiaomiBleProtocolV2, XiaomiSppPacketV2, XiaomiAuthService,
//   XiaomiWatchfaceService, XiaomiDataUploadService.
// Gadgetbridge ліцензовано за AGPL-3.0, тому цей застосунок теж розповсюджується за AGPL-3.0 (див. LICENSE).

enum BandError: LocalizedError {
    case notConnected
    case badAuthKey
    case badFaceFile(String)
    case protocolUnsupported(String)
    case authFailed
    case timeout(String)
    case device(String)
    case disconnected

    var errorDescription: String? {
        switch self {
        case .notConnected: return String(localized: "Браслет не підключено")
        case .badAuthKey: return String(localized: "Auth key має бути 32 hex-символи (16 байт)")
        case .badFaceFile(let why): return String(localized: "Некоректний файл циферблата: \(why)")
        case .protocolUnsupported(let why): return why
        case .authFailed: return String(localized: "Автентифікація не вдалася: перевірте auth key")
        case .timeout(let what): return String(localized: "Браслет не відповів (\(what))")
        case .device(let why): return String(localized: "Браслет відхилив операцію: \(why)")
        case .disconnected: return String(localized: "З'єднання розірвано")
        }
    }
}

/// Циферблат, що вже є на браслеті.
struct BandWatchface: Identifiable, Hashable {
    let id: String
    let name: String
    let active: Bool
    let canDelete: Bool
}

/// Одна операція = одна сесія: відкриття сесії, автентифікація, команда(и).
///
/// Особливість Band 10 (з'ясована на реальному пристрої): якщо підтверджувати (ack) кожен
/// пакет браслета, він перестає приймати наші команди. Тому ми не підтверджуємо пакети,
/// а коли браслет надіслав повне вікно (6 пакетів) без підтвердження, надсилаємо одне
/// сукупне підтвердження останнього пакета — інакше він не надішле наступну відповідь.
final class XiaomiBandSession {
    enum Operation {
        case install(FaceFile)
    }

    static let rxUUID = CBUUID(string: "0000005e-0000-1000-8000-00805f9b34fb") // браслет → телефон
    static let txUUID = CBUUID(string: "0000005f-0000-1000-8000-00805f9b34fb") // телефон → браслет
    static let v1CommandUUID = CBUUID(string: "00000051-0000-1000-8000-00805f9b34fb")

    /// Скільки непідтверджених пакетів браслет надсилає, перш ніж чекати на ack.
    private static let bandWindow = 6

    private enum Command {
        static let auth: UInt32 = 1
        static let system: UInt32 = 2
        static let watchface: UInt32 = 4
        static let dataUpload: UInt32 = 22

        static let authNonce: UInt32 = 26
        static let authStep3: UInt32 = 27
        static let authUserId: UInt32 = 5

        static let systemBattery: UInt32 = 1
        static let systemDeviceInfo: UInt32 = 2

        static let watchfaceList: UInt32 = 0
        static let watchfaceSet: UInt32 = 1
        static let watchfaceDelete: UInt32 = 2
        static let watchfaceInstall: UInt32 = 4

        static let uploadStart: UInt32 = 0
        static let uploadTypeWatchface: UInt32 = 16
    }

    private enum Stage {
        case idle, waitingSession, waitingWatchNonce, waitingAuthResult, probing
        case waitingInstallStatus, listing, deleting, activating
        case waitingUploadAck, uploading, done
    }

    private let ble: BLEManager
    private let secretKey: Data

    private var operation: Operation?
    private var stage: Stage = .idle
    private var progress: ((Double, String) -> Void)?
    private var completion: ((Result<String, Error>) -> Void)?

    private var rxBuffer: [UInt8] = []
    private var sequence: UInt8 = 0
    private var phoneNonce = Data()
    private var encryptionKey: Data?
    private var decryptionKey: Data?
    private var encryptionNonce = Data()

    private var seenRx: Set<UInt8> = []
    private var highestRx: UInt8?
    private var lastAckedRx: UInt8?

    private var successNote = ""
    private var timeoutWork: DispatchWorkItem?
    private var uploadParts: [Data] = []
    private var lastInstallStatus: UInt64 = 0
    private var retriedAfterDelete = false
    private var sessionOpened = false

    init(ble: BLEManager, authKeyHex: String) throws {
        guard let key = Data(hex: authKeyHex), key.count == 16 else { throw BandError.badAuthKey }
        self.ble = ble
        self.secretKey = key
    }

    private var face: FaceFile? {
        if case .install(let f)? = operation { return f }
        return nil
    }

    // MARK: - Публічний API

    func run(_ operation: Operation,
             progress: @escaping (Double, String) -> Void = { _, _ in },
             completion: @escaping (Result<String, Error>) -> Void) {
        guard stage == .idle || stage == .done else { return }
        self.operation = operation
        self.progress = progress
        self.completion = completion
        rxBuffer.removeAll()
        sequence = 0
        seenRx.removeAll()
        highestRx = nil
        lastAckedRx = nil
        retriedAfterDelete = false
        encryptionKey = nil
        decryptionKey = nil

        guard ble.connectedID != nil else { return fail(BandError.notConnected) }
        guard ble.characteristics[Self.rxUUID] != nil, ble.characteristics[Self.txUUID] != nil else {
            if ble.characteristics[Self.v1CommandUUID] != nil {
                return fail(BandError.protocolUnsupported(
                    String(localized: "Браслет використовує протокол V1 (характеристики 0x51–0x55). Його ще не реалізовано.")))
            }
            return fail(BandError.protocolUnsupported(
                String(localized: "У браслета немає BLE-характеристик 0x5E/0x5F. Схоже, на цій прошивці обмін іде лише через Bluetooth Classic, який iOS не підтримує.")))
        }

        ble.onData = { [weak self] uuid, data in self?.handleNotification(uuid, data) }
        ble.onDisconnect = { [weak self] in self?.fail(BandError.disconnected) }

        stage = .waitingSession
        report(0, String(localized: "Відкриття сесії…"))
        armTimeout(20, String(localized: "відкриття сесії"))
        ble.subscribe(to: Self.rxUUID) { [weak self] ok in
            guard let self, self.stage == .waitingSession else { return }
            guard ok else { return self.fail(BandError.protocolUnsupported(String(localized: "Не вдалося підписатися на сповіщення 0x5E"))) }
            self.sendStartSession(attempt: 1)
        }
    }

    /// Браслет іноді не відповідає з першого разу, тож повторюємо до 3 разів.
    /// Відкриття сесії. Якщо браслет мовчить (наприклад, сесію тримає Mi Fitness),
    /// наступні спроби спершу закривають стару сесію, а потім відкривають нову.
    private func sendStartSession(attempt: Int) {
        guard stage == .waitingSession else { return }
        sessionOpened = true
        if attempt == 1 {
            ble.debug("→ START_SESSION (спроба 1)")
            ble.enqueue(XiaomiPacketV2.startSessionRequest(), to: Self.txUUID)
        } else {
            ble.debug("→ STOP_SESSION + START_SESSION (спроба \(attempt))")
            ble.enqueue(XiaomiPacketV2.stopSessionRequest(), to: Self.txUUID)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, self.stage == .waitingSession else { return }
                self.ble.enqueue(XiaomiPacketV2.startSessionRequest(), to: Self.txUUID)
            }
        }
        guard attempt < 4 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.sendStartSession(attempt: attempt + 1)
        }
    }

    private func handleNotification(_ uuid: CBUUID, _ data: Data) {
        guard uuid == Self.rxUUID else { return }
        if stage == .waitingSession { ble.debug("← \(Self.hex(data, max: 24))") }
        rxBuffer.append(contentsOf: data)
        processBuffer()
    }

    private func processBuffer() {
        while true {
            switch XiaomiPacketV2.parse(rxBuffer) {
            case .incomplete:
                return
            case .invalid:
                if let next = rxBuffer.dropFirst().firstIndex(of: XiaomiPacketV2.preamble[0]) {
                    ble.debug("Некоректний кадр, пропускаю \(next) байт")
                    rxBuffer.removeFirst(next)
                } else {
                    ble.debug("Некоректний кадр, буфер очищено")
                    rxBuffer.removeAll()
                    return
                }
            case .complete(let packet, let size):
                rxBuffer.removeFirst(size)
                if let packet { handlePacket(packet) }
            }
        }
    }

    private func handlePacket(_ packet: XiaomiPacketV2.Parsed) {
        switch packet {
        case .ack(let seq):
            ble.debug("← ack \(seq)")
        case .sessionConfig(_, let opcode):
            ble.debug("← SESSION_CONFIG op=\(opcode)")
            // 2 = відповідь на START_SESSION (відповідь на STOP_SESSION — 4, її пропускаємо)
            if stage == .waitingSession && opcode == 2 { startHandshake() }
        case .data(let seq, let channel, let opcode, let payload):
            // Браслет повторює непідтверджені пакети — обробляємо кожен лише раз
            guard seenRx.insert(seq).inserted else {
                ble.debug("← повтор пакета \(seq)")
                return
            }
            highestRx = seq

            var plain = payload
            if opcode == XiaomiPacketV2.opEncrypted {
                guard let key = decryptionKey else {
                    ble.debug("← зашифрований пакет до автентифікації, ігнорую")
                    return
                }
                plain = XiaomiCrypto.v2Crypt(key: key, data: payload)
            }

            if channel == .protobuf {
                handleCommand(plain)
            } else {
                ble.debug("← канал \(channel): \(plain.count) байт")
            }
        }
    }

    private func handleCommand(_ bytes: Data) {
        guard let msg = ProtoMessage(bytes), let type = msg.uint(1) else {
            ble.debug("← не вдалося розібрати команду")
            return
        }
        let subtype = msg.uint(2) ?? 0
        ble.debug("← \(type)/\(subtype) \(Self.hex(bytes))")

        switch UInt32(type) {
        case Command.auth: handleAuth(msg, subtype: UInt32(subtype))
        case Command.system: handleSystem(msg, subtype: UInt32(subtype))
        case Command.watchface: handleWatchface(msg, subtype: UInt32(subtype))
        case Command.dataUpload: handleUpload(msg, subtype: UInt32(subtype))
        default: break
        }
    }

    // MARK: - Автентифікація

    private func startHandshake() {
        stage = .waitingWatchNonce
        report(0, String(localized: "Автентифікація…"))
        armTimeout(15, String(localized: "автентифікація"))

        var nonce = Data(count: 16)
        let status = nonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { return fail(BandError.authFailed) }
        phoneNonce = nonce

        var phone = ProtoWriter()
        phone.bytes(1, nonce)
        var auth = ProtoWriter()
        auth.message(30, phone)
        sendCommand(type: Command.auth, subtype: Command.authNonce) { $0.message(3, auth) }
    }

    private func handleAuth(_ msg: ProtoMessage, subtype: UInt32) {
        switch subtype {
        case Command.authNonce:
            guard stage == .waitingWatchNonce,
                  let watch = msg.message(3)?.message(31),
                  let watchNonce = watch.data(1),
                  let watchHmac = watch.data(2) else { return }

            let keys = XiaomiCrypto.deriveSessionKeys(secretKey: secretKey, phoneNonce: phoneNonce, watchNonce: watchNonce)
            let decKey = keys.subdata(in: 0..<16)
            let encKey = keys.subdata(in: 16..<32)
            encryptionNonce = keys.subdata(in: 36..<40)

            let expected = XiaomiCrypto.hmacSHA256(key: decKey, data: watchNonce + phoneNonce)
            guard expected == watchHmac else {
                ble.addLog(String(localized: "Браслет не прийняв ключ: неправильний auth key?"))
                return fail(BandError.authFailed)
            }
            decryptionKey = decKey
            encryptionKey = encKey

            let encryptedNonces = XiaomiCrypto.hmacSHA256(key: encKey, data: phoneNonce + watchNonce)

            var info = ProtoWriter()
            info.uint(1, 0)
            info.float32(2, 34)
            info.string(3, UIDevice.current.model)
            info.uint(4, 224)
            info.string(5, Self.regionCode())
            let ccmNonce = encryptionNonce + Data(count: 8)
            let encryptedInfo = XiaomiCrypto.aesCCMEncrypt(key: encKey, nonce: ccmNonce, plaintext: info.data)

            var step3 = ProtoWriter()
            step3.bytes(1, encryptedNonces)
            step3.bytes(2, encryptedInfo)
            var auth = ProtoWriter()
            auth.message(32, step3)

            stage = .waitingAuthResult
            armTimeout(15, String(localized: "підтвердження автентифікації"))
            sendCommand(type: Command.auth, subtype: Command.authStep3) { $0.message(3, auth) }

        case Command.authStep3, Command.authUserId:
            guard stage == .waitingAuthResult else { return }
            ble.addLog(String(localized: "Підключено до браслета"))
            afterAuth()

        default:
            ble.debug("Невідома auth-команда \(subtype)")
        }
    }

    private static func regionCode() -> String {
        let code = Locale.current.language.languageCode?.identifier.uppercased() ?? "EN"
        return String(code.prefix(2)).count == 2 ? String(code.prefix(2)) : "EN"
    }

    private func afterAuth() {
        // Перевірений на Band 10 порядок: інформація про пристрій, заряд, потім встановлення
        stage = .probing
        armTimeout(20, String(localized: "інформація про браслет"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.stage == .probing else { return }
            self.sendCommand(type: Command.system, subtype: Command.systemDeviceInfo) { _ in }
            self.sendCommand(type: Command.system, subtype: Command.systemBattery) { _ in }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.stage == .probing else { return }
                self.beginInstall()
            }
        }
    }

    private func handleSystem(_ msg: ProtoMessage, subtype: UInt32) {
        guard let system = msg.message(4) else { return }
        switch subtype {
        case Command.systemDeviceInfo:
            if let info = system.message(3) {
                let model = info.string(4) ?? "?"
                let fw = info.string(2) ?? "?"
                ble.addLog(String(localized: "Браслет: модель \(model), прошивка \(fw)"))
            }
        case Command.systemBattery:
            if let level = system.message(2)?.message(1)?.uint(1) {
                ble.addLog(String(localized: "Заряд: \(String(level))") + "%")
            }
        default:
            break
        }
    }

    // MARK: - Циферблати

    private func beginInstall() {
        guard let face else { return }
        stage = .waitingInstallStatus
        armTimeout(20, String(localized: "запит на встановлення"))
        report(0, String(localized: "Запит на встановлення…"))

        var start = ProtoWriter()
        start.string(1, face.id)
        start.uint(2, UInt32(face.data.count))
        var wf = ProtoWriter()
        wf.message(6, start)
        sendCommand(type: Command.watchface, subtype: Command.watchfaceInstall) { $0.message(6, wf) }
        ble.addLog(String(localized: "Встановлення \(face.id) (\(String(face.data.count / 1024)) КБ)…"))
    }

    private func requestList() {
        stage = .listing
        report(0, String(localized: "Отримання списку…"))
        armTimeout(15, String(localized: "список циферблатів"))
        sendCommand(type: Command.watchface, subtype: Command.watchfaceList) { _ in }
    }

    private func activate(_ id: String, note: String) {
        stage = .activating
        successNote = note
        report(1, String(localized: "Активація…"))
        armTimeout(12, String(localized: "активація циферблата"), softSuccess: note + " " + String(localized: "(підтвердження не отримано)"))
        var wf = ProtoWriter()
        wf.string(2, id)
        sendCommand(type: Command.watchface, subtype: Command.watchfaceSet) { $0.message(6, wf) }
    }

    private func deleteFace(_ id: String) {
        stage = .deleting
        report(0, String(localized: "Видалення…"))
        armTimeout(15, String(localized: "видалення циферблата"))
        var wf = ProtoWriter()
        wf.string(2, id)
        sendCommand(type: Command.watchface, subtype: Command.watchfaceDelete) { $0.message(6, wf) }
    }

    private static func parseList(_ msg: ProtoMessage) -> [BandWatchface] {
        (msg.message(6)?.message(1)?.messages(1) ?? []).map { item in
            BandWatchface(id: item.string(1) ?? "?",
                          name: item.string(2) ?? "",
                          active: (item.uint(3) ?? 0) != 0,
                          canDelete: (item.uint(4) ?? 0) != 0)
        }
    }

    private func handleWatchface(_ msg: ProtoMessage, subtype: UInt32) {
        switch subtype {
        case Command.watchfaceInstall:
            guard stage == .waitingInstallStatus else { return }
            let status = msg.message(6)?.uint(5) ?? 0
            switch status {
            case 0:
                requestUpload()
            case 2:
                ble.addLog(String(localized: "Цей циферблат уже є на браслеті"))
                activate(face?.id ?? "", note: String(localized: "Циферблат уже був на браслеті, його активовано"))
            default:
                // Щоб зрозуміти причину, дивимось список циферблатів на браслеті
                lastInstallStatus = status
                ble.addLog(String(localized: "Браслет відмовив (статус \(String(status))), перевіряю список циферблатів"))
                requestList()
            }

        case Command.watchfaceList:
            guard stage == .listing else { return }
            let list = Self.parseList(msg)
            ble.addLog(String(localized: "Циферблатів на браслеті: \(String(list.count))"))
            guard let face else { return }
            explainInstallFailure(face: face, list: list)

        case Command.watchfaceDelete:
            guard stage == .deleting else { return }
            ble.addLog(String(localized: "Стару версію видалено, повторюю встановлення"))
            beginInstall()

        case Command.watchfaceSet:
            guard stage == .activating else { return }
            succeed(successNote)

        default:
            break
        }
    }

    private func explainInstallFailure(face: FaceFile, list: [BandWatchface]) {
        let same = list.first { $0.id == face.id }
        if let same, same.canDelete, !retriedAfterDelete {
            if same.active {
                return fail(BandError.device(String(localized: "на браслеті вже є стара версія цього циферблата, і вона зараз активна. Перемкніть на браслеті інший циферблат і спробуйте ще раз — стару версію буде замінено")))
            }
            ble.addLog(String(localized: "Знайдено стару версію цього циферблата — замінюю"))
            retriedAfterDelete = true
            deleteFace(face.id)
            return
        }
        let userFaces = list.filter(\.canDelete).count
        var why = String(localized: "статус \(String(lastInstallStatus))")
        if userFaces >= 10 { why += ". " + String(localized: "Власних циферблатів на браслеті: \(String(userFaces)) — видаліть кілька (ліміт ≈10)") }
        else if same != nil { why += ". " + String(localized: "Циферблат з таким ID уже є, і його не вдалося замінити") }
        else { why += ". " + String(localized: "Можливо, файл не призначений для Band 10, завеликий або браслету бракує пам'яті") }
        fail(BandError.device(why))
    }

    // MARK: - Завантаження даних

    private func requestUpload() {
        guard let face else { return }
        stage = .waitingUploadAck
        armTimeout(20, String(localized: "запит на завантаження"))

        var req = ProtoWriter()
        req.uint(1, Command.uploadTypeWatchface)
        req.bytes(2, XiaomiCrypto.md5(face.data))
        req.uint(3, UInt32(face.data.count))
        var upload = ProtoWriter()
        upload.message(1, req)
        sendCommand(type: Command.dataUpload, subtype: Command.uploadStart) { $0.message(24, upload) }
    }

    private func handleUpload(_ msg: ProtoMessage, subtype: UInt32) {
        guard subtype == Command.uploadStart, stage == .waitingUploadAck else { return }
        let ack = msg.message(24)?.message(2)
        let unknown2 = ack?.uint(2) ?? 0
        guard unknown2 == 0 else { return fail(BandError.device(String(localized: "несподівана відповідь на завантаження (\(String(unknown2)))"))) }

        let resume = Int(ack?.uint(4) ?? 0)
        let chunk = Int(ack?.uint(5) ?? 2048)
        guard let face, resume <= face.data.count, chunk > 4 else {
            return fail(BandError.device(String(localized: "некоректні параметри завантаження")))
        }
        ble.debug("Завантаження: chunk=\(chunk), resume=\(resume)")
        startUpload(face: face, resume: resume, chunkSize: chunk)
    }

    private func startUpload(face: FaceFile, resume: Int, chunkSize: Int) {
        var head = Data([0, UInt8(Command.uploadTypeWatchface)])
        head.append(XiaomiCrypto.md5(face.data))
        head.append(Self.le32(UInt32(face.data.count)))
        head.append(face.data.subdata(in: resume..<face.data.count))
        var payload = head
        payload.append(Self.le32(XiaomiCrypto.crc32(head)))

        let partSize = chunkSize - 4
        let total = (payload.count + partSize - 1) / partSize
        guard total < 0x10000 else { return fail(BandError.badFaceFile(String(localized: "завеликий для передачі"))) }

        uploadParts = (0..<total).map { i in
            let start = i * partSize
            let end = min(start + partSize, payload.count)
            var part = Data()
            part.append(Self.le16(UInt16(total)))
            part.append(Self.le16(UInt16(i + 1)))
            part.append(payload.subdata(in: start..<end))
            return part
        }

        ble.addLog(String(localized: "Передача файлу (частин: \(String(total)))…"))
        stage = .uploading
        sendPart(0)
    }

    private func sendPart(_ index: Int) {
        guard stage == .uploading else { return }
        guard index < uploadParts.count else {
            uploadParts.removeAll()
            ble.addLog(String(localized: "Файл передано"))
            activate(face?.id ?? "", note: String(localized: "Циферблат встановлено й активовано"))
            return
        }

        armTimeout(30, String(localized: "передача даних"))
        let packet = XiaomiPacketV2.dataPacket(seq: nextSequence(), channel: .data,
                                               opcode: XiaomiPacketV2.opPlaintext, payload: uploadParts[index])
        let total = uploadParts.count
        let queued = ble.enqueue(packet, to: Self.txUUID) { [weak self] in
            guard let self, self.stage == .uploading else { return }
            self.report(Double(index + 1) / Double(total), String(localized: "Передача \(String(index + 1))/\(String(total))"))
            self.sendPart(index + 1)
        }
        if !queued { fail(BandError.disconnected) }
    }

    // MARK: - Допоміжне

    private func nextSequence() -> UInt8 {
        defer { sequence &+= 1 }
        return sequence
    }

    /// Скільки пакетів браслета ще не підтверджено.
    private var unackedRx: Int {
        guard let highestRx else { return 0 }
        guard let lastAckedRx else { return Int(highestRx) + 1 }
        return Int(highestRx &- lastAckedRx)
    }

    private func sendCommand(type: UInt32, subtype: UInt32, build: (inout ProtoWriter) -> Void) {
        var w = ProtoWriter()
        w.uint(1, type)
        w.uint(2, subtype)
        build(&w)

        let encrypted = type != Command.auth
        var payload = w.data
        if encrypted {
            guard let key = encryptionKey else { return fail(BandError.authFailed) }
            payload = XiaomiCrypto.v2Crypt(key: key, data: payload)
        }
        let seq = nextSequence()
        let packet = XiaomiPacketV2.dataPacket(
            seq: seq,
            channel: .protobuf,
            opcode: encrypted ? XiaomiPacketV2.opEncrypted : XiaomiPacketV2.opPlaintext,
            payload: payload)
        // Вміст auth-команд не логуємо, щоб не світити матеріал для ключів
        ble.debug("→ \(type)/\(subtype) seq=\(seq)\(type == Command.auth ? "" : " " + Self.hex(w.data))")
        if !ble.enqueue(packet, to: Self.txUUID) { ble.addLog(String(localized: "Не вдалося надіслати команду")) }

        // Вікно браслета заповнене — без сукупного ack він не надішле відповідь на цю команду
        if encrypted, unackedRx >= Self.bandWindow, let last = highestRx {
            lastAckedRx = last
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.stage != .done else { return }
                self.ble.enqueue(XiaomiPacketV2.ack(seq: last), to: Self.txUUID)
                self.ble.debug("→ сукупний ack \(last)")
            }
        }
    }

    private static func hex(_ data: Data, max: Int = 48) -> String {
        let head = data.prefix(max).map { String(format: "%02x", $0) }.joined()
        return data.count > max ? head + "…(\(data.count)B)" : head
    }

    private static func le16(_ v: UInt16) -> Data { Data([UInt8(v & 0xFF), UInt8(v >> 8)]) }
    private static func le32(_ v: UInt32) -> Data {
        Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)])
    }

    private func report(_ value: Double, _ text: String) {
        progress?(value, text)
    }

    private func armTimeout(_ seconds: TimeInterval, _ what: String, softSuccess: String? = nil) {
        timeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.stage != .done, self.stage != .idle else { return }
            if let softSuccess { self.succeed(softSuccess) } else { self.fail(BandError.timeout(what)) }
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func succeed(_ message: String) {
        guard stage != .done else { return }
        stage = .done
        timeoutWork?.cancel()
        cleanup()
        ble.addLog(String(localized: "Готово: \(message)"))
        let cb = completion
        completion = nil
        cb?(.success(message))
    }

    private func fail(_ error: Error) {
        guard stage != .done else { return }
        stage = .done
        timeoutWork?.cancel()
        cleanup()
        ble.addLog(String(localized: "Помилка: \(error.localizedDescription)"))
        let cb = completion
        completion = nil
        cb?(.failure(error))
    }

    private func cleanup() {
        ble.onData = nil
        ble.onDisconnect = nil
        uploadParts.removeAll()
        releaseBand()
    }

    /// Закриває сесію й відписується від сповіщень, щоб браслет знову міг працювати з Mi Fitness.
    private func releaseBand() {
        guard sessionOpened, ble.connectedID != nil else { return }
        sessionOpened = false
        ble.enqueue(XiaomiPacketV2.stopSessionRequest(), to: Self.txUUID)
        ble.debug("→ STOP_SESSION")
        ble.unsubscribe(from: Self.rxUUID)
    }
}
