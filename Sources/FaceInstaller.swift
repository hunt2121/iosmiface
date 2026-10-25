import Foundation
import UIKit
import BandFaceKit

/// Встановлення циферблата через BandFaceKit поверх уже підключеного браслета.
/// Одна операція — одна сесія: бібліотека відкриває, автентифікує й завжди закриває її сама.
@MainActor
final class FaceInstaller {
    private let ble: BLEManager

    init(ble: BLEManager) {
        self.ble = ble
    }

    /// Повертає текст для користувача; помилки — `BandError` з локалізованим описом.
    func install(_ face: FaceFile, authKey: [UInt8],
                 progress: @escaping (Double, String) -> Void) async throws -> String {
        try await installOnce(face, authKey: authKey, progress: progress)
    }

    private func installOnce(_ face: FaceFile, authKey: [UInt8],
                             progress: @escaping (Double, String) -> Void) async throws -> String {
        guard ble.connectedID != nil else { throw BandError.notConnected }
        guard ble.hasBandCharacteristics else { throw BandError.characteristicNotFound }
        guard authKey.count == 16 else { throw BandError.invalidAuthKey }

        let ble = self.ble
        var configuration = BandSession.Configuration()
        // Технічний журнал бібліотеки — лише в режимі «Детальний журнал»
        configuration.log = { text in DispatchQueue.main.async { ble.debug(text) } }
        // Чужу сесію не закриваємо і з'єднання не рвемо: це може зламати браслету зв'язок з Mi Fitness
        configuration.closeOtherSessionOnRetry = false
        configuration.sessionOpenAttempts = 2
        // Як Mi Fitness (за записом HCI): кожен кадр браслета підтверджуємо одразу
        configuration.ackEveryFrame = true
        let session = BandSession(transport: ble, configuration: configuration)

        ble.onData = { uuid, data in
            if uuid == BandGATT.rx { session.receive(data) }
        }
        ble.onDisconnect = { Task { await session.connectionLost() } }
        defer {
            ble.onData = nil
            ble.onDisconnect = nil
            ble.unsubscribe(from: BandGATT.rx)
        }

        progress(0, String(localized: "Відкриття сесії…"))
        guard await ble.subscribeRX() else { throw BandError.characteristicNotFound }

        var installer = WatchfaceInstaller()
        installer.phoneModel = UIDevice.current.model
        installer.region = Self.regionCode()
        // Відповіді 2/2 і 2/1 бібліотека вже дочекалася, тож довгі паузи не потрібні
        installer.pauseAfterAuth = .milliseconds(500)
        installer.pauseBeforeInstall = .milliseconds(300)
        installer.activationTimeout = .seconds(4)
        // Тест: без активації — після 4/1 браслет перестає приймати кадри й ламає зв'язок з Mi Fitness
        installer.activateAfterInstall = false

        let reporter = PhaseReporter(face: face, ble: ble, progress: progress)
        do {
            try await installer.install(face, authKey: authKey, session: session) { phase in
                reporter.record(phase)
                DispatchQueue.main.async { reporter.show(phase) }
            }
        } catch BandError.timeout where reporter.reachedActivation {
            // Файл уже на браслеті, але команду активації браслет не підтвердив
            ble.addLog(String(localized: "Браслет не підтвердив активацію"))
            throw InstallFailure(errorDescription: String(localized: "Циферблат передано, але браслет не підтвердив активацію. Виберіть його на браслеті вручну"))
        } catch BandError.timeout {
            // Кажемо, на якому саме етапі браслет замовк
            throw InstallFailure(errorDescription: String(localized: "Браслет не відповів (\(reporter.stage))"))
        }
        return reporter.alreadyInstalled
            ? String(localized: "Циферблат уже є на браслеті. Виберіть його на браслеті")
            : String(localized: "Циферблат передано. Виберіть його на браслеті")
    }

    private static func regionCode() -> String {
        let code = Locale.current.language.languageCode?.identifier.uppercased() ?? "EN"
        return code.count == 2 ? code : "EN"
    }
}

/// Перетворює етапи бібліотеки на прогрес і записи журналу.
/// `record` викликається одразу з потоку бібліотеки, `show` — на головному потоці
/// (через DispatchQueue.main, що зберігає порядок етапів).
private final class PhaseReporter: @unchecked Sendable {
    private let face: FaceFile
    private let ble: BLEManager
    private let progress: (Double, String) -> Void
    private let lock = NSLock()
    private var _reachedActivation = false
    private var _alreadyInstalled = false
    private var _stage = String(localized: "відкриття сесії")

