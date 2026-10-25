// SPDX-License-Identifier: MIT
//
// Наскрізний тест сесії з імітацією браслета. Імітація поводиться як Band 10:
// надсилає не більше 6 непідтверджених кадрів і чекає сукупного підтвердження.

import XCTest
@testable import BandFaceKit

final class MockBand: BandTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let authKey: [UInt8]
    private let bandNonce = Array<UInt8>(0x20...0x2F)
    private var parser = FrameParser()
    private var keys: SessionKeys?
    private var phoneNonce: [UInt8] = []
    private var sequence: UInt8 = 0
    private var unacked = 0
    private var held: [[UInt8]] = [] // кадри, що чекають місця у вікні
    weak var session: BandSession?

    private(set) var receivedParts: [[UInt8]] = []
    private(set) var acksReceived: [UInt8] = []
    private(set) var commandsReceived: [String] = []
    private(set) var phoneSequences: [UInt8] = []
    var installStatus: UInt64 = 0

    init(authKey: [UInt8]) { self.authKey = authKey }

    func write(_ frame: [UInt8]) async throws {
        let outgoing: [[UInt8]] = lock.withLock {
            var out: [[UInt8]] = []
            for f in parser.append(frame) { out += handle(f) }
            return out
        }
        for bytes in outgoing { session?.receive(Data(bytes)) }
    }

    private func handle(_ frame: Frame) -> [[UInt8]] {
        switch frame.type {
        case .session:
            let code = frame.payload.first
            if code == 1 {
                sequence = 0; unacked = 0; held = []; keys = nil
                let response = SessionControl(code: .openResponse, parameters: [(key: 1, value: [3, 0, 65])])
                return [Frame(type: .session, sequence: 0, payload: response.payload).encoded()]
            }
            if code == 3 {
                return [Frame(type: .session, sequence: 0, payload: SessionControl(code: .closeResponse).payload).encoded()]
            }
            return []
        case .ack:
            acksReceived.append(frame.sequence)
            unacked = 0
            let release = held
            held = []
            return release.flatMap { emit($0) }
        case .data:
            phoneSequences.append(frame.sequence)
            let packet = DataPacket(payload: frame.payload)!
            if packet.channel == DataChannel.file.rawValue {
                receivedParts.append(packet.body)
                // Як Band 10: частини файлу браслет підтверджує сам
                return [Frame.ack(frame.sequence).encoded()]
            }
            let body = packet.opcode == DataOpcode.encrypted.rawValue
                ? BandCrypto.aesCTR(key: keys!.encryptionKey, iv: keys!.encryptionKey, data: packet.body)
                : packet.body
            let command = try! Command(body: body)
            commandsReceived.append(command.name)
            return reply(to: command).flatMap { emit($0) }
        }
    }

    /// Нумерує кадр і надсилає його або притримує, якщо вікно з 6 кадрів заповнене.
    private func emit(_ body: [UInt8]) -> [[UInt8]] {
        guard unacked < 6 else {
            held.append(body)
            return []
        }
        unacked += 1
        let encrypted = keys != nil && (try? Command(body: body))?.type != Command.Kind.auth
        let payloadBody = encrypted
            ? BandCrypto.aesCTR(key: keys!.decryptionKey, iv: keys!.decryptionKey, data: body)
            : body
        let packet = DataPacket(channel: .protobuf, opcode: encrypted ? .encrypted : .plain, body: payloadBody)
        let frame = Frame(type: .data, sequence: sequence, payload: packet.payload).encoded()
        sequence &+= 1
        return [frame]
    }

    private func reply(to command: Command) -> [[UInt8]] {
        switch (command.type, command.subtype) {
        case (1, 26):
            phoneNonce = command.root.bytes(at: [3, 30, 1])!
            let k = SessionKeys(authKey: authKey, phoneNonce: phoneNonce, bandNonce: bandNonce)
            keys = nil // відповідь на крок 1 — відкритим текстом
            let hmac = k.expectedBandHMAC(phoneNonce: phoneNonce, bandNonce: bandNonce)
            let out = Command.build(1, 26) { w in
                w.message(3) { a in a.message(31) { $0.bytes(1, self.bandNonce); $0.bytes(2, hmac) } }
            }
            pendingKeys = k
            return [out]
        case (1, 27):
            guard let k = pendingKeys,
                  command.root.bytes(at: [3, 32, 1]) == k.phoneConfirmation(phoneNonce: phoneNonce, bandNonce: bandNonce)
            else { return [] }
            let out = Command.build(1, 27)
            keys = k
            return [out]
        case (2, 2):
            return [Command.build(2, 2) { w in w.message(4) { s in s.message(3) {
                $0.string(1, "SN"); $0.string(2, "3.2.7"); $0.string(4, "M2459B1")
            } } }]
        case (2, 1):
            return [Command.build(2, 1) { w in w.message(4) { s in s.message(2) { b in b.message(1) { $0.varint(1, UInt64(52)) } } } }]
        case (4, 4):
            let status = installStatus
            return [Command.build(4, 4) { w in w.message(6) { $0.varint(5, status) } }]
        case (22, 0):
            return [Command.build(22, 0) { w in w.message(24) { d in d.message(2) { m in
                m.varint(2, UInt64(0)); m.varint(4, UInt64(0)); m.varint(5, UInt64(4096))
            } } }]
        case (4, 1):
            return [Command.build(4, 1) { w in w.message(6) { $0.varint(4, UInt64(0)) } }]
        default:
            return []
        }
    }

    private var pendingKeys: SessionKeys?
}

