// SPDX-License-Identifier: MIT
// «Зображення»: усі картинки проєкту з мініатюрами; заміна по одній (з Фото або «Файлів»),
// «Поділитися PNG». Ті самі дії — в інспекторі вибраного елемента.

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import FaceCompiler

struct ImageRef: Identifiable, Hashable {
    let src: String
    let owner: XNode
    var id: String { src }
    static func == (a: ImageRef, b: ImageRef) -> Bool { a.src == b.src }
    func hash(into h: inout Hasher) { h.combine(src) }
}

enum ProjectImages {
    /// Усі картинки, на які посилаються ресурси (для масиву кадрів — кожен кадр окремо)
    static func all(_ p: FaceProject) -> [ImageRef] {
        var out: [ImageRef] = []
        var seen = Set<String>()
        func walk(_ owner: XNode, _ n: XNode) {
            if let s = n.string("src"), p.file(s) != nil, seen.insert(MemoryStorage.normalizedPath(s)).inserted { out.append(ImageRef(src: s, owner: owner)) }
            for c in n.elements { walk(owner, c) }
        }
        for r in p.resources.elements { walk(r, r) }
        return out
    }

    /// Картинки елемента разом з тими, на які він посилається (фон шкали, кадри цифр…)
    static func of(_ p: FaceProject, _ res: XNode?) -> [ImageRef] {
        guard let res else { return [] }
        var names: Set<String> = [res.string("name") ?? ""]
        func refs(_ n: XNode) {
            for (k, _) in n.attrs { if let v = n.string(k), v.hasPrefix("@") { names.insert(String(v.dropFirst())) } }
            for c in n.elements { refs(c) }
        }
        refs(res)
        return all(p).filter { names.contains($0.owner.string("name") ?? "") }
    }

    static func uiImage(_ p: FaceProject, _ src: String) -> UIImage? { p.file(src).flatMap { UIImage(data: $0) } }

    /// PNG у тимчасовій теці — щоб поділитися або зберегти у «Файли»
    static func exportURL(_ p: FaceProject, _ src: String) -> URL? {
        guard let d = p.file(src) else { return nil }
        let name = (src as NSString).lastPathComponent
        let url = FileManager.default.temporaryDirectory.appendingPathComponent((name as NSString).deletingPathExtension + ".png")
        try? d.write(to: url)
        return url
    }

    /// Підігнати картинку під розмір (вписати по центру)
    static func fit(_ img: UIImage, _ w: Int, _ h: Int) -> RGBAImage {
        AssetFactory.render(w, h) { _ in
            let s = min(CGFloat(w) / img.size.width, CGFloat(h) / img.size.height)
            let sz = CGSize(width: img.size.width * s, height: img.size.height * s)
            img.draw(in: CGRect(x: (CGFloat(w) - sz.width) / 2, y: (CGFloat(h) - sz.height) / 2, width: sz.width, height: sz.height))
        }
    }

    static func replace(_ p: FaceProject, _ im: ImageRef, with img: RGBAImage) {
        let owner = im.owner, src = im.src
        p.edit { pr in
            pr.setFile(src, img.png)
            // своя картинка — параметри малювання цього ресурсу більше не діють
            pr.meta.generators.removeValue(forKey: owner.string("name") ?? "")
            ColorVariants.refresh(pr, element: owner)
        }
    }
}

/// Заміна однієї картинки: з Фото або з «Файлів»; інший розмір — запитати, чи підігнати
struct ImageReplacer: ViewModifier {
    @ObservedObject var project: FaceProject
    @Binding var target: ImageRef?
    @Binding var fromFiles: Bool
    @State private var photo: PhotosPickerItem?
    @State private var pending: UIImage?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: Binding(get: { target != nil && !fromFiles }, set: { if !$0 && photo == nil && pending == nil { target = nil } }),
                          selection: $photo, matching: .images)
            .fileImporter(isPresented: Binding(get: { target != nil && fromFiles }, set: { if !$0 && pending == nil { fromFiles = false } }),
                          allowedContentTypes: [.png, .jpeg, .image]) { r in
                if case .success(let url) = r {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let d = try? Data(contentsOf: url), let img = UIImage(data: d) { got(img) }
                }
                fromFiles = false
            }
            .onChange(of: photo) { it in
                guard let it else { return }
                Task { @MainActor in
                    if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) { got(img) }
                    photo = nil
                }
            }
            .confirmationDialog(sizeQuestion, isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil; target = nil } }), titleVisibility: .visible) {
                if let old = oldSize {
                    Button(loc("Підігнати під") + " \(old.0)×\(old.1)") { apply(fit: true) }
                }
                Button(loc("Лишити як є")) { apply(fit: false) }
                Button(loc("Скасувати"), role: .cancel) { pending = nil; target = nil }
            }
    }

    private var oldSize: (Int, Int)? {
        guard let t = target, let u = ProjectImages.uiImage(project, t.src) else { return nil }
        return (Int(u.size.width * u.scale), Int(u.size.height * u.scale))
    }

    private var sizeQuestion: String {
        guard let p = pending, let o = oldSize else { return "" }
        return String(format: loc("Нова картинка %d×%d, а стара — %d×%d."), Int(p.size.width * p.scale), Int(p.size.height * p.scale), o.0, o.1)
    }

    private func got(_ img: UIImage) {
        guard let o = oldSize else { apply(img, fit: false); return }
        if Int(img.size.width * img.scale) == o.0 && Int(img.size.height * img.scale) == o.1 { apply(img, fit: false) } else { pending = img }
    }

    private func apply(fit: Bool) { if let p = pending { apply(p, fit: fit) }; pending = nil }

    private func apply(_ img: UIImage, fit: Bool) {
        guard let t = target else { return }
        let rgba: RGBAImage
        if fit, let o = oldSize { rgba = ProjectImages.fit(img, o.0, o.1) }
        else { rgba = AssetFactory.fromUIImage(img, maxSide: 2000) }
        ProjectImages.replace(project, t, with: rgba)
        target = nil
    }
}

