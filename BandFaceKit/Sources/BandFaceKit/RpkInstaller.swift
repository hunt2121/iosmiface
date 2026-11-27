// SPDX-License-Identifier: MIT
import Foundation

extension Command {
    public static func rpkListRequest() -> [UInt8] { build(20, 0) }
    public static func rpkInstallRequest(id: String, versionCode: UInt32, size: Int) -> [UInt8] {
        build(20, 1) { w in w.message(22) { r in r.message(2) {
            $0.string(1, id); $0.varint(2, UInt64(versionCode)); $0.varint(3, UInt64(size))
        } } }
    }
    public static func rpkDeleteRequest(id: String, sha: [UInt8]) -> [UInt8] {
        build(20, 3) { w in w.message(22) { r in r.message(5) {
            $0.string(1, id); $0.bytes(2, sha)
        } } }
    }
}

public struct RpkInfo: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    /// Opaque bytes returned by the device, required verbatim for deletion.
    public let sha: [UInt8]

    static func list(from command: Command) throws -> [RpkInfo] {
        try checkStatus(command)
        guard command.matches(20, 0), let list = command.root.message(at: [22, 1]) else {
            throw RpkError.unconfirmed("Браслет не вернул список RPK-приложений")
        }
        return try list.all(1).map { value in
            guard case .lengthDelimited(let bytes) = value,
                  let message = try? ProtoMessage(bytes), let id = message.string(1), !id.isEmpty else {
                throw RpkError.unconfirmed("Некорректная запись в списке RPK")
            }
            return RpkInfo(id: id, name: message.string(5) ?? id, sha: message.bytes(2) ?? [])
        }
    }
}

private func checkStatus(_ command: Command) throws {
    if let status = command.status, status != 0 {
        throw RpkError.rejected("Браслет отклонил команду \(command.name): \(status)")
    }
}

protocol RpkCommandSession: Sendable {
    func command(_ body: [UInt8], timeout: Duration?) async throws -> Command
    func sendCommandWithoutReply(_ body: [UInt8]) async throws
    func sendFileParts(_ parts: [[UInt8]], progress: (@Sendable (Int, Int) -> Void)?) async throws
}
extension BandSession: RpkCommandSession {}

/// Operations on an already authenticated session, isolated for protocol tests.
struct RpkOperations {
    let session: any RpkCommandSession
    var verificationAttempts = 12
    var verificationDelay: Duration = .milliseconds(500)

    func list() async throws -> [RpkInfo] {
        try RpkInfo.list(from: await session.command(Command.rpkListRequest(), timeout: .seconds(5)))
    }

    func install(_ file: RpkFile, progress: (@Sendable (Int, Int) -> Void)?) async throws -> [RpkInfo] {
        // A pre-existing ID cannot prove a successful update. Require an explicit
        // deletion first instead of reporting an old installation as a new one.
        guard try await !list().contains(where: { $0.id == file.id }) else {
            throw RpkError.rejected("Приложение \(file.id) уже установлено. Для замены сначала удалите его в списке.")
        }
        let start = try await session.command(Command.rpkInstallRequest(id: file.id, versionCode: file.versionCode, size: file.size), timeout: nil)
        try checkStatus(start)
        guard let status = start.root.varint(at: [22, 3, 1]) else {
            throw RpkError.unconfirmed("В ответе нет статуса установки RPK")
        }
        guard status == 0 else { throw RpkError.rejected("Браслет отклонил RPK: код \(status)") }
        let md5 = file.md5
        let upload = try await session.command(Command.uploadRequest(type: 0x40, md5: md5, size: file.size), timeout: nil)
        try checkStatus(upload)
        guard let ack = upload.root.message(at: [24, 2]), let errno = ack.varint(2), errno == 0 else {
            throw RpkError.rejected("Браслет не разрешил передачу RPK")
        }
        if let echoed = ack.bytes(1), echoed != md5 { throw RpkError.unconfirmed("MD5 ответа не совпадает с RPK") }
        let resume = ack.varint(4) ?? 0, chunk = ack.varint(5) ?? 2048
        guard resume <= UInt64(file.size), chunk > 4, chunk <= 64000 else {
            throw RpkError.unconfirmed("Некорректные параметры передачи RPK")
        }
        let remaining = file.size - Int(resume) + 26, payloadSize = Int(chunk) - 4
        guard (remaining + payloadSize - 1) / payloadSize <= 65535 else {
            throw RpkError.rejected("Слишком много частей RPK для размера блока браслета")
        }
        let parts = FileTransfer.parts(file: file.data, md5: md5, resumePosition: Int(resume), chunkSize: Int(chunk), type: 0x40)
        try await session.sendFileParts(parts, progress: progress)
        // 20/2 notification alone is not proof. Query the device until the newly
        // installed package appears. This also tolerates a lost notification.
        return try await verify(id: file.id, present: true)
    }

    func delete(_ selected: RpkInfo) async throws -> [RpkInfo] {
        let current = try await list()
        guard let app = current.first(where: { $0.id == selected.id }) else { return current }
        guard !app.sha.isEmpty else { throw RpkError.rejected("Браслет не вернул SHA для удаления этого приложения") }
        // The device does not reply to 20/3. Use the freshest SHA, then verify list.
        try await session.sendCommandWithoutReply(Command.rpkDeleteRequest(id: app.id, sha: app.sha))
        return try await verify(id: app.id, present: false)
    }

    private func verify(id: String, present: Bool) async throws -> [RpkInfo] {
        for attempt in 0..<verificationAttempts {
            try Task.checkCancellation()
            if attempt > 0 { try await Task.sleep(for: verificationDelay) }
            let apps = try await list()
            if apps.contains(where: { $0.id == id }) == present { return apps }
        }
        throw RpkError.unconfirmed(present ? "Файл передан, но установка RPK не подтверждена списком браслета" : "Удаление RPK не подтверждено: приложение осталось в списке")
    }
}

public struct RpkInstaller: Sendable {
    public var phoneInfo: [UInt8]?
    public var commandsAfterAuth: [[UInt8]] = []
    public init() {}

    private func run<T>(authKey: [UInt8], session: BandSession,
                        operation: (RpkOperations) async throws -> T) async throws -> T {
        do {
            try await session.open()
            try await session.authenticate(authKey: authKey, phoneInfo: phoneInfo)
            for command in commandsAfterAuth { _ = try? await session.command(command, timeout: .seconds(3)) }
            try await Task.sleep(for: .milliseconds(500))
            let result = try await operation(RpkOperations(session: session))
            await session.close()
            return result
        } catch { await session.close(); throw error }
    }

    public func list(authKey: [UInt8], session: BandSession) async throws -> [RpkInfo] {
        try await run(authKey: authKey, session: session) { try await $0.list() }
    }
    public func install(_ file: RpkFile, authKey: [UInt8], session: BandSession,
                        progress: (@Sendable (Int, Int) -> Void)? = nil) async throws -> [RpkInfo] {
        try await run(authKey: authKey, session: session) { try await $0.install(file, progress: progress) }
    }
    public func delete(_ app: RpkInfo, authKey: [UInt8], session: BandSession) async throws -> [RpkInfo] {
        try await run(authKey: authKey, session: session) { try await $0.delete(app) }
    }
}
