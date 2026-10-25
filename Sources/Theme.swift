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
