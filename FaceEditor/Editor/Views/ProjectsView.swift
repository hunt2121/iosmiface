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
    /// Проєкт з елементами, не перевіреними на браслеті (Б-1) — питаємо перед встановленням
    @State private var askUntested: FaceProject?
    @State private var share: ShareItem?
    /// Мініатюри й анімації за ключем проєкту (змінюється після кожної зміни), тож після закриття редактора
    /// незмінені проєкти показуються одразу, без чорних капсул
    @State private var thumbs: [String: UIImage] = [:]
    @State private var gifs: [String: Data] = [:]
    /// Вага готового .bin за ключем превʼю (рахується у фоні разом з мініатюрою)
    @State private var sizes: [String: Int] = [:]
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
            .refreshable { await install?.refresh() }
            .navigationTitle(title)
            .inlineLargeTitle()
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
        // стандартне вікно «Поділитися» (показ UIKit, як в інших застосунках), а не SwiftUI-аркуш
        .onChange(of: share?.id) { _ in
            guard let item = share else { return }
            share = nil
            ShotShare.present(items: [item.url])
        }
        .alert("Не перевірено на браслеті", isPresented: Binding(get: { askUntested != nil }, set: { if !$0 { askUntested = nil } }), presenting: askUntested) { p in
            Button("Встановити все одно", role: .destructive) { installProject(p, force: true) }
            Button("Скасувати", role: .cancel) {}
        } message: { _ in
            Text("У циферблаті є текст, який малює сам браслет. Його немає в жодному відомому циферблаті Smart Band 10, тож на браслеті він не перевірений і може зламати прошивку. Для чисел і дати безпечніше взяти «Цифри».")
        }
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
            // дві кнопки на всю ширину, як у картці магазину: синя скляна (як «Вибрати») і біла з синім підписом
            VStack(spacing: 12) {
                Button { showNew = true } label: {
                    Label("Новий циферблат", systemImage: "plus")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .foregroundStyle(.white)
                        .background(Capsule().fill(Color.accentColor))
                        .capsuleGlass(tint: Color.accentColor)
                }
                .buttonStyle(.plain)
                Button { showImporter = true } label: {
                    Label("Відкрити .bin", systemImage: "doc")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .foregroundStyle(Color.accentColor)
                        .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    /// Відступ під капсулою до рамки рядка назви: від капсули до верху великих літер — 22 pt,
    /// як від верху картки до капсули (над великими літерами в рамці тексту — ascender − capHeight)
    private static let capsuleToName: CGFloat = {
        let f = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .semibold)
        return max(0, 22 - (f.ascender - f.capHeight))
    }()

    /// Картка як у магазині BandFace: капсула, назва, дата зміни; у BandFace ще й «Встановити».
    private func card(_ p: FaceProject) -> some View {
        Button { editing = p } label: {
            VStack(alignment: .leading, spacing: 0) {
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
                .faceCapsule(active: (install?.status.activeID).map { $0 == p.root.string("id") } ?? false)
                .frame(maxWidth: .infinity)
                // як у магазині: від капсули до букв назви — стільки ж, скільки від верху картки до капсули
                .padding(.top, 12)
                .padding(.bottom, Self.capsuleToName)

                // як картка магазину: назва й кольори праворуч; нижче «вага · дата» і кількість стилів
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text(p.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        ProjectColorDots(colors: ColorVariants.colors(p))
                    }
                    HStack(spacing: 6) {
                        Text(meta(p))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        let n = Self.styleCount(p)
                        if n > 1 { Text(Self.styles(n)).lineLimit(1) }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)

                if let install {
                    ProjectInstallButton(project: p, status: install.status) { installProject(p) }
                        .padding(.top, 10)
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
            if sizes[k] == nil, let n = await Task.detached(priority: .utility, operation: { (try? p.compile())?.0.count }).value {
                sizes[k] = n
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

    /// «1,2 MB · 15.11.26» (рік двома цифрами — вміщається у вузьку картку поруч зі стилями);
    /// поки вага рахується — лише дата
    private func meta(_ p: FaceProject) -> String {
        let date = p.meta.modified.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits))
        guard let n = sizes[FacePreviews.key(p)] else { return date }
        return ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file) + " · " + date
    }

    /// Стилі: звичайні теми (у старих файлах без типів тем друга тема — AOD)
    static func styleCount(_ p: FaceProject) -> Int { max(p.styleThemes.count, 1) }

    /// «2 стилі», «5 стилів» мовою інтерфейсу
    static func styles(_ n: Int) -> String {
        let a = n % 10, b = n % 100
        let few = (2...4).contains(a) && !(12...14).contains(b), one = a == 1 && b != 11
        switch Bundle.main.preferredLocalizations.first ?? "en" {
        case "uk": return "\(n) " + (one ? "стиль" : few ? "стилі" : "стилів")
        case "ru": return "\(n) " + (one ? "стиль" : few ? "стиля" : "стилей")
        default: return n == 1 ? "1 style" : "\(n) styles"
        }
    }

    private func installProject(_ p: FaceProject, force: Bool = false) {
        guard let install else { return }
        if !force && !Band10.untested(p.root).isEmpty { askUntested = p; return }
        guard install.status.current == nil else { return }
        do {
            let (data, _) = try p.compile()
            FacePreviews.alias(data, from: p)
            install.status.begin(p.id, modified: p.meta.modified)
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

    /// Тека проєкту, запакована в .zip (теку саму по собі більшість застосунків не приймає).
    /// Пакує система: NSFileCoordinator з .forUploading віддає тимчасовий zip теки.
    static func zip(_ folder: URL, name: String) -> URL? {
        let safe = name.isEmpty ? folder.lastPathComponent : name.replacingOccurrences(of: "/", with: "-")
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).zip")
        var result: URL?
        var err: NSError?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &err) { tmp in
            try? FileManager.default.removeItem(at: out)
            if (try? FileManager.default.copyItem(at: tmp, to: out)) != nil { result = out }
        }
        return result
    }
}

struct NewFaceSheet: View {
    var onCreate: (String) -> Void
    @State private var name = loc("Мій циферблат")

    var body: some View {
        NavigationStack {
            Form {
                Section("Назва") { InputRow(title: "Назва", value: name, placeholder: "Назва") { t in name = t } }
            }
            .inputBarHost()
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

/// Кнопка під карткою, як у магазині: «Встановити» → смужка з етапом і відсотками;
/// циферблат уже на браслеті — «Перевстановити»
struct ProjectInstallButton: View {
    @ObservedObject var project: FaceProject
    @ObservedObject var status: EditorInstallStatus
    let action: () -> Void

    var body: some View {
        if status.current == project.id {
            InstallProgress(progress: status.progress, text: status.text, large: false)
                .padding(.horizontal, 6)
                .frame(height: 36)
        } else if status.onBand.contains(project.root.string("id") ?? "") {
            // циферблат уже на браслеті — «Перевстановити» (замінить його на браслеті)
            Button(action: action) {
                Text("Перевстановити")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Capsule().fill(Color(.systemGroupedBackground)))
            }
            .buttonStyle(.plain)
            .disabled(status.current != nil)
        } else {
            Button(action: action) {
                Text("Встановити")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color.accentColor))
                    .capsuleGlass(tint: Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(status.current != nil)
        }
    }
}

/// Кольори циферблата на картці, як у магазині BandFace: до 4 кружечків 15 pt внахлест, далі «+N»
struct ProjectColorDots: View {
    let colors: [String]

    var body: some View {
        if colors.count > 1 {
            HStack(spacing: -5) {
                ForEach(Array(colors.prefix(4).enumerated()), id: \.offset) { i, c in
                    Circle().fill(Self.color(c))
                        .frame(width: 15, height: 15)
                        .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 1.5))
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                        .zIndex(Double(10 - i))
                }
                if colors.count > 4 {
                    Text(verbatim: "+\(colors.count - 4)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
            }
            .accessibilityHidden(true)
        }
    }

    static func color(_ hex: String) -> Color {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return Color(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