struct ImagesList: View {
    @ObservedObject var project: FaceProject
    let theme: Int
    @Binding var selected: XNode?
    @State private var target: ImageRef?
    @State private var fromFiles = false

    var body: some View {
        let list = ProjectImages.all(project)
        List {
            if list.isEmpty { Text("У проєкті ще немає картинок.").font(.footnote).foregroundStyle(.secondary) }
            ForEach(list) { im in
                HStack(spacing: 12) {
                    Thumb(image: ProjectImages.uiImage(project, im.src)).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: im.src).font(.subheadline).lineLimit(1)
                        Text(verbatim: info(im)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Menu {
                        Button { fromFiles = false; target = im } label: { Label("Замінити з Фото", systemImage: "photo") }
                        Button { fromFiles = true; target = im } label: { Label("Замінити з Файлів", systemImage: "folder") }
                        if let url = ProjectImages.exportURL(project, im.src) {
                            ShareLink(item: url) { Label("Поділитися PNG", systemImage: "square.and.arrow.up") }
                        }
                        Button { pick(im) } label: { Label("Вибрати шар", systemImage: "scope") }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.system(size: 20))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { fromFiles = false; target = im }
            }
        }
        .modifier(ImageReplacer(project: project, target: $target, fromFiles: $fromFiles))
    }

    private func info(_ im: ImageRef) -> String {
        let d = project.file(im.src)?.count ?? 0
        let u = ProjectImages.uiImage(project, im.src)
        let size = u.map { "\(Int($0.size.width * $0.scale))×\(Int($0.size.height * $0.scale)) · " } ?? ""
        return size + "\(max(1, (d + 512) / 1024)) KB · " + (im.owner.string("name") ?? im.owner.tag)
    }

    /// Шар, що показує цю картинку
    private func pick(_ im: ImageRef) {
        if let l = project.layouts(theme).last(where: { ProjectImages.of(project, project.element(of: $0)).contains(im) }) { selected = l }
    }
}

/// Мініатюра на «шаховому» тлі — видно прозорість
struct Thumb: View {
    let image: UIImage?
    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let s: CGFloat = 6
                for y in stride(from: 0, to: size.height, by: s) {
                    for x in stride(from: 0, to: size.width, by: s) {
                        let dark = (Int(x / s) + Int(y / s)) % 2 == 0
                        ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(dark ? Color(white: 0.35) : Color(white: 0.27)))
                    }
                }
            }
            if let image { Image(uiImage: image).resizable().interpolation(.high).scaledToFit().padding(2) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Блок «Зображення» в інспекторі будь-якого елемента: усі його картинки мініатюрами (дотик — замінити або поділитися),
/// «Намалювати шрифтом…» — лише для текстових елементів (числа, написи, значки за значенням)
struct ElementImages: View {
    @ObservedObject var project: FaceProject
    let res: XNode
    @State private var target: ImageRef?
    @State private var fromFiles = false
    @State private var fontArt = false

    private var canFont: Bool {
        let k = ElementKind.of(res, in: project)
        return ElementFactory.slotCount(project, res) > 0 && (k == .digits || k == .label || k == .values)
    }

    var body: some View {
        let list = ProjectImages.of(project, res)
        if !list.isEmpty || canFont {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: loc("ЗОБРАЖЕННЯ") + (list.count > 1 ? " · \(list.count)" : "")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if !list.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 50, maximum: 60), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(list) { im in
                            Menu {
                                Button { fromFiles = false; target = im } label: { Label("Замінити з Фото", systemImage: "photo") }
                                Button { fromFiles = true; target = im } label: { Label("Замінити з Файлів", systemImage: "folder") }
                                if let url = ProjectImages.exportURL(project, im.src) {
                                    ShareLink(item: url) { Label("Поділитися PNG", systemImage: "square.and.arrow.up") }
                                }
                            } label: {
                                Thumb(image: ProjectImages.uiImage(project, im.src)).frame(width: 52, height: 52)
                            }
                        }
                    }
                    Text("Торкніться картинки, щоб замінити її. Усі картинки — у «Файлах»: На iPhone → BandFace → FaceProjects.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if canFont {
                    Button { fontArt = true } label: {
                        Label("Намалювати шрифтом…", systemImage: "textformat").font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).frame(height: 36)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .modifier(ImageReplacer(project: project, target: $target, fromFiles: $fromFiles))
            .sheet(isPresented: $fontArt) { FontArtSheet(project: project, res: res) }
        }
    }
}

