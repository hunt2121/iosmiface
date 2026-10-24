import Foundation
import CoreBluetooth

enum BandError: LocalizedError {
    case notConnected
    case badAuthKey
    case badFaceFile(String)
    case protocolNotImplemented

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Браслет не підключено"
        case .badAuthKey: return "Auth key має бути 32 hex-символи (16 байт)"
        case .badFaceFile(let why): return "Некоректний файл циферблата: \(why)"
        case .protocolNotImplemented:
            return "Протокол Xiaomi (авторизація + передача файлу) ще не портовано. Дивіться README, розділ «Що лишилось»."
        }
    }
}

/// Перевірка файлу перед відправкою.
enum FaceFileValidator {
    static func validate(_ data: Data, name: String) throws {
        guard !data.isEmpty else { throw BandError.badFaceFile("файл порожній") }
        guard data.count < 8 * 1024 * 1024 else { throw BandError.badFaceFile("файл завеликий (>8 МБ)") }
        guard name.lowercased().hasSuffix(".face") || name.lowercased().hasSuffix(".bin") else {
            throw BandError.badFaceFile("очікується .face")
        }
    }
}

/// Сесія зв'язку з браслетом Xiaomi Smart Band 10.
///
/// ВАЖЛИВО: у цьому файлі реалізовано лише каркас. Реальний обмін
/// (UUID характеристик, автентифікація за auth key, шифрування, protobuf-команди,
/// чанки завантаження файлу з CRC) потрібно портувати з проєкту Gadgetbridge:
/// пакет nodomain.freeyourgadget.gadgetbridge.devices.xiaomi
/// (XiaomiBleProtocol, XiaomiAuthService, XiaomiWatchfaceService, XiaomiDataUploadService).
/// Нічого з цього тут навмисно не вигадано, щоб не відправити на браслет сміття.
final class XiaomiBandSession {
    private let ble: BLEManager
    private let authKey: Data

    init(ble: BLEManager, authKeyHex: String) throws {
        guard let key = Data(hex: authKeyHex), key.count == 16 else { throw BandError.badAuthKey }
        self.ble = ble
        self.authKey = key
    }

    /// Встановлює циферблат. Прогрес 0...1 повідомляється через `progress`.
    func installWatchface(_ data: Data, name: String,
                          progress: @escaping (Double) -> Void) async throws {
        guard ble.connectedID != nil else { throw BandError.notConnected }
        try FaceFileValidator.validate(data, name: name)

        // TODO 1: рукостискання/автентифікація (nonce, HMAC на основі authKey), вивід сесійних ключів.
        // TODO 2: шифрування/дешифрування кадрів (AES-CCM; CryptoKit його не має, потрібна власна реалізація).
        // TODO 3: protobuf-команда «встановити циферблат» (type/subtype із Gadgetbridge).
        // TODO 4: завантаження даних чанками (розмір з ble.maxWriteLength()) з контрольною сумою та підтвердженнями.
        _ = authKey
        progress(0)
        throw BandError.protocolNotImplemented
    }
}
