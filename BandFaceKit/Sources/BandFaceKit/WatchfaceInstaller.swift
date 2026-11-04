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
    func activateWatchface(id: String, timeout: Duration) async throws {
        let response = try await command(Command.activateWatchface(id: id), timeout: timeout)
        if let result = response.root.varint(at: [6, 4]), result != 1 { throw BandError.activationFailed }
    }
}

/// Циферблат, який зараз є на браслеті.
public struct WatchfaceInfo: Sendable, Equatable {
    public var id: String
    public var isActive: Bool
    /// Браслет дозволяє видалити (вбудовані циферблати — ні).
    public var canDelete: Bool = true
    /// Назва з браслета (може бути відсутня)
    public var name: String? = nil
}

/// Стан батареї браслета (nil — браслет не повідомив)
public struct BandInfo: Sendable, Equatable {
    /// Заряд у відсотках
    public var battery: Int?
    /// Браслет зараз на зарядці
    public var charging: Bool?
    /// Коли браслет востаннє заряджали
    public var lastCharge: Date?
    public init(battery: Int? = nil, charging: Bool? = nil, lastCharge: Date? = nil) {
        self.battery = battery
        self.charging = charging
        self.lastCharge = lastCharge
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

/// Повний сценарій встановлення: відкриття сесії → автентифікація → 2/2, 2/1 → 4/4 → 22/0 → файл → закриття.
/// Прийнявши файл, браслет сам вмикає новий циферблат і повідомляє 4/5; команда 4/1 потрібна
/// лише тоді, коли такий циферблат уже був на браслеті, але неактивний.
public struct WatchfaceInstaller: Sendable {
    public var phoneModel = "iPhone"
    public var region = "UK"
    /// Власні дані про телефон для автентифікації (protobuf); nil — стандартні.
    public var phoneInfo: [UInt8]?
    /// Команди (тіла protobuf), які надіслати одразу після автентифікації; відповіді не обов'язкові.
    public var commandsAfterAuth: [[UInt8]] = []
    public var pauseAfterAuth: Duration = .milliseconds(500)
    public var pauseBeforeInstall: Duration = .milliseconds(300)
    /// Найдовше очікування 4/5 після передачі файлу.
    public var waitForInstallStatus: Duration = .milliseconds(1500)
    /// Скільки чекати відповідь на одну спробу активації (4/1).
    public var activationTimeout: Duration = .seconds(4)
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

            let check = try await requestInstall(face, session: session, onPhase: onPhase)
            switch check {
            case .needsUpload:
                try await upload(face, session: session, onPhase: onPhase)
                try await confirmInstalled(session: session)
            case .alreadyInstalled:
                onPhase?(.activating)
                try await activate(face, session: session)
            case .alreadyActive:
                break
            }

            onPhase?(.closing)
            await session.close()
            onPhase?(.done(alreadyInstalled: check != .needsUpload))
        } catch {
            await session.close()
            throw error
        }
    }

    /// Результат кроку 4/4: файл треба передати, циферблат уже є, або він уже є й активний.
    private enum InstallCheck { case needsUpload, alreadyInstalled, alreadyActive }

    private func requestInstall(_ face: FaceFile, session: BandSession, onPhase: (@Sendable (InstallPhase) -> Void)?) async throws -> InstallCheck {
        onPhase?(.requestingInstall)
        var removedOld = false
        while true {
            let response = try await session.command(Command.installRequest(id: face.id, size: face.size))
            let status = response.root.varint(at: [6, 5]) ?? 0
            switch status {
            case 0:
                return .needsUpload
            case 2:
                return .alreadyInstalled
            default:
                // Статус 5: циферблат з цим ID уже є. Активний — встановлювати нічого;
                // неактивну стару версію видаляємо і пробуємо ще раз.
                guard !removedOld else { throw BandError.installRejected(status: status) }
                let list = try await session.watchfaces()
                guard let old = list.first(where: { $0.id == face.id }) else {
                    throw BandError.installRejected(status: status)
                }
                if old.isActive { return .alreadyActive }
                guard old.canDelete else { throw BandError.installRejected(status: status) }
                onPhase?(.removingOldVersion)
                try await session.deleteWatchface(id: face.id)
                removedOld = true
            }
        }
    }

    /// Чекаємо 4/5 і перевіряємо, що браслет прийняв циферблат.
    private func confirmInstalled(session: BandSession) async throws {
        _ = await session.waitFor(Command.Kind.watchface, 5, timeout: waitForInstallStatus)
        if let status = await session.installStatus, status != BandSession.installedStatus {
            throw BandError.installAborted(status: status)
        }
    }

