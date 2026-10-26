// SPDX-License-Identifier: MIT
//
// Запасний пошук auth key для версій Mi Fitness, у яких дані лежать не так, як у глобальній
// (наприклад, китайська «小米运动健康»). Стандартна база VirtualDevice_registerList там може
// бути відсутня, тому переглядаються всі файли вибраної папки: бази SQLite (усі таблиці),
// plist, JSON і текстові журнали. Шукаються поля encryptKey / authKey / bindKey
// (у будь-якому регістрі й з підкресленнями) зі значенням у 16 байтів.

import Foundation
import SQLite3

/// Що було переглянуто — для журналу «Режиму розробника».
public struct ScanReport: Sendable, Equatable {
    public var filesScanned = 0
    public var databasesScanned = 0
    /// Сканування перервано за часом або за кількістю файлів
    public var truncated = false
    /// Папки (до 4 рівнів углиб) з кількістю файлів і розміром
    public var folders: [String] = []
    /// Бази, plist і JSON, які були переглянуті
    public var interestingFiles: [String] = []

    public init() {}

    public var lines: [String] {
        var out = ["Full scan: \(filesScanned) files, \(databasesScanned) databases" + (truncated ? " (stopped early)" : "")]
        out += folders.map { "  dir " + $0 }
        out += interestingFiles.map { "  file " + $0 }
        return out
    }
}

public enum AuthKeyScanner {
    /// Назви полів з ключем без регістру й підкреслень
    static let keyFields = ["encryptkey", "authkey", "bindkey"]
    static let maxFiles = 30_000
    static let maxFileSize = 256 * 1024 * 1024
    /// Не бази: більші файли пропускаються
    static let maxTextSize = 4 * 1024 * 1024
    static let maxTotalTextBytes = 256 * 1024 * 1024
    static let maxRowsPerTable = 20_000
    static let maxCellSize = 1024 * 1024
    static let maxListedFolders = 40
    static let maxListedFiles = 40

    private static let sqliteMagic = Array("SQLite format 3\0".utf8)
    private static let bplistMagic = Array("bplist00".utf8)

