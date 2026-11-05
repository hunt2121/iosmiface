// SPDX-License-Identifier: MIT
// Превʼю готового .bin, намальоване з його ресурсів (а не вбудована зменшена картинка).
// Одне джерело для всього застосунку: магазин, сторінка циферблата, меню «Встановлено», вибраний файл.
// Для кожного файла один раз (за один розпак) малюються основний екран, «Завжди на екрані» і GIF анімації;
// усе в 256 кольорах, на диску — палітрові PNG і GIF, у пам'яті — ті самі UIImage для всіх розділів.

import UIKit
import CryptoKit
import FaceCompiler

enum FacePreviews {
    /// Усі превʼю одного циферблата
    final class Shots {
        let main: UIImage
        /// «Завжди на екрані», якщо в циферблата є друга тема
        let alwaysOn: UIImage?
        /// Анімація основного екрана (GIF), якщо на ньому є Sprite
        let gif: Data?
        init(main: UIImage, alwaysOn: UIImage?, gif: Data?) { self.main = main; self.alwaysOn = alwaysOn; self.gif = gif }
    }

    /// Висота капсули превʼю в BandFace (FaceCapsule 96×236 pt)
    static let capsuleHeight: CGFloat = 236
    /// Масштаб екрана телефона. Задає застосунок на старті: з фонових потоків UIScreen не читаємо
    static var displayScale: CGFloat = 3
    /// Пікселів кадру на піксель браслета — рівно під капсулу у фізичних пікселях (3x: 520 → 708 px)
    static var scale: CGFloat { capsuleHeight * displayScale / 520 }
    /// Змінюється разом із рендером або розміром; файли інших версій видаляються
    private static var version: String { "r4-\(Int(displayScale))x" }

    private static let dir: URL = {
        let fm = FileManager.default
        let d = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("FacePreviews")
        try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        // старі версії превʼю більше не потрібні
        for name in (try? fm.contentsOfDirectory(atPath: d.path)) ?? [] where !name.contains("-\(version)") {
            try? fm.removeItem(at: d.appendingPathComponent(name))
        }
        return d
    }()

    /// Ті самі об'єкти для всіх розділів: картинка декодується один раз
    private static let memory: NSCache<NSString, Shots> = {
        let c = NSCache<NSString, Shots>()
        c.countLimit = 40
        return c
    }()
    /// Малювання по черзі: два розділи, що одночасно просять той самий циферблат, не малюють його двічі
    private static let queue = DispatchQueue(label: "FacePreviews", qos: .userInitiated)

    private static func key(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined() + "-" + version
    }

    /// Лише з пам'яті або диска — швидко, можна з головного потоку. nil — ще не малювали або не вдалося.
    static func cached(for data: Data) -> Shots? {
        load(key(data))
    }

    /// З кешу або малює. Викликати не з головного потоку. nil — циферблат не вдалося намалювати
    /// (тоді показуємо вбудоване у файл превʼю).
    static func get(for data: Data) -> Shots? {
        let k = key(data)
        if let s = memory.object(forKey: k as NSString) { return s }
        return queue.sync { () -> Shots? in
            if let s = load(k) { return s }
            if FileManager.default.fileExists(atPath: url(k, "none").path) { return nil }
            guard let s = render(data) else {
                FileManager.default.createFile(atPath: url(k, "none").path, contents: Data())
                return nil
            }
            store(s, k)
            return s
        }
    }

    // MARK: Кеш

    private static func url(_ k: String, _ part: String) -> URL { dir.appendingPathComponent("\(k)-\(part)") }

    private static func load(_ k: String) -> Shots? {
        if let s = memory.object(forKey: k as NSString) { return s }
        guard let d = try? Data(contentsOf: url(k, "main.png")), let main = UIImage(data: d, scale: 1) else { return nil }
        let aod = (try? Data(contentsOf: url(k, "aod.png"))).flatMap { UIImage(data: $0, scale: 1) }
        let gif = try? Data(contentsOf: url(k, "anim.gif"))
        let s = Shots(main: main, alwaysOn: aod, gif: gif)
        memory.setObject(s, forKey: k as NSString)
        return s
    }

    private static func store(_ s: Shots, _ k: String) {
        memory.setObject(s, forKey: k as NSString)
    }

    // MARK: Малювання

    /// Один розпак: основний екран, AOD і анімація. Картинки зберігаються як палітрові PNG (256 кольорів).
    private static func render(_ data: Data) -> Shots? {
        guard let unpacked = try? FaceProject.unpack(data) else { return nil }
        let (root, files) = unpacked
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString)")
        let project = FaceProject(id: tmp.lastPathComponent, folder: tmp, root: root, files: files, meta: ProjectMeta())
        // порожня основна тема — превʼю не довіряємо
        guard !project.layouts(0).isEmpty else { return nil }
        let renderer = FaceRenderer(project)
        let k = key(data)

