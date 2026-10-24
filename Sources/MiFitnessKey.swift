import Foundation
import SQLite3

/// Пошук auth key у даних Mi Fitness, які застосунок показує у «Файлах» (На iPhone › Mi Fitness).
///
/// Ключ лежить у `MHWCahe/<id користувача>/VirtualDevice_registerList/manifest.sqlite`:
/// таблиця `manifest`, рядок з ключем `registerList_<регіон>`, поле `inline_data` —
/// бінарний plist (NSKeyedArchiver) зі списком пристроїв, у кожного є `encryptKey`.
/// Розташування з'ясовано за проєктом github.com/artyomxx/xiaomi-band-ios-export.
enum MiFitnessKey {
    struct Device: Hashable {
        let name: String
        let mac: String?
        let key: String
    }

    enum SearchError: LocalizedError {
        case noAccess, noDatabase, noKey

        var errorDescription: String? {
            switch self {
            case .noAccess: return "Немає доступу до вибраної папки"
            case .noDatabase: return "У папці не знайдено даних Mi Fitness (VirtualDevice_registerList). Виберіть папку Mi Fitness або MHWCahe"
            case .noKey: return "Дані Mi Fitness знайдено, але ключа браслета в них немає. Відкрийте Mi Fitness, дочекайтеся підключення браслета й спробуйте ще раз"
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
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let data = try? url.bookmarkData() {
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        }
    }

    static func forgetFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    static func savedFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
        if stale { saveFolder(url) }
        return url
    }

    static func findDevices(in folder: URL) throws -> [Device] {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        guard let walker = fm.enumerator(at: folder, includingPropertiesForKeys: nil) else {
            throw SearchError.noAccess
        }
        var databases: [URL] = []
        for case let url as URL in walker
        where url.lastPathComponent == "manifest.sqlite"
            && url.deletingLastPathComponent().lastPathComponent == "VirtualDevice_registerList" {
            databases.append(url)
        }
        guard !databases.isEmpty else { throw SearchError.noDatabase }

        var result: [Device] = []
        for db in databases {
            for device in (try? devices(fromDatabase: db)) ?? [] where !result.contains(device) {
                result.append(device)
            }
        }
        guard !result.isEmpty else { throw SearchError.noKey }
        return result
    }

    // MARK: - SQLite

    private static func devices(fromDatabase db: URL) throws -> [Device] {
        // Копіюємо базу разом із журналом WAL у тимчасову папку й читаємо копію
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let copy = tmp.appendingPathComponent("manifest.sqlite")
        try fm.copyItem(at: db, to: copy)
        for suffix in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: db.path + suffix)
            if fm.fileExists(atPath: side.path) {
                try? fm.copyItem(at: side, to: URL(fileURLWithPath: copy.path + suffix))
            }
        }

        var handle: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let handle else {
            return []
        }
        defer { sqlite3_close(handle) }

        var stmt: OpaquePointer?
        let sql = "select inline_data from manifest where key like 'registerList%'"
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        var out: [Device] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(stmt, 0) else { continue }
            let blob = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))
            out.append(contentsOf: devices(fromArchive: blob))
        }
        return out
    }

    // MARK: - NSKeyedArchiver

    private static func devices(fromArchive blob: Data) -> [Device] {
        guard let plist = try? PropertyListSerialization.propertyList(from: blob, format: nil) as? [String: Any],
              let objects = plist["$objects"] as? [Any] else { return [] }

        func resolve(_ value: Any?) -> Any? {
            guard let value else { return nil }
            if let index = uidValue(value), index < objects.count {
                let target = objects[index]
                if let s = target as? String, s == "$null" { return nil }
                return target
            }
            return value
        }

        var found: [Device] = []
        for case let dict as [String: Any] in objects {
            guard let raw = resolve(dict["encryptKey"] ?? dict["encrypt_key"]) as? String else { continue }
            let key = raw.trimmingCharacters(in: .whitespaces).lowercased()
                .replacingOccurrences(of: "0x", with: "")
            guard key.count == 32, key.allSatisfy(\.isHexDigit) else { continue }
            let name = (resolve(dict["name"]) as? String) ?? ""
            let mac = (resolve(dict["mac"]) as? String) ?? (resolve(dict["randomMac"]) as? String)
            found.append(Device(name: name, mac: mac, key: key))
        }
        return found
    }

    /// Значення CFKeyedArchiverUID (у Swift цей тип непрозорий, тож беремо його з опису: "{value = 7}").
    private static func uidValue(_ value: Any) -> Int? {
        let text = String(describing: value)
        guard text.contains("CFKeyedArchiverUID"),
              let range = text.range(of: #"value = (\d+)"#, options: .regularExpression) else { return nil }
        return Int(text[range].split(separator: " ").last ?? "")
    }
}
