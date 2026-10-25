// SPDX-License-Identifier: MIT
//
// Високорівневі операції над відкритою й автентифікованою сесією.

import Foundation

extension BandSession {
    func watchfaces() async throws -> [WatchfaceEntry] {
        WatchfaceEntry.list(from: try await command(Command.watchfaceListRequest()))
    }

    func deleteWatchface(id: String) async throws {
        _ = try await command(Command.deleteWatchface(id: id))
    }

    func activateWatchface(id: String, timeout: Duration = .seconds(30)) async throws {
        _ = try await command(Command.activateWatchface(id: id), timeout: timeout)
    }
}

public enum InstallPhase: Sendable, Equatable {
    case connecting
    case authenticating
    case requestingInstall
    case removingOldVersion
    case uploading(sent: Int, total: Int)
    case activating
    case closing
    case done(alreadyInstalled: Bool)
}

/// Повний сценарій встановлення: відкриття сесії → автентифікація → 2/2, 2/1 → 4/4 → 22/0 → файл → 4/1 → закриття.
public struct WatchfaceInstaller: Sendable {
    public var phoneModel = "iPhone"
    public var region = "UK"
    /// Паузи, перевірені на Band 10 (чи вони обов'язкові — не перевірялося).
    public var pauseAfterAuth: Duration = .milliseconds(1500)
    public var pauseBeforeInstall: Duration = .milliseconds(1500)
    /// Пауза після передачі файлу: браслет перевіряє й розпаковує циферблат.
    public var pauseBeforeActivation: Duration = .milliseconds(1500)
    /// Скільки чекати відповідь на одну спробу активації (4/1).
    public var activationTimeout: Duration = .seconds(5)
    /// Скільки разів надсилати 4/1, якщо браслет не відповідає.
    public var activationAttempts = 2

    public init() {}

    /// Встановлює циферблат. Сесію закриває завжди, навіть після помилки.
    public func install(
        _ face: FaceFile,
        authKey: [UInt8],
        session: BandSession,
        onPhase: (@Sendable (InstallPhase) -> Void)? = nil
    ) async throws {
        onPhase?(.connecting)
        try await session.open()
        do {
            onPhase?(.authenticating)
            try await session.authenticate(authKey: authKey, phoneModel: phoneModel, region: region)

            // 2/2 і 2/1 — як офіційний застосунок; відповіді не потрібні
            try await Task.sleep(for: pauseAfterAuth)
            _ = try? await session.command(Command.deviceInfoRequest())
            _ = try? await session.command(Command.batteryRequest())
            try await Task.sleep(for: pauseBeforeInstall)

            let alreadyInstalled = try await requestInstall(face, session: session, onPhase: onPhase)
            if !alreadyInstalled {
                try await upload(face, session: session, onPhase: onPhase)
            }

            onPhase?(.activating)
            try await activate(face, session: session, afterUpload: !alreadyInstalled)

            onPhase?(.closing)
            await session.close()
            onPhase?(.done(alreadyInstalled: alreadyInstalled))
        } catch {
            await session.close()
            throw error
        }
    }

    /// Крок 1 (4/4). Повертає true, якщо циферблат уже є на браслеті.
    private func requestInstall(_ face: FaceFile, session: BandSession, onPhase: (@Sendable (InstallPhase) -> Void)?) async throws -> Bool {
        onPhase?(.requestingInstall)
        var removedOld = false
        while true {
            let response = try await session.command(Command.installRequest(id: face.id, size: face.size))
            let status = response.root.varint(at: [6, 5]) ?? 0
            switch status {
            case 0:
                return false
            case 2:
                return true
            default:
                // Резервний шлях: неактивну стару версію з тим самим ID видаляємо і пробуємо ще раз.
                guard !removedOld else { throw BandError.installRejected(status: status) }
                let list = try await session.watchfaces()
                guard let old = list.first(where: { $0.id == face.id }), !old.isActive, old.canDelete else {
                    throw BandError.installRejected(status: status)
                }
                onPhase?(.removingOldVersion)
                try await session.deleteWatchface(id: face.id)
                removedOld = true
            }
        }
    }

    /// Крок 4 (4/1). Перед кожною спробою підтверджуємо все, що надіслав браслет.
    private func activate(_ face: FaceFile, session: BandSession, afterUpload: Bool) async throws {
        if afterUpload { try await Task.sleep(for: pauseBeforeActivation) }
        for attempt in 1...max(activationAttempts, 1) {
            await session.acknowledgeReceived()
            do {
                try await session.activateWatchface(id: face.id, timeout: activationTimeout)
                return
            } catch BandError.timeout where attempt < activationAttempts {
                continue
            }
        }
    }

    /// Кроки 2–3: 22/0 і передача файлу.
    private func upload(_ face: FaceFile, session: BandSession, onPhase: (@Sendable (InstallPhase) -> Void)?) async throws {
        let md5 = face.md5
        let response = UploadResponse(command: try await session.command(Command.uploadRequest(md5: md5, size: face.size)))
        guard response.status == 0 else { throw BandError.uploadRejected(status: response.status) }
        guard response.chunkSize > 4 else { throw BandError.malformedResponse("chunk size \(response.chunkSize)") }

        let parts = FileTransfer.parts(
            file: face.data,
            md5: md5,
            resumePosition: response.resumePosition,
            chunkSize: response.chunkSize
        )
        onPhase?(.uploading(sent: 0, total: parts.count))
        try await session.sendFileParts(parts) { sent, total in
            onPhase?(.uploading(sent: sent, total: total))
        }
    }
}