    init(face: FaceFile, ble: BLEManager, progress: @escaping (Double, String) -> Void) {
        self.face = face
        self.ble = ble
        self.progress = progress
    }

    var reachedActivation: Bool { lock.withLock { _reachedActivation } }
    var alreadyInstalled: Bool { lock.withLock { _alreadyInstalled } }
    /// Назва поточного етапу для повідомлення про тайм-аут.
    var stage: String { lock.withLock { _stage } }

    func record(_ phase: InstallPhase) {
        lock.withLock {
            switch phase {
            case .authenticating: _stage = String(localized: "автентифікація")
            case .requestingInstall: _stage = String(localized: "запит на встановлення")
            case .removingOldVersion: _stage = String(localized: "видалення циферблата")
            case .uploading: _stage = String(localized: "передача даних")
            case .activating:
                _stage = String(localized: "активація циферблата")
                _reachedActivation = true
            case .done(let already): _alreadyInstalled = already
            case .connecting, .closing: break
            }
        }
    }

    func show(_ phase: InstallPhase) {
        switch phase {
        case .connecting:
            progress(0, String(localized: "Відкриття сесії…"))
        case .authenticating:
            progress(0, String(localized: "Автентифікація…"))
        case .requestingInstall:
            ble.addLog(String(localized: "Підключено до браслета"))
            ble.addLog(String(localized: "Встановлення \(face.id) (\(String(face.size / 1024)) КБ)…"))
            progress(0, String(localized: "Запит на встановлення…"))
        case .removingOldVersion:
            ble.addLog(String(localized: "Знайдено стару версію цього циферблата — замінюю"))
        case .uploading(let sent, let total):
            if sent == 0 { ble.addLog(String(localized: "Передача файлу (частин: \(String(total)))…")) }
            guard total > 0 else { return }
            progress(Double(sent) / Double(total), String(localized: "Передача \(String(sent))/\(String(total))"))
            if sent == total { ble.addLog(String(localized: "Файл передано")) }
        case .activating:
            progress(1, String(localized: "Активація…"))
        case .closing:
            break
        case .done(let already):
            if already { ble.addLog(String(localized: "Цей циферблат уже є на браслеті")) }
        }
    }
}

struct InstallFailure: LocalizedError {
    let errorDescription: String?
}

// MARK: - Тексти помилок бібліотеки

extension BandError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return String(localized: "Браслет не підключено")
        case .characteristicNotFound:
            return String(localized: "У браслета немає BLE-характеристик 0x5E/0x5F. Схоже, на цій прошивці обмін іде лише через Bluetooth Classic, який iOS не підтримує.")
        case .invalidAuthKey:
            return String(localized: "Auth key має бути 32 hex-символи (16 байт)")
        case .authKeyMismatch, .notAuthenticated:
            return String(localized: "Автентифікація не вдалася: перевірте auth key")
        case .sessionOpenFailed, .sessionNotOpen:
            return String(localized: "Браслет не відповів (\(String(localized: "відкриття сесії")))")
        case .timeout:
            return String(localized: "Браслет не відповів (\(String(localized: "передача даних")))")
        case .installRejected(let status):
            let why = String(localized: "статус \(String(status))") + ". "
                + String(localized: "Можливо, стара версія цього циферблата зараз активна (перемкніть інший), власних циферблатів забагато (ліміт ≈10) або файл не для Band 10")
            return String(localized: "Браслет відхилив операцію: \(why)")
        case .uploadRejected(let status):
            return String(localized: "Браслет відхилив операцію: \(String(localized: "несподівана відповідь на завантаження (\(String(status)))"))")
        case .installAborted(let status):
            return String(localized: "Браслет перервав прийом файлу (статус \(String(status))). Спробуйте ще раз")
        case .activationFailed:
            return String(localized: "Браслет не активував циферблат. Спробуйте встановити ще раз")
        case .malformedResponse, .malformedProtobuf:
            return String(localized: "Браслет відхилив операцію: \(String(localized: "некоректні параметри завантаження"))")
        case .invalidFaceFile(let why):
            let reason: String
            switch why {
            case "file too short": reason = String(localized: "файл замалий для циферблата")
            case "bad signature": reason = String(localized: "це не файл циферблата Xiaomi (немає заголовка 5A A5)")
            case "bad watchface id": reason = String(localized: "у заголовку немає ідентифікатора циферблата")
            default: reason = why
            }
            return String(localized: "Некоректний файл циферблата: \(reason)")
        case .invalidPreview(let why):
            return String(localized: "Некоректний файл циферблата: \(why)")
        case .database(let why):
            return why
        case .cancelled, .disconnected:
            return String(localized: "З'єднання розірвано")
        }
    }
}
