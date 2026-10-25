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

    /// Відповідь 4/1: 6.4 = 1 — активовано, 0 — браслет відмовив (бачили після перерваного прийому).
    func activateWatchface(id: String, timeout: Duration = .seconds(30)) async throws {
        let response = try await command(Command.activateWatchface(id: id), timeout: timeout)
        if let result = response.root.varint(at: [6, 4]), result != 1 { throw BandError.activationFailed }
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
    /// Власні дані про телефон для автентифікації (protobuf); nil — стандартні.
    public var phoneInfo: [UInt8]?
    /// Команди (тіла protobuf), які надіслати одразу після автентифікації; відповіді не обов'язкові.
    public var commandsAfterAuth: [[UInt8]] = []
    /// Паузи, перевірені на Band 10 (чи вони обов'язкові — не перевірялося).
    public var pauseAfterAuth: Duration = .milliseconds(1500)
    public var pauseBeforeInstall: Duration = .milliseconds(1500)
    /// Найдовше очікування після передачі файлу: браслет перевіряє циферблат і повідомляє 4/5.
    public var pauseBeforeActivation: Duration = .milliseconds(1500)
    /// Скільки чекати відповідь на одну спробу активації (4/1).
    public var activationTimeout: Duration = .seconds(5)
    /// Скільки після активації чекати запити браслета до компаньйона (останній — погода 10/3).
    public var waitForBandRequests: Duration = .seconds(2)
    /// false — лише передати файл, без 4/1: циферблат користувач вибирає на браслеті.
    /// Після 4/1 браслет надсилає компаньйону запити (2/42, 17/7, 10/3) і перестає приймати кадри.
    public var activateAfterInstall = true
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
            try await session.authenticate(authKey: authKey, phoneModel: phoneModel, region: region, phoneInfo: phoneInfo)
            for body in commandsAfterAuth {
                _ = try? await session.command(body, timeout: .seconds(3))
            }

            // 2/2 і 2/1 — як офіційний застосунок; відповіді не потрібні
            try await Task.sleep(for: pauseAfterAuth)
            _ = try? await session.command(Command.deviceInfoRequest())
            _ = try? await session.command(Command.batteryRequest())
            try await Task.sleep(for: pauseBeforeInstall)

            let alreadyInstalled = try await requestInstall(face, session: session, onPhase: onPhase)
            if !alreadyInstalled {
                try await upload(face, session: session, onPhase: onPhase)
            }

            guard activateAfterInstall else {
                if !alreadyInstalled { try await confirmInstalled(session: session) }
                onPhase?(.closing)
                await session.close()
                onPhase?(.done(alreadyInstalled: alreadyInstalled))
                return
            }

            onPhase?(.activating)
            try await activate(face, session: session, afterUpload: !alreadyInstalled)

            // Після активації браслет надсилає запити (2/42, 17/7, погода 10/3). Якщо закрити сесію
            // раніше, вони лишаються в черзі, і в наступній сесії браслет на них зависає.
            onPhase?(.closing)
            if await session.waitFor(10, 3, timeout: waitForBandRequests) {
                try? await Task.sleep(for: .milliseconds(300)) // встигнути відповісти на запити
            }
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

    /// Без активації: чекаємо 4/5 і перевіряємо, що браслет прийняв циферблат.
    private func confirmInstalled(session: BandSession) async throws {
        _ = await session.waitFor(Command.Kind.watchface, 5, timeout: pauseBeforeActivation)
        if let status = await session.installStatus, status != BandSession.installedStatus {
            throw BandError.installAborted(status: status)
        }
    }

    /// Крок 4 (4/1). Перед кожною спробою підтверджуємо все, що надіслав браслет.
    private func activate(_ face: FaceFile, session: BandSession, afterUpload: Bool) async throws {
        // Браслет повідомляє 4/5, щойно циферблат готовий; без нього чекаємо не довше паузи
        if afterUpload {
            _ = await session.waitFor(Command.Kind.watchface, 5, timeout: pauseBeforeActivation)
            if let status = await session.installStatus, status != BandSession.installedStatus {
                throw BandError.installAborted(status: status)
            }
        }
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
