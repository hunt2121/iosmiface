// SPDX-License-Identifier: MIT
// Аркуші редактора: додавання елемента, джерело даних, шари, фон, перегляд; редактор тексту й заміна картинки.

import SwiftUI
import PhotosUI
import FaceCompiler

// MARK: - Додати елемент

struct AddElementSheet: View {
    @ObservedObject var project: FaceProject
    let theme: Int
    var onAdded: (XNode?) -> Void
    @Environment(\.dismiss) private var dismiss

    enum Filter: String, CaseIterable, Identifiable { case all = "Усі", data = "Дані", gauges = "Шкали", decor = "Декор"; var id: String { rawValue } }
    @State private var filter: Filter = .all
    @State private var query = ""
    @State private var pendingKind: ElementKind?
    @State private var showSource = false
    @State private var photo: PhotosPickerItem?
    @State private var photos: [PhotosPickerItem] = []
    @State private var showPhoto = false
    @State private var showFrames = false
    /// «Значки за значенням»: після вибору джерела — вибір картинок
    @State private var valuesSource: String?
    @State private var showValuePhotos = false
    @State private var valuePhotos: [PhotosPickerItem] = []
    /// Картинки значків: свої фото чи намальовані шрифтом (дні тижня, місяці, AM/PM, числа)
    @State private var askValuesHow = false
    @State private var fontArtFor: XNode?

    private struct Tile: Identifiable {
        let kind: ElementKind; let caption: String; let filter: Filter; let enabled: Bool
        var preset: String? = nil
        var title: String { preset == "clock" ? loc("Годинник") : kind.title }
        var id: String { preset ?? kind.rawValue }
    }
    private let tiles: [Tile] = [
        Tile(kind: .label, caption: "рядок картинкою", filter: .decor, enabled: true),
        Tile(kind: .digits, caption: "картинки цифр", filter: .data, enabled: true),
        Tile(kind: .values, caption: "картинка за значенням", filter: .data, enabled: true),
        Tile(kind: .pointer, caption: "три стрілки", filter: .gauges, enabled: true, preset: "clock"),
        Tile(kind: .image, caption: "PNG, фото", filter: .decor, enabled: true),
        Tile(kind: .animation, caption: "кадри, інтервал", filter: .decor, enabled: true),
        Tile(kind: .pointer, caption: "обертання", filter: .gauges, enabled: true),
        Tile(kind: .arc, caption: "шкала", filter: .gauges, enabled: true),
        Tile(kind: .line, caption: "шкала", filter: .gauges, enabled: true),
        Tile(kind: .widget, caption: "у готових циферблатах", filter: .decor, enabled: false),
        Tile(kind: .slot, caption: "у готових циферблатах", filter: .decor, enabled: false),
    ]

