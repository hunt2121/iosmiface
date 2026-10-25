// SPDX-License-Identifier: MIT
//
// Читання auth key браслета з даних Mi Fitness на iPhone.
// Папка «На iPhone › Mi Fitness», файл MHWCahe/<ID акаунта>/VirtualDevice_registerList/manifest.sqlite
// (назва папки саме «Cahe»). Таблиця manifest, рядки registerList_<регіон>, колонка inline_data —
// бінарний plist NSKeyedArchiver зі списком пристроїв.

import Foundation
import SQLite3

public struct BandCredentials: Sendable, Equatable {
    public var name: String
    public var mac: String?
    /// Auth key, 16 байтів.
    public var authKey: [UInt8]

    public var authKeyHex: String { authKey.map { String(format: "%02x", $0) }.joined() }
}

public enum AuthKeyStore {
    /// Шукає всі manifest.sqlite усередині вибраної користувачем папки Mi Fitness.
    public static func findManifests(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else {
            return []
        }
        var result: [URL] = []
        for case let url as URL in enumerator
        where url.lastPathComponent == "manifest.sqlite"
            && url.deletingLastPathComponent().lastPathComponent == "VirtualDevice_registerList" {
            result.append(url)
        }
        return result
    }

    /// Копіює базу разом з -wal і -shm у тимчасову папку (останні зміни можуть бути лише в WAL) і читає її.
    public static func credentials(fromManifest url: URL) throws -> [BandCredentials] {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("BandFaceKit-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temp) }

        let copy = temp.appendingPathComponent("manifest.sqlite")
        try fm.copyItem(at: url, to: copy)
        for suffix in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: url.path + suffix)
            if fm.fileExists(atPath: side.path) {
                try fm.copyItem(at: side, to: URL(fileURLWithPath: copy.path + suffix))
            }
        }

        var result: [BandCredentials] = []
        for blob in try registerListBlobs(databasePath: copy.path) {
            result.append(contentsOf: try credentials(fromKeyedArchive: blob))
        }
        return result
    }

    static func registerListBlobs(databasePath: String) throws -> [Data] {
        var handle: OpaquePointer?
        // Без READONLY: SQLite має змогу застосувати журнал WAL до копії.
        guard sqlite3_open_v2(databasePath, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            throw BandError.database("cannot open database")
        }
        defer { sqlite3_close(db) }

        var prepared: OpaquePointer?
        let sql = "SELECT inline_data FROM manifest WHERE key LIKE 'registerList%'"
        guard sqlite3_prepare_v2(db, sql, -1, &prepared, nil) == SQLITE_OK, let statement = prepared else {
            throw BandError.database(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var blobs: [Data] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let length = Int(sqlite3_column_bytes(statement, 0))
            guard length > 0, let pointer = sqlite3_column_blob(statement, 0) else { continue }
            blobs.append(Data(bytes: pointer, count: length))
        }
        return blobs
    }

    /// Розбирає plist NSKeyedArchiver: у масиві $objects шукає словники з ключем encryptKey.
    public static func credentials(fromKeyedArchive data: Data) throws -> [BandCredentials] {
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let objects = root["$objects"] as? [Any]
        else { throw BandError.database("not a keyed archive") }

        func resolve(_ value: Any?) -> Any? {
            guard let value else { return nil }
            if let index = uidValue(value), index < objects.count { return objects[index] }
            return value
        }

        func string(_ value: Any?) -> String? {
            switch resolve(value) {
            case let s as String: return s
            case let d as Data: return String(data: d, encoding: .utf8)
            default: return nil
            }
        }

        var result: [BandCredentials] = []
        for case let dict as [String: Any] in objects {
            guard let raw = string(dict["encryptKey"]),
                  let key = Hex.decode(raw), key.count == 16
            else { continue }
            let name = (string(dict["name"]) ?? "")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
            let mac = string(dict["mac"]) ?? string(dict["randomMac"])
            let credentials = BandCredentials(name: name, mac: mac, authKey: key)
            if !result.contains(credentials) { result.append(credentials) }
        }
        return result
    }

    /// Номер об'єкта з CFKeyedArchiverUID. Foundation не дає прямого доступу до значення,
    /// тому воно читається з опису виду «<CFKeyedArchiverUID 0x…>{value = 12}».
    static func uidValue(_ value: Any) -> Int? {
        let typeName = String(describing: type(of: value))
        let description = String(describing: value)
        guard typeName.contains("UID") || description.contains("CFKeyedArchiverUID") else { return nil }
        guard let range = description.range(of: #"value = (\d+)"#, options: .regularExpression) else { return nil }
        return Int(description[range].dropFirst("value = ".count))
    }
}

/// Збереження доступу до папки Mi Fitness між запусками (bookmark).
/// Закладку створюйте, поки доступ відкритий, — одразу після вибору папки.
public enum FolderBookmark {
    public static func make(for folder: URL) throws -> Data {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        return try folder.bookmarkData()
    }

    /// Повертає URL і ознаку, що закладку варто перестворити.
    public static func resolve(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
        return (url, stale)
    }
}
