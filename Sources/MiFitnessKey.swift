import Foundation
import BandFaceKit

/// Пошук auth key у даних Mi Fitness, які застосунок показує у «Файлах» (На iPhone › Mi Fitness).
///
/// Ключ лежить у `MHWCahe/<id користувача>/VirtualDevice_registerList/manifest.sqlite`:
/// таблиця `manifest`, рядок з ключем `registerList_<регіон>`, поле `inline_data` —
/// бінарний plist (NSKeyedArchiver) зі списком пристроїв, у кожного є `encryptKey`.
/// Розташування з'ясовано за проєктом github.com/artyomxx/xiaomi-band-ios-export.
/// Саме читання бази робить BandFaceKit (AuthKeyStore).
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
            case .noDatabase: return String(localized: "У папці не знайдено даних Mi Fitness (VirtualDevice_registerList). Виберіть папку Mi Fitness або MHWCahe")
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

    static func findDevices(in folder: URL) throws -> [Device] {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let databases = AuthKeyStore.findManifests(in: folder)
        guard !databases.isEmpty else { throw SearchError.noDatabase }

        var result: [Device] = []
        for db in databases {
            for band in (try? AuthKeyStore.credentials(fromManifest: db)) ?? [] {
                let device = Device(name: clean(band.name), mac: band.mac.map(clean), key: band.authKeyHex)
                if !result.contains(device) { result.append(device) }
            }
        }
        guard !result.isEmpty else { throw SearchError.noKey }
        return result
    }

    /// Порожнє значення в архіві виглядає як «$null»; керівні символи в назві обрізаємо.
    private static func clean(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.controlCharacters))
        return trimmed == "$null" ? "" : trimmed
    }
}
