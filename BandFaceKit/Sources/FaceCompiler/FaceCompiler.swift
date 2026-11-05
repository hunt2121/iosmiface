// SPDX-License-Identifier: MIT
// Публічний інтерфейс компілятора циферблатів (порт WatchfaceCompiler 0.9.8).

import Foundation
#if canImport(ImageIO)
import ImageIO
import CoreGraphics
#endif

public enum WatchfaceCompiler {
    public static let version = "0.9.8"

    /// .bin -> файли проєкту (manifest.xml, PNG, Lua тощо).
    @discardableResult
    public static func unpack(_ data: Data, to storage: FaceStorage, options: FaceCompilerOptions = .init(),
                              log: FaceCompilerLog = .init()) throws -> FaceUnpacker {
        log.info("Loading watchface binary...")
        let u = try FaceUnpacker(data: data, options: options, log: log)
        log.info("Loaded!")
        try u.save(to: storage)
        return u
    }

    /// Файли проєкту -> .bin.
    public static func build(from storage: FaceStorage, options: FaceCompilerOptions = .init(),
                             log: FaceCompilerLog = .init()) throws -> Data {
        try FaceBuilder(storage: storage, options: options, log: log).build()
    }

    /// Перевірка назви пристрою, як у exe (усі пристрої мають однаковий набір ресурсів і джерел).
    public static func checkDevice(_ name: String, log: FaceCompilerLog) {
        if name != "band10" && name != "band9" {
            log.warn("Device \(name) is unknown. Assuming common resource and source sets.")
        }
    }
}

/// Декодування зображень для збирання: PNG — власним декодером (як stb_image), інші формати — системою.
public enum ImageDecoder {
    public static func decode(_ d: [UInt8]) -> PNG.Image? {
        if let p = PNG.decode(d) { return p }
        #if canImport(ImageIO)
        return systemDecode(d)
        #else
        return nil
        #endif
    }
}

#if canImport(ImageIO)
extension ImageDecoder {
    /// JPEG/BMP/GIF тощо: малювання в RGBA (без альфи ці формати не потребують розмноження).
    static func systemDecode(_ d: [UInt8]) -> PNG.Image? {
        guard let src = CGImageSourceCreateWithData(Data(d) as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = buf.withUnsafeMutableBytes { p in
            guard let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        // зняття розмноження на альфу
        for i in stride(from: 0, to: buf.count, by: 4) {
            let a = Int(buf[i + 3])
            if a != 0 && a != 255 {
                for c in 0..<3 { buf[i + c] = UInt8(min(255, (Int(buf[i + c]) * 255 + a / 2) / a)) }
            }
        }
        return PNG.Image(w: w, h: h, rgba: buf)
    }
}
#endif

/// Довідники для редактора.
public enum FaceCatalog {
    /// Усі джерела даних: (назва, id) у порядку exe.
    public static var sources: [(String, UInt16)] { FaceTables.sources }
    public static var jumpApps: [String] { FaceTables.jumpApps.map { $0.1 } }
    public static var fontIds: [String] { FaceTables.fontIds.map { $0.0 } }
    public static var fontWeights: [String] { FaceTables.fontWeights.map { $0.0 } }
    public static var appWidgets: [String] { FaceTables.appWidgets.map { $0.0 } }
    /// Кодування пікселів (для редактора: дізнатися, чи вміщається зображення в indexed8).
    public static func colorCount(_ rgba: [UInt8], limit: Int = 257) -> Int {
        var set = Set<UInt32>()
        var i = 0
        while i + 3 < rgba.count {
            set.insert(UInt32(rgba[i]) | UInt32(rgba[i + 1]) << 8 | UInt32(rgba[i + 2]) << 16 | UInt32(rgba[i + 3]) << 24)
            if set.count >= limit { break }
            i += 4
        }
        return set.count
    }
}
