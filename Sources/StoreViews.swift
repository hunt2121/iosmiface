import SwiftUI

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