    private var center: (Int, Int) { (project.meta.device.width / 2, project.meta.device.height / 2) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        ForEach(Filter.allCases) { f in
                            Button { filter = f } label: {
                                Text(loc(f.rawValue)).font(.subheadline.weight(filter == f ? .semibold : .medium))
                                    .padding(.horizontal, 14).frame(height: 32)
                                    .foregroundStyle(filter == f ? Color.white : Color.primary)
                                    .background(Capsule().fill(filter == f ? Color.accentColor : Color(.tertiarySystemGroupedBackground)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(tiles.filter { (filter == .all || $0.filter == filter) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || loc($0.caption).localizedCaseInsensitiveContains(query)) }) { t in
                            Button { if t.preset == "clock" { addClock() } else { choose(t.kind) } } label: { tile(t) }
                                .buttonStyle(.plain)
                                // довге натискання — «Як це виглядає»
                                .contextMenu {
                                    Button { if t.preset == "clock" { addClock() } else { choose(t.kind) } } label: { Label("Додати", systemImage: "plus") }
                                } preview: {
                                    GalleryPreviewCard(kind: t.kind, clock: t.preset == "clock", title: t.title)
                                }
                                .accessibilityLabel(Text(t.title))
                                .accessibilityHint(Text(loc(t.caption)))
                                .disabled(!t.enabled)
                                .opacity(t.enabled ? 1 : 0.45)
                        }
                    }
                    Text("Утримуйте плитку, щоб побачити, як виглядає елемент. Далі обираєте, які дані він показує: час, дата, кроки, пульс, погода, батарея та інші. Елемент з'являється по центру — його можна перетягнути й налаштувати.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .searchable(text: $query, prompt: "Пошук елемента")
            .navigationTitle("Додати елемент")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } } }
            .navigationDestination(isPresented: $showSource) {
                DataSourcePicker(current: nil, onPick: { src in if let k = pendingKind { add(k, source: src) } }, keepOpen: true, kind: pendingKind)
            }
        }
        .photosPicker(isPresented: $showPhoto, selection: $photo, matching: .images)
        .photosPicker(isPresented: $showFrames, selection: $photos, maxSelectionCount: 60, matching: .images)
        .photosPicker(isPresented: $showValuePhotos, selection: $valuePhotos, maxSelectionCount: 30, matching: .images)
        .confirmationDialog("Як створити картинки?", isPresented: $askValuesHow, titleVisibility: .visible) {
            Button("Намалювати шрифтом (дні тижня, місяці, числа)") { addValuesByFont() }
            Button("Вибрати фото") { showValuePhotos = true }
            Button("Скасувати", role: .cancel) {}
        }
        .sheet(item: Binding(get: { fontArtFor.map { NodeBox(node: $0) } }, set: { fontArtFor = $0?.node })) { box in
            FontArtSheet(project: project, res: box.node, onCancel: { project.undo() })
                .onDisappear { finish() }
        }
        .onChange(of: valuePhotos) { items in
            guard !items.isEmpty, let src = valuesSource else { return }
            Task { @MainActor in
                var imgs: [RGBAImage] = []
                for it in items {
                    if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                        imgs.append(AssetFactory.fromUIImage(img, maxSide: 200))
                    }
                }
                if !imgs.isEmpty {
                    let c = center
                    project.edit { ElementFactory.addValues($0, source: src, images: imgs, theme: theme, center: c) }
                    finish()
                }
            }
        }
        .onChange(of: photo) { item in
            guard let item else { return }
            Task { @MainActor in
                if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    let rgba = AssetFactory.fromUIImage(img, maxSide: CGFloat(max(project.meta.device.width, project.meta.device.height)))
                    project.edit { ElementFactory.addImage($0, rgba, theme: theme, center: center) }
                    finish()
                }
            }
        }
        .onChange(of: photos) { items in
            guard !items.isEmpty else { return }
            Task { @MainActor in
                var frames: [RGBAImage] = []
                var size: CGSize?
                for it in items {
                    guard let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) else { continue }
                    let s = size ?? CGSize(width: min(img.size.width, 200), height: min(img.size.width, 200) * img.size.height / max(img.size.width, 1))
                    size = s
                    frames.append(AssetFactory.render(Int(s.width), Int(s.height)) { _ in img.draw(in: CGRect(origin: .zero, size: s)) })
                }
                if !frames.isEmpty {
                    project.edit { ElementFactory.addAnimation($0, frames, interval: 100, theme: theme, center: center) }
                    finish()
                }
            }
        }
    }

    private func tile(_ t: Tile) -> some View {
        VStack(spacing: 6) {
            ElementIcon(kind: t.kind).frame(height: 44)
            Text(t.title).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
            Text(loc(t.caption)).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.tertiarySystemGroupedBackground)))
    }

    private func choose(_ k: ElementKind) {
        switch k {
        case .image: showPhoto = true
        case .animation: showFrames = true
        case .label: addLabel()
        default: pendingKind = k; showSource = true
        }
    }

    /// Напис одразу по центру; рядок, шрифт і колір — у властивостях
    private func addLabel() {
        let c = center
        let g = Generator(kind: .label, color: "#FFFFFF", fontSize: 28, weight: 600, style: "rounded", text: loc("Напис"))
        project.edit { ElementFactory.addLabel($0, gen: g, theme: theme, center: c) }
        finish()
    }

    private func addClock() {
        let c = center
        project.edit { ElementFactory.addAnalogClock($0, theme: theme, center: c) }
        finish()
    }

    private func add(_ k: ElementKind, source: String) {
        if k == .values {
            // далі — картинки для значень
            valuesSource = source
            askValuesHow = true
            return
        }
        let c = center
        project.edit { p in
            switch k {
            case .digits:
                ElementFactory.addDigits(p, source: source, gen: Generator(kind: .digits, color: "#FFFFFF", fontSize: 48, weight: 700, style: "rounded"), theme: theme, center: c)
            case .pointer:
                ElementFactory.addPointer(p, source: source, gen: Generator(kind: .pointer, color: "#FFFFFF", width: 6, length: 80), theme: theme, center: c)
            case .arc:
                ElementFactory.addArc(p, source: source, gen: Generator(kind: .arc, color: "#30B455", bgColor: "#3A3A3C", radius: 60, width: 10), theme: theme, center: c)
            case .line:
                ElementFactory.addLine(p, source: source, gen: Generator(kind: .line, color: "#0A6CF0", bgColor: "#3A3A3C", width: 8, length: 140), theme: theme, center: c)
            default: break
            }
        }
        finish()
    }

    /// Елемент значків з порожніми картинками → одразу «Намалювати шрифтом»; скасували — прибираємо
    private func addValuesByFont() {
        guard let src = valuesSource else { return }
        let l = src.lowercased()
        let n = l.contains("week") ? 7 : l.contains("month") ? 12 : l.contains("ampm") ? 2 : 5
        let blank = (0..<n).map { _ in RGBAImage(w: 40, h: 40, px: [UInt8](repeating: 0, count: 40 * 40 * 4)) }
        let c = center
        project.edit { ElementFactory.addValues($0, source: src, images: blank, theme: theme, center: c) }
        fontArtFor = project.layouts(theme).last.flatMap { project.element(of: $0) }
    }

    private func finish() {
        onAdded(project.layouts(theme).last)
        dismiss()
    }
}

