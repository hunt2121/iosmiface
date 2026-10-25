import SwiftUI

/// Збір коштів на публікацію в App Store: капсула над панеллю вкладок і аркуш зі способами підтримки.
struct DonationService: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let icon: ServiceIcon
    /// Немає посилання — рядок видно, але він неактивний («Посилання незабаром»)
    let url: URL?

    static let all: [DonationService] = [
        DonationService(id: "monobank", name: String(localized: "Монобанка"),
                        subtitle: String(localized: "Банка · гривні, картка"),
                        icon: .jar, url: nil),
        DonationService(id: "bmc", name: "Buy Me a Coffee",
                        subtitle: String(localized: "Разова підтримка · картка"),
                        icon: .cup, url: nil),
        DonationService(id: "kofi", name: "Ko-fi",
                        subtitle: String(localized: "Разова підтримка · PayPal, картка"),
                        icon: .cupHeart, url: nil),
        DonationService(id: "patreon", name: "Patreon",
                        subtitle: String(localized: "Щомісячна підтримка"),
                        icon: .calendar, url: nil),
        DonationService(id: "github", name: "GitHub Sponsors",
                        subtitle: String(localized: "Разово або щомісяця"),
                        icon: .heart, url: nil),
    ]
}

// MARK: - Іконки сервісів

/// Контурні іконки з макета (сітка 24×24): банка, чашка, чашка із серцем, календар, серце.
enum ServiceIcon { case jar, cup, cupHeart, calendar, heart }

struct ServiceIconShape: Shape {
    let icon: ServiceIcon

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let o = CGPoint(x: rect.midX - 12 * s, y: rect.midY - 12 * s)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        func line(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), into path: inout Path) {
            path.move(to: p(a.0, a.1)); path.addLine(to: p(b.0, b.1))
        }
        /// Чашка з ручкою; top — верхній край
        func cup(top: CGFloat, into path: inout Path) {
            path.move(to: p(4, top))
            path.addLine(to: p(16, top))
            path.addArc(tangent1End: p(16, 19), tangent2End: p(11, 19), radius: 5 * s)
            path.addArc(tangent1End: p(4, 19), tangent2End: p(4, 14), radius: 5 * s)
            path.closeSubpath()
            path.move(to: p(16, top + 2))
            path.addLine(to: p(17.5, top + 2))
            path.addArc(center: p(17.5, top + 4.5), radius: 2.5 * s,
                        startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: p(16, top + 7))
        }
        var path = Path()
        switch icon {
        case .jar:
            path.move(to: p(7, 7.5))
            path.addLine(to: p(17, 7.5))
            path.addLine(to: p(17, 9.5))
            path.addCurve(to: p(20, 15.5), control1: p(19, 10.8), control2: p(20, 12.8))
            path.addArc(tangent1End: p(20, 21.5), tangent2End: p(17, 21.5), radius: 3 * s)
            path.addArc(tangent1End: p(4, 21.5), tangent2End: p(4, 18.5), radius: 3 * s)
            path.addLine(to: p(4, 15.5))
            path.addCurve(to: p(7, 9.5), control1: p(4, 12.8), control2: p(5, 10.8))
            path.closeSubpath()
            path.addRoundedRect(in: CGRect(origin: p(6, 3.5), size: CGSize(width: 12 * s, height: 4 * s)),
                                cornerSize: CGSize(width: 1.2 * s, height: 1.2 * s))
            line((8.5, 15.5), (15.5, 15.5), into: &path)
        case .cup:
            cup(top: 9, into: &path)
            path.move(to: p(8, 3.5)); path.addCurve(to: p(9, 6.5), control1: p(8, 5), control2: p(9, 5))
            path.move(to: p(12, 3.5)); path.addCurve(to: p(13, 6.5), control1: p(12, 5), control2: p(13, 5))
        case .cupHeart:
            cup(top: 8, into: &path)
            path.move(to: p(10, 15.5))
            path.addCurve(to: p(7.2, 12), control1: p(8.6, 14.6), control2: p(7.2, 13.4))
            path.addCurve(to: p(10, 11.2), control1: p(7.2, 10.4), control2: p(9.2, 10))
            path.addCurve(to: p(12.8, 12), control1: p(10.8, 10), control2: p(12.8, 10.4))
            path.addCurve(to: p(10, 15.5), control1: p(12.8, 13.4), control2: p(11.4, 14.6))
            path.closeSubpath()
        case .calendar:
            path.addRoundedRect(in: CGRect(origin: p(4, 5), size: CGSize(width: 16 * s, height: 15 * s)),
                                cornerSize: CGSize(width: 2.5 * s, height: 2.5 * s))
            line((4, 9.5), (20, 9.5), into: &path)
            line((8.5, 3), (8.5, 7), into: &path)
            line((15.5, 3), (15.5, 7), into: &path)
            path.move(to: p(9, 14.5)); path.addLine(to: p(11, 16.5)); path.addLine(to: p(15, 12.5))
        case .heart:
            path.move(to: p(12, 20))
            path.addCurve(to: p(2.8, 10.7), control1: p(12, 20), control2: p(4.5, 15.4))
            path.addCurve(to: p(7.2, 4), control1: p(1.6, 7.4), control2: p(3.8, 4))
            path.addCurve(to: p(12, 6.8), control1: p(9.2, 4), control2: p(10.8, 5.1))
            path.addCurve(to: p(16.8, 4), control1: p(13.2, 5.1), control2: p(14.8, 4))
            path.addCurve(to: p(21.2, 10.7), control1: p(20.2, 4), control2: p(22.4, 7.4))
            path.addCurve(to: p(12, 20), control1: p(19.5, 15.4), control2: p(12, 20))
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - Ракета

/// Контурна ракета (сітка 24×24), та сама, що на макеті.
struct RocketShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let o = CGPoint(x: rect.midX - 12 * s, y: rect.midY - 12 * s)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        var path = Path()
        // Корпус
        path.move(to: p(12, 2.5))
        path.addCurve(to: p(16.5, 13), control1: p(15.5, 4.5), control2: p(17, 8.5))
        path.addLine(to: p(14.5, 15.5))
        path.addLine(to: p(9.5, 15.5))
        path.addLine(to: p(7.5, 13))
        path.addCurve(to: p(12, 2.5), control1: p(7, 8.5), control2: p(8.5, 4.5))
        path.closeSubpath()
        // Ілюмінатор
        path.addEllipse(in: CGRect(x: o.x + 10.2 * s, y: o.y + 7.2 * s, width: 3.6 * s, height: 3.6 * s))
        // Крила
        path.move(to: p(7.7, 12.5)); path.addLine(to: p(5, 15)); path.addLine(to: p(6, 18.5)); path.addLine(to: p(9, 16.5))
        path.move(to: p(16.3, 12.5)); path.addLine(to: p(19, 15)); path.addLine(to: p(18, 18.5)); path.addLine(to: p(15, 16.5))
        // Полум'я
        path.move(to: p(10.5, 18.5)); path.addLine(to: p(12, 21.5)); path.addLine(to: p(13.5, 18.5))
        return path
    }
}