// MARK: - «Як це виглядає» для галереї «Додати елемент»

enum GalleryPreview {
    private static func art(_ w: Int, _ h: Int, _ a: String, _ b: String) -> RGBAImage {
        AssetFactory.render(w, h) { ctx in
            let path = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 14).cgPath
            ctx.addPath(path); ctx.clip()
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [AssetFactory.color(a).cgColor, AssetFactory.color(b).cgColor] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: w, y: h), options: [])
            }
        }
    }

    /// Тимчасовий циферблат з одним елементом у центрі
    static func image(_ kind: ElementKind, clock: Bool) -> UIImage? {
        let root = XNode("Watchface")
        root.set("id", "1").set("name", "preview")
        root.add("Resources")
        root.add("Theme").set("type", "normal").set("name", "").set("bgColor", "#000000")
        let p = FaceProject(id: "gallery", folder: FileManager.default.temporaryDirectory.appendingPathComponent("gallery-preview"), root: root, files: [:], meta: ProjectMeta())
        let c = (p.meta.device.width / 2, p.meta.device.height / 2)
        switch kind {
        case .digits: ElementFactory.addDigits(p, source: "timeHour", gen: Generator(kind: .digits, color: "#FFFFFF", fontSize: 48, weight: 700, style: "rounded"), theme: 0, center: c)
        case .label:
            var g = Generator(kind: .label, color: "#FFFFFF", fontSize: 28, weight: 600, style: "rounded"); g.text = loc("Напис")
            ElementFactory.addLabel(p, gen: g, theme: 0, center: c)
        case .values: ElementFactory.addValues(p, source: "systemStatusBattery", images: ["#FF453A", "#FFD60A", "#30D158"].map { art(56, 56, $0, $0) }, theme: 0, center: c)
        case .pointer:
            if clock { ElementFactory.addAnalogClock(p, theme: 0, center: c) }
            else { var g = Generator(kind: .pointer, color: "#FFFFFF"); g.width = 6; g.length = 80; ElementFactory.addPointer(p, source: "timeSecond", gen: g, theme: 0, center: c) }
        case .arc: var g = Generator(kind: .arc, color: "#30D158"); g.radius = 60; g.width = 10; ElementFactory.addArc(p, source: "healthStepProgress", gen: g, theme: 0, center: c)
        case .line: var g = Generator(kind: .line, color: "#0A84FF"); g.width = 8; g.length = 140; ElementFactory.addLine(p, source: "systemStatusBattery", gen: g, theme: 0, center: c)
        case .image: ElementFactory.addImage(p, art(120, 90, "#5E8BFF", "#B05EFF"), theme: 0, center: c)
        case .animation: ElementFactory.addAnimation(p, [art(90, 90, "#FF9500", "#FF375F")], interval: 100, theme: 0, center: c)
        default: return nil
        }
        return FaceRenderer(p).render(theme: 0, scale: 2).0
    }

    static func about(_ kind: ElementKind, clock: Bool) -> String {
        switch kind {
        case .digits: return loc("Кожна цифра — окрема картинка, намальована вибраним шрифтом. Після додавання можна змінити шрифт, розмір і колір.")
        case .values: return loc("Показує одну з ваших картинок залежно від значення: заряду, погоди, дня тижня.")
        case .pointer: return clock ? loc("Три стрілки й крапка в центрі одним натисканням.") : loc("Стрілка повертається за значенням.")
        case .arc: return loc("Дуга заповнюється за значенням. Кінці можна тягнути на полотні.")
        case .line: return loc("Смуга заповнюється за значенням. Можна повернути під будь-яким кутом.")
        case .label: return loc("Рядок малюється в картинку, тож працює будь-який шрифт, і ваш теж.")
        case .image: return loc("PNG або фото. Потім його можна замінити в «Шари → Зображення».")
        case .animation: return loc("Кілька картинок стають кадрами.")
        default: return ""
        }
    }
}

/// Попередній перегляд плитки (довге натискання)
struct GalleryPreviewCard: View {
    let kind: ElementKind
    let clock: Bool
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Як це виглядає").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 14) {
                if let img = GalleryPreview.image(kind, clock: clock) {
                    Image(uiImage: img).resizable().scaledToFit().frame(height: 220).clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.gray, lineWidth: 3))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: title).font(.headline)
                    Text(verbatim: GalleryPreview.about(kind, clock: clock)).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
