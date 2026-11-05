import SwiftUI

@main
struct BandFaceApp: App {
    @StateObject private var ble = BLEManager()

    init() {
        // UI-тести починають без циферблатів у редакторі
        if CommandLine.arguments.contains("-uitest-reset") {
            let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("FaceProjects")
            try? FileManager.default.removeItem(at: d)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(ble)
        }
    }
}
