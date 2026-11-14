import SwiftUI
import UIKit
import CryptoKit
import BandFaceKit

/// Каталог магазину з сервера (catalog.json, формат 3). Запис має варіанти — окремий .bin на мову,
/// формат часу й пристрій; телефон сам вибирає підхожий (див. StoreVariants). У варіанта — кольори
/// циферблата й стилі з превʼю для кожного кольору.
struct RemoteCatalog: Codable {
    let categories: [Category]
    let faces: [Entry]

    struct Category: Codable {
        let key: String
        let name: [String: String]
    }

    struct Entry: Codable {
        let id: String
        let version: String
        let whatsNew: [String: String]?
        let updated: String?
        let added: String?
        let name: [String: String]
        let about: [String: String]
        let kinds: [String]
        let price: String?
        let bands: [Int]
        let variants: [String: Variant]
    }

    struct Variant: Codable {
        let faceId: String
        let size: Int
        let sha256: String
        let langs: [String]
        let clock: String?
        let bands: [Int]?
        let download: String
        let colors: [String]
        let styles: [Style]
    }

    struct Style: Codable {
        let name: String
        let previews: [Preview]
        let anim: String?
    }

    struct Preview: Codable {
        let main: String
        let aod: String?
    }
}

/// Адреса сервера магазину — у Info.plist (BandFaceStoreURL, задається в project.yml).
/// Порожня — магазин порожній.
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
    private static var catalogFile: URL { dir.appendingPathComponent("catalog-v3.json") }

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
        prune(catalog)
        return catalog
    }

    private static func local(_ path: String) -> URL { dir.appendingPathComponent(path.replacingOccurrences(of: "/", with: "_")) }

    /// Превʼю за шляхом з каталогу («b/<відбиток>.png»). Шлях — відбиток вмісту, тож файл ніколи не змінюється:
    /// кеш на диску назавжди, а зміна превʼю на сервері — це новий шлях
    static func file(_ path: String) async -> Data? {
        let url = local(path)
        if let d = try? Data(contentsOf: url) { return d }
        guard let base, let r = try? await URLSession.shared.data(from: base.appendingPathComponent(path)),
              (r.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        try? r.0.write(to: url, options: .atomic)
        return r.0
    }

    /// Прибирає з кешу превʼю, на які новий каталог уже не посилається
    private static func prune(_ catalog: RemoteCatalog) {
        var keep: Set<String> = ["catalog-v3.json"]
        for e in catalog.faces {
            for v in e.variants.values {
                for s in v.styles {
                    if let a = s.anim { keep.insert(local(a).lastPathComponent) }
                    for p in s.previews {
                        keep.insert(local(p.main).lastPathComponent)
                        if let a = p.aod { keep.insert(local(a).lastPathComponent) }
                    }
                }
            }
        }
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where !keep.contains(name) {
            try? fm.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// Файл варіанта для встановлення (платного — з ID покупки App Store):
    /// перевіряються розмір, sha256 і ID на браслеті
    static func download(_ v: RemoteCatalog.Variant, transaction: String? = nil) async throws -> FaceFile {
        guard let base, let url = URL(string: v.download, relativeTo: base.appendingPathComponent("/")) else {
            throw URLError(.badURL)
        }
        var r = URLRequest(url: url)
        if let transaction {
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONEncoder().encode(["transaction": transaction])
        }
        let (data, response) = try await URLSession.shared.data(for: r)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 402 { throw StoreError(String(localized: "Покупку не підтверджено")) }
        if status == 503 && transaction != nil { throw StoreError(String(localized: "Покупки в магазині поки не налаштовано")) }
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

/// Версії циферблата: «1.0», «1.10» (порівняння за числами: 1.10 > 1.9)
enum StoreVersions {
    static func older(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let d = (i < x.count ? x[i] : 0) - (i < y.count ? y[i] : 0)
            if d != 0 { return d < 0 }
        }
        return false
    }
}

/// Вибір варіанта: пристрій, потім мова телефона (за списком мов у налаштуваннях), інакше «для всіх інших»
/// ("*"); серед них — той, чий формат часу збігається з налаштуванням телефона (точний збіг важливіший)
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

    /// Варіанти для пристрою (модель Smart Band; невідома — 10)
    static func forBand(_ variants: [String: RemoteCatalog.Variant], _ band: Int) -> [String: RemoteCatalog.Variant] {
        let fit = variants.filter { $0.value.bands?.contains(band) ?? true }
        return fit.isEmpty ? variants : fit
    }

    static func choose(_ all: [String: RemoteCatalog.Variant], band: Int) -> String? {
        let variants = forBand(all, band)
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

/// Превʼю з сервера в пам'яті: ті самі об'єкти для картки, сторінки й меню
@MainActor
final class StorePreviewCache {
    static let shared = StorePreviewCache()
    private(set) var images: [String: UIImage] = [:]
    private(set) var gifs: [String: Data] = [:]

    func image(_ path: String?) -> UIImage? { path.flatMap { images[$0] } }
    func gif(_ path: String?) -> Data? { path.flatMap { gifs[$0] } }

    /// Завантажує відсутні (з диска або сервера); true — щось додалося
    func load(png: [String], gif: [String]) async -> Bool {
        let pngs = Array(Set(png.filter { images[$0] == nil }))
        let anims = Array(Set(gif.filter { gifs[$0] == nil }))
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

    /// На головній — лише основне превʼю й анімація основного стилю вибраних варіантів
    func loadGrid(_ faces: [StoreFace]) async -> Bool {
        await load(png: faces.compactMap { $0.look(style: 0, color: 0)?.main },
                   gif: faces.compactMap { $0.styles.first?.anim })
    }
}

/// Стиль варіанта: назва з файла, превʼю для кожного кольору, анімація основного кольору
struct StoreStyle: Equatable {
    let name: String
    let previews: [(main: String, aod: String?)]
    let anim: String?

    static func == (a: StoreStyle, b: StoreStyle) -> Bool {
        a.name == b.name && a.anim == b.anim && a.previews.map(\.main) == b.previews.map(\.main)
    }
}

extension StoreFace {
    /// Шляхи превʼю стилю й кольору
    func look(style: Int, color: Int) -> (main: String, aod: String?)? {
        guard styles.indices.contains(style) else { return nil }
        let p = styles[style].previews
        return p.indices.contains(color) ? p[color] : p.first
    }
}

extension StoreCatalog {
    /// Записи з сервера, кожен — вибраним варіантом. Вибір: ручний (override) → той, що вже на браслеті →
    /// автоматичний (пристрій, мова, формат часу)
    @MainActor
    static func faces(_ catalog: RemoteCatalog, installed: [String: String], overrides: [String: String], band: Int,
                      prices: [String: String], owned: Set<String>) -> [StoreFace] {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "UTC")
        day.dateFormat = "yyyy-MM-dd"
        let kinds = Dictionary(catalog.categories.map { ($0.key, StoreVariants.text($0.name, variant: nil)) }, uniquingKeysWith: { a, _ in a })
        let cache = StorePreviewCache.shared
        return catalog.faces.compactMap { e in
            let onBand = e.variants.first { installed[$0.value.faceId] != nil }?.key
            guard let key = overrides[e.id].flatMap({ e.variants[$0] != nil ? $0 : nil }) ?? onBand
                    ?? StoreVariants.choose(e.variants, band: band), let v = e.variants[key] else { return nil }
            var item = StoreFace(id: v.faceId, name: StoreVariants.text(e.name, variant: v),
                                 kinds: e.kinds.compactMap { kinds[$0] }, version: e.version,
                                 about: StoreVariants.text(e.about, variant: v), price: e.price, preview: nil)
            item.kindKeys = e.kinds
            item.key = e.id
            item.size = v.size
            item.remote = v
            item.allIDs = Set(e.variants.values.map(\.faceId))
            item.added = (e.added ?? e.updated).flatMap { day.date(from: String($0.prefix(10))) }
            item.updated = e.updated.flatMap { day.date(from: String($0.prefix(10))) }
            item.bands = e.bands
            item.variantKey = key
            item.colors = v.colors
            item.styles = v.styles.map { s in StoreStyle(name: s.name, previews: s.previews.map { ($0.main, $0.aod) }, anim: s.anim) }
            item.whatsNew = e.whatsNew.map { StoreVariants.text($0, variant: v) } ?? ""
            if let p = e.price {
                item.priceText = prices[p]
                item.owned = owned.contains(p)
            }
            let options = StoreVariants.forBand(e.variants, band)
            item.variantOptions = options.keys.sorted { a, b in
                // спершу мова телефона, далі за назвою
                let la = StoreVariants.phoneLanguages.contains(String(a.prefix(2)))
                let lb = StoreVariants.phoneLanguages.contains(String(b.prefix(2)))
                return la != lb ? la : StoreVariants.label(a, options[a]!) < StoreVariants.label(b, options[b]!)
            }.map { StoreVariantOption(key: $0, label: StoreVariants.label($0, options[$0]!)) }
            let main = item.look(style: 0, color: 0)
            item.preview = cache.image(main?.main)
            item.animation = cache.gif(item.styles.first?.anim)
            item.previews = [FacePreview(title: String(localized: "Звичайний"), image: item.preview)]
            if let a = main?.aod {
                item.previews.append(FacePreview(title: String(localized: "Завжди на екрані"), image: cache.image(a)))
            }
            return item
        }
    }
}