final class SessionTests: XCTestCase {
    let authKey = Array<UInt8>(0x00...0x0F)

    private func makeSession(_ band: MockBand) -> BandSession {
        var configuration = BandSession.Configuration()
        configuration.cumulativeAckDelay = .milliseconds(50)
        configuration.commandTimeout = .seconds(3)
        let session = BandSession(transport: band, configuration: configuration)
        band.session = session
        return session
    }

    private func makeInstaller() -> WatchfaceInstaller {
        var installer = WatchfaceInstaller()
        installer.pauseAfterAuth = .zero
        installer.pauseBeforeInstall = .zero
        installer.pauseBeforeActivation = .zero
        installer.waitForBandRequests = .zero
        return installer
    }

    func testFullInstallFlow() async throws {
        let band = MockBand(authKey: authKey)
        let session = makeSession(band)
        var bytes = FaceFileTests.makeFace()
        bytes += (0..<9_000).map { UInt8(truncatingIfNeeded: $0) }
        let face = try FaceFile(bytes: bytes)

        try await makeInstaller().install(face, authKey: authKey, session: session)

        XCTAssertEqual(band.commandsReceived, ["1/26", "1/27", "2/2", "2/1", "4/4", "22/0", "4/1"])
        // Перед 4/1 — сукупне підтвердження шести відповідей, перед закриттям — відповіді на 4/1.
        XCTAssertEqual(band.acksReceived, [5, 6])
        // Номери кадрів даних телефону йдуть підряд, включно зі шматками файлу.
        XCTAssertEqual(band.phoneSequences, Array(0..<UInt8(band.phoneSequences.count)))

        let stream = band.receivedParts.flatMap { $0.dropFirst(4) }
        XCTAssertEqual(stream, FileTransfer.stream(file: face.data, md5: face.md5))
        let state = await session.state
        XCTAssertEqual(state, .closed)
    }

    func testAlreadyInstalledSkipsUpload() async throws {
        let band = MockBand(authKey: authKey)
        band.installStatus = 2
        let session = makeSession(band)
        let face = try FaceFile(bytes: FaceFileTests.makeFace())
        try await makeInstaller().install(face, authKey: authKey, session: session)
        XCTAssertEqual(band.commandsReceived, ["1/26", "1/27", "2/2", "2/1", "4/4", "4/1"])
        XCTAssertTrue(band.receivedParts.isEmpty)
    }

    func testWrongAuthKeyFails() async throws {
        let band = MockBand(authKey: authKey)
        let session = makeSession(band)
        try await session.open()
        do {
            try await session.authenticate(authKey: [UInt8](repeating: 0xEE, count: 16))
            XCTFail("expected mismatch")
        } catch {
            XCTAssertEqual(error as? BandError, .authKeyMismatch)
        }
        await session.close()
    }
}
