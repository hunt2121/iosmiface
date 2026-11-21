import SwiftUI
import UIKit
import CoreText

/// «Інформація» на сторінці циферблата: плитки 2×2 (сумісність, вигляд, мова, дата) і категорії.
/// Усе в плитці стоїть на одній лінії від лівої стінки саме на око: рядки тексту зсуваються на
/// порожнє місце перед першою літерою, значки намальовані без полів, значок — по центру великих літер.
struct StoreInfoTiles: View {
    let item: StoreFace

    private static let inset: CGFloat = 16
    private static let tileFill = Color(.secondarySystemGroupedBackground)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Інформація").font(.title3.weight(.bold)).padding(.horizontal, 4)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                tile(.band, String(localized: "Сумісність"),
                     "Band " + item.bands.map(String.init).joined(separator: " · ")) {
                    InkText("Xiaomi Smart Band", font: InfoFont.note, color: .secondary)
                }
                tile(.palette, String(localized: "Вигляд"), StoreText.styles(max(item.styles.count, 1))) {
                    if item.colors.count > 1 {
                        HStack(spacing: 6) {
                            InfoDots(colors: item.colors, ring: Self.tileFill)
                            InkText(StoreText.colors(item.colors.count), font: InfoFont.note, color: .secondary, alignLeft: false)
                        }
                    } else {
                        InkText(String(localized: "Без вибору кольору"), font: InfoFont.note, color: .secondary)
                    }
                }
                tile(.globe, String(localized: "Мова"), language) {
                    InkText(clock, font: InfoFont.note, color: .secondary)
                }
                if let d = item.updated ?? item.added {
                    tile(.calendar, String(localized: "Оновлено"), Self.dayMonth(d)) {
                        InkText(Self.year(d), font: InfoFont.note, color: .secondary)
                    }
                }
            }
            if !item.kinds.isEmpty {
                VStack(alignment: .leading, spacing: 11) {
                    InfoCaption(icon: .tag, text: String(localized: "Категорії"))
                    InfoFlow(spacing: 6) {
                        ForEach(item.kinds, id: \.self) { InfoChip(text: $0) }
                    }
                }
                .padding(.horizontal, Self.inset)
                .padding(.top, 15)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Self.tileFill))
            }
        }
    }

    private func tile<Note: View>(_ icon: InfoIcon.Kind, _ caption: String, _ value: String,
                                  @ViewBuilder note: () -> Note) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InfoCaption(icon: icon, text: caption)
            Spacer(minLength: 6)
            InkText(value, font: InfoFont.value, color: .primary)
            note()
                .frame(height: 17, alignment: .leading)
                .padding(.top, 1)
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, 15)
        .padding(.bottom, 13)
        .frame(maxWidth: .infinity, minHeight: 96, maxHeight: 96, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Self.tileFill))
    }

    /// Мова варіанта мовою інтерфейсу: «Українська»; варіант для всіх мов — «Усі мови»
    private var language: String {
        guard let code = item.remote?.langs.first(where: { $0 != "*" }) ?? item.variantKey.map({ String($0.prefix(2)) }),
              code != "*" else { return String(localized: "Усі мови") }
        let name = Locale.current.localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private var clock: String {
        switch item.remote?.clock {
        case "12h": return String(localized: "12-годинний формат")
        case "24h": return String(localized: "24-годинний формат")
        default: return String(localized: "Будь-який формат часу")
        }
    }

    private static var interfaceLocale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }

    /// «14 листопада»
    static func dayMonth(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(locale: interfaceLocale).day().month(.wide))
    }

    static func year(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(locale: interfaceLocale).year())
    }
}

/// Шрифти плиток: фіксовані розміри, щоб плитки 2×2 мали однакову висоту
enum InfoFont {
    static let caption = UIFont.systemFont(ofSize: 11, weight: .semibold)
    static let value = UIFont.systemFont(ofSize: 19, weight: .semibold)
    static let note = UIFont.systemFont(ofSize: 13, weight: .regular)
    static let chip = UIFont.systemFont(ofSize: 13, weight: .semibold)
    static let captionTracking: CGFloat = 0.4
}

/// Рядок тексту, лівий край якого — перша намальована точка літери, а не початок її клітинки
struct InkText: View {
    let text: String
    let font: UIFont
    let color: Color
    var tracking: CGFloat = 0
    var alignLeft = true

    init(_ text: String, font: UIFont, color: Color, tracking: CGFloat = 0, alignLeft: Bool = true) {
        self.text = text
        self.font = font
        self.color = color
        self.tracking = tracking
        self.alignLeft = alignLeft
    }

