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

    /// Розмір фігури-фону навколо вмісту w×h і заокруглення
    static func badgeBox(_ g: Generator, w: Int, h: Int) -> (Int, Int, CGFloat) {
        let pad = Int(ceil(max(3, g.fontSize * 0.16)))
        switch g.badge {
        case "circle": let b = max(w, h) + pad * 2; return (b, b, CGFloat(b) / 2)
        case "capsule": let bh = h + pad * 2; return (max(bh, w + bh * 2 / 3), bh, CGFloat(bh) / 2)
        default: return (w + pad * 2, h + pad * 2, max(2, CGFloat(pad) * 0.9))
        }
    }

    /// Лише фігура-фон для вмісту w×h (для числа — під усіма його цифрами)
    static func badgeImage(_ g: Generator, w: CGFloat, h: CGFloat) -> RGBAImage? {
        guard !g.badge.isEmpty, w > 0, h > 0 else { return nil }
        let (bw, bh, r) = badgeBox(g, w: Int(w.rounded(.up)), h: Int(h.rounded(.up)))
        let fill = color(g.badgeColor)
        return render(bw, bh) { _ in
            fill.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: bw, height: bh), cornerRadius: r).fill()
        }
    }

    /// Фон під знаком (коло, капсула, квадрат): більший кадр з фігурою кольору badgeColor, знак по центру
    static func withBadge(_ g: Generator, _ frames: [RGBAImage]) -> [RGBAImage] {
        guard !g.badge.isEmpty, let f0 = frames.first else { return frames }
        let (bw, bh, r) = badgeBox(g, w: f0.w, h: f0.h)
        let fill = color(g.badgeColor)
        return frames.map { f in
            render(bw, bh) { ctx in
                fill.setFill()
                UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: bw, height: bh), cornerRadius: r).fill()
                if let cg = f.cgImage {
                    UIImage(cgImage: cg).draw(in: CGRect(x: CGFloat(bw - f.w) / 2, y: CGFloat(bh - f.h) / 2, width: CGFloat(f.w), height: CGFloat(f.h)))
                }
            }
        }
    }

    /// Атрибути рядка: шрифт, колір і міжлітерний інтервал
    static func textAttrs(_ g: Generator, _ f: UIFont) -> [NSAttributedString.Key: Any] {
        var a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color(g.color)]
        if g.tracking != 0 { a[.kern] = CGFloat(g.tracking) }
        return a
    }

    /// Ширина рядка з інтервалом (без зайвого інтервалу після останньої літери)
    static func textWidth(_ t: String, _ f: UIFont, _ g: Generator) -> CGFloat {
        let w = NSAttributedString(string: t, attributes: textAttrs(g, f)).size().width
        return t.isEmpty ? w : w - CGFloat(g.tracking)
    }

    /// Контури літер рядка одним шляхом (координати «вниз», база рядка в base)
    static func glyphPath(_ line: CTLine, base: CGPoint) -> CGPath {
        let path = CGMutablePath()
        for case let run as CTRun in (CTLineGetGlyphRuns(line) as [AnyObject]) {
            let attrs = CTRunGetAttributes(run) as NSDictionary
            let font = attrs[kCTFontAttributeName as String] as! CTFont
            let n = CTRunGetGlyphCount(run)
            var gl = [CGGlyph](repeating: 0, count: n), pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRangeMake(0, 0), &gl)
            CTRunGetPositions(run, CFRangeMake(0, 0), &pos)
            for i in 0..<n {
                if let gp = CTFontCreatePathForGlyph(font, gl[i], nil) {
                    path.addPath(gp, transform: CGAffineTransform(translationX: base.x + pos[i].x, y: base.y + pos[i].y).scaledBy(x: 1, y: -1))
                }
            }
        }
        return path
    }

    /// Рядок з ефектами: тінь → заливка (колір чи градієнт, зі своєю прозорістю) → обведення (колір, прозорість, положення).
    /// Усе малюється за контуром літер. Ширина літер стискає/розтягує рядок відносно його середини.
    static func drawStyled(_ text: String, font f: UIFont, at p: CGPoint, g: Generator, in ctx: CGContext) {
        guard g.styled else { NSAttributedString(string: text, attributes: textAttrs(g, f)).draw(at: p); return }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: f, .kern: CGFloat(g.tracking)]))
        let w = textWidth(text, f, g)
        let k = widthK(g)
        let base = CGPoint(x: p.x, y: p.y + f.ascender)
        let path = glyphPath(line, base: base)
        let big = CGRect(x: -10000, y: -10000, width: 20000, height: 20000)
        func layer(dx: CGFloat = 0, dy: CGFloat = 0, alpha: Double, _ body: () -> Void) {
            guard alpha > 0 else { return }
            ctx.saveGState()
            ctx.translateBy(x: p.x + w / 2 + dx, y: dy); ctx.scaleBy(x: k, y: 1); ctx.translateBy(x: -(p.x + w / 2), y: 0)
            ctx.setAlpha(CGFloat(min(1, alpha / 100)))
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            body()
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }
        func strokeOutline(_ c: UIColor) {
            let t = CGFloat(g.outline)
            ctx.saveGState()
            switch g.outlinePos {
            case 1: ctx.setLineWidth(t)
            case 2: ctx.addPath(path); ctx.clip(); ctx.setLineWidth(t * 2)
            default:
                let m = CGMutablePath(); m.addRect(big); m.addPath(path)
                ctx.addPath(m); ctx.clip(using: .evenOdd); ctx.setLineWidth(t * 2)
            }
            ctx.setStrokeColor(c.cgColor); ctx.setLineJoin(.round)
            ctx.addPath(path); ctx.strokePath()
            ctx.restoreGState()
        }
        if g.shadowX != 0 || g.shadowY != 0 {
            let sc = color(g.shadowColor)
            layer(dx: g.shadowX, dy: g.shadowY, alpha: g.shadowAlpha) {
                if g.fillAlpha > 0 { ctx.setFillColor(sc.cgColor); ctx.addPath(path); ctx.fillPath() }
                if g.outline > 0 { strokeOutline(sc) }
            }
        }
        layer(alpha: g.fillAlpha) {
            if g.color2.isEmpty {
                ctx.setFillColor(color(g.color).cgColor); ctx.addPath(path); ctx.fillPath()
            } else {
                ctx.saveGState()
                ctx.addPath(path); ctx.clip()
                if let gr = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(g.color).cgColor, color(g.color2).cgColor] as CFArray, locations: [0, 1]) {
                    let top = p.y + f.ascender - f.capHeight, bottom = p.y + f.ascender
                    let (s0, s1) = g.gradDir == 1 ? (CGPoint(x: p.x, y: top), CGPoint(x: p.x + w, y: bottom)) : (CGPoint(x: 0, y: top), CGPoint(x: 0, y: bottom))
                    ctx.drawLinearGradient(gr, start: s0, end: s1, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
                ctx.restoreGState()
            }
        }
        if g.outline > 0 { layer(alpha: g.outlineAlpha) { strokeOutline(color(g.outlineColor)) } }
    }

    /// Кадри «0»…«9» однакового розміру, щільно по висоті цифр (межі — за справжніми пікселями).
    /// Кадри «0»…«9». Фігура-фон для чисел — одна навколо всього числа (NumberBadge), а відстань між цифрами —
    /// «space» елемента, тому в кожну цифру окремо вони не малюються.
    static func digitFrames(_ g: Generator) -> [RGBAImage] {
        var c = g; c.badge = ""; c.tracking = 0
        return textFrames(c, (0...9).map { "\($0)" })
    }

    /// Набір рядків одним шрифтом (цифри, дні тижня, місяці, AM/PM…): однакова ширина (рядок по центру)
    /// й однакова вирізка по висоті — щоб на браслеті не стрибали.
    static func textFrames(_ g: Generator, _ texts: [String]) -> [RGBAImage] {
        guard !texts.isEmpty else { return [] }
        let texts = texts.map { $0.isEmpty ? " " : $0 }
        let f = font(g)
        var advance: CGFloat = 0
        for t in texts { advance = max(advance, textWidth(t, f, g)) }
        let pd = pad(g)
        let w = Int(ceil(advance * widthK(g))) + 2 + pd * 2
        let lh = ceil(f.lineHeight)
        let tall = Int(lh * 2) + pd * 2
        let top = lh / 2 + CGFloat(pd)
        let full = texts.map { t in
            render(w, tall) { ctx in
                let sw = textWidth(t, f, g)
                drawStyled(t, font: f, at: CGPoint(x: (CGFloat(w) - sw) / 2, y: top), g: g, in: ctx)
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
        if maxY < minY { return withBadge(g, full) }
        let y0 = max(0, minY - 1), y1 = min(tall - 1, maxY + 1)
        let h = y1 - y0 + 1
        return withBadge(g, full.map { img in
            RGBAImage(w: w, h: h, px: Array(img.px[(y0 * w * 4)..<((y1 + 1) * w * 4)]))
        })
    }

    /// Напис: рядок вибраним шрифтом і кольором, щільно обрізаний за справжніми пікселями (з полем 1 px).
    /// Текст на браслеті — лише картинками: власний текст браслета (DataItemText) на Smart Band 10 не перевірений.
    static func labelImage(_ g: Generator) -> RGBAImage? {
        let t = g.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let f = font(g)
        let size = CGSize(width: textWidth(t, f, g), height: 0)
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
        return withBadge(g, [RGBAImage(w: cw, h: ch, px: px)]).first
    }

    /// Значок одиниці («%», «°», «км»…) тим самим шрифтом і кольором, що й цифри, тієї ж висоти —
    /// щоб стояв на одній лінії з числом.
    static func unitImage(_ text: String, _ g: Generator) -> RGBAImage? {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let digit = digitFrames(g).first else { return nil }
        let f = font(g)
        let sw = textWidth(t, f, g)
        let pd = pad(g)
        let w = Int(ceil(sw * widthK(g))) + 4 + pd * 2
        let lh = ceil(f.lineHeight)
        let tall = Int(lh * 2) + pd * 2
        let top = lh / 2 + CGFloat(pd)
        let full = render(w, tall) { ctx in drawStyled(t, font: f, at: CGPoint(x: (CGFloat(w) - sw) / 2, y: top), g: g, in: ctx) }
        // та сама вертикальна вирізка, що й у цифр: шукаємо її за кадром «0»
        let zero = render(digit.w, tall) { ctx in
            drawStyled("0", font: f, at: CGPoint(x: (CGFloat(digit.w) - textWidth("0", f, g)) / 2, y: top), g: g, in: ctx)
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
