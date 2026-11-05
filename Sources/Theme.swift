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
