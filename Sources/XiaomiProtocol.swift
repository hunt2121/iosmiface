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
        case .notConnected: return "Браслет не підключено"
        case .badAuthKey: return "Auth key має бути 32 hex-символи (16 байт)"
        case .badFaceFile(let why): return "Некоректний файл циферблата: \(why)"
        case .protocolUnsupported(let why): return why
        case .authFailed: return "Автентифікація не вдалася: перевірте auth key"
        case .timeout(let what): return "Браслет не відповів (\(what))"
        case .device(let why): return "Браслет відхилив операцію: \(why)"
        case .disconnected: return "З'єднання розірвано"
        }
    }
}

final class XiaomiBandSession {
    // BLE V2 (Mi Band 9 Active та новіші)
    static let rxUUID = CBUUID(string: "0000005e-0000-1000-8000-00805f9b34fb") // браслет → телефон (notify)
    static let txUUID = CBUUID(string: "0000005f-0000-1000-8000-00805f9b34fb") // телефон → браслет
    // BLE V1 (Mi Band 8), тут лише для діагностики
    static let v1CommandUUID = CBUUID(string: "00000051-0000-1000-8000-00805f9b34fb")

    private enum Command {
        static let auth: UInt32 = 1
        static let watchface: UInt32 = 4
        static let dataUpload: UInt32 = 22

        static let authNonce: UInt32 = 26
        static let authStep3: UInt32 = 27
        static let authUserId: UInt32 = 5

        static let watchfaceSet: UInt32 = 1
        static let watchfaceInstall: UInt32 = 4

        static let uploadStart: UInt32 = 0
        static let uploadTypeWatchface: UInt32 = 16
    }

    private enum Stage {
        case idle, waitingSession, waitingWatchNonce, waitingAuthResult
        case waitingInstallStatus, waitingUploadAck, uploading, finishing, done
    }

    private let ble: BLEManager
    private let secretKey: Data

    private var stage: Stage = .idle
    private var face: FaceFile?
    private var progress: ((Double, String) -> Void)?
    private var completion: ((Result<String, Error>) -> Void)?

    private var rxBuffer: [UInt8] = []
    private var sequence: UInt8 = 0
    private var phoneNonce = Data()
    private var encryptionKey: Data?
    private var decryptionKey: Data?
    private var encryptionNonce = Data()

    private var successNote = "Циферблат встановлено й активовано"
    private var timeoutWork: DispatchWorkItem?
    private var uploadParts: [Data] = []

    init(ble: BLEManager, authKeyHex: String) throws {
        guard let key = Data(hex: authKeyHex), key.count == 16 else { throw BandError.badAuthKey }
        self.ble = ble
        self.secretKey = key
    }

    // MARK: - Публічний API

    func install(face: FaceFile,
                 progress: @escaping (Double, String) -> Void,
                 completion: @escaping (Result<String, Error>) -> Void) {
        guard stage == .idle || stage == .done else { return }
        self.face = face
        self.progress = progress
        self.completion = completion
        self.rxBuffer.removeAll()
        self.sequence = 0
        self.encryptionKey = nil
        self.decryptionKey = nil

        guard ble.connectedID != nil else { return fail(BandError.notConnected) }
        guard ble.characteristics[Self.rxUUID] != nil, ble.characteristics[Self.txUUID] != nil else {
            if ble.characteristics[Self.v1CommandUUID] != nil {
                return fail(BandError.protocolUnsupported(
                    "Браслет використовує протокол V1 (характеристики 0x51–0x55). Його ще не реалізовано."))
            }
            return fail(BandError.protocolUnsupported(
                "У браслета немає BLE-характеристик 0x5E/0x5F. Схоже, на цій прошивці обмін іде лише через Bluetooth Classic, який iOS не підтримує."))
        }

        ble.onData = { [weak self] uuid, data in self?.handleNotification(uuid, data) }
        ble.onDisconnect = { [weak self] in self?.fail(BandError.disconnected) }

        stage = .waitingSession
        report(0, "Відкриття сесії…")
        armTimeout(18, "відкриття сесії")
        ble.subscribe(to: Self.rxUUID) { [weak self] ok in
            guard let self, self.stage == .waitingSession else { return }
            guard ok else { return self.fail(BandError.protocolUnsupported("Не вдалося підписатися на сповіщення 0x5E")) }
            // Діагностика: 0x5F теж має notify, тож слухаємо й його
            self.ble.subscribe(to: Self.txUUID) { _ in }
            self.sendStartSession(attempt: 1)
        }
    }

