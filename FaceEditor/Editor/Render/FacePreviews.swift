// SPDX-License-Identifier: MIT
// Превʼю готового .bin, намальоване з його ресурсів (фон, цифри, стрілки в повному розмірі браслета),
// а не вбудована в файл зменшена картинка на 256 кольорів. Використовує BandFace: магазин, вибраний файл.

import UIKit
import CryptoKit
import FaceCompiler

enum FacePreviews {
    /// Тема циферблата з назвою для підпису
    struct Shot {
        let image: UIImage
        /// true — екран «Завжди на екрані» (AOD)
        let alwaysOn: Bool
    }

    /// Висота капсули превʼю в BandFace (FaceCapsule 96×236 pt)
    static let capsuleHeight: CGFloat = 236
    /// Масштаб екрана телефона. Задає застосунок на старті: з фонових потоків UIScreen не читаємо
    static var displayScale: CGFloat = 3
    /// Пікселів кадру на піксель браслета — рівно під капсулу у фізичних пікселях
    /// (3x: 520 → 708 px, кадр 289×708; 2x: 472 px). Без зайвого перемасштабування й пам'яті.
    static var scale: CGFloat { capsuleHeight * displayScale / 520 }
    /// Змінюється, коли змінюється рендер або розмір: старі кадри в кеші тоді не використовуються
    private static var version: String { "r3-\(Int(displayScale))x" }

    private static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("FacePreviews")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static func key(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined() + "-" + version
    }

    /// Лише з кешу на диску: nil — ще не малювали; порожньо — циферблат не вдалося намалювати.
    static func cached(for data: Data) -> [Shot]? {
        let k = key(data)
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(k)-none").path) { return [] }
        var out: [Shot] = []
        for i in 0..<2 {
            guard let d = try? Data(contentsOf: dir.appendingPathComponent("\(k)-\(i).png")),
                  let img = UIImage(data: d, scale: 1) else { break }
            out.append(Shot(image: img, alwaysOn: i > 0))
        }
        return out.isEmpty ? nil : out
    }

    /// Кадри всіх тем (основна, потім AOD). Порожньо — циферблат не вдалося намалювати
    /// (тоді показуємо вбудоване превʼю). Кешується на диску за вмістом файла.
    static func shots(for data: Data) -> [Shot] {
        if let c = cached(for: data) { return c }
        let k = key(data)
        let shots = render(data)
        if shots.isEmpty {
            FileManager.default.createFile(atPath: dir.appendingPathComponent("\(k)-none").path, contents: Data())
        }
        for (i, s) in shots.enumerated() {
            try? s.image.pngData()?.write(to: dir.appendingPathComponent("\(k)-\(i).png"))
        }
        return shots
    }

    /// Малює без кешу: перша тема — основний екран, друга (якщо є) — «Завжди на екрані».
    static func render(_ data: Data) -> [Shot] {
        guard let unpacked = try? FaceProject.unpack(data) else { return [] }
        let (root, files) = unpacked
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString)")
        let project = FaceProject(id: tmp.lastPathComponent, folder: tmp, root: root, files: files, meta: ProjectMeta())
        let renderer = FaceRenderer(project)
        var out: [Shot] = []
        for i in 0..<min(2, project.themes.count) {
            // порожня основна тема — превʼю не довіряємо; порожній AOD просто не показуємо
            guard !project.layouts(i).isEmpty else { break }
            let (img, _) = renderer.render(theme: i, scale: scale)
            out.append(Shot(image: img, alwaysOn: i > 0))
        }
        return out
    }

    // MARK: Анімація

    /// Анімації в пам'яті: ліміт за обсягом кадрів (≈12 МБ на 16 кадрів 289×708), решту iOS викидає сама
    private static let animationCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 120 << 20
        return c
    }()

    /// Анімований кадр теми (UIImage з кадрами), якщо на ній є Sprite; nil — анімації немає.
    /// Кадри малюються з кроком інтервалу першої анімації, не більше 60.
    static func animation(for data: Data, theme: Int = 0) -> UIImage? {
        let k = "\(key(data))-\(theme)" as NSString
        if let c = animationCache.object(forKey: k) { return c }
        guard let unpacked = try? FaceProject.unpack(data) else { return nil }
        let (root, files) = unpacked
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("anim-\(UUID().uuidString)")
        let project = FaceProject(id: tmp.lastPathComponent, folder: tmp, root: root, files: files, meta: ProjectMeta())
        let sprites = project.layouts(theme).compactMap { project.resource(ref: $0.string("ref")) }.filter { $0.tag == "Sprite" }
        guard let first = sprites.first else { return nil }
        let renderer = FaceRenderer(project)
        let count = sprites.map { renderer.frames(project.resource(ref: $0.string("ref"))).count }.max() ?? 0
        guard count > 1 else { return nil }
        let interval = Double(max(16, Int(first.int("interval", 100)))) / 1000
        let frames = (0..<min(count, 60)).map { i -> UIImage in
            renderer.time = Double(i) * interval + interval / 2
            return renderer.render(theme: theme, scale: scale).0
        }
        guard let anim = UIImage.animatedImage(with: frames, duration: interval * Double(frames.count)) else { return nil }
        let px = frames.first.map { Int($0.size.width * $0.scale) * Int($0.size.height * $0.scale) * 4 } ?? 0
        animationCache.setObject(anim, forKey: k, cost: px * frames.count)
        return anim
    }
}
