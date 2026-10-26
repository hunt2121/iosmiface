import Foundation
import BandFaceKit

/// Пошук auth key у даних Mi Fitness, які застосунок показує у «Файлах» (На iPhone › Mi Fitness).
///
/// Ключ лежить у `MHWCahe/<id користувача>/VirtualDevice_registerList/manifest.sqlite`:
/// таблиця `manifest`, рядок з ключем `registerList_<регіон>`, поле `inline_data` —
/// бінарний plist (NSKeyedArchiver) зі списком пристроїв, у кожного є `encryptKey`.
/// Розташування з'ясовано за проєктом github.com/artyomxx/xiaomi-band-ios-export.
/// Саме читання бази робить BandFaceKit (AuthKeyStore).
/// Якщо такої бази немає (китайська версія «小米运动健康» зберігає дані інакше), перегляд усіх
/// файлів застосунку виконує AuthKeyScanner.
enum MiFitnessKey {
    struct Device: Hashable {
        let name: String
        let mac: String?
        let key: String
    }

    enum SearchError: LocalizedError {
        case noDatabase, noKey

        var errorDescription: String? {
            switch self {
            case .noDatabase: return String(localized: "У папці не знайдено ключа браслета. Виберіть папку застосунку Mi Fitness (для китайської версії — «小米运动健康»). Якщо не допомагає, увімкніть «Режим розробника» в «Журналі», повторіть пошук і надішліть журнал розробнику")
            case .noKey: return String(localized: "Дані Mi Fitness знайдено, але ключа браслета в них немає. Відкрийте Mi Fitness, дочекайтеся підключення браслета й спробуйте ще раз")
            }
        }
    }

    private static let bookmarkKey = "miFitnessFolderBookmark"

    static var hasSavedFolder: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// Запам'ятовує папку, щоб наступного разу не вибирати її знову.
    static func saveFolder(_ url: URL) {
        // Закладку треба створювати, поки доступ до папки відкритий, інакше після
        // перезапуску застосунку iOS не дасть до неї доступу
        if let data = try? FolderBookmark.make(for: url) {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }

    static func forgetFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    static func savedFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        guard let resolved = try? FolderBookmark.resolve(data) else { return nil }
        if resolved.isStale { saveFolder(resolved.url) }
        return resolved.url
    }

    /// Журнал останнього повного сканування (порожній, якщо знайшлася стандартна база Mi Fitness).
    /// Показується в журналі «Режиму розробника».
    private(set) static var lastScanLines: [String] = []

    static func findDevices(in folder: URL) throws -> [Device] {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        lastScanLines = []

        let databases = AuthKeyStore.findManifests(in: folder)
        var credentials: [BandCredentials] = []
        for db in databases {
            for band in (try? AuthKeyStore.credentials(fromManifest: db)) ?? [] where !credentials.contains(band) {
                credentials.append(band)
            }
        }

        if credentials.isEmpty {
            // Нестандартна структура даних (наприклад, китайська «小米运动健康»):
            // переглядаємо всі файли застосунку
            let scan = AuthKeyScanner.scan(folder: folder)
            credentials = scan.credentials
            lastScanLines = scan.report.lines
        }

        let result = credentials.map { Device(name: clean($0.name), mac: $0.mac.map(clean), key: $0.authKeyHex) }
        guard !result.isEmpty else { throw databases.isEmpty ? SearchError.noDatabase : SearchError.noKey }
        return result
    }

    /// Порожнє значення в архіві виглядає як «$null»; керівні символи в назві обрізаємо.
    private static func clean(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.controlCharacters))
        return trimmed == "$null" ? "" : trimmed
    }
}
