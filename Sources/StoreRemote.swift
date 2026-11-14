import SwiftUI
import UIKit
import CryptoKit
import BandFaceKit

/// Каталог магазину з сервера (catalog.json). Запис має кілька варіантів — окремий .bin на мову
/// й формат часу; телефон сам вибирає підхожий (див. StoreVariants).
struct RemoteCatalog: Codable {
    let faces: [Entry]

    struct Entry: Codable {
        let id: String
        let version: Int
        let name: [String: String]
        let about: [String: String]
        let kind: String
        let price: String?
        let bands: [Int]
        let added: String?
        let variants: [String: Variant]
    }

    struct Variant: Codable {
        let faceId: String
        let size: Int
        let sha256: String
        let langs: [String]
        let clock: String?
        let download: String
        let main: String
        let aod: String?
        let anim: String?
    }
}

/// Адреса сервера магазину — у Info.plist (BandFaceStoreURL, задається в project.yml).
/// Порожня — лише вбудовані циферблати.
enum StoreServer {
    static let base: URL? = {
        guard var s = Bundle.main.object(forInfoDictionaryKey: "BandFaceStoreURL") as? String else { return nil }
        s = s.trimmingCharacters(in: .whitespaces)
        while s.hasSuffix("/") { s.removeLast() }
        return s.isEmpty ? nil : URL(string: s)
    }()

    private static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Store")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private static var catalogFile: URL { dir.appendingPathComponent("catalog.json") }

    /// Останній завантажений каталог — для запуску без мережі
    static func cachedCatalog() -> RemoteCatalog? {
        guard base != nil, let d = try? Data(contentsOf: catalogFile) else { return nil }
        return try? JSONDecoder().decode(RemoteCatalog.self, from: d)
    }

    static func fetchCatalog() async throws -> RemoteCatalog {
        guard let base else { throw URLError(.badURL) }
        var r = URLRequest(url: base.appendingPathComponent("catalog.json"))
        r.cachePolicy = .reloadRevalidatingCacheData
        let (data, response) = try await URLSession.shared.data(for: r)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let catalog = try JSONDecoder().decode(RemoteCatalog.self, from: data)
        try? data.write(to: catalogFile, options: .atomic)
        return catalog
    }

    /// Превʼю за шляхом з каталогу. Шлях містить версію, тож файл ніколи не змінюється — кеш на диску назавжди
    static func file(_ path: String) async -> Data? {
        let local = dir.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_"))
        if let d = try? Data(contentsOf: local) { return d }
        guard let base, let r = try? await URLSession.shared.data(from: base.appendingPathComponent(path)),
              (r.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? r.0.write(to: local, options: .atomic)
        return r.0
    }

    /// Файл варіанта для встановлення: перевіряються розмір, sha256 і ID на браслеті
    static func download(_ v: RemoteCatalog.Variant) async throws -> FaceFile {
        guard let base, let url = URL(string: v.download, relativeTo: base.appendingPathComponent("/")) else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 402 { throw StoreError(String(localized: "Цей циферблат платний")) }
        guard status == 200 else { throw StoreError(String(localized: "Не вдалося завантажити циферблат (\(status))")) }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard data.count == v.size, hash == v.sha256 else {
            throw StoreError(String(localized: "Файл циферблата пошкоджено під час завантаження"))
        }
        let face = try FaceFile(data: data)
        guard face.id == v.faceId else { throw StoreError(String(localized: "Файл циферблата пошкоджено під час завантаження")) }
        return face
    }
}

struct StoreError: LocalizedError {
    let text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}

/// Вибір варіанта: мова телефона (за списком мов у налаштуваннях), інакше «для всіх інших мов» ("*");
/// серед них — той, чий формат часу збігається з налаштуванням телефона (точний збіг важливіший за «будь-який»)
enum StoreVariants {
    /// Мови телефона в порядку налаштувань: ["uk", "en"]
    static var phoneLanguages: [String] {
        var out: [String] = []
        for id in Locale.preferredLanguages {
            let code = String(id.prefix(2)).lowercased()
            if !out.contains(code) { out.append(code) }
        }
        return out
    }

    /// 12-годинний формат часу на телефоні (з урахуванням перемикача «24-годинний час»)
    static var phoneClock: String {
        let f = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? ""
        return f.contains("a") ? "12h" : "24h"
    }

    static func choose(_ variants: [String: RemoteCatalog.Variant]) -> String? {
        let clock = phoneClock
        func best(_ keys: [String]) -> String? {
            keys.first { variants[$0]?.clock == clock } ?? keys.first { variants[$0]?.clock == nil } ?? keys.first
        }
        let keys = variants.keys.sorted()
        for lang in phoneLanguages {
            let match = keys.filter { variants[$0]!.langs.contains(lang) }
            if !match.isEmpty { return best(match) }
        }
        return best(keys.filter { variants[$0]!.langs.contains("*") }) ?? best(keys)
    }