    /// 4/1 для циферблата, який уже був на браслеті.
    private func activate(_ face: FaceFile, session: BandSession) async throws {
        for attempt in 1...max(activationAttempts, 1) {
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

extension WatchfaceInstaller {
    /// Повертає циферблати, що зараз є на браслеті (команда 4/0). Сесію закриває завжди.
    public func listWatchfaces(authKey: [UInt8], session: BandSession) async throws -> [WatchfaceInfo] {
        try await session.open()
        do {
            try await session.authenticate(authKey: authKey, phoneModel: phoneModel, region: region, phoneInfo: phoneInfo)
            for body in commandsAfterAuth {
                _ = try? await session.command(body, timeout: .seconds(3))
            }
            try await Task.sleep(for: pauseAfterAuth)
            let list = try await session.watchfaces()
            await session.close()
            return list.map(WatchfaceInfo.init(entry:))
        } catch {
            await session.close()
            throw error
        }
    }

    /// Список циферблатів і стан батареї за одну сесію. Стан батареї необов'язковий:
    /// якщо браслет не відповів — nil. Сесію закриває завжди.
    public func bandState(authKey: [UInt8], session: BandSession) async throws -> (faces: [WatchfaceInfo], info: BandInfo) {
        try await session.open()
        do {
            try await session.authenticate(authKey: authKey, phoneModel: phoneModel, region: region, phoneInfo: phoneInfo)
            for body in commandsAfterAuth {
                _ = try? await session.command(body, timeout: .seconds(3))
            }
            try await Task.sleep(for: pauseAfterAuth)
            var info = BandInfo()
            // 2/1: System(4).power(2).battery(1): level(1), state(2: 1 — заряджається), lastCharge(3).timestamp(2)
            if let r = try? await session.command(Command.batteryRequest(), timeout: .seconds(2)),
               let battery = r.root.message(at: [4, 2, 1]) {
                if let level = battery.varint(1), level <= 100 { info.battery = Int(level) }
                if let state = battery.varint(2) { info.charging = state == 1 }
                if let seconds = battery.message(3)?.varint(2), seconds > 0 {
                    info.lastCharge = Date(timeIntervalSince1970: TimeInterval(seconds))
                }
            }
            let list = try await session.watchfaces()
            await session.close()
            return (list.map(WatchfaceInfo.init(entry:)), info)
        } catch {
            await session.close()
            throw error
        }
    }

    /// Робить циферблат активним (4/1) і повертає оновлений список. Сесію закриває завжди.
    public func activateWatchface(id: String, authKey: [UInt8], session: BandSession) async throws -> [WatchfaceInfo] {
        let timeout = activationTimeout
        return try await withSession(authKey: authKey, session: session) { s in
            try await s.activateWatchface(id: id, timeout: timeout)
            return try await s.watchfaces()
        }
    }

    /// Видаляє циферблат (4/2) і повертає оновлений список: за ним видно, чи браслет справді його видалив.
    /// Сесію закриває завжди.
    public func deleteWatchface(id: String, authKey: [UInt8], session: BandSession) async throws -> [WatchfaceInfo] {
        try await withSession(authKey: authKey, session: session) { s in
            // Відповідь на 4/2 не обов'язкова: результат перевіряємо новим списком
            _ = try? await s.command(Command.deleteWatchface(id: id), timeout: .seconds(4))
            return try await s.watchfaces()
        }
    }

    /// Відкриття, автентифікація, дія, закриття — як у `listWatchfaces`.
    private func withSession(
        authKey: [UInt8],
        session: BandSession,
        _ body: @Sendable (BandSession) async throws -> [WatchfaceEntry]
    ) async throws -> [WatchfaceInfo] {
        try await session.open()
        do {
            try await session.authenticate(authKey: authKey, phoneModel: phoneModel, region: region, phoneInfo: phoneInfo)
            for command in commandsAfterAuth {
                _ = try? await session.command(command, timeout: .seconds(3))
            }
            try await Task.sleep(for: pauseAfterAuth)
            let list = try await body(session)
            await session.close()
            return list.map(WatchfaceInfo.init(entry:))
        } catch {
            await session.close()
            throw error
        }
    }
}

extension WatchfaceInfo {
    init(entry: WatchfaceEntry) {
        self.init(id: entry.id, isActive: entry.isActive, canDelete: entry.canDelete, name: entry.name)
    }
}
