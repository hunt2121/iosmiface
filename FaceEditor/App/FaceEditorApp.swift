// SPDX-License-Identifier: MIT
// Тестовий застосунок редактора циферблатів. Увесь код редактора лежить у FaceEditor/Editor
// і переноситься в BandFace разом з інтерфейсом.

import SwiftUI

@main
struct FaceEditorApp: App {
    init() {
        // UI-тести починають із порожнього списку
        if CommandLine.arguments.contains("-uitest-reset") {
            let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("FaceProjects")
            try? FileManager.default.removeItem(at: d)
        }
    }

    var body: some Scene {
        WindowGroup {
            ProjectsView()
        }
    }
}