    /// Браслет іноді не відповідає з першого разу, тож повторюємо до 3 разів.
    private func sendStartSession(attempt: Int) {
        guard stage == .waitingSession else { return }
        ble.addLog("→ START_SESSION (спроба \(attempt))")
        ble.enqueue(XiaomiPacketV2.startSessionRequest(), to: Self.txUUID)
        guard attempt < 3 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.sendStartSession(attempt: attempt + 1)
        }
    }

    // MARK: - Прийом

    private func handleNotification(_ uuid: CBUUID, _ data: Data) {
        if stage == .waitingSession || stage == .waitingWatchNonce || stage == .waitingAuthResult {
            ble.addLog("← raw \(uuid.uuidString.prefix(4)) \(Self.hex(data, max: 24))")
        }
        guard uuid == Self.rxUUID else { return }
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
                    ble.addLog("Некоректний кадр, пропускаю \(next) байт")
                    rxBuffer.removeFirst(next)
                } else {
                    ble.addLog("Некоректний кадр, буфер очищено")
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
        case .ack:
            break
        case .sessionConfig(_, let opcode):
            ble.addLog("← SESSION_CONFIG op=\(opcode)")
            if stage == .waitingSession { startHandshake() }
        case .data(let seq, let channel, let opcode, let payload):
            ble.addLog("← pkt seq=\(seq) ch=\(channel) op=\(opcode) len=\(payload.count)")
            ble.enqueue(XiaomiPacketV2.ack(seq: seq), to: Self.txUUID)

            var plain = payload
            if opcode == XiaomiPacketV2.opEncrypted {
                guard let key = decryptionKey else {
                    ble.addLog("← зашифрований пакет до завершення автентифікації, ігнорую")
                    return
                }
                plain = XiaomiCrypto.v2Crypt(key: key, data: payload)
            }

            if channel == .protobuf {
                handleCommand(plain)
            } else {
                ble.addLog("← канал \(channel): \(plain.count) байт")
            }
        }
    }

    private func handleCommand(_ bytes: Data) {
        guard let msg = ProtoMessage(bytes), let type = msg.uint(1) else {
            ble.addLog("← не вдалося розібрати команду")
            return
        }
        let subtype = msg.uint(2) ?? 0
        let status = msg.uint(100).map { " status=\($0)" } ?? ""
        ble.addLog("← команда \(type)/\(subtype)\(status) \(Self.hex(bytes))")

        switch UInt32(type) {
        case Command.auth: handleAuth(msg, subtype: UInt32(subtype))
        case Command.watchface: handleWatchface(msg, subtype: UInt32(subtype))
        case Command.dataUpload: handleUpload(msg, subtype: UInt32(subtype))
        default: break
        }
    }

    // MARK: - Автентифікація

    private func startHandshake() {
        stage = .waitingWatchNonce
        armTimeout(15, "автентифікація")

        var nonce = Data(count: 16)
        let status = nonce.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { return fail(BandError.authFailed) }
        phoneNonce = nonce

        var phone = ProtoWriter()
        phone.bytes(1, nonce)
        var auth = ProtoWriter()
        auth.message(30, phone)
        sendCommand(type: Command.auth, subtype: Command.authNonce) { $0.message(3, auth) }
        ble.addLog("→ auth: phone nonce")
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
                ble.addLog("HMAC браслета не збігся: неправильний auth key?")
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
            armTimeout(15, "підтвердження автентифікації")
            sendCommand(type: Command.auth, subtype: Command.authStep3) { $0.message(3, auth) }
            ble.addLog("→ auth: step 3")

        case Command.authStep3, Command.authUserId:
            guard stage == .waitingAuthResult else { return }
            ble.addLog("Автентифіковано")
            beginInstall()

        default:
            ble.addLog("Невідома auth-команда \(subtype)")
        }
    }

    private static func regionCode() -> String {
        let code = Locale.current.language.languageCode?.identifier.uppercased() ?? "EN"
        return String(code.prefix(2)).count == 2 ? String(code.prefix(2)) : "EN"
    }

    // MARK: - Циферблат

    private func beginInstall() {
        guard let face else { return }
        stage = .waitingInstallStatus
        armTimeout(20, "запит на встановлення")
        report(0, "Запит на встановлення…")

        var start = ProtoWriter()
        start.string(1, face.id)
        start.uint(2, UInt32(face.data.count))
        var wf = ProtoWriter()
        wf.message(6, start)
        sendCommand(type: Command.watchface, subtype: Command.watchfaceInstall) { $0.message(6, wf) }
        ble.addLog("→ install \(face.id), \(face.data.count) байт")
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
                ble.addLog("Циферблат уже встановлений, активую")
                activateWatchface(note: "Циферблат уже був на браслеті, його активовано")
            default:
                fail(BandError.device("статус встановлення \(status)"))
            }

        case Command.watchfaceSet:
            ble.addLog("← підтвердження активації (ack=\(msg.message(6)?.uint(4) ?? 0))")
            if stage == .finishing { succeed(successNote) }

        default:
            break
        }
    }

    private func activateWatchface(note: String) {
        guard let face else { return }
        stage = .finishing
        successNote = note
        armTimeout(8, "активація циферблата", softSuccess: note + " (підтвердження не отримано)")
        var wf = ProtoWriter()
        wf.string(2, face.id)
        sendCommand(type: Command.watchface, subtype: Command.watchfaceSet) { $0.message(6, wf) }
        ble.addLog("→ set watchface \(face.id)")
    }

    // MARK: - Завантаження даних

    private func requestUpload() {
        guard let face else { return }
        stage = .waitingUploadAck
        armTimeout(20, "запит на завантаження")

        var req = ProtoWriter()
        req.uint(1, Command.uploadTypeWatchface)
        req.bytes(2, XiaomiCrypto.md5(face.data))
        req.uint(3, UInt32(face.data.count))
        var upload = ProtoWriter()
        upload.message(1, req)
        sendCommand(type: Command.dataUpload, subtype: Command.uploadStart) { $0.message(24, upload) }
        ble.addLog("→ upload request")
    }

    private func handleUpload(_ msg: ProtoMessage, subtype: UInt32) {
        guard subtype == Command.uploadStart, stage == .waitingUploadAck else { return }
        let ack = msg.message(24)?.message(2)
        let unknown2 = ack?.uint(2) ?? 0
        guard unknown2 == 0 else { return fail(BandError.device("несподівана відповідь на завантаження (\(unknown2))")) }

        let resume = Int(ack?.uint(4) ?? 0)
        let chunk = Int(ack?.uint(5) ?? 2048)
        guard let face, resume <= face.data.count, chunk > 4 else {
            return fail(BandError.device("некоректні параметри завантаження"))
        }
        ble.addLog("Завантаження: chunk=\(chunk), resume=\(resume)")
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
        guard total < 0x10000 else { return fail(BandError.badFaceFile("завеликий для передачі")) }

        uploadParts = (0..<total).map { i in
            let start = i * partSize
            let end = min(start + partSize, payload.count)
            var part = Data()
            part.append(Self.le16(UInt16(total)))
            part.append(Self.le16(UInt16(i + 1)))
            part.append(payload.subdata(in: start..<end))
            return part
        }

        stage = .uploading
        sendPart(0)
    }

    private func sendPart(_ index: Int) {
        guard stage == .uploading else { return }
        guard index < uploadParts.count else {
            uploadParts.removeAll()
            report(1, "Дані передано, активація…")
            activateWatchface(note: "Циферблат встановлено й активовано")
            return
        }

        armTimeout(30, "передача даних")
        let packet = XiaomiPacketV2.dataPacket(seq: nextSequence(), channel: .data,
                                               opcode: XiaomiPacketV2.opPlaintext, payload: uploadParts[index])
        let total = uploadParts.count
        let queued = ble.enqueue(packet, to: Self.txUUID) { [weak self] in
            guard let self, self.stage == .uploading else { return }
            self.report(Double(index + 1) / Double(total), "Передача \(index + 1)/\(total)")
            self.sendPart(index + 1)
        }
        if !queued { fail(BandError.disconnected) }
    }

    // MARK: - Допоміжне

    private func nextSequence() -> UInt8 {
        defer { sequence &+= 1 }
        return sequence
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
        let shown = type == Command.auth ? "" : " " + Self.hex(w.data)
        ble.addLog("→ cmd \(type)/\(subtype) seq=\(seq) \(encrypted ? "enc" : "plain") \(packet.count)B\(shown)")
        let queued = ble.enqueue(packet, to: Self.txUUID)
        if !queued { ble.addLog("! не вдалося поставити пакет у чергу запису") }
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
        let cb = completion
        completion = nil
        cb?(.success(message))
    }

    private func fail(_ error: Error) {
        guard stage != .done else { return }
        stage = .done
        timeoutWork?.cancel()
        cleanup()
        ble.addLog("Помилка: \(error.localizedDescription)")
        let cb = completion
        completion = nil
        cb?(.failure(error))
    }

    private func cleanup() {
        ble.onData = nil
        ble.onDisconnect = nil
        uploadParts.removeAll()
    }
}
