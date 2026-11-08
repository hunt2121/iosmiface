// SPDX-License-Identifier: MIT
// Генерація картинок для нових елементів: цифри зі шрифту, дуги, лінії, стрілки.
// Пікселі — RGBA без розмноження на альфу; у файл пишеться PNG тим самим кодером, що й у компіляторі.

import UIKit
import FaceCompiler

struct RGBAImage {
    var w: Int
    var h: Int
    var px: [UInt8]
    /// PNG ресурсу циферблата: завжди не більше 256 кольорів (Band 10/11 знає лише indexed8 — Б-1, див. Band10.swift)
    var png: Data { Data(PNG.encode(w, h, Band10.to256(px, w, h))) }
    /// Формат для компілятора: на Band 10/11 усі картинки — indexed8 (фото зменшуються до 256 кольорів).
    var bestFormat: String { "indexed8" }
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
        // шрифт користувача з бібліотеки (.ttf / .otf / .ttc)
        if !g.font.isEmpty, let uf = FontLibrary.font(g.font, size: size) { return uf }
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

    static func widthK(_ g: Generator) -> CGFloat { CGFloat(max(0.3, min(2, g.widthPct / 100))) }
    /// Поле навколо знака під обвідку й тінь
    static func pad(_ g: Generator) -> Int { g.styled ? Int(ceil(max(0, g.outline) + max(abs(g.shadowX), abs(g.shadowY)))) + 1 : 0 }