    var body: some View {
        let ink = alignLeft ? InkMetrics.bearings(text, font: font, tracking: tracking).left : 0
        Text(text)
            .font(Font(font as CTFont))
            .tracking(tracking)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .offset(x: -ink)
            .padding(.trailing, -ink)
    }
}

/// Порожнє місце перед першою і після останньої літери рядка (у точках)
enum InkMetrics {
    private static var cache: [String: (CGFloat, CGFloat)] = [:]

    static func bearings(_ text: String, font: UIFont, tracking: CGFloat = 0) -> (left: CGFloat, right: CGFloat) {
        guard !text.isEmpty else { return (0, 0) }
        let key = "\(font.fontName)|\(font.pointSize)|\(tracking)|\(text)"
        if let c = cache[key] { return (c.0, c.1) }
        var attrs: [NSAttributedString.Key: Any] = [.font: font]
        if tracking != 0 { attrs[.kern] = tracking }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let ink = CTLineGetImageBounds(line, nil)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let r: (CGFloat, CGFloat) = ink.isNull ? (0, 0) : (max(0, ink.minX), max(0, width - ink.maxX - tracking))
        cache[key] = r
        return r
    }
}

/// Підпис плитки: значок і великі літери; центр значка — посередині великих літер
struct InfoCaption: View {
    let icon: InfoIcon.Kind
    let text: String

