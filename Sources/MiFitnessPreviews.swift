import Foundation
import SQLite3
import UIKit

/// Пошук прев'ю встановлених циферблатів у даних Mi Fitness (папка, вибрана для ключа).
///
/// Браслет передає лише ID і назви циферблатів, тому картинки беремо з кешу Mi Fitness:
///  1. файли-зображення, у шляху яких є ID циферблата;
///  2. записи кешу (`manifest.sqlite`, бінарні plist або JSON), де поруч з ID є посилання
///     на картинку або вбудоване зображення; посилання завантажуються з інтернету.
/// Формат кешу Mi Fitness не задокументований, тому пошук евристичний і пише діагностику.
enum MiFitnessPreviews {
    struct Result {
        var images: [String: UIImage] = [:]
        var log: [String] = []
    }

    static func search(ids: [String]) async -> Result {
        var result = Result()
        guard !ids.isEmpty else { return result }
        guard let root = MiFitnessKey.savedFolder() else {
            result.log.append("Прев'ю: папку Mi Fitness ще не вибрано (вкладка «Ключ»)")
            return result
        }

        var urls: [String: [URL]] = [:]
        let scoped = root.startAccessingSecurityScopedResource()
        scan(root: root, ids: Set(ids), result: &result, urls: &urls)
        if scoped { root.stopAccessingSecurityScopedResource() }

        // Завантажуємо картинки за знайденими посиланнями
        for id in ids where result.images[id] == nil {
            for url in urls[id] ?? [] {
                if let img = await download(url) {
                    result.images[id] = img
                    result.log.append("Прев'ю \(id): завантажено з \(url.host ?? "мережі")")
                    break
                }
            }
        }
        let missing = ids.filter { result.images[$0] == nil }
        result.log.append("Прев'ю: знайдено \(ids.count - missing.count) з \(ids.count)"
                          + (missing.isEmpty ? "" : ", без картинки: \(missing.joined(separator: ", "))"))
        return result
    }

    // MARK: - Обхід папки

    private static func scan(root: URL, ids: Set<String>, result: inout Result, urls: inout [String: [URL]]) {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "heic"]
        var caches: [String: Int] = [:]
        var databases = 0

