// SPDX-License-Identifier: MIT
//
// Сесія з браслетом поверх будь-якого транспорту: відкриття і закриття, автентифікація,
// шифрування команд, сукупні підтвердження і передача файлу.

import Foundation

/// Транспорт, що доставляє цілі кадри до браслета.
/// Реалізація сама ріже кадр на шматки за розміром запису без відповіді і стежить за керуванням потоком.
public protocol BandTransport: AnyObject, Sendable {
    func write(_ frame: [UInt8]) async throws
}

public actor BandSession {
    public struct Configuration: Sendable {
        /// Скільки непідтверджених кадрів браслет надсилає до паузи.
        public var bandWindow = 6
        /// Затримка перед сукупним підтвердженням після надсилання команди.
        public var cumulativeAckDelay: Duration = .milliseconds(500)
        public var sessionOpenTimeout: Duration = .seconds(4)
        public var sessionOpenAttempts = 3
        /// Пауза між закриттям старої сесії і повторним відкриттям.
        public var sessionRetryPause: Duration = .milliseconds(500)
        public var sessionCloseTimeout: Duration = .seconds(1)
        public var commandTimeout: Duration = .seconds(10)
        /// Журнал. Ключі й вміст команд автентифікації в нього не потрапляють.
        public var log: (@Sendable (String) -> Void)?

        public init() {}
    }

    public enum State: Sendable, Equatable {
        case idle, opening, open, authenticated, closed
    }

    private struct Waiter {
        let matches: @Sendable (Command) -> Bool
        let continuation: CheckedContinuation<Command, Error>
    }

    private let transport: BandTransport
    public let configuration: Configuration

    public private(set) var state: State = .idle
    public private(set) var bandSessionParameters: SessionControl?

    private var parser = FrameParser()
    private var phoneSequence: UInt8 = 0
    private var expectedBandSequence: UInt8?
    private var lastBandSequence: UInt8?
    private var unacknowledged = 0
    private var ackScheduled = false
    private var keys: SessionKeys?
    private var waiters: [UUID: Waiter] = [:]
    private var sessionWaiter: (code: UInt8, continuation: CheckedContinuation<SessionControl, Error>)?
    private var unsolicitedHandler: (@Sendable (Command) -> Void)?

    private let inputStream: AsyncStream<[UInt8]>
    private let inputContinuation: AsyncStream<[UInt8]>.Continuation
    private var pumpTask: Task<Void, Never>?

    public init(transport: BandTransport, configuration: Configuration = Configuration()) {
        self.transport = transport
        self.configuration = configuration
        let pair = AsyncStream.makeStream(of: [UInt8].self)
        inputStream = pair.stream
        inputContinuation = pair.continuation
    }

    deinit {
        inputContinuation.finish()
        pumpTask?.cancel()
    }

    /// Передайте сюди кожне сповіщення з характеристики RX — у порядку надходження.
    public nonisolated func receive(_ data: Data) {
        inputContinuation.yield([UInt8](data))
    }

    /// Команди, які браслет надсилає сам (погода, сповіщення тощо).
    public func setUnsolicitedHandler(_ handler: (@Sendable (Command) -> Void)?) {
        unsolicitedHandler = handler
    }

    private func log(_ message: @autoclosure () -> String) {
        configuration.log?(message())
    }

    private func startPumpIfNeeded() {
        guard pumpTask == nil else { return }
        let stream = inputStream
        pumpTask = Task { [weak self] in
            for await chunk in stream {
                guard let self else { return }
                await self.process(chunk)
            }
        }
    }

    // MARK: - Сесія

    public func open() async throws {
        startPumpIfNeeded()
        state = .opening
        for attempt in 1...max(configuration.sessionOpenAttempts, 1) {
            if attempt > 1 {
                // Сесію може тримати Mi Fitness: спершу просимо закрити.
                log("session: retry \(attempt), sending close first")
                try await transport.write(Frame(type: .session, sequence: 0, payload: SessionControl.closeRequest.payload).encoded())
                // Даємо браслету закрити стару сесію, перш ніж просити нову.
                try await Task.sleep(for: configuration.sessionRetryPause)
            }
            resetCounters()
            do {
                let response = try await sessionExchange(
                    SessionControl.openRequest,
                    expecting: SessionControl.Code.openResponse.rawValue,
                    timeout: configuration.sessionOpenTimeout
                )
                bandSessionParameters = response
                state = .open
                let version = response.version ?? "?"
                let maxFrame = response.maxFrameSize.map { String($0) } ?? "?"
                log("session: open, band version \(version), max frame \(maxFrame)")
                return
            } catch BandError.timeout {
                continue
            }
        }
        state = .idle
        throw BandError.sessionOpenFailed
    }

    /// Закриває сесію. Помилки ігнорує: браслет може вже не відповідати.
    public func close() async {
        failAllWaiters(BandError.cancelled)
        if state == .open || state == .authenticated || state == .opening {
            _ = try? await sessionExchange(
                SessionControl.closeRequest,
                expecting: SessionControl.Code.closeResponse.rawValue,
                timeout: configuration.sessionCloseTimeout
            )
        }
        keys = nil
        state = .closed
        log("session: closed")
    }

    /// Викликайте, коли BLE-з'єднання розірвалося.
    public func connectionLost() {
        failAllWaiters(BandError.disconnected)
        if let waiter = sessionWaiter {
            sessionWaiter = nil
            waiter.continuation.resume(throwing: BandError.disconnected)
        }
        keys = nil
        state = .closed
    }

    private func resetCounters() {
        parser.reset()
        phoneSequence = 0
        expectedBandSequence = nil
        lastBandSequence = nil
        unacknowledged = 0
        ackScheduled = false
        keys = nil
    }

    private func sessionExchange(_ control: SessionControl, expecting code: UInt8, timeout: Duration) async throws -> SessionControl {
        if let old = sessionWaiter {
            sessionWaiter = nil
            old.continuation.resume(throwing: BandError.cancelled)
        }
        return try await withCheckedThrowingContinuation { continuation in
            sessionWaiter = (code: code, continuation: continuation)
            let frame = Frame(type: .session, sequence: 0, payload: control.payload).encoded()
            Task {
                do {
                    try await self.transport.write(frame)
                } catch {
                    await self.failSessionWaiter(code: code, error: error)
                    return
                }
                try? await Task.sleep(for: timeout)
                await self.failSessionWaiter(code: code, error: BandError.timeout)
            }
        }
    }

    private func failSessionWaiter(code: UInt8, error: Error) {
        guard let waiter = sessionWaiter, waiter.code == code else { return }
        sessionWaiter = nil
        waiter.continuation.resume(throwing: error)
    }

    // MARK: - Автентифікація

    /// Автентифікація ключем браслета (16 байтів).
    public func authenticate(authKey: [UInt8], phoneModel: String = "iPhone", region: String = "UK") async throws {
        guard authKey.count == 16 else { throw BandError.invalidAuthKey }
        guard state == .open else { throw BandError.sessionNotOpen }

        let phoneNonce = randomBytes(16)
        log("auth: step 1")
        let step2 = try await request(
            Command.authPhoneNonce(phoneNonce),
            encrypted: false,
            redactLog: true
        ) { $0.matches(Command.Kind.auth, 26) }

        guard let bandNonce = step2.root.bytes(at: [3, 31, 1]), bandNonce.count == 16,
              let bandHMAC = step2.root.bytes(at: [3, 31, 2]), bandHMAC.count == 32
        else { throw BandError.malformedResponse("auth step 2") }

        let sessionKeys = SessionKeys(authKey: authKey, phoneNonce: phoneNonce, bandNonce: bandNonce)
        guard constantTimeEqual(sessionKeys.expectedBandHMAC(phoneNonce: phoneNonce, bandNonce: bandNonce), bandHMAC) else {
            throw BandError.authKeyMismatch
        }

        let info = sessionKeys.encryptPhoneInfo(Command.phoneInfo(model: phoneModel, region: region))
        let confirmation = sessionKeys.phoneConfirmation(phoneNonce: phoneNonce, bandNonce: bandNonce)
        log("auth: step 3")
        // Ключі потрібні вже зараз: браслет може одразу надіслати зашифровані команди.
        keys = sessionKeys
        do {
            _ = try await request(
                Command.authConfirm(confirmation: confirmation, encryptedPhoneInfo: info),
                encrypted: false,
                redactLog: true
            ) { $0.matches(Command.Kind.auth, 27, 5) }
        } catch {
            keys = nil
            throw error
        }
        state = .authenticated
        log("auth: done")
    }

    // MARK: - Команди

    /// Надсилає команду каналом 1 і чекає першу відповідь, що задовольняє `matches`.
    public func request(
        _ body: [UInt8],
        encrypted: Bool = true,
        timeout: Duration? = nil,
        redactLog: Bool = false,
        matches: @escaping @Sendable (Command) -> Bool
    ) async throws -> Command {
        if encrypted && keys == nil { throw BandError.notAuthenticated }
        let id = UUID()
        let timeout = timeout ?? configuration.commandTimeout
        return try await withCheckedThrowingContinuation { continuation in
            waiters[id] = Waiter(matches: matches, continuation: continuation)
            Task { await self.sendRegistered(id: id, body: body, encrypted: encrypted, timeout: timeout, redactLog: redactLog) }
        }
    }

    /// Зашифрована команда «тип/підтип», відповідь — той самий «тип/підтип».
    public func command(_ body: [UInt8], timeout: Duration? = nil) async throws -> Command {
        let header = try Command(body: body)
        let type = header.type, subtype = header.subtype
        return try await request(body, timeout: timeout) { $0.type == type && $0.subtype == subtype }
    }

    private func sendRegistered(id: UUID, body: [UInt8], encrypted: Bool, timeout: Duration, redactLog: Bool) async {
        guard waiters[id] != nil else { return }
        let header = (try? Command(body: body))?.name ?? "?"
        log("→ cmd \(header)" + (redactLog ? "" : " \(body.hexString)"))
        do {
            let payloadBody: [UInt8]
            if encrypted {
                guard let keys else { throw BandError.notAuthenticated }
                payloadBody = keys.encryptCommand(body)
            } else {
                payloadBody = body
            }
            try await writeData(DataPacket(channel: .protobuf, opcode: encrypted ? .encrypted : .plain, body: payloadBody))
        } catch {
            fail(id, error)
            return
        }
        scheduleCumulativeAck()
        Task {
            try? await Task.sleep(for: timeout)
            await self.fail(id, BandError.timeout)
        }
    }

    private func fail(_ id: UUID, _ error: Error) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(throwing: error)
    }

    private func failAllWaiters(_ error: Error) {
        let all = waiters
        waiters.removeAll()
        for waiter in all.values { waiter.continuation.resume(throwing: error) }
    }

    private func writeData(_ packet: DataPacket) async throws {
        let frame = Frame(type: .data, sequence: phoneSequence, payload: packet.payload)
        phoneSequence &+= 1
        try await transport.write(frame.encoded())
    }

    // MARK: - Файл

    /// Надсилає частини файлу каналом 2 відкритим текстом. Браслет підтверджує їх сам.
    public func sendFileParts(_ parts: [[UInt8]], progress: (@Sendable (Int, Int) -> Void)? = nil) async throws {
        guard state == .authenticated else { throw BandError.notAuthenticated }
        log("file: sending \(parts.count) parts")
        for (index, part) in parts.enumerated() {
            try Task.checkCancellation()
            try await writeData(DataPacket(channel: .file, opcode: .plain, body: part))
            progress?(index + 1, parts.count)
        }
    }

    // MARK: - Вхідні кадри

    private func process(_ bytes: [UInt8]) {
        for frame in parser.append(bytes) {
            switch frame.type {
            case .session:
                handleSession(frame)
            case .ack:
                log("← ack \(frame.sequence)")
            case .data:
                handleData(frame)
            }
        }
    }

    private func handleSession(_ frame: Frame) {
        guard let control = SessionControl(payload: frame.payload) else { return }
        log("← session code \(control.code)")
        guard let waiter = sessionWaiter, waiter.code == control.code else { return }
        sessionWaiter = nil
        waiter.continuation.resume(returning: control)
    }

    private func handleData(_ frame: Frame) {
        // Повтори (номер, що вже був або старший за пів кола назад) відкидаємо.
        // Пропуск номерів (втрачений кадр) не зупиняє сесію: приймаємо новіший кадр.
        if let expected = expectedBandSequence, frame.sequence &- expected >= 128 {
            log("← data \(frame.sequence) dropped (expected \(expected))")
            return
        }
        expectedBandSequence = frame.sequence &+ 1
        lastBandSequence = frame.sequence
        unacknowledged += 1

        defer { scheduleCumulativeAck() }

        guard let packet = DataPacket(payload: frame.payload) else { return }
        guard packet.channel == DataChannel.protobuf.rawValue else {
            log("← data \(frame.sequence) channel \(packet.channel), \(packet.body.count) bytes")
            return
        }

        let body: [UInt8]
        switch DataOpcode(rawValue: packet.opcode) {
        case .encrypted:
            guard let keys else {
                log("← data \(frame.sequence): encrypted, but no keys")
                return
            }
            body = keys.decryptCommand(packet.body)
        case .plain:
            body = packet.body
        case nil:
            log("← data \(frame.sequence): unknown opcode \(packet.opcode)")
            return
        }

        guard let command = try? Command(body: body) else {
            log("← data \(frame.sequence): undecodable command")
            return
        }
        let redact = command.type == Command.Kind.auth
        log("← cmd \(command.name) seq \(frame.sequence)" + (redact ? "" : " \(body.hexString)"))

        if let entry = waiters.first(where: { $0.value.matches(command) }) {
            waiters.removeValue(forKey: entry.key)
            entry.value.continuation.resume(returning: command)
        } else {
            unsolicitedHandler?(command)
        }
    }

    // MARK: - Сукупне підтвердження
    //
    // Band 10 не можна підтверджувати кожен кадр. Телефон мовчить, поки браслет не надіслав повне вікно
    // (6 кадрів) і телефон чекає ще одну відповідь; тоді ~0,5 с після команди — одне підтвердження
    // з номером останнього отриманого кадру.

    private func scheduleCumulativeAck() {
        guard !ackScheduled, !waiters.isEmpty, unacknowledged >= configuration.bandWindow else { return }
        ackScheduled = true
        let delay = configuration.cumulativeAckDelay
        Task {
            try? await Task.sleep(for: delay)
            await self.sendCumulativeAckIfNeeded()
        }
    }

    private func sendCumulativeAckIfNeeded() async {
        ackScheduled = false
        guard !waiters.isEmpty, unacknowledged >= configuration.bandWindow, let sequence = lastBandSequence else { return }
        unacknowledged = 0
        log("→ ack \(sequence) (cumulative)")
        try? await transport.write(Frame.ack(sequence).encoded())
    }
}