    /// Рядок з ефектами набору цифр: тінь → обвідка (зовнішня) → заливка (колір або градієнт згори донизу).
    /// Ширина літер стискає/розтягує рядок відносно його середини. Без ефектів — звичайне малювання.
    static func drawStyled(_ text: String, font f: UIFont, at p: CGPoint, g: Generator, in ctx: CGContext) {
        let plain = NSAttributedString(string: text, attributes: [.font: f, .foregroundColor: color(g.color)])
        guard g.styled else { plain.draw(at: p); return }
        let a = NSAttributedString(string: text, attributes: [.font: f, NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true])
        let line = CTLineCreateWithAttributedString(a)
        let w = plain.size().width
        let k = widthK(g)
        let base = CGPoint(x: p.x, y: p.y + f.ascender)
        func pass(_ mode: CGTextDrawingMode, dx: CGFloat = 0, dy: CGFloat = 0, fill: UIColor? = nil, stroke: UIColor? = nil, lineWidth: CGFloat = 0, after: (() -> Void)? = nil) {
            ctx.saveGState()
            ctx.translateBy(x: p.x + w / 2 + dx, y: dy); ctx.scaleBy(x: k, y: 1); ctx.translateBy(x: -(p.x + w / 2), y: 0)
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            ctx.textPosition = base
            ctx.setTextDrawingMode(mode)
            if let fill { ctx.setFillColor(fill.cgColor) }
            if let stroke { ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(lineWidth); ctx.setLineJoin(.round) }
            CTLineDraw(line, ctx)
            after?()
            ctx.restoreGState()
        }
        if g.shadowX != 0 || g.shadowY != 0 {
            let sc = color(g.shadowColor).withAlphaComponent(0.6)
            pass(g.outline > 0 ? .fillStroke : .fill, dx: g.shadowX, dy: g.shadowY, fill: sc, stroke: sc, lineWidth: g.outline * 2)
        }
        if g.outline > 0 { pass(.stroke, stroke: color(g.outlineColor), lineWidth: g.outline * 2) }
        if g.color2.isEmpty {
            pass(.fill, fill: color(g.color))
        } else {
            // заливка градієнтом: обрис літер — як маска
            pass(.clip) {
                let cs = CGColorSpaceCreateDeviceRGB()
                if let gr = CGGradient(colorsSpace: cs, colors: [color(g.color).cgColor, color(g.color2).cgColor] as CFArray, locations: [0, 1]) {
                    ctx.drawLinearGradient(gr, start: CGPoint(x: 0, y: p.y + f.ascender - f.capHeight), end: CGPoint(x: 0, y: p.y + f.ascender),
                                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
            }
        }
    }

    /// Кадри «0»…«9» однакового розміру, щільно по висоті цифр (межі — за справжніми пікселями).
    static func digitFrames(_ g: Generator) -> [RGBAImage] {
        let f = font(g)
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color(g.color)]
        var advance: CGFloat = 0
        for d in 0...9 { advance = max(advance, NSAttributedString(string: "\(d)", attributes: attrs).size().width) }
        let pd = pad(g)
        let w = Int(ceil(advance * widthK(g))) + 2 + pd * 2
        let lh = ceil(f.lineHeight)
        let tall = Int(lh * 2) + pd * 2
        let top = lh / 2 + CGFloat(pd)
        let full = (0...9).map { d in
            render(w, tall) { ctx in
                let sw = NSAttributedString(string: "\(d)", attributes: attrs).size().width
                drawStyled("\(d)", font: f, at: CGPoint(x: (CGFloat(w) - sw) / 2, y: top), g: g, in: ctx)
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

    /// Напис: рядок вибраним шрифтом і кольором, щільно обрізаний за справжніми пікселями (з полем 1 px).
    /// Текст на браслеті — лише картинками: власний текст браслета (DataItemText) на Smart Band 10 не перевірений.
    static func labelImage(_ g: Generator) -> RGBAImage? {
        let t = g.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let f = font(g)
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color(g.color)]
        let s = NSAttributedString(string: t, attributes: attrs)
        let size = s.size()
        let pd = pad(g)
        let w = Int(ceil(size.width * widthK(g))) + 8 + pd * 2
        let lh = ceil(f.lineHeight)
        let tall = Int(lh * 2) + pd * 2
        let full = render(w, tall) { ctx in drawStyled(t, font: f, at: CGPoint(x: (CGFloat(w) - size.width) / 2, y: lh / 2 + CGFloat(pd)), g: g, in: ctx) }
        var minX = w, maxX = -1, minY = tall, maxY = -1
        for y in 0..<tall {
            for x in 0..<w where full.px[(y * w + x) * 4 + 3] != 0 {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let x0 = max(0, minX - 1), x1 = min(w - 1, maxX + 1), y0 = max(0, minY - 1), y1 = min(tall - 1, maxY + 1)
        let cw = x1 - x0 + 1, ch = y1 - y0 + 1
        var px = [UInt8](repeating: 0, count: cw * ch * 4)
        for y in 0..<ch {
            let src = ((y0 + y) * w + x0) * 4
            px.replaceSubrange((y * cw * 4)..<((y + 1) * cw * 4), with: full.px[src..<(src + cw * 4)])
        }
        return RGBAImage(w: cw, h: ch, px: px)
    }

    /// Значок одиниці («%», «°», «км»…) тим самим шрифтом і кольором, що й цифри, тієї ж висоти —
    /// щоб стояв на одній лінії з числом.
    static func unitImage(_ text: String, _ g: Generator) -> RGBAImage? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let digit = digitFrames(g).first else { return nil }
        let f = font(g)
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color(g.color)]
        let s = NSAttributedString(string: t, attributes: attrs)
        let sw = s.size().width
        let pd = pad(g)
        let w = Int(ceil(sw * widthK(g))) + 4 + pd * 2
        let lh = ceil(f.lineHeight)
        let tall = Int(lh * 2) + pd * 2
        let top = lh / 2 + CGFloat(pd)
        let full = render(w, tall) { ctx in drawStyled(t, font: f, at: CGPoint(x: (CGFloat(w) - sw) / 2, y: top), g: g, in: ctx) }
        // та сама вертикальна вирізка, що й у цифр: шукаємо її за кадром «0»
        let zero = render(digit.w, tall) { ctx in
            let z = NSAttributedString(string: "0", attributes: attrs)
            drawStyled("0", font: f, at: CGPoint(x: (CGFloat(digit.w) - z.size().width) / 2, y: top), g: g, in: ctx)
        }
        var y0 = tall
        for y in 0..<tall where y0 == tall {
            for x in 0..<digit.w where zero.px[(y * digit.w + x) * 4 + 3] != 0 { y0 = y; break }
        }
        y0 = max(0, y0 - 1)
        let h = digit.h
        guard y0 + h <= tall else { return nil }
        return RGBAImage(w: w, h: h, px: Array(full.px[(y0 * w * 4)..<((y0 + h) * w * 4)]))
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

    private static func onCircle(_ m: CGFloat, _ r: CGFloat, _ deg: Double) -> CGPoint {
        let t = deg * .pi / 180
        return CGPoint(x: m + r * CGFloat(sin(t)), y: m - r * CGFloat(cos(t)))
    }

    /// Дуга від start на range градусів (0° — угорі, за годинниковою; від'ємна — проти).
    /// Розмір картинки — як у повного кільця, центр посередині (вісь не залежить від кута).
    static func arcSegment(radius: Double, width: Double, color c: String, start: Double, range: Double, round: Bool) -> RGBAImage {
        if abs(range) >= 359.99 { return ring(radius: radius, width: width, color: c) }
        let size = Int(ceil(radius * 2 + width + 4))
        let m = CGFloat(size) / 2
        return render(size, size) { ctx in
            guard abs(range) > 0.01 else { return }
            ctx.setStrokeColor(color(c).cgColor)
            ctx.setLineWidth(CGFloat(width))
            ctx.setLineCap(round ? .round : .butt)
            // UIKit-координати (y донизу): кут від верху за годинниковою = кут від осі X мінус 90°
            ctx.addArc(center: CGPoint(x: m, y: m), radius: CGFloat(radius), startAngle: CGFloat((start - 90) * .pi / 180),
                       endAngle: CGFloat((start + range - 90) * .pi / 180), clockwise: range < 0)
            ctx.strokePath()
        }
    }

    /// Лінія під будь-яким кутом (0° — праворуч, 90° — донизу). Повертає картинку й кінці лінії в ній.
    static func lineSegment(length: Double, width: Double, color c: String, angle: Double, round: Bool) -> (RGBAImage, CGPoint, CGPoint) {
        let t = angle * .pi / 180
        var dx = cos(t) * length, dy = sin(t) * length
        if abs(dx) < 0.01 { dx = 0 }
        if abs(dy) < 0.01 { dy = 0 }
        let pd = width / 2 + 1
        let w = Int(ceil(abs(dx) + pd * 2)), h = Int(ceil(abs(dy) + pd * 2))
        let s = CGPoint(x: pd - min(0, dx), y: pd - min(0, dy))
        let e = CGPoint(x: s.x + dx, y: s.y + dy)
        let img = render(w, h) { ctx in
            ctx.setStrokeColor(color(c).cgColor)
            ctx.setLineWidth(CGFloat(width))
            ctx.setLineCap(round ? .round : .butt)
            ctx.move(to: s); ctx.addLine(to: e); ctx.strokePath()
        }
        return (img, s, e)
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

extension RGBAImage {
    /// Не більше 256 кольорів (разом із прозорістю) — для indexed8
    func quantized() -> RGBAImage { RGBAImage(w: w, h: h, px: Band10.to256(px, w, h)) }
}