    /// «Англійська · 12 год» — назва мовою інтерфейсу
    static func label(_ key: String, _ v: RemoteCatalog.Variant) -> String {
        let code = String(key.prefix(2))
        let name = Locale.current.localizedString(forLanguageCode: code) ?? code
        let title = name.prefix(1).uppercased() + name.dropFirst()
        switch v.clock {
        case "12h": return title + " · " + String(localized: "12 год")
        case "24h": return title + " · " + String(localized: "24 год")
        default: return title
        }
    }

    /// Текст мовою телефона, інакше першою мовою варіанта, інакше англійською чи українською
    static func text(_ dict: [String: String], variant: RemoteCatalog.Variant?) -> String {
        let order = phoneLanguages + (variant?.langs.filter { $0 != "*" } ?? []) + ["en", "uk"]
        for l in order { if let s = dict[l], !s.isEmpty { return s } }
        return dict.values.first { !$0.isEmpty } ?? ""
    }
}

/// Категорії з каталогу (ключі) — назва мовою інтерфейсу
enum StoreKinds {
    static func label(_ key: String) -> String {
        switch key {
        case "digital": return String(localized: "Цифровий")
        case "analog": return String(localized: "Аналоговий")
        case "humor": return String(localized: "Гумор")
        case "minimal": return String(localized: "Мінімалізм")
        case "sport": return String(localized: "Спорт")
        case "art": return String(localized: "Мистецтво")
        case "other": return String(localized: "Інше")
        default: return key
        }
    }
}

/// Превʼю з сервера в пам'яті: ті самі об'єкти для картки, сторінки й меню
@MainActor
final class StorePreviewCache {
    static let shared = StorePreviewCache()
    private(set) var images: [String: UIImage] = [:]
    private(set) var gifs: [String: Data] = [:]

    /// Завантажує відсутні (з диска або сервера); true — щось додалося
    func load(_ catalog: RemoteCatalog, variants: [String: String]) async -> Bool {
        var pngs: [String] = [], anims: [String] = []
        for e in catalog.faces {
            guard let key = variants[e.id], let v = e.variants[key] else { continue }
            pngs.append(v.main)
            if let a = v.aod { pngs.append(a) }
            if let g = v.anim { anims.append(g) }
        }
        pngs = pngs.filter { images[$0] == nil }
        anims = anims.filter { gifs[$0] == nil }
        guard !pngs.isEmpty || !anims.isEmpty else { return false }
        let loaded = await withTaskGroup(of: (String, Data?).self) { group -> [(String, Data?)] in
            for p in pngs + anims { group.addTask { (p, await StoreServer.file(p)) } }
            var out: [(String, Data?)] = []
            for await r in group { out.append(r) }
            return out
        }
        var added = false
        for (path, data) in loaded {
            guard let data else { continue }
            if anims.contains(path) { gifs[path] = data; added = true }
            else if let img = UIImage(data: data, scale: 1) { images[path] = img; added = true }
        }
        return added
    }
}

extension StoreCatalog {
    /// Записи з сервера, кожен — вибраним варіантом. Вибір: ручний (override) → той, що вже на браслеті → автоматичний
    @MainActor
    static func faces(_ catalog: RemoteCatalog, installed: [String: Int], overrides: [String: String]) -> [StoreFace] {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "UTC")
        day.dateFormat = "yyyy-MM-dd"
        let cache = StorePreviewCache.shared
        return catalog.faces.compactMap { e in
            let onBand = e.variants.first { installed[$0.value.faceId] != nil }?.key
            guard let key = overrides[e.id].flatMap({ e.variants[$0] != nil ? $0 : nil }) ?? onBand
                    ?? StoreVariants.choose(e.variants), let v = e.variants[key] else { return nil }
            var item = StoreFace(id: v.faceId, name: StoreVariants.text(e.name, variant: v),
                                 kind: StoreKinds.label(e.kind), version: e.version,
                                 about: StoreVariants.text(e.about, variant: v), price: e.price, face: nil, preview: nil)
            item.key = e.id
            item.size = v.size
            item.remote = v
            item.allIDs = Set(e.variants.values.map(\.faceId))
            item.added = e.added.flatMap { day.date(from: $0) }
            item.bands = e.bands
            item.variantKey = key
            item.variantOptions = e.variants.keys.sorted { a, b in
                // спершу мова телефона, далі за назвою
                let la = StoreVariants.phoneLanguages.contains(String(a.prefix(2)))
                let lb = StoreVariants.phoneLanguages.contains(String(b.prefix(2)))
                return la != lb ? la : StoreVariants.label(a, e.variants[a]!) < StoreVariants.label(b, e.variants[b]!)
            }.map { StoreVariantOption(key: $0, label: StoreVariants.label($0, e.variants[$0]!)) }
            let main = cache.images[v.main]
            item.preview = main
            item.animation = v.anim.flatMap { cache.gifs[$0] }
            item.previews = [FacePreview(title: String(localized: "Звичайний"), image: main)]
            if let a = v.aod {
                item.previews.append(FacePreview(title: String(localized: "Завжди на екрані"), image: cache.images[a]))
            }
            return item
        }
    }
}
