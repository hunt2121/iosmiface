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

/// «↓ 1.1k  👁 4.8k» — вирівняно за чорнилом: від значка до числа рівно 3 pt, уся група точно по центру.
/// Між парами 14 pt; з roomy (картка магазину) малі числа трохи розсунуті: чим коротші пари, тим більший проміжок —
/// від 14 (від «1.1k  4.8k» і довших) до 24 (для «0  0»), у масштабі шрифту
struct StoreStatsRow: View {
    let downloads: String
    let views: String
    let font: UIFont
    var roomy = false
    /// Числа без слів («1.2k», «3.4k») — проміжок між парами рахуємо за ними, щоб слова його не змінювали
    var gapBasis: (String, String)? = nil

    /// Відстань між штрихами: значок → число
    private static let iconGap: CGFloat = 3

    var body: some View {
        // стрілка рівно заввишки з цифри, око — 80% її висоти
        let arrowFont = Self.iconFont("arrow.down.to.line", font, 1), eyeFont = Self.iconFont("eye", font, 0.8)
        let arrow = InkMetrics.symbol("arrow.down.to.line", font: arrowFont)
        let eye = InkMetrics.symbol("eye", font: eyeFont)
        let dInk = InkMetrics.bearings(downloads, font: font), vInk = InkMetrics.bearings(views, font: font)
        let (gd, gv) = gapBasis ?? (downloads, views)
        let gap = roomy ? Self.gap(inkWidth(arrow) + Self.iconGap + textInk(gd, InkMetrics.bearings(gd, font: font))
                                   + inkWidth(eye) + Self.iconGap + textInk(gv, InkMetrics.bearings(gv, font: font)), font: font) : 14

        HStack(spacing: 0) {
            pair(arrow, downloads, dInk, dy: Self.iconShift("arrow.down.to.line", arrowFont, text: font))
            pair(eye, views, vInk, dy: Self.iconShift("eye", eyeFont, text: font))
                .padding(.leading, gap - dInk.right - eye.left)
        }
        .font(Font(font as CTFont))
        .foregroundStyle(.secondary)
        .fixedSize()
        // поля по краях групи різні (у стрілки й у цифр) — зсуваємо, щоб по центру було саме чорнило
        .offset(x: (vInk.right - arrow.left) / 2)
        .frame(maxWidth: .infinity)
    }

    /// Шрифт для значка: його чорнило заввишки ratio × висота цифр (висота великих літер шрифту)
    static func iconFont(_ name: String, _ font: UIFont, _ ratio: CGFloat) -> UIFont {
        let v = InkMetrics.symbolVertical(name, font: font)
        let ink = InkMetrics.symbol(name, font: font).image.size.height - v.top - v.bottom
        guard ink > 0 else { return font }
        return font.withSize(font.pointSize * font.capHeight * ratio / ink)
    }

    /// Зсув значка по вертикалі: центр його чорнила — на центрі цифр (а не центр картинки на центрі рядка тексту)
    static func iconShift(_ name: String, _ iconFont: UIFont, text font: UIFont) -> CGFloat {
        let img = InkMetrics.symbol(name, font: iconFont).image
        let v = InkMetrics.symbolVertical(name, font: iconFont)
        let inkCenter = v.top + (img.size.height - v.top - v.bottom) / 2 - img.size.height / 2   // від центру картинки
        let digitsCenter = font.ascender - font.capHeight / 2 - font.lineHeight / 2              // від центру рядка
        return digitsCenter - inkCenter
    }

    /// Проміжок між парами за шириною чорнила обох пар: ≤ 36 (×масштаб) — 24, ≥ 64 — 14, між ними плавно
    static func gap(_ pairs: CGFloat, font: UIFont) -> CGFloat {
        let k = font.pointSize / 10.5
        let t = min(1, max(0, (64 * k - pairs) / (28 * k)))
        return (14 + 10 * t) * k
    }

    /// Значок і число: від чорнила значка до чорнила числа — 3 pt
    private func pair(_ icon: (image: UIImage, left: CGFloat, right: CGFloat), _ text: String,
                      _ ink: (left: CGFloat, right: CGFloat), dy: CGFloat = 0) -> some View {
        HStack(spacing: 0) {
            Image(uiImage: icon.image).renderingMode(.template).offset(y: dy)
            Text(verbatim: text)
                .padding(.leading, Self.iconGap - icon.right - ink.left)
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
    static func font(_ style: UIFont.TextStyle) -> UIFont {
        UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: style).pointSize, weight: .regular)
    }
}

/// Капсула з числами на картці магазину: визирає з-за кнопки «Встановити» (нижні 11 pt під кнопкою);
/// «піднята» — колір картки з м'якою тінню
struct StoreStatsTab: View {
    let stats: StoreServer.FaceStats

    var body: some View {
        StoreStatsRow(downloads: StoreText.short(stats.downloads), views: StoreText.short(stats.views),
                      font: StoreStatsRow.font(.caption), roomy: true)
            .frame(height: 22)
            .padding(.bottom, Self.under)
            // «піднята»: колір картки з м'якою тінню (у темній темі трохи світліша за картку — тінь на темному не видно)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Self.fill)
                .shadow(color: Self.shadow, radius: 3, y: 1))
            .padding(.horizontal, 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: StoreText.downloads(stats.downloads) + ", " + StoreText.views(stats.views)))
    }

    /// Скільки капсули ховається під кнопкою
    static let under: CGFloat = 11

    /// Світла тема — колір картки; темна — #242426 (посередині між #2C2C2E і карткою #1C1C1E)
    static let fill = Color(UIColor { t in
        t.userInterfaceStyle == .dark ? UIColor(red: 0x24 / 255, green: 0x24 / 255, blue: 0x26 / 255, alpha: 1) : .secondarySystemGroupedBackground
    })
    static let shadow = Color(UIColor { t in UIColor.black.withAlphaComponent(t.userInterfaceStyle == .dark ? 0.6 : 0.22) })
}

/// Рядок у плашці «Розмір · Версія · Пристрої» на сторінці циферблата: «↓ 1.2k завантажень   👁 3.4k переглядів» —
/// числа коротко, як на картці, слово завжди «завантажень» / «переглядів»; проміжок — за правилом картки
struct StoreStatsLine: View {
    let stats: StoreServer.FaceStats

    var body: some View {
        let d = StoreText.short(stats.downloads), v = StoreText.short(stats.views)
        StoreStatsRow(downloads: d + " " + StoreText.downloadsWord, views: v + " " + StoreText.viewsWord,
                      font: StoreStatsRow.font(.footnote), roomy: true, gapBasis: (d, v))
            .frame(minHeight: 18)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: StoreText.downloads(stats.downloads) + ", " + StoreText.views(stats.views)))
    }
}
