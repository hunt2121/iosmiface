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
    @State private var pendingKind: ElementKind?
    @State private var showSource = false
    @State private var photo: PhotosPickerItem?
    @State private var photos: [PhotosPickerItem] = []
    @State private var showPhoto = false
    @State private var showFrames = false

    private struct Tile: Identifiable { let kind: ElementKind; let caption: String; let filter: Filter; let enabled: Bool; var id: String { kind.rawValue } }
    private let tiles: [Tile] = [
        Tile(kind: .text, caption: "рядок із даних", filter: .data, enabled: true),
        Tile(kind: .digits, caption: "картинки цифр", filter: .data, enabled: true),
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
                        ForEach(tiles.filter { filter == .all || $0.filter == filter }) { t in
                            Button { choose(t.kind) } label: { tile(t) }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(t.kind.title))
                                .accessibilityHint(Text(loc(t.caption)))
                                .disabled(!t.enabled)
                                .opacity(t.enabled ? 1 : 0.45)
                        }
                    }
                    Text("Далі обираєте, які дані показує елемент: час, дата, кроки, пульс, погода, батарея та інші. Елемент з'являється по центру — його можна перетягнути й налаштувати.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(16)
            }
            .navigationTitle("Додати елемент")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } } }
            .navigationDestination(isPresented: $showSource) {
                DataSourcePicker(current: nil, onPick: { src in if let k = pendingKind { add(k, source: src) } }, keepOpen: true)
            }
        }
        .photosPicker(isPresented: $showPhoto, selection: $photo, matching: .images)
        .photosPicker(isPresented: $showFrames, selection: $photos, maxSelectionCount: 60, matching: .images)
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
            Text(t.kind.title).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
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
        default: pendingKind = k; showSource = true
        }
    }

    private func add(_ k: ElementKind, source: String) {
        let c = center
        project.edit { p in
            switch k {
            case .text: ElementFactory.addText(p, string: "%s", sources: [source], theme: theme, center: c, color: "#FFFFFF")
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
        case .text: Text("Aa").font(.system(size: 20, weight: .bold))
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
    /// у потоці «Додати елемент» аркуш закриває сам себе
    var keepOpen = false

    var body: some View {
        List {
            ForEach(SampleData.groups) { g in
                let items = g.sources.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) || SampleData.title($0).localizedCaseInsensitiveContains(query) }
                if !items.isEmpty {
                    Section(loc(g.title)) {
                        ForEach(items, id: \.self) { s in
                            Button { onPick(s); if !keepOpen { dismiss() } } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(SampleData.title(s)).foregroundStyle(.primary)
                                        if SampleData.titles[s] != nil { Text(verbatim: s).font(.caption2).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    if s == current { Image(systemName: "checkmark").font(.body.weight(.bold)).foregroundStyle(Color.accentColor) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(SampleData.title(s)))
                        }
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

// MARK: - Текст

struct TextLook: View {
    @ObservedObject var project: FaceProject
    let res: XNode
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Текст").font(.subheadline)
                TextField("%s — місце для значення", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { let t = text; project.edit { _ in res.set("string", t) } }
                Text("«%s» замінюється значенням джерела (кожне наступне «%s» — наступним джерелом).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Chips(title: "Шрифт браслета", hint: nil, items: FaceCatalog.fontIds.map { ($0, $0.replacingOccurrences(of: "misans", with: "MiSans ").trimmingCharacters(in: .whitespaces)) },
                  selected: res.string("fontId") ?? "") { v in project.edit { _ in res.set("fontId", v) } }
            Chips(title: "Товщина", hint: nil, items: ["light", "regular", "medium", "bold", "heavy"].map { ($0, $0) },
                  selected: res.string("fontWeight") ?? "") { v in project.edit { _ in res.set("fontWeight", v) } }
            Chips(title: "Вирівнювання", hint: nil, items: [("left", "Ліворуч"), ("center", "Центр"), ("right", "Праворуч")],
                  selected: res.string("align") ?? "left") { v in project.edit { _ in res.set("align", v) } }
            CommitSlider(title: "Ширина поля", value: Double(res.int("w")), range: 10...Double(project.meta.device.width), step: 1) { v in project.edit { _ in res.set("w", int: Int(v)) } }
            CommitSlider(title: "Висота поля", value: Double(res.int("h")), range: 8...200, step: 1) { v in project.edit { _ in res.set("h", int: Int(v)) } }
            StepperRow(title: "Відстань між літерами", value: Int(res.int("letterSpace")), range: 0...40) { v in project.edit { _ in res.set("letterSpace", int: v) } }
            Text("Текст малює сам браслет своїм шрифтом, тож на полотні він виглядає приблизно.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { text = res.string("string") ?? "" }
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

struct LayersSheet: View {
    @ObservedObject var project: FaceProject
    let theme: Int
    @Binding var selected: XNode?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let ls = Array(project.layouts(theme).reversed())
                ForEach(Array(ls.enumerated()), id: \.offset) { _, l in
                    let res = project.resource(ref: l.string("ref"))
                    Button { selected = l; dismiss() } label: {
                        HStack(spacing: 12) {
                            ElementIcon(kind: ElementKind.of(res)).frame(width: 36).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ElementKind.of(res).title).foregroundStyle(.primary)
                                Text(res?.string("source").map(SampleData.title) ?? res?.string("name") ?? "").font(.caption).foregroundStyle(.secondary)
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
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Шари")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
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
                    DebouncedColor(title: "Колір фону", hex: project.theme(theme)?.string("bgColor") ?? "#000000") { h in
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