/// Значок типу елемента (як на макеті).
struct ElementIcon: View {
    let kind: ElementKind
    var body: some View {
        switch kind {
        case .text, .label: Text("Aa").font(.system(size: 20, weight: .bold))
        case .digits: Text("10 24").font(.system(size: 18, weight: .heavy)).tracking(-0.5)
        case .image: Image(systemName: "photo").font(.system(size: 24))
        case .animation: Image(systemName: "square.stack").font(.system(size: 24))
        case .pointer: Image(systemName: "clock").font(.system(size: 26))
        case .arc:
            ZStack {
                Circle().trim(from: 0.0, to: 0.75).stroke(Color(.systemGray4), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                Circle().trim(from: 0.0, to: 0.4).stroke(Color.green, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            .rotationEffect(.degrees(135)).frame(width: 32, height: 32)
        case .line:
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray4)).frame(width: 34, height: 7)
                Capsule().fill(Color.accentColor).frame(width: 22, height: 7)
            }
        case .values: Image(systemName: "square.grid.2x2").font(.system(size: 24))
        case .widget: Image(systemName: "plus.rectangle").font(.system(size: 24))
        case .slot: Image(systemName: "rectangle.dashed").font(.system(size: 24))
        case .other: Image(systemName: "square").font(.system(size: 24))
        }
    }
}

// MARK: - Джерело даних

struct DataSourcePicker: View {
    let current: String?
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// вибрана група ("" — усі)
    @State private var group = ""
    /// у потоці «Додати елемент» аркуш закриває сам себе
    var keepOpen = false
    /// для якого елемента — зверху «Найчастіше»
    var kind: ElementKind? = nil

