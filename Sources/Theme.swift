import SwiftUI
import UIKit

/// Кольори тексту з достатнім контрастом у світлій і темній темах.
/// Системні .green / .red на білому фоні виглядають блідо, тож у світлій темі вони темніші.
extension Color {
    static let okText = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor.systemGreen
            : UIColor(red: 0.08, green: 0.50, blue: 0.20, alpha: 1)
    })

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

    /// Пошук завжди видно під заголовком одразу після входу на екран.
    func storeSearchable(text: Binding<String>, prompt: Text) -> some View {
        searchable(text: text, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
    }
}
