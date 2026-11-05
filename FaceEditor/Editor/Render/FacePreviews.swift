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

    /// Анімоване превʼю основного екрана як GIF (до ~480 КБ), якщо на темі є Sprite; nil — анімації немає.
    /// Кешується на диску; показується покадрово (FaceAnimationView), тож у пам'яті лише один кадр.
    static func animationGIF(for data: Data, theme: Int = 0) -> Data? {
        let k = key(data)
        let file = dir.appendingPathComponent("\(k)-anim\(theme).gif")
        let none = dir.appendingPathComponent("\(k)-anim\(theme)-none")
        if let d = try? Data(contentsOf: file) { return d }
        if FileManager.default.fileExists(atPath: none.path) { return nil }
        let gif = makeGIF(data, theme: theme)
        if let gif { try? gif.write(to: file) } else { FileManager.default.createFile(atPath: none.path, contents: Data()) }
        return gif
    }

    private static func makeGIF(_ data: Data, theme: Int) -> Data? {
        guard let unpacked = try? FaceProject.unpack(data) else { return nil }
        let (root, files) = unpacked
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("anim-\(UUID().uuidString)")
        let project = FaceProject(id: tmp.lastPathComponent, folder: tmp, root: root, files: files, meta: ProjectMeta())
        let sprites = project.layouts(theme).compactMap { project.resource(ref: $0.string("ref")) }.filter { $0.tag == "Sprite" }
        guard let first = sprites.first else { return nil }
        let renderer = FaceRenderer(project)
        let count = sprites.map { renderer.frames(project.resource(ref: $0.string("ref"))).count }.max() ?? 0
        guard count > 1 else { return nil }
        let ms = max(20, Int(first.int("interval", 100)))
        var frames: [GIFEncoder.Frame] = []
        var w = 0, h = 0
        for i in 0..<min(count, 60) {
            renderer.time = (Double(i) + 0.5) * Double(ms) / 1000
            guard let cg = renderer.render(theme: theme, scale: scale).0.cgImage else { return nil }
            w = cg.width; h = cg.height
            var px = [UInt8](repeating: 0, count: w * h * 4)
            px.withUnsafeMutableBytes { p in
                guard let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            frames.append(GIFEncoder.Frame(rgba: px, durationMs: ms))
        }
        return GIFEncoder.encode(frames, width: w, height: h)
    }
}
