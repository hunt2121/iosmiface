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
        /// Перед повторним відкриттям закривати чужу сесію. Небезпечно, якщо з браслетом
        /// працює інший застосунок на цьому телефоні (Mi Fitness): його сесія ламається.
        public var closeOtherSessionOnRetry = true
        /// Запити браслета («тип/підтип»), на які відповідати порожньою командою того самого типу.
        /// Браслет надсилає їх застосунку-компаньйону (погода тощо) і без відповіді може зависнути.
        public var emptyReplies: Set<String> = []
        /// Підтверджувати кожен кадр браслета одразу, як офіційний застосунок (видно в записі HCI).
        /// false — стара поведінка: одне сукупне підтвердження, коли вікно браслета заповнене.
        public var ackEveryFrame = false
        /// Параметри відкриття сесії (TLV «ключ → значення»); nil — стандартні (версія, кадр, вікно, тайм-аут).
        public var openParameters: [(key: UInt8, value: [UInt8])]?
        /// Скільки частин файлу може бути в дорозі без підтвердження браслета.
        /// Band 10 підтверджує кожні 6 кадрів; більше 12 у дорозі він може загубити.
        public var fileWindow = 12
        /// Якщо браслет стільки часу не підтверджує частини файлу — надсилаємо їх повторно.
        public var fileAckTimeout: Duration = .seconds(3)
        public var fileResendAttempts = 3
        /// Скільки чекати підтверджень частин файлу, якщо браслет тим часом обслуговує інший застосунок.
        public var otherAppPatience: Duration = .seconds(120)
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

    private var parser = FrameParser()
    private var phoneSequence: UInt8 = 0
    private var expectedBandSequence: UInt8?
    private var lastBandSequence: UInt8?
    private var unacknowledged = 0
    private var ackScheduled = false
    private var keys: SessionKeys?
    /// Надіслані частини файлу, яких браслет ще не підтвердив (у порядку надсилання).
    private var unackedFileFrames: [(sequence: UInt8, bytes: [UInt8])] = []
    private var ackWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]
    /// Команди браслета, яких ніхто не чекав (від початку передачі файлу), — для `waitFor`.
    private var unsolicitedSeen: Set<String> = []
    /// Статус із 4/5 (6.7.2), який браслет надсилає після прийому файлу; nil — ще не надсилав.
    public private(set) var installStatus: UInt64?
    /// Останній момент, коли браслет явно працював з іншим застосунком на телефоні (Mi Fitness):
    /// відповідь на сесію, якої ми не запитували, або підтвердження кадру, якого ми не надсилали.
    public private(set) var otherAppSeenAt: ContinuousClock.Instant?

    private func noteOtherApp(_ reason: String) {
        if otherAppSeenAt == nil { log("other app on the band: \(reason)") }
        otherAppSeenAt = .now
    }

    private var otherAppActiveRecently: Bool {
        guard let seen = otherAppSeenAt else { return false }
        return ContinuousClock.now - seen < configuration.otherAppPatience
    }

    /// 4/5 зі статусом 3 — циферблат прийнято; 1 бачили, коли браслет перервав прийом.
    public static let installedStatus: UInt64 = 3
    private var waiters: [UUID: Waiter] = [:]
    private var sessionWaiter: (code: UInt8, continuation: CheckedContinuation<SessionControl, Error>)?

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
            if attempt > 1 && configuration.closeOtherSessionOnRetry {
                // Сесію може тримати Mi Fitness: спершу просимо закрити.
                log("session: retry \(attempt), sending close first")
                try await transport.write(Frame(type: .session, sequence: 0, payload: SessionControl.closeRequest.payload).encoded())
                // Даємо браслету закрити стару сесію, перш ніж просити нову.
                try await Task.sleep(for: configuration.sessionRetryPause)
            }
            resetCounters()
            do {
                _ = try await sessionExchange(
                    configuration.openParameters.map { SessionControl(code: .openRequest, parameters: $0) }
                        ?? SessionControl.openRequest,
                    expecting: SessionControl.Code.openResponse.rawValue,
                    timeout: configuration.sessionOpenTimeout
                )
                state = .open
                log("session: open")
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
            // Із заповненим вікном браслет не відповідає на закриття і потім не відкриває нову сесію
            await acknowledgeReceived()
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
        resumeAckWaiters(false)
        for id in eventWaiters.keys { resumeEventWaiter(id, nil) }
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
        unackedFileFrames.removeAll()
        resumeAckWaiters(false)
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
    /// `phoneInfo` — власні дані про телефон для кроку 3 (protobuf до шифрування); nil — стандартні.
    public func authenticate(authKey: [UInt8], phoneModel: String = "iPhone", region: String = "UK",
                             phoneInfo: [UInt8]? = nil) async throws {
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

        let info = sessionKeys.encryptPhoneInfo(phoneInfo ?? Command.phoneInfo(model: phoneModel, region: region))
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

    private func writeData(_ packet: DataPacket, trackAck: Bool = false) async throws {
        let frame = Frame(type: .data, sequence: phoneSequence, payload: packet.payload)
        let bytes = frame.encoded()
        if trackAck { unackedFileFrames.append((sequence: phoneSequence, bytes: bytes)) }
        phoneSequence &+= 1
        try await transport.write(bytes)
    }

    // MARK: - Файл

    /// Надсилає частини файлу каналом 2 відкритим текстом. Браслет підтверджує їх сам.
    public func sendFileParts(_ parts: [[UInt8]], progress: (@Sendable (Int, Int) -> Void)? = nil) async throws {
        guard state == .authenticated else { throw BandError.notAuthenticated }
        log("file: sending \(parts.count) parts")
        unackedFileFrames.removeAll()
        unsolicitedSeen.removeAll()
        installStatus = nil
        for (index, part) in parts.enumerated() {
            try Task.checkCancellation()
            // Не випереджаємо браслет більше ніж на вікно: інакше він губить частини
            try await waitForFileAcks(below: max(configuration.fileWindow, 1))
            try await writeData(DataPacket(channel: .file, opcode: .plain, body: part), trackAck: true)
            progress?(index + 1, parts.count)
        }
        log("file: all parts sent, waiting for the band to confirm")
        // Свої підтвердження й сигнал «циферблат готовий» (4/5) браслет притримує,
        // поки його вікно заповнене, — звільняємо його одразу
        await acknowledgeReceived()
        // Браслет має підтвердити всі частини, перш ніж активувати циферблат
        try await waitForFileAcks(below: 1)
        log("file: all parts confirmed")
    }

    /// Чекає, поки непідтверджених частин стане менше `limit`.
    /// Якщо підтверджень немає `fileAckTimeout`, надсилає непідтверджені частини повторно.
    private func waitForFileAcks(below limit: Int) async throws {
        var resends = 0
        while unackedFileFrames.count >= limit {
            // Браслет сам повідомив, що прийом перервано, — далі надсилати немає сенсу
            if let status = installStatus, status != Self.installedStatus {
                throw BandError.installAborted(status: status)
            }
            if await waitForBandAck(timeout: configuration.fileAckTimeout) {
                resends = 0
                continue
            }
            // Поки браслет зайнятий іншим застосунком (Mi Fitness синхронізується), спроби не рахуємо
            if !otherAppActiveRecently { resends += 1 }
            guard resends <= configuration.fileResendAttempts, let first = unackedFileFrames.first else {
                throw BandError.timeout
            }
            log("file: no ack, resending \(unackedFileFrames.count) parts from \(first.sequence)")
            for frame in unackedFileFrames { try await transport.write(frame.bytes) }
        }
    }

    /// true — прийшло підтвердження від браслета, false — минув тайм-аут.
    private func waitForBandAck(timeout: Duration) async -> Bool {
        let id = UUID()
        return await withCheckedContinuation { continuation in
            ackWaiters[id] = continuation
            Task {
                try? await Task.sleep(for: timeout)
                await self.resumeAckWaiter(id, false)
            }
        }
    }

    private func resumeAckWaiter(_ id: UUID, _ value: Bool) {
        ackWaiters.removeValue(forKey: id)?.resume(returning: value)
    }

    private func resumeAckWaiters(_ value: Bool) {
        let all = ackWaiters
        ackWaiters.removeAll()
        for waiter in all.values { waiter.resume(returning: value) }
    }

    /// Підтвердження браслета сукупне: номер N означає, що отримано всі кадри до N включно.
    private func handleBandAck(_ sequence: UInt8) {
        let before = unackedFileFrames.count
        unackedFileFrames.removeAll { sequence &- $0.sequence < 128 }
        if unackedFileFrames.count != before { resumeAckWaiters(true) }
    }

    // MARK: - Вхідні кадри

    private func process(_ bytes: [UInt8]) {
        for frame in parser.append(bytes) {
            switch frame.type {
            case .session:
                handleSession(frame)
            case .ack:
                log("← ack \(frame.sequence)")
                // Номер, якого ми ще не надсилали, — підтвердження чужого кадру
                if state != .opening, frame.sequence &- phoneSequence < 128 {
                    noteOtherApp("ack \(frame.sequence), our next frame is \(phoneSequence)")
                }
                handleBandAck(frame.sequence)
            case .data:
                handleData(frame)
            }
        }
    }

    private func handleSession(_ frame: Frame) {
        guard let control = SessionControl(payload: frame.payload) else { return }
        log("← session code \(control.code)")
        guard let waiter = sessionWaiter, waiter.code == control.code else {
            noteOtherApp("session code \(control.code) without our request")
            return
        }
        sessionWaiter = nil
        waiter.continuation.resume(returning: control)
    }

    private func handleData(_ frame: Frame) {
        // Повтори (номер, що вже був або старший за пів кола назад) відкидаємо.
        // Пропуск номерів (втрачений кадр) не зупиняє сесію: приймаємо новіший кадр.
        if let expected = expectedBandSequence, frame.sequence &- expected >= 128 {
            log("← data \(frame.sequence) dropped (expected \(expected)), flags \(frame.flags)")
            // Повтор означає, що наше підтвердження загубилося
            if configuration.ackEveryFrame { sendAckNow(frame.sequence) }
            return
        }
        expectedBandSequence = frame.sequence &+ 1
        lastBandSequence = frame.sequence
        if configuration.ackEveryFrame {
            sendAckNow(frame.sequence)
        } else {
            unacknowledged += 1
        }

        defer { scheduleCumulativeAck() }

        guard let packet = DataPacket(payload: frame.payload) else { return }
        // Сирий заголовок — щоб бачити прапорці й канал кожного кадру браслета
        log("← frame seq \(frame.sequence) flags \(frame.flags) channel \(frame.payload[0]) opcode \(packet.opcode)")
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
            return
        }
        unsolicitedSeen.insert(command.name)
        if command.type == Command.Kind.watchface && command.subtype == 5 {
            installStatus = command.root.varint(at: [6, 7, 2])
            log("install status \(installStatus.map { "\($0)" } ?? "?")")
            resumeAckWaiters(true) // розбудити передачу файлу, щоб вона перевірила статус
        }
        for (id, waiter) in eventWaiters where waiter.name == command.name { resumeEventWaiter(id, command) }
        if configuration.emptyReplies.contains(command.name) {
            // Запит браслета до застосунку: відповідаємо порожньою командою того самого типу
            let reply = Command.build(command.type, command.subtype)
            Task { await self.sendEmptyReply(reply, name: command.name) }
        }
    }

    /// Чекає, поки браслет сам надішле команду «тип/підтип» (або вже надіслав після початку
    /// передачі файлу). true — дочекалися, false — минув тайм-аут.
    public func waitFor(_ type: UInt64, _ subtype: UInt64, timeout: Duration) async -> Bool {
        if unsolicitedSeen.contains("\(type)/\(subtype)") { return true }
        let id = UUID()
        let result: Command? = await withCheckedContinuation { (continuation: CheckedContinuation<Command?, Never>) in
            eventWaiters[id] = (name: "\(type)/\(subtype)", continuation: continuation)
            Task {
                try? await Task.sleep(for: timeout)
                await self.resumeEventWaiter(id, nil)
            }
        }
        return result != nil
    }

    private var eventWaiters: [UUID: (name: String, continuation: CheckedContinuation<Command?, Never>)] = [:]

    private func resumeEventWaiter(_ id: UUID, _ command: Command?) {
        eventWaiters.removeValue(forKey: id)?.continuation.resume(returning: command)
    }

    private func sendEmptyReply(_ body: [UInt8], name: String) async {
        guard let keys, state == .authenticated else { return }
        log("→ empty reply \(name)")
        try? await writeData(DataPacket(channel: .protobuf, opcode: .encrypted, body: keys.encryptCommand(body)))
    }

    private func sendAckNow(_ sequence: UInt8) {
        let bytes = Frame.ack(sequence).encoded()
        log("→ ack \(sequence)")
        Task { try? await self.transport.write(bytes) }
    }

    /// Одне сукупне підтвердження всіх уже отриманих кадрів браслета (якщо такі є).
    /// Перед важливою командою: браслет із заповненим вікном може не прийняти її.
    public func acknowledgeReceived() async {
        guard unacknowledged > 0, let sequence = lastBandSequence else { return }
        unacknowledged = 0
        log("→ ack \(sequence) (before command)")
        try? await transport.write(Frame.ack(sequence).encoded())
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
