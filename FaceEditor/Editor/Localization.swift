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
    /// стан встановлення з редактора — для прогресу під карткою циферблата, як у магазині
    let status: EditorInstallStatus
    let run: (Data, String) -> Void
    /// оновити список циферблатів на пристрої (потягнути вниз, як у магазині)
    var refresh: () async -> Void = {}
    func callAsFunction(_ data: Data, _ name: String) { run(data, name) }
}

/// Що зараз встановлюється з редактора і що вже встановлено (поки циферблат не змінювали)
final class EditorInstallStatus: ObservableObject {
    /// id проєкту, який встановлюється
    @Published private(set) var current: String?
    @Published var progress: Double = 0
    @Published var text = ""
    /// id циферблата, який зараз на екрані браслета (nil — невідомо або пристрій не підключено)
    @Published var activeID: String?
    /// id проєкту → дата зміни на момент встановлення
    @Published private(set) var installed: [String: Date] = [:]
    private var pending: Date?

    func begin(_ id: String, modified: Date) {
        current = id; pending = modified; progress = 0
        text = String(localized: "Старт…")
    }
    func succeeded() {
        if let id = current, let m = pending { installed[id] = m }
        current = nil; pending = nil
    }
    func failed() { current = nil; pending = nil }
    func isInstalled(_ id: String, modified: Date) -> Bool { installed[id] == modified }
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
