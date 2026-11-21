import SwiftUI
import UIKit
import CoreText

/// Кольори циферблата на картці магазину: до 4 кружечків 15 pt внахлест, далі «+N»
struct ColorDots: View {
    let colors: [String]

    var body: some View {
        if colors.count > 1 {
            HStack(spacing: -5) {
                ForEach(Array(colors.prefix(4).enumerated()), id: \.offset) { i, c in
                    Circle().fill(Color(hex: c))
                        .frame(width: 15, height: 15)
                        // облямівка кольору картки — кружечки розділені; тонкий контур — світлий колір на світлому тлі
                        .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 1.5))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                        .zIndex(Double(10 - i))
                }
                if colors.count > 4 {
                    Text(verbatim: "+\(colors.count - 4)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(StoreText.colors(colors.count)))
        }
    }
}

extension Color {
    /// «#RRGGBB»
    init(hex: String) {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

/// Кількості з правильними формами слів мовою інтерфейсу: «3 стилі», «5 кольорів»
enum StoreText {
    private static var lang: String { Bundle.main.preferredLocalizations.first ?? "en" }

    private static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let a = n % 10, b = n % 100
        if a == 1 && b != 11 { return "\(n) \(one)" }
        if (2...4).contains(a) && !(12...14).contains(b) { return "\(n) \(few)" }
        return "\(n) \(many)"
    }

    static func styles(_ n: Int) -> String {
        switch lang {
        case "uk": return plural(n, "стиль", "стилі", "стилів")
        case "ru": return plural(n, "стиль", "стиля", "стилей")
        default: return n == 1 ? "1 style" : "\(n) styles"
        }
    }

    static func colors(_ n: Int) -> String {
        switch lang {
        case "uk": return plural(n, "колір", "кольори", "кольорів")
        case "ru": return plural(n, "цвет", "цвета", "цветов")
        default: return n == 1 ? "1 color" : "\(n) colors"
        }
    }

    /// Число з розділювачем розрядів мови інтерфейсу: «1 240»
    private static func grouped(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: lang)
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    /// Слово до короткого числа в капсулі сторінки — завжди однакове: «1.2k завантажень», «7 переглядів»
    static var downloadsWord: String {
        switch lang { case "uk": return "завантажень"; case "ru": return "загрузок"; default: return "downloads" }
    }
    static var viewsWord: String {
        switch lang { case "uk": return "переглядів"; case "ru": return "просмотров"; default: return "views" }
    }

    /// Коротко для картки: до 999 — повністю; далі 1.1k, 15.5k, 120k, 1.2M (один знак до 100, округлення вниз)
    static func short(_ n: Int) -> String {
        if n < 1000 { return "\(n)" }
        func cut(_ v: Double, _ suffix: String) -> String {
            if v >= 100 { return "\(Int(v))\(suffix)" }
            let t = (v * 10).rounded(.down) / 10
            return (t == t.rounded(.down) ? "\(Int(t))" : String(format: "%.1f", t)) + suffix
        }
        if n < 1_000_000 { return cut(Double(n) / 1000, "k") }
        return cut(Double(n) / 1_000_000, "M")
    }

    private static func pluralWord(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let a = n % 10, b = n % 100
        if a == 1 && b != 11 { return one }
        if (2...4).contains(a) && !(12...14).contains(b) { return few }
        return many
    }

    /// «1 240 завантажень»
    static func downloads(_ n: Int) -> String {
        switch lang {
        case "uk": return grouped(n) + " " + pluralWord(n, "завантаження", "завантаження", "завантажень")
        case "ru": return grouped(n) + " " + pluralWord(n, "загрузка", "загрузки", "загрузок")
        default: return grouped(n) + (n == 1 ? " download" : " downloads")
        }
    }

    /// «3 400 переглядів»
    static func views(_ n: Int) -> String {
        switch lang {
        case "uk": return grouped(n) + " " + pluralWord(n, "перегляд", "перегляди", "переглядів")
        case "ru": return grouped(n) + " " + pluralWord(n, "просмотр", "просмотра", "просмотров")
        default: return grouped(n) + (n == 1 ? " view" : " views")
        }
    }

    /// «2 стилі · 4 кольори»
    static func looks(styles s: Int, colors c: Int) -> String {
        var parts: [String] = []
        if s > 1 { parts.append(styles(s)) }
        if c > 1 { parts.append(colors(c)) }
        return parts.joined(separator: " · ")
    }
}

/// Поля значків SF Symbols до «чорнила» (поля тексту — `InkMetrics.bearings` у StoreInfo.swift)
extension InkMetrics {
    private static var symbols: [String: (UIImage, CGFloat, CGFloat, CGFloat, CGFloat)] = [:]

