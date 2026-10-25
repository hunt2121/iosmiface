import SwiftUI

/// Збір коштів на публікацію в App Store: капсула над панеллю вкладок і аркуш зі способами підтримки.
struct DonationService: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let symbol: String
    /// Немає посилання — рядок видно, але він неактивний («Посилання незабаром»)
    let url: URL?

    static let all: [DonationService] = [
        DonationService(id: "monobank", name: String(localized: "Монобанка"),
                        subtitle: String(localized: "Банка · гривні, картка"),
                        symbol: "banknote", url: nil),
        DonationService(id: "bmc", name: "Buy Me a Coffee",
                        subtitle: String(localized: "Разова підтримка · картка"),
                        symbol: "cup.and.saucer", url: nil),
        DonationService(id: "kofi", name: "Ko-fi",
                        subtitle: String(localized: "Разова підтримка · PayPal, картка"),
                        symbol: "gift", url: nil),
        DonationService(id: "patreon", name: "Patreon",
                        subtitle: String(localized: "Щомісячна підтримка"),
                        symbol: "repeat", url: nil),
        DonationService(id: "github", name: "GitHub Sponsors",
                        subtitle: String(localized: "Разово або щомісяця"),
                        symbol: "heart", url: nil),
    ]
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
            HStack(spacing: 10) {
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
                Spacer(minLength: 4)
                if thanked {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Color.accentColor)
                        .padding(.trailing, 9)
                } else {
                    Text("Підтримати")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 15)
                        .frame(height: 40)
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
                    .frame(maxWidth: .infinity)
                    tile {
                        Text("Що це дасть").font(.caption).foregroundStyle(.secondary)
                        Text("Без Sideloadly, без перепідписування й з автооновленнями")
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
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
                Image(systemName: service.symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentColor)
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
