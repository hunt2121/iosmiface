// SPDX-License-Identifier: MIT
// Список циферблатів редактора: створення, відкриття .bin, експорт, копія, видалення.

import SwiftUI
import UniformTypeIdentifiers
import FaceCompiler

struct ProjectsView: View {
    @ObservedObject var store: ProjectStore
    /// Відкритий у редакторі циферблат (BandFace відкриває сюди й копії з магазину)
    @Binding var editing: FaceProject?
    var title: LocalizedStringKey = "Мої циферблати"
    /// «Встановити на пристрій» — лише в BandFace
    @Environment(\.faceInstall) private var install
    @State private var showNew = false
    @State private var showImporter = false
    @State private var alert: String?
    @State private var share: ShareItem?
    /// Мініатюри й анімації за ключем проєкту (змінюється після кожної зміни), тож після закриття редактора
    /// незмінені проєкти показуються одразу, без чорних капсул
    @State private var thumbs: [String: UIImage] = [:]
    @State private var gifs: [String: Data] = [:]
    @State private var askDelete: FaceProject?

    // як сітка магазину BandFace
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.projects.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(store.projects) { p in
                            card(p)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showNew = true } label: { Label("Новий циферблат", systemImage: "plus") }
                        Button { showImporter = true } label: { Label("Відкрити файл .bin", systemImage: "doc") }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(Text("Додати"))
                }
            }
        }
        .sheet(isPresented: $showNew) {
            NewFaceSheet { name in
                showNew = false
                editing = store.create(name: name)
            }
            .presentationDetents([.height(200)])
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                editing = try store.importBin(data, name: url.deletingPathExtension().lastPathComponent)
            } catch {
                alert = String(localized: "Не вдалося відкрити: \(error.localizedDescription)")
            }
        }
        .fullScreenCover(item: $editing, onDismiss: {
            store.reload()
        }) { p in
            EditorView(project: p)
                .environment(\.faceInstall, install)
        }
        .sheet(item: $share) { item in ActivityView(items: [item.url]) }
        .alert(alert ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
            Button("Гаразд", role: .cancel) {}
        }
        .alert(askDelete.map { String(localized: "Видалити «\($0.displayName)»?") } ?? "",
               isPresented: Binding(get: { askDelete != nil }, set: { if !$0 { askDelete = nil } }),
               presenting: askDelete) { p in
            Button("Видалити", role: .destructive) { store.delete(p) }
            Button("Скасувати", role: .cancel) {}
        } message: { _ in
            Text("Циферблат зникне з редактора. На пристрої він лишиться, якщо вже встановлений.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image("TabWatch").resizable().scaledToFit().frame(height: 48).foregroundStyle(.secondary)
            Text("Тут будуть ваші циферблати").font(.headline)
            Text("Створіть новий або відкрийте готовий файл .bin, щоб змінити його.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Новий циферблат") { showNew = true }.glassProminentStyle()
                Button("Відкрити .bin") { showImporter = true }.glassSecondaryStyle()
            }
            .padding(.top, 6)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    /// Картка як у магазині BandFace: капсула, назва, дата зміни; у BandFace ще й «Встановити».
    private func card(_ p: FaceProject) -> some View {
        Button { editing = p } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    Color.black
                    let k = FacePreviews.key(p)
                    if let gif = gifs[k] {
                        FaceAnimationView(gif: gif)
                    } else if let t = thumbs[k] ?? FacePreviews.cachedThumbnail(p) {
                        Image(uiImage: t).resizable().scaledToFill()
                    }
                }
                .frame(width: 96, height: 236)
                .faceCapsule()
                .frame(maxWidth: .infinity)
                .frame(height: 266)

                VStack(alignment: .leading, spacing: 0) {
                    Text(p.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(p.meta.modified.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)

                if install != nil {
                    Button { installProject(p) } label: {
                        Text("Встановити")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .foregroundStyle(.white)
                            .background(Capsule().fill(Color.accentColor))
                            .capsuleGlass(tint: Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .task(id: FacePreviews.key(p)) {
            // з кешу, поки проєкт не змінювали; інакше малюється у фоні (картинка, потім анімація)
            let k = FacePreviews.key(p)
            if thumbs[k] == nil, let t = await Task.detached(priority: .userInitiated, operation: { FacePreviews.thumbnail(p) }).value {
                thumbs[k] = t
            }
            if gifs[k] == nil, let g = await Task.detached(priority: .utility, operation: { FacePreviews.projectGIF(p) }).value {
                gifs[k] = g
            }
        }
        .contextMenu {
            if install != nil {
                Button { installProject(p) } label: { Label("Встановити на пристрій", systemImage: "arrow.down.to.line") }
            }
            Button { editing = p } label: { Label("Змінити", systemImage: "pencil") }
            Button { export(p) } label: { Label("Зберегти .bin", systemImage: "square.and.arrow.up") }
            Button { store.duplicate(p) } label: { Label("Копія", systemImage: "plus.square.on.square") }
            Button(role: .destructive) { askDelete = p } label: { Label("Видалити", systemImage: "trash") }
        }
    }

    private func installProject(_ p: FaceProject) {
        guard let install else { return }
        do {
            let (data, _) = try p.compile()
            install(data, p.displayName)
        } catch {
            alert = String(localized: "Не вдалося зібрати: \(error.localizedDescription)")
        }
    }

    private func export(_ p: FaceProject) {
        do {
            let (data, _) = try p.compile()
            share = ShareItem(url: try ShareItem.write(data, name: p.name))
        } catch {
            alert = String(localized: "Не вдалося зібрати: \(error.localizedDescription)")
        }
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: String { url.path }

    static func write(_ data: Data, name: String) throws -> URL {
        let safe = name.isEmpty ? "watchface" : name.replacingOccurrences(of: "/", with: "-")
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).bin")
        try? FileManager.default.removeItem(at: u)
        try data.write(to: u)
        return u
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct NewFaceSheet: View {
    var onCreate: (String) -> Void
    @State private var name = loc("Мій циферблат")

    var body: some View {
        NavigationStack {
            Form {
                Section("Назва") { TextField("Назва", text: $name) }
            }
            .navigationTitle("Новий циферблат")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Створити") { onCreate(name) }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
