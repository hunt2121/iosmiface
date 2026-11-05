// SPDX-License-Identifier: MIT
// Список циферблатів редактора: створення, відкриття .bin, експорт, копія, видалення.

import SwiftUI
import UniformTypeIdentifiers
import FaceCompiler

struct ProjectsView: View {
    @StateObject private var store = ProjectStore()
    @State private var editing: FaceProject?
    @State private var showNew = false
    @State private var showImporter = false
    @State private var alert: String?
    @State private var share: ShareItem?
    @State private var thumbs: [String: UIImage] = [:]

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.projects.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(store.projects) { p in
                            card(p)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Мої циферблати")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showNew = true } label: { Label("Новий циферблат", systemImage: "plus") }
                        Button { showImporter = true } label: { Label("Відкрити файл .bin", systemImage: "doc") }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Додати")
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
                alert = "Не вдалося відкрити: \(error.localizedDescription)"
            }
        }
        .fullScreenCover(item: $editing, onDismiss: {
            store.reload(); thumbs = [:]
        }) { p in
            EditorView(project: p)
        }
        .sheet(item: $share) { item in ActivityView(items: [item.url]) }
        .alert(alert ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
            Button("Гаразд", role: .cancel) {}
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "applewatch.watchface").font(.system(size: 48)).foregroundStyle(.secondary)
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

    private func card(_ p: FaceProject) -> some View {
        let dev = p.meta.device
        return Button { editing = p } label: {
            VStack(spacing: 8) {
                ZStack {
                    if let t = thumbs[p.id] {
                        Image(uiImage: t).resizable().scaledToFit()
                    } else {
                        Color.black
                    }
                }
                .frame(width: 194 * CGFloat(dev.width) / CGFloat(dev.height), height: 194)
                .faceCapsule()
                Text(p.name.isEmpty ? "Без назви" : p.name)
                    .font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .task(id: p.revision) {
            if thumbs[p.id] == nil { thumbs[p.id] = FaceRenderer(p).render(theme: 0, scale: 2).0 }
        }
        .contextMenu {
            Button { export(p) } label: { Label("Зберегти .bin", systemImage: "square.and.arrow.up") }
            Button { store.duplicate(p); thumbs = [:] } label: { Label("Копія", systemImage: "plus.square.on.square") }
            Button(role: .destructive) { store.delete(p) } label: { Label("Видалити", systemImage: "trash") }
        }
    }

    private func export(_ p: FaceProject) {
        do {
            let (data, _) = try p.compile()
            share = ShareItem(url: try ShareItem.write(data, name: p.name))
        } catch {
            alert = "Не вдалося зібрати: \(error.localizedDescription)"
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
    @State private var name = "Мій циферблат"

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
