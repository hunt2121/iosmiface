import SwiftUI

/// Один зелений і один червоний для обох тем: написи, галочки, позначки, обведення й кнопки
/// (плитки-іконки в налаштуваннях мають власні кольори).
extension Color {
    static let okGreen = Color(red: 34 / 255, green: 168 / 255, blue: 70 / 255)      // #22A846
    static let errorRed = Color(red: 232 / 255, green: 56 / 255, blue: 47 / 255)     // #E8382F
}

/// Liquid Glass на iOS 26 і запасний вигляд на старіших версіях.
extension View {
    @ViewBuilder func capsuleGlass(tint: Color? = nil) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.tint(tint).interactive(), in: Capsule())
        } else {
            self.background(Capsule().fill((tint ?? Color.gray).opacity(0.15)))
        }
    }

    @ViewBuilder func glassProminentStyle() -> some View {
        if #available(iOS 26, *) { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.borderedProminent) }
    }

    @ViewBuilder func glassSecondaryStyle() -> some View {
        if #available(iOS 26, *) { self.buttonStyle(.glass) } else { self.buttonStyle(.bordered) }
    }
}

/// Смужка прогресу встановлення з етапом і відсотками. `large` — як на головній і на сторінці
/// циферблата (смужка 12 pt, footnote); інакше компактна для картки магазину (8 pt, caption2)
struct InstallProgress: View {
    let progress: Double
    let text: String
    var large = true

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.3))
                    Capsule().fill(Color.accentColor)
                        .frame(width: max(large ? 12 : 8, geo.size.width * progress))
                }
            }
            .frame(height: large ? 12 : 8)
            HStack {
                Text(text).lineLimit(1)
                Spacer()
                Text(verbatim: "\(Int(progress * 100))%")
            }
            .font(large ? .footnote : .caption2)
            .foregroundStyle(.secondary)
        }
    }
}