    private static let textPattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?:encrypt_?key|auth_?key|bind_?key)\\*["']?\s*[:=]\s*\\*["']?(?:0x)?([0-9a-f]{32})(?![0-9a-f])"#,
        options: [.caseInsensitive])

    /// Переглядає всі файли папки. `timeLimit` — скільки секунд максимум.
    public static func scan(folder: URL, timeLimit: TimeInterval = 25) -> (credentials: [BandCredentials], report: ScanReport) {
        var report = ScanReport()
        var found: [BandCredentials] = []
        let deadline = Date().addingTimeInterval(timeLimit)
        var textBytes = 0
        var folderStats: [String: (files: Int, bytes: Int)] = [:]

        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else {
            return ([], report)
        }
        let base = folder.standardizedFileURL.path

        for case let url as URL in enumerator {
            if Date() > deadline || report.filesScanned >= maxFiles {
                report.truncated = true
                break
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let size = values.fileSize ?? 0
            report.filesScanned += 1

            let relative = relativePath(of: url, base: base)
            let directory = relative.split(separator: "/").dropLast().prefix(4).joined(separator: "/")
            let stat = folderStats[directory] ?? (0, 0)
            folderStats[directory] = (stat.files + 1, stat.bytes + size)

            guard size > 0, size <= maxFileSize,
                  let handle = try? FileHandle(forReadingFrom: url) else { continue }
            let head = [UInt8]((try? handle.read(upToCount: 16)) ?? Data())
            try? handle.close()

            if head.starts(with: sqliteMagic) {
                report.databasesScanned += 1
                note(&report, "\(relative) (sqlite, \(size / 1024) KB)")
                merge(credentials(inDatabase: url, deadline: deadline), into: &found)
                continue
            }

            guard size <= maxTextSize, textBytes + size <= maxTotalTextBytes,
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            textBytes += size
            let hits = credentials(inBlob: data)
            if !hits.isEmpty || looksStructured(head) {
                note(&report, "\(relative) (\(size / 1024) KB)" + (hits.isEmpty ? "" : " KEY"))
            }
            merge(hits, into: &found)
        }

        report.folders = folderStats.keys.sorted().prefix(maxListedFolders).map { directory in
            let stat = folderStats[directory] ?? (0, 0)
            return "\(directory.isEmpty ? "." : directory)/ — \(stat.files) files, \(stat.bytes / 1024) KB"
        }
        return (found, report)
    }

    // MARK: - Розбір вмісту

    /// Шукає ключі в довільних даних: plist (бінарний, XML і NSKeyedArchiver), JSON, звичайний текст.
    static func credentials(inBlob data: Data) -> [BandCredentials] {
        guard data.count >= 32 else { return [] }
        var result: [BandCredentials] = []
        var structured = false

        if let object = try? PropertyListSerialization.propertyList(from: data, format: nil) {
            structured = true
            walk(object, into: &result)
            if let archived = try? AuthKeyStore.credentials(fromKeyedArchive: data) {
                merge(archived, into: &result)
            }
        } else if let first = data.first(where: { $0 > 0x20 }),
                  first == UInt8(ascii: "{") || first == UInt8(ascii: "["),
                  data.count <= maxTextSize,
                  let object = try? JSONSerialization.jsonObject(with: data) {
            structured = true
            walk(object, into: &result)
        }
        if !structured || result.isEmpty {
            merge(credentials(inText: data), into: &result)
        }
        return result
    }

    /// Журнали й нерозпізнані файли: рядки на кшталт «encryptKey":"0011…»
    static func credentials(inText data: Data) -> [BandCredentials] {
        guard let pattern = textPattern, data.count <= maxTextSize else { return [] }
        let text = String(decoding: data, as: UTF8.self)
        guard text.range(of: "key", options: .caseInsensitive) != nil else { return [] }
        var result: [BandCredentials] = []
        let whole = NSRange(text.startIndex..., in: text)
        pattern.enumerateMatches(in: text, options: [], range: whole) { match, _, _ in
            guard let match, match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text),
                  let key = Hex.decode(String(text[range])), key.count == 16 else { return }
            merge([BandCredentials(name: "", mac: nil, authKey: key)], into: &result)
        }
        return result
    }

    /// Обходить словники й масиви; словник з полем ключа дає запис пристрою.
    static func walk(_ value: Any, into result: inout [BandCredentials], depth: Int = 0) {
        guard depth < 48 else { return }
        if let dict = value as? [String: Any] {
            var normalized: [String: Any] = [:]
            for (name, item) in dict { normalized[normalize(name)] = item }
            for field in keyFields {
                guard let raw = normalized[field], let key = keyBytes(raw) else { continue }
                let name = text(normalized["name"] ?? normalized["devicename"] ?? normalized["model"])
                let mac = text(normalized["mac"] ?? normalized["randommac"] ?? normalized["address"])
                merge([BandCredentials(name: name ?? "", mac: mac, authKey: key)], into: &result)
            }
            for item in dict.values { walk(item, into: &result, depth: depth + 1) }
        } else if let array = value as? [Any] {
            for item in array { walk(item, into: &result, depth: depth + 1) }
        }
    }

    static func keyBytes(_ value: Any) -> [UInt8]? {
        switch value {
        case let string as String:
            guard string.count <= 40, let key = Hex.decode(string), key.count == 16 else { return nil }
            return key
        case let data as Data:
            if data.count == 16 { return [UInt8](data) }
            if data.count <= 40, let string = String(data: data, encoding: .utf8) { return keyBytes(string) }
            return nil
        default:
            return nil
        }
    }

    // MARK: - SQLite

    /// Копіює базу з -wal і -shm у тимчасову папку й переглядає всі таблиці.
    static func credentials(inDatabase url: URL, deadline: Date) -> [BandCredentials] {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("BandFaceKit-scan-\(UUID().uuidString)", isDirectory: true)
        guard (try? fm.createDirectory(at: temp, withIntermediateDirectories: true)) != nil else { return [] }
        defer { try? fm.removeItem(at: temp) }

        let copy = temp.appendingPathComponent("db.sqlite")
        guard (try? fm.copyItem(at: url, to: copy)) != nil else { return [] }
        for suffix in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: url.path + suffix)
            if fm.fileExists(atPath: side.path) {
                try? fm.copyItem(at: side, to: URL(fileURLWithPath: copy.path + suffix))
            }
        }

        var handle: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            return []
        }
        defer { sqlite3_close(db) }

        var result: [BandCredentials] = []
        for table in tableNames(db) {
            if Date() > deadline { break }
            scan(table: table, in: db, deadline: deadline, into: &result)
        }
        return result
    }

    private static func tableNames(_ db: OpaquePointer) -> [String] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type = 'table'", -1, &statement, nil) == SQLITE_OK,
              let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let pointer = sqlite3_column_text(statement, 0) { names.append(String(cString: pointer)) }
        }
        return names
    }

    private static func scan(table: String, in db: OpaquePointer, deadline: Date, into result: inout [BandCredentials]) {
        let quoted = table.replacingOccurrences(of: "\"", with: "\"\"")
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT * FROM \"\(quoted)\" LIMIT \(maxRowsPerTable)", -1, &statement, nil) == SQLITE_OK,
              let statement else { return }
        defer { sqlite3_finalize(statement) }

        let columns = Int(sqlite3_column_count(statement))
        let names: [String] = (0..<columns).map { index in
            sqlite3_column_name(statement, Int32(index)).map { String(cString: $0) } ?? ""
        }

        var rows = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            rows += 1
            if rows % 500 == 0, Date() > deadline { break }
            var row: [String: Any] = [:]
            for index in 0..<columns {
                let type = sqlite3_column_type(statement, Int32(index))
                guard type == SQLITE_BLOB || type == SQLITE_TEXT else { continue }
                let length = Int(sqlite3_column_bytes(statement, Int32(index)))
                guard length > 0, length <= maxCellSize,
                      let pointer = sqlite3_column_blob(statement, Int32(index)) else { continue }
                let data = Data(bytes: pointer, count: length)
                if type == SQLITE_TEXT {
                    row[names[index]] = String(decoding: data, as: UTF8.self)
                } else {
                    row[names[index]] = data
                }
                merge(credentials(inBlob: data), into: &result)
            }
            // Колонки на кшталт encrypt_key / auth_key разом із name і mac в одному рядку
            walk(row, into: &result)
        }
    }

    // MARK: - Допоміжне

    static func merge(_ new: [BandCredentials], into list: inout [BandCredentials]) {
        for item in new {
            if let index = list.firstIndex(where: { $0.authKey == item.authKey }) {
                if list[index].name.isEmpty { list[index].name = item.name }
                if list[index].mac == nil { list[index].mac = item.mac }
            } else {
                list.append(item)
            }
        }
    }

    private static func normalize(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: "-", with: "")
    }

    private static func text(_ value: Any?) -> String? {
        let string: String?
        switch value {
        case let s as String: string = s
        case let d as Data: string = String(data: d, encoding: .utf8)
        default: string = nil
        }
        let trimmed = string?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet.controlCharacters))
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private static func looksStructured(_ head: [UInt8]) -> Bool {
        if head.starts(with: bplistMagic) { return true }
        guard let first = head.first(where: { $0 > 0x20 }) else { return false }
        return first == UInt8(ascii: "{") || first == UInt8(ascii: "[") || first == UInt8(ascii: "<")
    }

    private static func note(_ report: inout ScanReport, _ line: String) {
        if report.interestingFiles.count < maxListedFiles { report.interestingFiles.append(line) }
    }

    private static func relativePath(of url: URL, base: String) -> String {
        let path = url.standardizedFileURL.path
        if path.hasPrefix(base) {
            return String(path.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return url.lastPathComponent
    }
}
