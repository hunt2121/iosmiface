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

/// Рядок під «Встановити» на сторінці циферблата: «↓ 1 240 завантажень   👁 3 400 переглядів».
/// Системні значки стоять на базовій лінії тексту й сумірні з цифрами; по центру кнопки.
struct StoreStatsLine: View {
    let stats: StoreServer.FaceStats

    var body: some View {
        HStack(spacing: 16) {
            item("arrow.down.to.line", StoreText.downloads(stats.downloads))
            item("eye", StoreText.views(stats.views))
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func item(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5.5) {
            Image(systemName: symbol)
            Text(verbatim: text)
        }
    }
}

/// Межі «чорнила» (без бічних полів шрифту й символу) — для оптичного вирівнювання значків і чисел
enum InkMetrics {
    struct Ink { let left: CGFloat; let right: CGFloat }
    private static var symbols: [String: (UIImage, Ink)] = [:]

    /// Значок, як його й показуємо, та поля від краю картинки до чорнила зліва й справа
    static func symbol(_ name: String, font: UIFont) -> (image: UIImage, ink: Ink) {
        let key = "\(name)|\(font.pointSize)|\(font.fontName)"
        if let hit = symbols[key] { return hit }
        let image = UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(font: font))
            ?? UIImage()
        let result = (image, scan(image))
        symbols[key] = result
        return result
    }

    /// Поля числа: від початку рядка до першого штриха й від останнього штриха до кінця рядка
    static func text(_ string: String, font: UIFont) -> Ink {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: font]))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let ink = CTLineGetImageBounds(line, nil)
        guard !ink.isNull, ink.width > 0 else { return Ink(left: 0, right: 0) }
        return Ink(left: ink.minX, right: width - ink.maxX)
    }

    /// Малюємо значок чорним у 8× і шукаємо крайні стовпчики з чорнилом
    private static func scan(_ image: UIImage) -> Ink {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return Ink(left: 0, right: 0) }
        let scale: CGFloat = 8
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.withTintColor(.black, renderingMode: .alwaysOriginal).draw(at: .zero)
        }
        guard let cg = rendered.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            return Ink(left: 0, right: 0)
        }
        let bpp = cg.bitsPerPixel / 8, row = cg.bytesPerRow
        var minX = Int.max, maxX = -1
        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let p = y * row + x * bpp
                // чорне на прозорому: усе, крім прозорого тла, має ненульовий байт (альфа)
                var ink = false
                for b in 0..<bpp where bytes[p + b] > 24 { ink = true; break }
                if ink { minX = min(minX, x); maxX = max(maxX, x) }
            }
        }
        guard maxX >= 0 else { return Ink(left: 0, right: 0) }
        return Ink(left: CGFloat(minX) / scale, right: size.width - CGFloat(maxX + 1) / scale)
    }
}

/// Капсула з числами на картці магазину: визирає з-за кнопки «Встановити» (нижні 11 pt під кнопкою).
/// «↓ 1.1k  👁 4.8k» по центру — вирівняно за чорнилом: від значка до числа рівно 3 pt, між парами 14 pt,
/// і від лівого краю капсули до стрілки стільки ж, скільки від останньої цифри до правого краю
struct StoreStatsTab: View {
    let stats: StoreServer.FaceStats

    /// Відстані між штрихами: значок → число і число → наступний значок
    private static let iconGap: CGFloat = 3
    private static let pairGap: CGFloat = 14

    var body: some View {
        let font = UIFont.monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize,
                                                    weight: .semibold)
        let arrow = InkMetrics.symbol("arrow.down.to.line", font: font)
        let eye = InkMetrics.symbol("eye", font: font)
        let d = StoreText.short(stats.downloads), v = StoreText.short(stats.views)
        let dInk = InkMetrics.text(d, font: font), vInk = InkMetrics.text(v, font: font)

        HStack(spacing: 0) {
            Image(uiImage: arrow.image).renderingMode(.template)
            Text(verbatim: d)
                .padding(.leading, Self.iconGap - arrow.ink.right - dInk.left)
            Image(uiImage: eye.image).renderingMode(.template)
                .padding(.leading, Self.pairGap - dInk.right - eye.ink.left)
            Text(verbatim: v)
                .padding(.leading, Self.iconGap - eye.ink.right - vInk.left)
        }
        .font(Font(font as CTFont))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
        // поля по краях групи різні (у стрілки й у цифр) — зсуваємо, щоб по центру було саме чорнило
        .offset(x: (vInk.right - arrow.ink.left) / 2)
        .frame(maxWidth: .infinity)
        .frame(height: 22)
        .padding(.bottom, Self.under)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(.tertiarySystemFill)))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: StoreText.downloads(stats.downloads) + ", " + StoreText.views(stats.views)))
    }

    /// Скільки капсули ховається під кнопкою
    static let under: CGFloat = 11
}
