import SwiftUI
import UIKit

/// Кольори тексту з достатнім контрастом у світлій і темній темах.
/// Системні .green / .red на білому фоні виглядають блідо, тож у світлій темі вони темніші.
extension Color {
    /// Усі зелені галочки, написи й обведення (крім плиток-іконок) — один колір для обох тем:
    /// середина між колишніми зеленими написами світлої (#148033) і темної (#30D158) тем
    static let okIcon = Color(red: 34 / 255, green: 168 / 255, blue: 70 / 255)
    static let okText = okIcon

    static let errorText = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor.systemRed
            : UIColor(red: 0.78, green: 0.12, blue: 0.10, alpha: 1)
    })
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