    /// Значок, як його й показуємо, та поля від краю картинки до чорнила зліва й справа
    static func symbol(_ name: String, font: UIFont) -> (image: UIImage, left: CGFloat, right: CGFloat) {
        let s = scanned(name, font)
        return (s.0, s.1, s.2)
    }

    /// Поля до чорнила зверху й знизу (для вертикального вирівнювання за чорнилом)
    static func symbolVertical(_ name: String, font: UIFont) -> (top: CGFloat, bottom: CGFloat) {
        let s = scanned(name, font)
        return (s.3, s.4)
    }

    private static func scanned(_ name: String, _ font: UIFont) -> (UIImage, CGFloat, CGFloat, CGFloat, CGFloat) {
        let key = "\(name)|\(font.pointSize)|\(font.fontName)"
        if let hit = symbols[key] { return hit }
        let image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(font: font)) ?? UIImage()
        let e = scan(image)
        let r = (image, e.0, e.1, e.2, e.3)
        symbols[key] = r
        return r
    }

    /// Малюємо значок чорним у 8× і шукаємо крайні стовпчики з чорнилом
    private static var strokes: [String: CGFloat] = [:]

    /// Товщина лінії значка: перший відрізок чорнила зверху в середньому стовпчику (для ока — верхня дуга)
    static func strokeTop(_ name: String, font: UIFont) -> CGFloat {
        let key = "\(name)|\(font.pointSize)|\(font.fontName)"
        if let hit = strokes[key] { return hit }
        let image = symbol(name, font: font).image
        let size = image.size, scale: CGFloat = 8
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.withTintColor(.black, renderingMode: .alwaysOriginal).draw(at: .zero)
        }
        var run = 0
        if let cg = rendered.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) {
            let bpp = cg.bitsPerPixel / 8, row = cg.bytesPerRow, x = cg.width / 2
            var started = false
            for y in 0..<cg.height {
                let p = y * row + x * bpp
                var alpha = 0
                for b in 0..<bpp { alpha = max(alpha, Int(bytes[p + b])) }
                if alpha > 127 { started = true; run += 1 } else if started { break }
            }
        }
        let w = max(1, CGFloat(run) / scale)
        strokes[key] = w
        return w
    }

    private static func scan(_ image: UIImage) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return (0, 0, 0, 0) }
        let scale: CGFloat = 8
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.withTintColor(.black, renderingMode: .alwaysOriginal).draw(at: .zero)
        }
        guard let cg = rendered.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return (0, 0, 0, 0) }
        let bpp = cg.bitsPerPixel / 8, row = cg.bytesPerRow
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let p = y * row + x * bpp
                // чорне на прозорому: усе, крім прозорого тла, має ненульовий байт (альфа)
                var ink = false
                for b in 0..<bpp where bytes[p + b] > 24 { ink = true; break }
                if ink { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
            }
        }
        guard maxX >= 0 else { return (0, 0, 0, 0) }
        return (CGFloat(minX) / scale, size.width - CGFloat(maxX + 1) / scale,
                CGFloat(minY) / scale, size.height - CGFloat(maxY + 1) / scale)
    }
}