    var body: some View {
        let font = InfoFont.caption
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            InfoIcon(kind: icon)
                .offset(y: icon.nudge)
                .alignmentGuide(.firstTextBaseline) { d in d.height / 2 + font.capHeight / 2 }
            Text(text.uppercased(with: Locale.current))
                .font(Font(font as CTFont))
                .tracking(InfoFont.captionTracking)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// Кружечки кольорів: 13 pt внахлест, розділені кільцем кольору плитки
struct InfoDots: View {
    let colors: [String]
    let ring: Color

    var body: some View {
        HStack(spacing: -3) {
            ForEach(Array(colors.prefix(4).enumerated()), id: \.offset) { i, c in
                Circle().fill(Color(hex: c))
                    .frame(width: 13, height: 13)
                    .background(Circle().fill(ring).padding(-1.5))
                    .zIndex(Double(10 - i))
            }
        }
    }
}

/// Капсула категорії: текст по центру на око (великі й малі літери разом) і з однаковими полями
struct InfoChip: View {
    let text: String

    var body: some View {
        let font = InfoFont.chip
        let b = InkMetrics.bearings(text, font: font)
        // центр великих і малих літер разом (над базовою лінією) ставиться в центр капсули; центр рядка шрифту — посередині між верхом і низом
        let visual = (font.capHeight + font.xHeight) / 4
        let box = (font.ascender + font.descender) / 2
        Text(text)
            .font(Font(font as CTFont))
            .lineLimit(1)
            .padding(.leading, 12 - b.left)
            .padding(.trailing, 12 - b.right)
            .offset(y: visual - box)
            .frame(height: 27)
            .background(Capsule().fill(Color(.tertiarySystemFill)))
    }
}

/// Значки плиток без полів: лівий край малюнка — лівий край значка
struct InfoIcon: View {
    enum Kind { case band, palette, globe, calendar, tag }
    let kind: Kind

    /// Межі малюнка в його координатах (сітка 24, браслет — 30) і висота в точках
    private var box: CGRect {
        switch kind {
        case .band: return CGRect(x: 8, y: 1.5, width: 14, height: 27)
        case .tag: return CGRect(x: 1.6, y: 2.6, width: 19.8, height: 19.8)
        default: return CGRect(x: 1.6, y: 1.6, width: 20.8, height: 20.8)
        }
    }
    private var height: CGFloat { kind == .band ? 15 : 11 }


    var body: some View {
        let b = box, h = height, s = h / b.height
        Canvas { ctx, _ in
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: -b.minX, y: -b.minY)
            let style = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
            let ink = GraphicsContext.Shading.color(Color.secondary)
            switch kind {
            case .band:
                var straps = Path()
                straps.addLines([CGPoint(x: 11.3, y: 1.5), CGPoint(x: 18.7, y: 1.5), CGPoint(x: 19.4, y: 6.6), CGPoint(x: 10.6, y: 6.6)])
                straps.closeSubpath()
                straps.addLines([CGPoint(x: 10.6, y: 23.4), CGPoint(x: 19.4, y: 23.4), CGPoint(x: 18.7, y: 28.5), CGPoint(x: 11.3, y: 28.5)])
                straps.closeSubpath()
                ctx.fill(straps, with: ink)
                var body = Path()
                body.addRoundedRect(in: CGRect(x: 8, y: 5.6, width: 14, height: 18.8), cornerSize: CGSize(width: 5.5, height: 5.4))
                body.addRoundedRect(in: CGRect(x: 10.9, y: 8.4, width: 8.2, height: 13.2), cornerSize: CGSize(width: 1.1, height: 1.2))
                ctx.fill(body, with: ink, style: FillStyle(eoFill: true))
            case .palette:
                var p = Path()
                p.move(to: CGPoint(x: 12, y: 3))
                p.addCurve(to: CGPoint(x: 3, y: 12), control1: CGPoint(x: 7.03, y: 3), control2: CGPoint(x: 3, y: 7.03))
                p.addCurve(to: CGPoint(x: 12, y: 21), control1: CGPoint(x: 3, y: 16.97), control2: CGPoint(x: 7.03, y: 21))
                p.addCurve(to: CGPoint(x: 13.1, y: 19.1), control1: CGPoint(x: 13.2, y: 21), control2: CGPoint(x: 13.6, y: 20))
                p.addCurve(to: CGPoint(x: 14.3, y: 17), control1: CGPoint(x: 12.5, y: 18.1), control2: CGPoint(x: 13.2, y: 17))
                p.addLine(to: CGPoint(x: 17, y: 17))
                p.addCurve(to: CGPoint(x: 21, y: 13), control1: CGPoint(x: 19.21, y: 17), control2: CGPoint(x: 21, y: 15.21))
                p.addCurve(to: CGPoint(x: 12, y: 3), control1: CGPoint(x: 21, y: 7.5), control2: CGPoint(x: 17, y: 3))
                p.closeSubpath()
                ctx.stroke(p, with: ink, style: style)
                for c in [CGPoint(x: 7.5, y: 11), CGPoint(x: 10.5, y: 7), CGPoint(x: 15, y: 7.5)] {
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 1, y: c.y - 1, width: 2, height: 2)), with: ink)
                }
            case .globe:
                var p = Path(ellipseIn: CGRect(x: 3, y: 3, width: 18, height: 18))
                p.move(to: CGPoint(x: 3, y: 12)); p.addLine(to: CGPoint(x: 21, y: 12))
                p.move(to: CGPoint(x: 12, y: 3))
                p.addCurve(to: CGPoint(x: 12, y: 21), control1: CGPoint(x: 15, y: 6.5), control2: CGPoint(x: 15, y: 17.5))
                p.move(to: CGPoint(x: 12, y: 3))
                p.addCurve(to: CGPoint(x: 12, y: 21), control1: CGPoint(x: 9, y: 6.5), control2: CGPoint(x: 9, y: 17.5))
                ctx.stroke(p, with: ink, style: style)
            case .calendar:
                var p = Path(roundedRect: CGRect(x: 3, y: 5, width: 18, height: 16), cornerRadius: 3)
                p.move(to: CGPoint(x: 3, y: 10)); p.addLine(to: CGPoint(x: 21, y: 10))
                p.move(to: CGPoint(x: 8, y: 3)); p.addLine(to: CGPoint(x: 8, y: 7))
                p.move(to: CGPoint(x: 16, y: 3)); p.addLine(to: CGPoint(x: 16, y: 7))
                ctx.stroke(p, with: ink, style: style)
            case .tag:
                var p = Path()
                p.addLines([CGPoint(x: 3, y: 12), CGPoint(x: 3, y: 4), CGPoint(x: 11, y: 4), CGPoint(x: 20, y: 13), CGPoint(x: 12, y: 21)])
                p.closeSubpath()
                p.addEllipse(in: CGRect(x: 6.2, y: 7.2, width: 2.6, height: 2.6))
                ctx.stroke(p, with: ink, style: style)
            }
        }
        .frame(width: b.width * s, height: h)
        .accessibilityHidden(true)
    }
}

/// Капсули в рядок з переносом
struct InfoFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        let w = rows.map { r in r.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(r.count - 1, 0)) }.max() ?? 0
        let h = rows.map { $0.map(\.height).max() ?? 0 }.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY, i = 0
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            let h = row.map(\.height).max() ?? 0
            for size in row {
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
                i += 1
            }
            y += h + spacing
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> [[CGSize]] {
        var rows: [[CGSize]] = [[]], x: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append(size)
            x += size.width + spacing
        }
        return rows
    }
}

extension InfoIcon.Kind {
    /// Оптичне підрівнювання значка по вертикалі (pt): «−» — вгору, «+» — вниз.
    /// Сумісність, Мова, Категорії — рівно по центру великих літер підпису; Оновлено — трохи вище
    var nudge: CGFloat {
        switch self {
        case .band, .globe, .tag: return 1.0 / 6
        case .calendar: return -0.5
        default: return 0
        }
    }
}
