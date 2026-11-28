// SPDX-License-Identifier: MIT
// Великий заголовок у рядку кнопок (спільний для BandFace і тестового застосунку редактора).

import SwiftUI

/// Великий заголовок у рядку кнопок (як у TestFlight): по центру висоти рядка, при прокрутці згортається.
/// iOS 16 — звичайний великий заголовок
struct InlineLargeTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17, *) { content.toolbarTitleDisplayMode(.inlineLarge) } else { content }
    }
}

extension View {
    func inlineLargeTitle() -> some View { modifier(InlineLargeTitle()) }
}