        func png(_ theme: Int, _ part: String) -> UIImage? {
            guard let px = pixels(renderer, theme) else { return nil }
            let (idx, pal) = GIFEncoder.indexed(px.rgba)
            let d = Data(PNG.encodeIndexed(px.w, px.h, idx, palette: pal))
            try? d.write(to: url(k, part))
            return UIImage(data: d, scale: 1)
        }
        guard let main = png(0, "main.png") else { return nil }
        let aod = project.themes.count > 1 && !project.layouts(1).isEmpty ? png(1, "aod.png") : nil
        let gif = animation(project, renderer)
        if let gif { try? gif.write(to: url(k, "anim.gif")) }
        return Shots(main: main, alwaysOn: aod, gif: gif)
    }

    /// Кадр теми у RGBA рівно під капсулу
    private static func pixels(_ r: FaceRenderer, _ theme: Int) -> (rgba: [UInt8], w: Int, h: Int)? {
        guard let cg = r.render(theme: theme, scale: scale).0.cgImage else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok = px.withUnsafeMutableBytes { p -> Bool in
            guard let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (px, w, h) : nil
    }

    /// GIF основного екрана, якщо на ньому є Sprite: кадри з кроком інтервалу першої анімації (не більше 60)
    private static func animation(_ project: FaceProject, _ renderer: FaceRenderer) -> Data? {
        let sprites = project.layouts(0).compactMap { project.resource(ref: $0.string("ref")) }.filter { $0.tag == "Sprite" }
        guard let first = sprites.first else { return nil }
        let count = sprites.map { renderer.frames(project.resource(ref: $0.string("ref"))).count }.max() ?? 0
        guard count > 1 else { return nil }
        let ms = max(20, Int(first.int("interval", 100)))
        var frames: [GIFEncoder.Frame] = []
        var w = 0, h = 0
        for i in 0..<min(count, 60) {
            renderer.time = (Double(i) + 0.5) * Double(ms) / 1000
            guard let px = pixels(renderer, 0) else { return nil }
            w = px.w; h = px.h
            frames.append(GIFEncoder.Frame(rgba: px.rgba, durationMs: ms))
        }
        renderer.time = 0
        return GIFEncoder.encode(frames, width: w, height: h)
    }

    // MARK: Мініатюри проєктів редактора

    private static let thumbs: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 60
        return c
    }()

    /// Ключ проєкту: змінюється після кожної зміни проєкту
    static func key(_ p: FaceProject) -> String {
        "p-\(p.id)-\(Int(p.meta.modified.timeIntervalSince1970 * 1000))-\(version)"
    }

    /// Мініатюра з пам'яті або диска (миттєво; nil — ще не малювали)
    static func cachedThumbnail(_ p: FaceProject) -> UIImage? {
        let k = key(p)
        if let t = thumbs.object(forKey: k as NSString) { return t }
        guard let d = try? Data(contentsOf: url(k, "main.png")), let t = UIImage(data: d, scale: 1) else { return nil }
        thumbs.setObject(t, forKey: k as NSString)
        return t
    }

    /// Мініатюра проєкту під капсулу (256 кольорів). Малюється заново лише після зміни проєкту.
    /// Можна не з головного потоку.
    static func thumbnail(_ p: FaceProject) -> UIImage? {
        if let t = cachedThumbnail(p) { return t }
        let k = key(p)
        return queue.sync { () -> UIImage? in
            if let t = cachedThumbnail(p) { return t }
            dropOld(p)
            guard let px = pixels(FaceRenderer(p), 0) else { return nil }
            let (idx, pal) = GIFEncoder.indexed(px.rgba)
            let d = Data(PNG.encodeIndexed(px.w, px.h, idx, palette: pal))
            try? d.write(to: url(k, "main.png"))
            guard let t = UIImage(data: d, scale: 1) else { return nil }
            thumbs.setObject(t, forKey: k as NSString)
            return t
        }
    }

    /// Анімація проєкту (GIF), якщо на основному екрані є Sprite; nil — анімації немає
    static func projectGIF(_ p: FaceProject) -> Data? {
        let k = key(p)
        if let d = try? Data(contentsOf: url(k, "anim.gif")) { return d }
        if FileManager.default.fileExists(atPath: url(k, "noanim").path) { return nil }
        return queue.sync { () -> Data? in
            if let d = try? Data(contentsOf: url(k, "anim.gif")) { return d }
            let gif = animation(p, FaceRenderer(p))
            if let gif { try? gif.write(to: url(k, "anim.gif")) }
            else { FileManager.default.createFile(atPath: url(k, "noanim").path, contents: Data()) }
            return gif
        }
    }

    /// Файли попередніх версій цього проєкту більше не потрібні
    private static func dropOld(_ p: FaceProject) {
        let prefix = "p-\(p.id)-", current = key(p)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        where name.hasPrefix(prefix) && !name.hasPrefix(current) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }
}
