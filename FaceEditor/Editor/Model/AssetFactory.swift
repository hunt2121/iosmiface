// SPDX-License-Identifier: MIT
// Генерація картинок для нових елементів: цифри зі шрифту, дуги, лінії, стрілки.
// Пікселі — RGBA без розмноження на альфу; у файл пишеться PNG тим самим кодером, що й у компіляторі.

import UIKit
import FaceCompiler

struct RGBAImage {
    var w: Int
    var h: Int
    var px: [UInt8]
    var png: Data { Data(PNG.encode(w, h, px)) }
    /// Формат для компілятора: indexed8, якщо вистачає 256 кольорів, інакше RGB565A8.
    var bestFormat: String { FaceCatalog.colorCount(px) <= 256 ? "indexed8" : "RGB565A8" }
}

enum AssetFactory {
    /// Малювання в RGBA (CoreGraphics малює з розмноженням — знімаємо його).
    static func render(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> RGBAImage {
        let w = max(1, w), h = max(1, h)
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        buf.withUnsafeMutableBytes { p in
            guard let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            // UIKit-координати: початок угорі ліворуч
            ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(ctx)
            draw(ctx)
            UIGraphicsPopContext()
        }
        for i in stride(from: 0, to: buf.count, by: 4) {
            let a = Int(buf[i + 3])
            if a != 0 && a != 255 {
                for c in 0..<3 { buf[i + c] = UInt8(min(255, (Int(buf[i + c]) * 255 + a / 2) / a)) }
            }
        }
        return RGBAImage(w: w, h: h, px: buf)
    }

    static func color(_ hex: String) -> UIColor {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt32(s, radix: 16) ?? 0xFFFFFF
        return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    static func font(_ g: Generator) -> UIFont {
        let size = CGFloat(g.fontSize)
        let weight: UIFont.Weight = {
            switch g.weight {
            case ..<200: return .ultraLight
            case ..<300: return .thin
            case ..<400: return .light
            case ..<500: return .regular
            case ..<600: return .medium
            case ..<700: return .semibold
            case ..<800: return .bold
            case ..<900: return .heavy
            default: return .black
            }
        }()
        var f: UIFont
        switch g.style {
        case "condensed": f = UIFont.systemFont(ofSize: size, weight: weight, width: .condensed)
        case "mono": f = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        default:
            f = UIFont.systemFont(ofSize: size, weight: weight)
            if g.style == "rounded", let d = f.fontDescriptor.withDesign(.rounded) { f = UIFont(descriptor: d, size: size) }
        }
        // однакова ширина цифр
        let feature: [UIFontDescriptor.FeatureKey: Int] = [
            UIFontDescriptor.FeatureKey(rawValue: "CTFeatureTypeIdentifier"): 6,
            UIFontDescriptor.FeatureKey(rawValue: "CTFeatureSelectorIdentifier"): 0,
        ]
        let d = f.fontDescriptor.addingAttributes([.featureSettings: [feature]])
        return UIFont(descriptor: d, size: size)
    }

    /// Кадри «0»…«9» однакового розміру, щільно по висоті цифр (межі — за справжніми пікселями).
    static func digitFrames(_ g: Generator) -> [RGBAImage] {
        let f = font(g)
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color(g.color)]
        var advance: CGFloat = 0
        for d in 0...9 { advance = max(advance, NSAttributedString(string: "\(d)", attributes: attrs).size().width) }
        let w = Int(ceil(advance)) + 2
        let lh = ceil(f.lineHeight)
        let tall = Int(lh * 2)
        let top = lh / 2
        let full = (0...9).map { d in
            render(w, tall) { _ in
                let s = NSAttributedString(string: "\(d)", attributes: attrs)
                s.draw(at: CGPoint(x: (CGFloat(w) - s.size().width) / 2, y: top))
            }
        }
        // спільні верх і низ усіх цифр
        var minY = tall, maxY = -1
        for img in full {
            for y in 0..<tall {
                var any = false
                for x in 0..<w where img.px[(y * w + x) * 4 + 3] != 0 { any = true; break }
                if any { minY = min(minY, y); maxY = max(maxY, y) }
            }
        }
        if maxY < minY { return full }
        let y0 = max(0, minY - 1), y1 = min(tall - 1, maxY + 1)
        let h = y1 - y0 + 1
        return full.map { img in
            RGBAImage(w: w, h: h, px: Array(img.px[(y0 * w * 4)..<((y1 + 1) * w * 4)]))
        }
    }

    /// Кільце: повне коло заданого кольору (для дуги й фону дуги).
    static func ring(radius: Double, width: Double, color c: String) -> RGBAImage {
        let size = Int(ceil(radius * 2 + width + 4))
        return render(size, size) { ctx in
            ctx.setStrokeColor(color(c).cgColor)
            ctx.setLineWidth(CGFloat(width))
            let m = CGFloat(size) / 2
            ctx.strokeEllipse(in: CGRect(x: m - CGFloat(radius), y: m - CGFloat(radius), width: CGFloat(radius * 2), height: CGFloat(radius * 2)))
        }
    }

    /// Смуга для лінійної шкали.
    static func bar(length: Double, width: Double, color c: String) -> RGBAImage {
        render(Int(ceil(length)), Int(ceil(width))) { ctx in
            ctx.setFillColor(color(c).cgColor)
            let r = CGRect(x: 0, y: 0, width: CGFloat(length), height: CGFloat(width))
            ctx.addPath(UIBezierPath(roundedRect: r, cornerRadius: CGFloat(width) / 2).cgPath); ctx.fillPath()
        }
    }

    /// Стрілка: заокруглена смужка, вісь обертання — внизу по центру.
    static func hand(length: Double, width: Double, color c: String) -> RGBAImage {
        let w = Int(ceil(width + 2)), h = Int(ceil(length + width + 2))
        return render(w, h) { ctx in
            ctx.setFillColor(color(c).cgColor)
            let r = CGRect(x: 1, y: 1, width: CGFloat(width), height: CGFloat(length + width))
            ctx.addPath(UIBezierPath(roundedRect: r, cornerRadius: CGFloat(width) / 2).cgPath); ctx.fillPath()
        }
    }

    /// Будь-яке зображення (з Фото/Файлів) -> RGBA; за потреби зменшення до maxSide.
    static func fromUIImage(_ img: UIImage, maxSide: CGFloat = 1000) -> RGBAImage {
        let s = min(1, maxSide / max(img.size.width, img.size.height))
        let w = Int((img.size.width * s).rounded()), h = Int((img.size.height * s).rounded())
        return render(w, h) { _ in img.draw(in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))) }
    }
}

extension RGBAImage {
    /// CGImage для показу (без розмноження: альфа «last»).
    var cgImage: CGImage? {
        let data = Data(px) as CFData
        guard let prov = CGDataProvider(data: data) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}