/// «👁 4.8k  ↓ 1.1k» — спершу перегляди, потім завантаження; вирівняно за чорнилом: від значка до числа рівно 3 pt,
/// уся група точно по центру. Між парами minGap (14 pt); з roomy малі числа трохи розсунуті: чим коротші пари,
/// тим більший проміжок — від minGap (від «4.8k  1.1k» і довших) до minGap + 10 (для «0  0»), у масштабі шрифту
struct StoreStatsRow: View {
    let downloads: String
    let views: String
    let font: UIFont
    var roomy = false
    /// Числа без слів («1.2k», «3.4k») — проміжок між парами рахуємо за ними, щоб слова його не змінювали
    var gapBasis: (String, String)? = nil
    /// Найменший проміжок між парами (до масштабу шрифту): 14 — сторінка циферблата, 18 — картка магазину
    var minGap: CGFloat = 14
    /// Найбільший проміжок (для зовсім малих чисел): типово minGap + 10; картка магазину — 37
    var maxGap: CGFloat? = nil

    init(downloads: String, views: String, font: UIFont, roomy: Bool = false,
         gapBasis: (String, String)? = nil, minGap: CGFloat = 14, maxGap: CGFloat? = nil) {
        self.downloads = downloads
        self.views = views
        self.font = font
        self.roomy = roomy
        self.gapBasis = gapBasis
        self.minGap = minGap
        self.maxGap = maxGap
    }

    /// Відстань між штрихами: значок → число
    private static let iconGap: CGFloat = 3

    var body: some View {
        // око — заввишки з цифри, трохи товще за текст
        let eyeFont = Self.iconFont("eye", font, 1)
        let eye = InkMetrics.symbol("eye", font: eyeFont)
        // значок завантажень — лоток зі стрілкою: на 3 пікселі вужчий за око, на піксель вища й нижча за цифри, лінії такої ж товщини, як в ока
        let arrow = (image: Self.arrowImage(width: inkWidth(eye) - Self.onePixel * 3, height: Self.digitHeight(font) + Self.onePixel * 2,
                                            line: InkMetrics.strokeTop("eye", font: eyeFont)), left: CGFloat(0), right: CGFloat(0))
        let dInk = InkMetrics.bearings(downloads, font: font), vInk = InkMetrics.bearings(views, font: font)
        let (gd, gv) = gapBasis ?? (downloads, views)
        let gap = roomy ? Self.gap(inkWidth(arrow) + Self.iconGap + Self.onePixel + textInk(gd, InkMetrics.bearings(gd, font: font))
                                   + inkWidth(eye) + Self.iconGap + textInk(gv, InkMetrics.bearings(gv, font: font)), font: font, min: minGap, max: maxGap) : minGap

        HStack(spacing: 0) {
            pair(eye, views, vInk, dy: Self.iconShift("eye", eyeFont, text: font))
            pair(arrow, downloads, dInk, dy: font.ascender - Self.digitHeight(font) / 2 - font.lineHeight / 2, extra: Self.onePixel)
                .padding(.leading, gap - vInk.right - arrow.left)
        }
        .font(Font(font as CTFont))
        .foregroundStyle(.secondary)
        .fixedSize()
        // поля по краях групи різні (у стрілки й у цифр) — зсуваємо, щоб по центру було саме чорнило
        .offset(x: (dInk.right - eye.left) / 2)
        .frame(maxWidth: .infinity)
    }

    /// Висота чорнила цифри «1» над базовою лінією — справжня висота плоских цифр (capHeight шрифту від неї трохи відрізняється)
    static func digitHeight(_ font: UIFont) -> CGFloat {
        var ch: UniChar = 0x31, g: CGGlyph = 0
        guard CTFontGetGlyphsForCharacters(font as CTFont, &ch, &g, 1) else { return font.capHeight }
        var r = CGRect.zero
        CTFontGetBoundingRectsForGlyphs(font as CTFont, .horizontal, &g, &r, 1)
        return r.maxY > 0 ? r.maxY : font.capHeight
    }

