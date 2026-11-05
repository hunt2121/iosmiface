// SPDX-License-Identifier: MIT
// Переклад рядків редактора. Ключі — українські тексти; переклади англійською й російською лежать
// у Localizable.xcstrings застосунку BandFace. В окремому тестовому застосунку перекладів немає — показується ключ.

import Foundation
import SwiftUI

/// Рядок інтерфейсу з таблиці перекладів (для текстів, що передаються як String).
func loc(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

// MARK: - Встановлення з редактора

/// Дія «Встановити на пристрій»: її дає BandFace (передає зібраний .bin і назву).
/// В окремому застосунку редактора її немає — пункт меню не показується.
struct FaceInstallAction {
    let run: (Data, String) -> Void
    func callAsFunction(_ data: Data, _ name: String) { run(data, name) }
}

private struct FaceInstallActionKey: EnvironmentKey {
    static let defaultValue: FaceInstallAction? = nil
}

extension EnvironmentValues {
    var faceInstall: FaceInstallAction? {
        get { self[FaceInstallActionKey.self] }
        set { self[FaceInstallActionKey.self] = newValue }
    }
}
