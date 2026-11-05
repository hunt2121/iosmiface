// SPDX-License-Identifier: MIT
// Тестовий застосунок редактора циферблатів. Увесь код редактора лежить у FaceEditor/Editor
// і переноситься в BandFace разом з інтерфейсом.

import SwiftUI

@main
struct FaceEditorApp: App {
    var body: some Scene {
        WindowGroup {
            ProjectsView()
        }
    }
}
