// SPDX-License-Identifier: MIT
// Властивості циферблата: назва, ID, екрани (основний і «Завжди на екрані»), розмір файла.

import SwiftUI
import FaceCompiler

struct FacePropertiesSheet: View {
    @ObservedObject var project: FaceProject
    @Binding var theme: Int
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var size: Int?
    @State private var askDeleteAOD = false
    @FocusState private var nameFocused: Bool

    /// Браслет зберігає назву в 64 байтах UTF-8 (кирилиця — 2 байти на літеру)
    private static let maxBytes = 63
    private var bytes: Int { name.utf8.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(loc("Назва"), text: $name)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(saveName)
                        if !name.isEmpty {
                            Button { name = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Очистити"))
                        }
                    }
                } header: {
                    Text("Назва")
                } footer: {
                    Text(String(format: loc("Так циферблат зветься на браслеті й у списках. %d з %d байтів."), bytes, Self.maxBytes))
                        .foregroundStyle(bytes > Self.maxBytes ? Color.red : Color.secondary)
                }

                Section {
                    HStack {
                        Text(project.root.string("id") ?? "—").font(.body.monospacedDigit())
                        Spacer()
                        Button("Новий ID") {
                            project.edit { $0.root.set("id", ProjectStore.newFaceID()) }
                        }
                    }
                } header: {
                    Text("Ідентифікатор")
                } footer: {
                    Text("Браслет розрізняє циферблати за ID: циферблат із тим самим ID замінює встановлений. Новий ID — щоб поставити його поруч.")
                }

                Section("Екрани") {
                    Button { theme = 0; dismiss() } label: {
                        row(loc("Основний екран"), selected: theme == 0)
                    }
                    if project.themes.count > 1 {
                        Button { theme = 1; dismiss() } label: {
                            row(loc("Завжди на екрані"), selected: theme == 1)
                        }
                        Button(role: .destructive) { askDeleteAOD = true } label: {
                            Text("Видалити «Завжди на екрані»")
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Розмір файла")
                        Spacer()
                        if let size {
                            Text(String(format: loc("%d КБ"), (size + 1023) / 1024)).foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                    }
                    HStack {
                        Text("Екран")
                        Spacer()
                        Text(verbatim: "\(project.meta.device.title) · \(project.meta.device.width)×\(project.meta.device.height)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Циферблат")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { saveName(); dismiss() }
                        .disabled(bytes > Self.maxBytes)
                }
            }
            .confirmationDialog("Видалити екран «Завжди на екрані»?", isPresented: $askDeleteAOD, titleVisibility: .visible) {
                Button("Видалити", role: .destructive) {
                    theme = 0
                    project.edit { ElementFactory.deleteTheme($0, index: 1) }
                }
                Button("Скасувати", role: .cancel) {}
            }
        }
        .onAppear {
            name = project.name
            // розмір готового .bin — коли аркуш уже відкрився
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                size = try? project.compile().0.count
            }
        }
    }

    private func row(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
        }
    }

    private func saveName() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard n != project.name, n.utf8.count <= Self.maxBytes else { return }
        project.edit { $0.root.set("name", n) }
    }
}