        for case let url as URL in walker {
            let path = url.path
            let ext = url.pathExtension.lowercased()

            // Назви папок кешу — для діагностики
            if url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "MHWCahe" {
                caches[url.lastPathComponent, default: 0] += 1
            }

            if imageExts.contains(ext) {
                for id in ids where result.images[id] == nil && path.contains(id) {
                    if let img = UIImage(contentsOfFile: path) {
                        result.images[id] = img
                        result.log.append("Прев'ю \(id): файл \(url.lastPathComponent)")
                    }
                }
            } else if ext == "sqlite" || ext == "db" {
                databases += 1
                scanDatabase(url, ids: ids, result: &result, urls: &urls)
            } else if ext == "json" || ext == "plist" {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if size > 0, size < 20_000_000, let data = try? Data(contentsOf: url), contains(data, anyOf: ids) {
                    inspect(blob: data, source: url.lastPathComponent, ids: ids, result: &result, urls: &urls)
                }
            }
        }
        if !caches.isEmpty {
            result.log.append("Кеш Mi Fitness: " + caches.keys.sorted().joined(separator: ", "))
        }
        result.log.append("Переглянуто баз даних: \(databases)")
    }

    private static func scanDatabase(_ db: URL, ids: Set<String>, result: inout Result, urls: inout [String: [URL]]) {
        var handle: OpaquePointer?
        // immutable=1: читаємо без блокувань і без запису журналу в чужу папку
        let uri = "file:" + (db.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? db.path) + "?immutable=1"
        guard sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            return
        }
        defer { sqlite3_close(handle) }

        // Таблиці й текстові/бінарні колонки
        var tables: [String] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(handle, "select name from sqlite_master where type='table'", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) { tables.append(String(cString: c)) }
            }
        }
        sqlite3_finalize(stmt)

        for table in tables where !table.hasPrefix("sqlite_") {
            var q: OpaquePointer?
            guard sqlite3_prepare_v2(handle, "select * from \"\(table)\" limit 5000", -1, &q, nil) == SQLITE_OK else { continue }
            while sqlite3_step(q) == SQLITE_ROW {
                var cells: [Data] = []
                for col in 0..<sqlite3_column_count(q) {
                    switch sqlite3_column_type(q, col) {
                    case SQLITE_TEXT, SQLITE_BLOB:
                        if let p = sqlite3_column_blob(q, col) {
                            cells.append(Data(bytes: p, count: Int(sqlite3_column_bytes(q, col))))
                        }
                    default: break
                    }
                }
                guard cells.contains(where: { contains($0, anyOf: ids) }) else { continue }
                let source = "\(db.deletingLastPathComponent().lastPathComponent)/\(table)"
                // Рядок згадує ID: розбираємо кожну комірку
                for cell in cells { inspect(blob: cell, source: source, ids: ids, result: &result, urls: &urls) }
                // Якщо ID і посилання лежать у різних колонках одного рядка
                if let id = ids.first(where: { id in cells.contains { contains($0, anyOf: [id]) } }) {
                    for cell in cells {
                        if let s = String(data: cell, encoding: .utf8), let u = imageURL(s) { add(u, for: id, &urls) }
                        if result.images[id] == nil, let img = embeddedImage(cell) { result.images[id] = img }
                    }
                }
            }
            sqlite3_finalize(q)
        }
    }

    // MARK: - Розбір записів

    private static func inspect(blob: Data, source: String, ids: Set<String>, result: inout Result, urls: inout [String: [URL]]) {
        guard contains(blob, anyOf: ids) else { return }
        if blob.starts(with: Data("bplist".utf8)),
           let plist = try? PropertyListSerialization.propertyList(from: blob, format: nil) {
            if let dict = plist as? [String: Any], let objects = dict["$objects"] as? [Any] {
                inspectArchive(objects, source: source, ids: ids, result: &result, urls: &urls)
            } else {
                walk(plist, ids: ids, result: &result, urls: &urls)
            }
        } else if let json = try? JSONSerialization.jsonObject(with: blob, options: [.fragmentsAllowed]) {
            walk(json, ids: ids, result: &result, urls: &urls)
        }
    }

    /// NSKeyedArchiver: шукаємо об'єкти-словники, у яких одне значення — ID, а інше — посилання/картинка.
    private static func inspectArchive(_ objects: [Any], source: String, ids: Set<String>,
                                       result: inout Result, urls: inout [String: [URL]]) {
        func resolve(_ v: Any) -> Any {
            if let i = MiFitnessKey.uidValue(v), i < objects.count { return objects[i] }
            return v
        }
        for case let dict as [String: Any] in objects {
            let values = dict.values.map(resolve)
            guard let id = values.lazy.compactMap({ v -> String? in
                let s = (v as? String) ?? (v as? NSNumber)?.stringValue
                return s.flatMap { ids.contains($0) ? $0 : nil }
            }).first else { continue }
            for v in values {
                if let s = v as? String, let u = imageURL(s) { add(u, for: id, &urls) }
                if let d = v as? Data, result.images[id] == nil, let img = embeddedImage(d) {
                    result.images[id] = img
                    result.log.append("Прев'ю \(id): вбудоване зображення (\(source))")
                }
            }
        }
    }

    /// JSON / звичайний plist: рекурсивно шукаємо словники з ID і посиланням на картинку.
    private static func walk(_ node: Any, ids: Set<String>, result: inout Result, urls: inout [String: [URL]]) {
        if let dict = node as? [String: Any] {
            let flat = dict.values.compactMap { ($0 as? String) ?? ($0 as? NSNumber)?.stringValue }
            if let id = flat.first(where: { ids.contains($0) }) {
                for case let s as String in dict.values { if let u = imageURL(s) { add(u, for: id, &urls) } }
            }
            for v in dict.values { walk(v, ids: ids, result: &result, urls: &urls) }
        } else if let arr = node as? [Any] {
            for v in arr { walk(v, ids: ids, result: &result, urls: &urls) }
        } else if let s = node as? String, s.first == "{" || s.first == "[",
                  let d = s.data(using: .utf8), let inner = try? JSONSerialization.jsonObject(with: d) {
            walk(inner, ids: ids, result: &result, urls: &urls)
        }
    }

    // MARK: - Допоміжне

    private static func contains(_ data: Data, anyOf ids: Set<String>) -> Bool {
        ids.contains { data.range(of: Data($0.utf8)) != nil }
    }

    private static func imageURL(_ s: String) -> URL? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("http"), let u = URL(string: t) else { return nil }
        let ext = u.pathExtension.lowercased()
        let looksLikeImage = ["png", "jpg", "jpeg", "webp", "gif"].contains(ext)
            || t.lowercased().contains("image") || t.lowercased().contains("icon") || t.lowercased().contains("preview")
        return looksLikeImage ? u : nil
    }

    private static func add(_ url: URL, for id: String, _ urls: inout [String: [URL]]) {
        if !(urls[id] ?? []).contains(url) { urls[id, default: []].append(url) }
    }

    private static func embeddedImage(_ d: Data) -> UIImage? {
        let png = Data([0x89, 0x50, 0x4E, 0x47]), jpg = Data([0xFF, 0xD8, 0xFF])
        guard d.starts(with: png) || d.starts(with: jpg) else { return nil }
        return UIImage(data: d)
    }

    private static func download(_ url: URL) async -> UIImage? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        guard let pair = try? await URLSession.shared.data(for: req) else { return nil }
        let status = (pair.1 as? HTTPURLResponse)?.statusCode ?? 200
        guard status < 400 else { return nil }
        return UIImage(data: pair.0)
    }
}
