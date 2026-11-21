// SPDX-License-Identifier: MIT
// Властивості циферблата: назва, ID, стилі (у кожного — звичайний екран і свій «Завжди на екрані»), розмір файла.

import SwiftUI
import FaceCompiler

struct FacePropertiesSheet: View {
    @ObservedObject var project: FaceProject
    @Binding var theme: Int
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var size: Int?
    /// Підтвердження: видалити AOD (номер теми) / стиль (номер теми)
    @State private var askDeleteAOD: Int?
    @State private var askDeleteStyle: Int?
    @State private var idText = ""
    @State private var idInvalid = false

    /// Браслет зберігає назву в 64 байтах UTF-8 (кирилиця — 2 байти на літеру)
    private static let maxBytes = 63
    private var bytes: Int { name.utf8.count }

    private func commitId() {
        let t = idText.trimmingCharacters(in: .whitespaces)
        guard t != (project.root.string("id") ?? "") else { idInvalid = false; return }
        // ID завжди рівно 9 цифр (як у нових циферблатів), перша не 0
        if t.count == 9, t.allSatisfy({ $0.isASCII && $0.isNumber }), t.first != "0" { project.edit { $0.root.set("id", t) }; idInvalid = false }
        else { idInvalid = true; idText = project.root.string("id") ?? "" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    InputRow(title: "Назва", value: name, placeholder: "Назва") { t in name = t; saveName() }
                } header: {
                    Text("Назва")
                } footer: {
                    Text(String(format: loc("Так циферблат зветься на браслеті й у списках. %d з %d байтів."), bytes, Self.maxBytes))
                        .foregroundStyle(bytes > Self.maxBytes ? Color.red : Color.secondary)
                }

                Section {
                    HStack {
                        // ID можна ввести вручну: рівно 9 цифр
                        InputRow(title: "ID", value: idText, numeric: true) { t in
                            idText = String(t.filter { $0.isASCII && $0.isNumber }.prefix(9)); commitId()
                        }
                        .font(.body.monospacedDigit())
                        .onAppear { idText = project.root.string("id") ?? "" }
                        Button("Новий ID") {
                            let n = ProjectStore.newFaceID()
                            project.edit { $0.root.set("id", n) }
                            idText = n
                        }
                    }
                    if idInvalid {
                        Text("ID — рівно 9 цифр, перша не 0.").font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Ідентифікатор")
                } footer: {
                    Text("Браслет розрізняє циферблати за ID: циферблат із тим самим ID замінює встановлений. Новий ID — щоб поставити його поруч.")
                }

                // Стилі: у кожного — звичайний екран і, за бажанням, свій «Завжди на екрані» з власним приглушенням
                ForEach(project.styleThemes, id: \.self) { st in
                    Section {
                        InputRow(title: "Назва стилю", value: project.theme(st)?.string("name") ?? "", placeholder: "Без назви") { t in
                            if t != (project.theme(st)?.string("name") ?? "") { project.edit { $0.theme(st)?.set("name", t) } }
                        }
                        Button { theme = st; dismiss() } label: {
                            row(loc("Звичайний екран"), selected: theme == st)
                        }
                        if let aod = project.aodTheme(forStyle: st) {
                            Button { theme = aod; dismiss() } label: {
                                row(loc("Завжди на екрані"), selected: theme == aod)
                            }
                            // приглушення всього екрана AOD — чорний напівпрозорий шар поверх
                            CommitSlider(title: "Приглушення AOD, %", value: Double(AodDim.percent(project, aod: aod)), range: 0...90, step: 1) { v in
                                let pc = Int(v.rounded())
                                if pc != AodDim.percent(project, aod: aod) { project.edit { AodDim.set($0, aod: aod, percent: pc) } }
                            }
                            Button(role: .destructive) { askDeleteAOD = aod } label: { Text("Видалити «Завжди на екрані»") }
                        } else {
                            Button {
                                var t = st
                                project.edit { t = ElementFactory.addAod($0, style: st) }
                                theme = t; dismiss()
                            } label: { Text("Додати «Завжди на екрані»") }
                        }
                        if project.styleThemes.count > 1 {
                            Button(role: .destructive) { askDeleteStyle = st } label: { Text("Видалити стиль") }
                        }
                    } header: {
                        Text(project.styleTitle(st))
                    }
                }
                Section {
                    Button {
                        var t = theme
                        let cur = project.styleTheme(of: theme)
                        project.edit { t = ElementFactory.addStyle($0, copyOf: cur) }
                        theme = t; dismiss()
                    } label: { Label("Копіювати поточний стиль", systemImage: "square.on.square") }
                    Button {
                        var t = theme
                        project.edit { t = ElementFactory.addStyle($0, copyOf: nil) }
                        theme = t; dismiss()
                    } label: { Label("Новий порожній стиль", systemImage: "plus") }
                } footer: {
                    Text("Копія стилю використовує ті самі картинки — файли не дублюються. «Приглушення AOD» — чорний напівпрозорий шар поверх «Завжди на екрані»: картинки спільні зі звичайним екраном, а в AOD виглядають тьмяніше. На браслеті стиль вибирається довгим натисканням на циферблат.")
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
            .inputBarHost()
            .navigationTitle("Циферблат")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { saveName(); dismiss() }
                        .disabled(bytes > Self.maxBytes)
                }
            }
            .confirmationDialog("Видалити екран «Завжди на екрані»?",
                                isPresented: Binding(get: { askDeleteAOD != nil }, set: { if !$0 { askDeleteAOD = nil } }),
                                titleVisibility: .visible) {
                Button("Видалити", role: .destructive) {
                    if let a = askDeleteAOD {
                        theme = project.styleTheme(of: a)
                        project.edit { ElementFactory.deleteTheme($0, index: a) }
                    }
                }
                Button("Скасувати", role: .cancel) {}
            }
            .confirmationDialog("Видалити стиль разом з його «Завжди на екрані»?",
                                isPresented: Binding(get: { askDeleteStyle != nil }, set: { if !$0 { askDeleteStyle = nil } }),
                                titleVisibility: .visible) {
                Button("Видалити", role: .destructive) {
                    if let st = askDeleteStyle {
                        theme = 0
                        project.edit { ElementFactory.deleteStyle($0, style: st) }
                    }
                }
                Button("Скасувати", role: .cancel) {}
            } message: {
                Text("Картинки, які використовують інші стилі, лишаються.")
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