struct RocketBadge: View {
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor)
            RocketShape()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8 * size * 0.6 / 24, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.6, height: size * 0.6)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Капсула над вкладками

struct DonationBar: View {
    let thanked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RocketBadge()
                VStack(alignment: .leading, spacing: 1) {
                    Group {
                        if thanked { Text("Дякуємо за підтримку!") } else { Text("Запустимо BandFace") }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    Group {
                        if thanked { Text("Разом запустимо BandFace в App Store") } else { Text("в App Store — разом") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                // Заголовок не обрізається: за потреби трохи зменшується
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
                Spacer(minLength: 0)
                if thanked {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Color.accentColor)
                        .padding(.trailing, 9)
                } else {
                    Text("Підтримати")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .frame(height: 40)
                        .fixedSize()
                        .background(Capsule().fill(Color.accentColor))
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .frame(height: 56)
            .contentShape(Capsule())
            .glassCapsule()
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    /// Liquid Glass на iOS 26, на старших системах — матеріал.
    @ViewBuilder func glassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
        }
    }
}

// MARK: - Аркуш

struct DonationSheet: View {
    /// Користувач відкрив сторінку одного з сервісів
    let onOpen: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    RocketBadge(size: 58)
                        .shadow(color: Color.accentColor.opacity(0.45), radius: 12)
                    Text("Запустимо BandFace в App Store")
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.trailing, 36)

                Text("BandFace безкоштовний і з відкритим кодом. Щоб опублікувати його в App Store, потрібен акаунт розробника Apple. Усі зібрані кошти підуть саме на нього.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                HStack(alignment: .top, spacing: 8) {
                    tile {
                        Text("Мета").font(.caption).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(verbatim: "99 $").font(.title3.bold())
                            Text("на рік").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    // Фіксована ширина: інакше довга плитка праворуч стискає цю до нуля
                    .frame(width: 132)
                    tile {
                        Text("Що це дасть").font(.caption).foregroundStyle(.secondary)
                        Text("Без Sideloadly, без перепідписування й з автооновленнями")
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
                // Обидві плитки однакової висоти
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

                Text("Обери зручний спосіб")
                    .textCase(.uppercase)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)
                    .padding(.leading, 4)
                    .padding(.bottom, 7)

                VStack(spacing: 0) {
                    ForEach(Array(DonationService.all.enumerated()), id: \.element.id) { index, service in
                        if index > 0 { Divider().padding(.leading, 63) }
                        row(service)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground)))

                Text("Сторінка відкриється в браузері. Застосунок не бачить і не зберігає твоїх платіжних даних.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 9)
                    .padding(.horizontal, 4)

                Button { dismiss() } label: {
                    Text("Не зараз")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                }
                .buttonStyle(.plain)
                .padding(.top, 22)
            }
            .padding(.horizontal, 18)
            .padding(.top, 26)
            .padding(.bottom, 20)
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Закрити"))
            .padding(.top, 18)
            .padding(.trailing, 16)
        }
    }

    private func tile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3, content: content)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground)))
    }

    private func row(_ service: DonationService) -> some View {
        Button {
            guard let url = service.url else { return }
            onOpen()
            openURL(url)
        } label: {
            HStack(spacing: 13) {
                ServiceIconShape(icon: service.icon)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.65, lineCap: .round, lineJoin: .round))
                    .frame(width: 22, height: 22)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: service.name).foregroundStyle(.primary)
                    Text(service.url == nil ? String(localized: "Посилання незабаром") : service.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
            .padding(.leading, 12)
            .padding(.trailing, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(service.url == nil)
        .opacity(service.url == nil ? 0.5 : 1)
    }
}