    /// Шрифт для значка: його чорнило заввишки ratio × висота цифр (висота великих літер шрифту)
    private static var arrows: [String: UIImage] = [:]

    /// Лоток зі стрілкою вниз, малюнок рівно по чорнилу (без полів) width × height; лінії line, круглі кінці
    static func arrowImage(width: CGFloat, height: CGFloat, line: CGFloat) -> UIImage {
        let key = "\(width)|\(height)|\(line)"
        if let hit = arrows[key] { return hit }
        let W = width, H = height, r = line / 2
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: format).image { _ in
            let p = UIBezierPath()
            // стрілка
            let cx = W / 2, tip = H * 0.50, arm = H * 0.24
            p.move(to: CGPoint(x: cx, y: r)); p.addLine(to: CGPoint(x: cx, y: tip))
            p.move(to: CGPoint(x: cx - arm, y: tip - arm)); p.addLine(to: CGPoint(x: cx, y: tip)); p.addLine(to: CGPoint(x: cx + arm, y: tip - arm))
            // лоток: боки й дно з заокругленими кутами
            let l = r, rr = W - r, b = H - r, rim = H * 0.58, rad = H * 0.12
            p.move(to: CGPoint(x: l, y: rim)); p.addLine(to: CGPoint(x: l, y: b - rad))
            p.addQuadCurve(to: CGPoint(x: l + rad, y: b), controlPoint: CGPoint(x: l, y: b))
            p.addLine(to: CGPoint(x: rr - rad, y: b))
            p.addQuadCurve(to: CGPoint(x: rr, y: b - rad), controlPoint: CGPoint(x: rr, y: b))
            p.addLine(to: CGPoint(x: rr, y: rim))
            // обідок з виїмкою посередині
            p.move(to: CGPoint(x: l, y: rim)); p.addLine(to: CGPoint(x: W * 0.30, y: rim))
            p.addLine(to: CGPoint(x: W * 0.36, y: H * 0.74)); p.addLine(to: CGPoint(x: W * 0.64, y: H * 0.74))
            p.addLine(to: CGPoint(x: W * 0.70, y: rim)); p.addLine(to: CGPoint(x: rr, y: rim))
            p.lineWidth = line
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            UIColor.black.setStroke()
            p.stroke()
        }.withRenderingMode(.alwaysTemplate)
        arrows[key] = image
        return image
    }

    /// Один піксель екрана в точках
    static var onePixel: CGFloat { 1 / max(1, UIScreen.main.scale) }

    /// Шрифт для значка (напівжирніший за текст — значок трохи товщий): чорнило заввишки ratio × висота цифр + extra
    static func iconFont(_ name: String, _ font: UIFont, _ ratio: CGFloat, extra: CGFloat = 0) -> UIFont {
        let base = UIFont.systemFont(ofSize: font.pointSize, weight: .medium)
        let v = InkMetrics.symbolVertical(name, font: base)
        let ink = InkMetrics.symbol(name, font: base).image.size.height - v.top - v.bottom
        guard ink > 0 else { return base }
        return base.withSize(base.pointSize * (digitHeight(font) * ratio + extra) / ink)
    }

    /// Зсув значка по вертикалі: центр його чорнила — на центрі цифр (а не центр картинки на центрі рядка тексту)
    static func iconShift(_ name: String, _ iconFont: UIFont, text font: UIFont) -> CGFloat {
        let img = InkMetrics.symbol(name, font: iconFont).image
        let v = InkMetrics.symbolVertical(name, font: iconFont)
        let inkCenter = v.top + (img.size.height - v.top - v.bottom) / 2 - img.size.height / 2   // від центру картинки
        let digitsCenter = font.ascender - digitHeight(font) / 2 - font.lineHeight / 2              // від центру рядка
        return digitsCenter - inkCenter
    }

    /// Проміжок між парами за шириною чорнила обох пар: ≤ 36 (×масштаб) — min + 10, ≥ 64 — min, між ними плавно
    static func gap(_ pairs: CGFloat, font: UIFont, min minGap: CGFloat = 14, max maxGap: CGFloat? = nil) -> CGFloat {
        let k = font.pointSize / 10.5
        let t = min(1, max(0, (64 * k - pairs) / (28 * k)))
        return (minGap + ((maxGap ?? minGap + 10) - minGap) * t) * k
    }

    /// Значок і число: від чорнила значка до чорнила числа — 3 pt
    private func pair(_ icon: (image: UIImage, left: CGFloat, right: CGFloat), _ text: String,
                      _ ink: (left: CGFloat, right: CGFloat), dy: CGFloat = 0, extra: CGFloat = 0) -> some View {
        HStack(spacing: 0) {
            Image(uiImage: icon.image).renderingMode(.template).offset(y: dy)
            Text(verbatim: text)
                .padding(.leading, Self.iconGap + extra - icon.right - ink.left)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func inkWidth(_ icon: (image: UIImage, left: CGFloat, right: CGFloat)) -> CGFloat {
        icon.image.size.width - icon.left - icon.right
    }

    private func textInk(_ text: String, _ ink: (left: CGFloat, right: CGFloat)) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width - ink.left - ink.right
    }

    /// Звичайний шрифт стилю (як «102 КБ · v2.0» поруч) з цифрами однакової ширини (числа змінюються — сусіди не зсуваються)
    static func textFont(_ style: UIFont.TextStyle) -> UIFont {
        UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: .regular)
    }
}