    private static let recommended: [ElementKind: [String]] = [
        .digits: ["timeHour", "timeMinute", "dateDay", "dateMonth", "healthStepCount", "healthHeartRate", "systemStatusBattery"],
        .values: ["systemStatusBattery", "weatherCurrentWeather", "dateWeek", "systemStatusBluetooth"],
        .pointer: ["timeHour", "timeMinute", "timeSecond", "systemStatusBattery"],
        .arc: ["healthStepProgress", "healthCalorieProgress", "healthStandProgress", "systemStatusBattery", "healthHeartRate"],
        .line: ["systemStatusBattery", "healthStepProgress", "healthCalorieProgress", "healthStandProgress"],
    ]

    /// Приклад значення праворуч від назви
    static func example(_ s: String) -> String {
        let v = SampleData.value(s)
        let l = s.lowercased()
        if l.contains("progress") || l.contains("battery") || l.contains("humidity") { return "\(v) %" }
        if l.contains("heartrate") { return "\(v) bpm" }
        if l.contains("temperature") { return "\(v)°" }
        if ["timeHour", "timeMinute", "timeSecond"].contains(s) { return String(format: "%02d", v) }
        return "\(v)"
    }

    private func row(_ s: String) -> some View {
        Button { onPick(s); if !keepOpen { dismiss() } } label: {
            HStack(spacing: 12) {
                SourceTile(source: s)
                VStack(alignment: .leading, spacing: 1) {
                    Text(SampleData.title(s)).foregroundStyle(.primary)
                    if SampleData.titles[s] != nil { Text(verbatim: s).font(.caption2).foregroundStyle(.secondary) }
                }
                Spacer()
                Text(verbatim: Self.example(s)).font(.caption.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(.tertiarySystemGroupedBackground)))
                if s == current { Image(systemName: "checkmark").font(.body.weight(.bold)).foregroundStyle(Color.accentColor) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(SampleData.title(s)))
    }

    private func groupChip(_ id: String, _ title: String) -> some View {
        let on = id == group
        return Button { group = id } label: {
            Text(verbatim: title).font(.subheadline.weight(on ? .semibold : .regular))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .foregroundStyle(on ? Color.white : Color.primary)
                .background(Capsule().fill(on ? Color.accentColor : Color(.tertiarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        List {
            // перемикачі груп
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        groupChip("", loc("Усе"))
                        ForEach(SampleData.groups) { g in groupChip(g.id, loc(g.title)) }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            if group.isEmpty, let k = kind, let rec = Self.recommended[k] {
                let items = rec.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) || SampleData.title($0).localizedCaseInsensitiveContains(query) }
                if !items.isEmpty { Section(loc("Найчастіше")) { ForEach(items, id: \.self) { row($0) } } }
            }
            ForEach(SampleData.groups.filter { group.isEmpty || $0.id == group }) { g in
                let items = g.sources.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) || SampleData.title($0).localizedCaseInsensitiveContains(query) }
                if !items.isEmpty {
                    Section(loc(g.title)) {
                        ForEach(items, id: \.self) { row($0) }
                    }
                }
            }
            Section {
                Text("Загалом \(FaceCatalog.sources.count) джерел: час, дата, здоров'я, погода, система та інші.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .searchable(text: $query, prompt: "Пошук")
        .navigationTitle("Що показувати")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Плитка зі значком групи джерела
struct SourceTile: View {
    let source: String
    var body: some View {
        Image(systemName: SampleData.symbol(SampleData.groupOf(source)))
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(.tertiarySystemGroupedBackground)))
    }
}

/// Кнопка «Що показує»: значок групи, назва (і технічне імʼя, якщо є назва), приклад значення, стрілка
struct SourceButton: View {
    let source: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                SourceTile(source: source)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: SampleData.title(source)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    if SampleData.titles[source] != nil { Text(verbatim: source).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 6)
                Text(verbatim: DataSourcePicker.example(source)).font(.caption.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(.tertiarySystemGroupedBackground)))
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Заміна картинки

struct ImageReplaceRow: View {
    @ObservedObject var project: FaceProject
    let res: XNode
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            Label(loc(res.tag == "ImageArray" ? "Замінити кадри недоступно" : "Замінити зображення"), systemImage: "photo")
                .font(.subheadline.weight(.semibold))
        }
        .disabled(res.tag != "Image")
        .onChange(of: item) { it in
            guard let it else { return }
            Task { @MainActor in
                if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                    let rgba = AssetFactory.fromUIImage(img, maxSide: CGFloat(max(project.meta.device.width, project.meta.device.height)))
                    project.edit {
                        ElementFactory.replaceImage($0, res, rgba)
                        ColorVariants.refresh($0, element: res)
                    }
                }
            }
        }
    }
}

// MARK: - Шари

/// Підпис шару в списку: джерело даних, текст напису або ім'я ресурсу
func layerSubtitle(_ p: FaceProject, _ res: XNode?) -> String {
    if let s = res?.string("source") { return SampleData.title(s) }
    let name = res?.string("name") ?? ""
    if let g = p.meta.generators[name], g.kind == .label { return "«" + g.text + "»" }
    return name
}

struct LayersSheet: View {
    @ObservedObject var project: FaceProject
    let theme: Int
    @Binding var selected: XNode?
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    Text("Шари").tag(0)
                    Text("Зображення").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 8)
                if tab == 0 { layers } else { ImagesList(project: project, theme: theme, selected: $selected) }
            }
            .navigationTitle(tab == 0 ? loc("Шари") : loc("Зображення"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }

    private var layers: some View {
            List {
                // «Циферблат» — завжди зверху: назва, фон, кольори циферблата
                Section {
                    Button { selected = nil; dismiss() } label: {
                        HStack(spacing: 12) {
                            Image("TabWatch").renderingMode(.template).resizable().scaledToFit().frame(width: 24, height: 24).frame(width: 36).foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Циферблат").foregroundStyle(.primary).fontWeight(.semibold)
                                Text("Назва, фон, кольори, файл").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selected == nil { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .moveDisabled(true).deleteDisabled(true)
                }
                Section {
                let ls = Array(project.layouts(theme).reversed())
                ForEach(Array(ls.enumerated()), id: \.offset) { _, l in
                    let res = project.element(of: l)
                    Button { selected = l; dismiss() } label: {
                        HStack(spacing: 12) {
                            ElementIcon(kind: ElementKind.of(res, in: project)).frame(width: 36).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ElementKind.of(res, in: project).title).foregroundStyle(.primary)
                                Text(layerSubtitle(project, res)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if l === selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .onMove { from, to in
                    guard let f = from.first else { return }
                    let n = ls.count
                    let moving = ls[f]
                    // список перевернутий: верхній рядок — останній шар
                    let target = n - (to > f ? to - 1 : to) - 1
                    project.edit { ElementFactory.move($0, layout: moving, theme: theme, to: target) }
                }
                .onDelete { idx in
                    for i in idx {
                        let l = ls[i]
                        if l === selected { selected = nil }
                        project.edit { ElementFactory.delete($0, layout: l, theme: theme) }
                    }
                }
                }
            }
            .environment(\.editMode, .constant(.active))
    }
}

// MARK: - Фон

struct BackgroundSheet: View {
    @ObservedObject var project: FaceProject
    let theme: Int
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ColorRow(title: "Колір фону", hex: project.theme(theme)?.string("bgColor") ?? "#000000") { h in
                        project.edit { $0.theme(theme)?.set("bgColor", h) }
                    }
                }
                Section {
                    PhotosPicker(selection: $item, matching: .images) {
                        Label("Фонове зображення", systemImage: "photo")
                    }
                } footer: {
                    Text("Картинка розтягується на весь екран і стає найнижчим шаром.")
                }
            }
            .navigationTitle("Фон")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .onChange(of: item) { it in
            guard let it else { return }
            Task { @MainActor in
                guard let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) else { return }
                let dev = project.meta.device
                let size = CGSize(width: dev.width, height: dev.height)
                // заповнення екрана з обрізанням країв
                let s = max(size.width / img.size.width, size.height / img.size.height)
                let dr = CGRect(x: (size.width - img.size.width * s) / 2, y: (size.height - img.size.height * s) / 2,
                                width: img.size.width * s, height: img.size.height * s)
                let rgba = AssetFactory.render(dev.width, dev.height) { _ in img.draw(in: dr) }
                project.edit { p in
                    let name = ElementFactory.addImageResource(p, rgba, base: "background")
                    guard let th = p.theme(theme) else { return }
                    let l = XNode("Layout")
                    l.set("ref", "@" + name).set("x", int: 0).set("y", int: 0)
                    let first = th.kids.firstIndex { $0.tag == "Layout" } ?? th.kids.count
                    th.kids.insert(l, at: first)
                }
                dismiss()
            }
        }
    }
}

// MARK: - Перегляд

struct PreviewView: View {
    @ObservedObject var project: FaceProject
    let theme: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var renderer: FaceRenderer?
    @State private var sprite: SpriteLayer?

    /// Анімація на темі: шари під нею й над нею малюються раз на секунду (живий час), а сама анімація —
    /// кадрами з циферблата в UIImageView (без перемальовування всього екрана 16 разів на секунду)
    struct SpriteLayer {
        let index: Int
        let x: CGFloat, y: CGFloat
        let frames: [UIImage]
        let duration: Double
        let repeats: Int
    }

    var body: some View {
        GeometryReader { geo in
            let dev = project.meta.device
            // рівно під фізичні пікселі капсули на весь екран
            let fit = min((geo.size.width - 80) / CGFloat(dev.width), (geo.size.height - 80) / CGFloat(dev.height))
            ZStack {
                Color.black.ignoresSafeArea()
                TimelineView(.periodic(from: Date(), by: 1)) { _ in
                    let r = renderer ?? FaceRenderer(project)
                    let s = sprite
                    let below = { () -> UIImage in
                        r.live = true
                        let filter: ((Int) -> Bool)? = s.map { sp -> (Int) -> Bool in { $0 < sp.index } }
                        return r.render(theme: theme, scale: max(1, fit * displayScale), layers: filter).0
                    }()
                    let above: UIImage? = s.map { sp -> UIImage in
                        r.render(theme: theme, scale: max(1, fit * displayScale), layers: { $0 > sp.index }, opaque: false).0
                    }
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: below).resizable()
                        if let s {
                            SpriteFramesView(frames: s.frames, duration: s.duration, repeats: s.repeats)
                                .frame(width: (s.frames.first?.size.width ?? 0) * fit, height: (s.frames.first?.size.height ?? 0) * fit)
                                .offset(x: s.x * fit, y: s.y * fit)
                        }
                        if let above { Image(uiImage: above).resizable() }
                    }
                    .frame(width: CGFloat(dev.width) * fit, height: CGFloat(dev.height) * fit)
                    .clipped()
                    .faceCapsule()
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            let r = FaceRenderer(project)
            renderer = r
            let ls = project.layouts(theme)
            if let i = ls.firstIndex(where: { project.resource(ref: $0.string("ref"))?.tag == "Sprite" }),
               let res = project.resource(ref: ls[i].string("ref")) {
                let frames = r.frames(project.resource(ref: res.string("ref"))).map { UIImage(cgImage: $0) }
                if frames.count > 1 {
                    let ms = Double(max(16, Int(res.int("interval", 100))))
                    sprite = SpriteLayer(index: i, x: CGFloat(ls[i].int("x")), y: CGFloat(ls[i].int("y")), frames: frames,
                                         duration: ms * Double(frames.count) / 1000, repeats: Int(res.int("repeatCount")))
                }
            }
        }
        .onTapGesture { dismiss() }
        .accessibilityLabel("Попередній перегляд. Торкніться, щоб закрити.")
    }
}

/// Кадри анімації (UIImageView: програє сама, без перемальовування SwiftUI)
struct SpriteFramesView: UIViewRepresentable {
    let frames: [UIImage]
    let duration: Double
    let repeats: Int

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleToFill
        v.layer.magnificationFilter = .linear
        v.animationImages = frames
        v.animationDuration = duration
        v.animationRepeatCount = max(0, repeats)
        v.image = repeats > 0 ? frames.last : frames.first
        v.startAnimating()
        return v
    }

    func updateUIView(_ v: UIImageView, context: Context) {}
}
