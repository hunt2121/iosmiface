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

    /// Масштаб кадру: 212×520 → 318×780 px, з запасом для капсули 96×236 pt на екрані 3x
    static let scale: CGFloat = 1.5
    /// Змінюється, коли змінюється рендер: старі кадри в кеші тоді не використовуються
    private static let version = "r1"

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
}