/// Рядок на картці магазину над кнопкою: «👁 4.8k   ↓ 1.1k» (числа коротко, без слів), малі числа трохи розсунуті
struct StoreStatsCardRow: View {
    let stats: StoreServer.FaceStats

    var body: some View {
        StoreStatsRow(downloads: StoreText.short(stats.downloads), views: StoreText.short(stats.views),
                      font: Self.font, roomy: true, minGap: 18, maxGap: 37)
            .frame(height: Self.font.lineHeight)
            .padding(.top, Self.insets.top)
            .padding(.bottom, Self.insets.bottom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: StoreText.views(stats.views) + ", " + StoreText.downloads(stats.downloads)))
    }

    static let font = StoreStatsRow.textFont(.caption1)

    /// Відступи рядка: від лінії до верху цифр і від низу цифр до кнопки — стільки ж, скільки від низу напису
    /// «вага · версія» до лінії (8 pt + частина рядка підписів під базовою лінією)
    static let insets: (top: CGFloat, bottom: CGFloat) = {
        let f = font
        let gap = 8 + (f.lineHeight - f.ascender)
        return (gap - (f.ascender - StoreStatsRow.digitHeight(f)), gap - (f.lineHeight - f.ascender))
    }()
}

/// Рядок у плашці «Розмір · Версія · Пристрої» на сторінці циферблата: «👁 3.4k переглядів   ↓ 1.2k завантажень» —
/// числа коротко, як на картці, слово завжди «завантажень» / «переглядів»; проміжок — за правилом картки
struct StoreStatsLine: View {
    let stats: StoreServer.FaceStats

    var body: some View {
        let d = StoreText.short(stats.downloads), v = StoreText.short(stats.views)
        StoreStatsRow(downloads: d + " " + StoreText.downloadsWord, views: v + " " + StoreText.viewsWord,
                      font: StoreStatsRow.textFont(.footnote), roomy: true, gapBasis: (d, v), maxGap: 37)
            .frame(minHeight: 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: StoreText.views(stats.views) + ", " + StoreText.downloads(stats.downloads)))
    }
}
