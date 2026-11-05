// SPDX-License-Identifier: MIT
// Єдина форма циферблата в редакторі — як FaceCapsule у BandFace: капсула, рамка 3 pt ЗЗОВНІ
// (циферблат не перекривається). Однакова на списку, полотні й у перегляді.

import SwiftUI

enum FaceFrame {
    /// Товщина рамки корпусу
    static let border: CGFloat = 3
    static let color = Color.gray.opacity(0.45)
}

extension View {
    /// Обрізає вміст капсулою і додає рамку корпусу назовні (розмір зростає на 2 × border).
    func faceCapsule(active: Bool = false) -> some View {
        self
            .clipShape(Capsule(style: .continuous))
            .padding(FaceFrame.border)
            .background(Capsule(style: .continuous).fill(active ? Color.accentColor : FaceFrame.color))
    }
}
