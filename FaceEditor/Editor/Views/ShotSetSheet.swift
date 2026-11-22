// SPDX-License-Identifier: MIT
// «Набір знімків»: які екрани потрапляють на картинку (кожен — свій стиль, колір, AOD, стани) і як вона оформлена.
// Дотик до екрана — меню (назва, стиль, колір, дублювати, прибрати); «Додати» — меню стилів і їхніх кольорів.

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ShotSetSheet: View {
    let project: FaceProject
    let initial: ShotSet
    // тексти редагуються прямо в рядках; список сам прокручує поле над клавіатуру
    var body: some View { ShotSetContent(project: project, shots: initial) }
}

private struct ShotSetContent: View {
    @ObservedObject var project: FaceProject
    @State var shots: ShotSet
    @Environment(\.dismiss) private var dismiss
    @State private var preview: UIImage?
    @State private var zoomed = false
    /// Поле в фокусі: назва екрана (id картки), рядок тексту чи час
    enum Field: Hashable { case name(UUID), title, above, below, time }
    @FocusState private var focus: Field?
    @State private var timeDraft = ""
    @State private var thumbs: [String: UIImage] = [:]
    @State private var customColor = Color.blue

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .top), count: 4)

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                screensSection
                formatSection
                screenLookSection
                backgroundSection
                textSection
                lookSection
                Section {
                    Toggle(loc("Запам'ятати для циферблата"), isOn: $shots.remember)
                } header: { Text(loc("Збереження")) } footer: {
                    Text(loc("Наступного разу набір відкриється з цими екранами й налаштуваннями."))
                }
            }
            .navigationTitle(loc("Набір знімків"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { close() } label: { Image(systemName: "xmark") }.accessibilityLabel(Text(loc("Закрити")))
                }
                ToolbarItem(placement: .confirmationAction) { doneMenu }
            }
        }
        .fullScreenCover(isPresented: $zoomed) { ShotZoomView(image: preview) }
        .task(id: shots) {
            // перегляд — трохи згодом, щоб не малювати на кожен дотик
            try? await Task.sleep(nanoseconds: 250_000_000)
            preview = ShotComposer.compose(project, shots)
        }
    }

    // MARK: Перегляд

    /// Перегляд на всю ширину екрана; дотик — на весь екран з масштабуванням
    private var previewSection: some View {
        let w = UIScreen.main.bounds.width
        return Section {
            ZStack {
                if let preview {
                    Image(uiImage: preview).resizable().scaledToFit()
                        .frame(width: w, height: min(w * preview.size.height / max(1, preview.size.width), 520))
                        .contentShape(Rectangle())
                        .onTapGesture { zoomed = true }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(Text(loc("Відкрити на весь екран")))
                } else {
                    ProgressView().frame(width: w, height: 240)
                }
            }
            // ширше за рядок списку — на всю ширину екрана (рядок не обрізає вміст)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } footer: {
            if let preview {
                Text(verbatim: "\(Int(preview.size.width * preview.scale)) × \(Int(preview.size.height * preview.scale)) · " + loc("торкніться, щоб збільшити"))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Екрани

    private var screensSection: some View {
        Section {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach($shots.screens) { $sc in card($sc) }
                addCard
            }
            .padding(.vertical, 6)
        } header: {
            Text(String(format: loc("Екрани: %d"), shots.count))
        } footer: {
            Text(loc("Торкніться екрана: назва, стиль, колір, дублювати, прибрати. Значки під ним вмикають стан на цьому екрані: Bluetooth від'єднано, заряд 15 %; обидва — два окремі екрани."))
        }
    }

    private var styles: [Int] { project.styleThemes }
    private var colors: [String] { ColorVariants.isEnabled(project) ? ColorVariants.colors(project) : [] }
    private var hasBluetooth: Bool { project.usesSource("bluetooth") }
    private var hasBattery: Bool { project.usesSource("battery") }

    private func thumb(_ sc: ShotScreen) -> UIImage? {
        let st = sc.bluetooth ? 1 : sc.battery ? 2 : 0
        let key = "\(ShotComposer.theme(project, sc))-\(sc.color)-\(st)-\(project.revision)-" + sc.widgets.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        if let t = thumbs[key] { return t }
        let r = FaceRenderer(project)
        r.colorVariant = sc.color
        r.slotChoice = sc.widgets
        r.bluetoothOff = st == 1
        r.lowBattery = st == 2
        let img = r.render(theme: ShotComposer.theme(project, sc), scale: 1).0
        DispatchQueue.main.async { thumbs[key] = img }
        return img
    }

    private func capsule(_ img: UIImage?) -> some View {
        Group {
            if let img { Image(uiImage: img).resizable() } else { Color.black }
        }
        .frame(width: 53, height: 130)
        .clipShape(Capsule())
        .padding(2.5)
        .background(Capsule().fill(Color.accentColor))
    }

    private func card(_ sc: Binding<ShotScreen>) -> some View {
        VStack(spacing: 0) {
            Menu { cardMenu(sc) } label: { capsule(thumb(sc.wrappedValue)) }
                .accessibilityLabel(Text(ShotComposer.name(project, sc.wrappedValue)))
            TextField(ShotComposer.defaultName(project, sc.wrappedValue) + (sc.wrappedValue.aod ? " · AOD" : ""), text: sc.name)
                .font(.footnote.weight(.medium)).lineLimit(1).multilineTextAlignment(.center)
                .focused($focus, equals: .name(sc.wrappedValue.id))
                .submitLabel(.done)
                .padding(.top, 8)
                // назва за замовчуванням — сірою підказкою; така сама вписана — те саме, що порожня
                .onSubmit { if sc.wrappedValue.name == ShotComposer.defaultName(project, sc.wrappedValue) { sc.wrappedValue.name = "" } }
            // під назвою — лише кружечок кольору (якщо кольори є); AOD видно в назві й по мініатюрі
            if !colors.isEmpty {
                Circle().fill(ProjectColorDots.color(colors[min(sc.wrappedValue.color, colors.count - 1)])).frame(width: 12, height: 12)
                    .padding(.top, 4)
            }
            if hasBluetooth || hasBattery {
                HStack(spacing: 6) {
                    if hasBluetooth { chip(1, on: sc.bluetooth, label: "Bluetooth від'єднано") }
                    if hasBattery { chip(2, on: sc.battery, label: "Заряд 15 %") }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func chip(_ state: Int, on: Binding<Bool>, label: String) -> some View {
        let isOn = on.wrappedValue
        return Button { on.wrappedValue.toggle() } label: {
            Image(uiImage: ShotComposer.stateIcon(state, size: 20, color: isOn ? .white : .label, low: isOn ? .white : .systemRed))
                .frame(width: 32, height: 32)
                .background(Circle().fill(on.wrappedValue ? Color.accentColor : Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(loc(label)))
        .accessibilityAddTraits(on.wrappedValue ? .isSelected : [])
    }

    @ViewBuilder private func cardMenu(_ sc: Binding<ShotScreen>) -> some View {
        Button {
            // поле назви під карткою: поточна назва вже в ньому
            if sc.wrappedValue.name.isEmpty { sc.wrappedValue.name = ShotComposer.defaultName(project, sc.wrappedValue) }
            let id = sc.wrappedValue.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focus = .name(id) }
        } label: { Label(loc("Назва екрана…"), systemImage: "pencil") }
        if !sc.wrappedValue.name.isEmpty {
            Button { sc.wrappedValue.name = "" } label: { Label(loc("Підпис стилем і кольором"), systemImage: "arrow.uturn.backward") }
        }
        Divider()
        if styles.count > 1 {
            Menu {
                Picker("", selection: sc.style) {
                    ForEach(styles.indices, id: \.self) { i in Text(verbatim: project.styleTitle(styles[i])).tag(i) }
                }
            } label: {
                Text(loc("Стиль"))
                Text(verbatim: project.styleTitle(styles[min(sc.wrappedValue.style, styles.count - 1)]))
            }
        }
        if !colors.isEmpty {
            Menu {
                Picker("", selection: sc.color) {
                    ForEach(colors.indices, id: \.self) { i in
                        Label { Text(ShotComposer.colorName(i)) } icon: { Image(uiImage: Self.dot(colors[i])) }.tag(i)
                    }
                }
            } label: {
                Text(loc("Колір"))
                Text(ShotComposer.colorName(sc.wrappedValue.color))
            }
        }
        let slots = project.slots(ShotComposer.theme(project, sc.wrappedValue))
        if !slots.isEmpty {
            Menu {
                ForEach(Array(slots.enumerated()), id: \.offset) { n, slot in
                    let name = slot.string("name") ?? ""
                    let ws = WidgetSlots.widgets(project, slot)
                    Section(String(format: loc("Слот %d"), n + 1)) {
                        Picker("", selection: Binding(get: { min(sc.wrappedValue.widgets[name] ?? WidgetSlots.shown(project, slot), max(0, ws.count - 1)) },
                                                      set: { sc.wrappedValue.widgets[name] = $0 })) {
                            ForEach(Array(ws.enumerated()), id: \.offset) { i, w in Text(verbatim: w.string("widgetName") ?? loc("Віджет")).tag(i) }
                        }
                    }
                }
            } label: {
                Label { Text(loc("Віджети")); Text(slots.count == 1 ? loc("1 слот") : String(format: loc("Слотів: %d"), slots.count)) } icon: { Image(systemName: "square.grid.2x2") }
            }
        }
        if project.aodTheme(forStyle: styles[min(sc.wrappedValue.style, styles.count - 1)]) != nil {
            Toggle(loc("Завжди на екрані (AOD)"), isOn: sc.aod)
        }
        Divider()
        Button {
            var copy = sc.wrappedValue; copy.id = UUID(); copy.name = ""
            if let i = shots.screens.firstIndex(where: { $0.id == sc.wrappedValue.id }) { shots.screens.insert(copy, at: i + 1) }
        } label: { Label(loc("Дублювати екран"), systemImage: "plus.square.on.square") }
        Button(role: .destructive) {
            shots.screens.removeAll { $0.id == sc.wrappedValue.id }
        } label: { Label(loc("Прибрати екран"), systemImage: "trash") }
    }

    private var addCard: some View {
        VStack(spacing: 0) {
            Menu {
                Section(loc("Новий екран")) {
                    ForEach(styles.indices, id: \.self) { i in addItem(style: i, aod: false) }
                }
                let aods = styles.indices.filter { project.aodTheme(forStyle: styles[$0]) != nil }
                if !aods.isEmpty {
                    Section(loc("Завжди на екрані (AOD)")) {
                        ForEach(aods, id: \.self) { i in addItem(style: i, aod: true) }
                    }
                }
            } label: {
                Image(systemName: "plus").font(.system(size: 22, weight: .semibold))
                    .frame(width: 58, height: 135)
                    .overlay(Capsule().strokeBorder(Color(.systemGray3), style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
            }
            Text(loc("Додати")).font(.footnote.weight(.medium)).foregroundStyle(Color.accentColor).padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func addItem(style i: Int, aod: Bool) -> some View {
        let title = project.styleTitle(styles[i]) + (aod ? " · AOD" : "")
        if colors.isEmpty {
            Button(title) { shots.screens.append(ShotScreen(style: i, aod: aod)) }
        } else {
            Menu(title) {
                ForEach(colors.indices, id: \.self) { c in
                    Button { shots.screens.append(ShotScreen(style: i, aod: aod, color: c)) } label: {
                        Label { Text(ShotComposer.colorName(c)) } icon: { Image(uiImage: Self.dot(colors[c])) }
                    }
                }
            }
        }
    }

    /// Кружечок кольору для меню (у меню працюють лише картинки)
    static func dot(_ hex: String) -> UIImage {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 18))
        return r.image { _ in
            AssetFactory.color(hex).setFill()
            UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 16, height: 16)).fill()
            UIColor(white: 1, alpha: 0.25).setStroke()
            UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 16, height: 16)).stroke()
        }.withRenderingMode(.alwaysOriginal)
    }

    // MARK: Оформлення

    private var formatSection: some View {
        Section {
            HStack(spacing: 10) {
                formatButton(.auto, "Авто", CGSize(width: 16, height: 22))
                formatButton(.square, "1 : 1", CGSize(width: 20, height: 20))
                formatButton(.wide, "16 : 9", CGSize(width: 24, height: 14))
            }
            .padding(.vertical, 4)
        } header: { Text(loc("Формат")) } footer: {
            Text(loc("Авто — розмір за кількістю екранів. 1:1 — для Instagram, 16:9 — для обкладинок."))
        }
    }

    private func formatButton(_ f: ShotSet.Format, _ title: String, _ icon: CGSize) -> some View {
        let on = shots.format == f
        return Button { shots.format = f } label: {
            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 3).strokeBorder(on ? Color.accentColor : Color.secondary, lineWidth: 1.8)
                    .frame(width: icon.width, height: icon.height).frame(height: 24)
                Text(verbatim: f == .auto ? loc(title) : title).font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.tertiarySystemFill)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var screenLookSection: some View {
        Section(loc("Екрани")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(loc("Рамка"))
                Picker("", selection: $shots.band) {
                    Text(loc("Капсула")).tag(false); Text(loc("Браслет")).tag(true)
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)
            HStack {
                Text(loc("Час на екранах"))
                Spacer()
                TextField("09:55", text: $timeDraft)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(focus == .time ? Color.primary : Color.secondary)
                    .focused($focus, equals: .time)
                    .submitLabel(.done)
                    .onSubmit(commitTime)
                    .frame(maxWidth: 120)
            }
            .onAppear { timeDraft = timeText }
            .onChange(of: focus) { f in if f != .time { commitTime() } }
            .swipeActions { if shots.time != nil { Button(loc("Як у циферблаті")) { shots.time = nil } } }
        }
    }

    private var timeText: String { shots.time ?? project.meta.demo.time ?? "09:55" }

    /// Час із поля: «10:08», «10.08», «10 08»; неправильний — повертається попередній
    private func commitTime() {
        let p = timeDraft.split(whereSeparator: { ":. ".contains($0) }).compactMap { Int($0) }
        if p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) {
            let t = String(format: "%02d:%02d", p[0], p[1])
            if t != timeText { shots.time = t }
        }
        timeDraft = timeText
    }

    private var backgroundSection: some View {
        Section(loc("Тло")) {
            HStack(spacing: 0) {
                ForEach(ShotSet.Background.allCases, id: \.self) { b in
                    swatch(b.rawValue, title: bgTitle(b))
                }
                VStack(spacing: 6) {
                    ColorPicker("", selection: Binding(get: { customColor }, set: { c in
                        customColor = c
                        shots.background = Self.hex(UIColor(c))
                    }), supportsOpacity: false).labelsHidden().frame(width: 30, height: 30)
                    Text(loc("Свій")).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 4)
        }
    }

    private func bgTitle(_ b: ShotSet.Background) -> String {
        switch b {
        case .dark: return "Темне"
        case .black: return "Чорне"
        case .white: return "Біле"
        case .light: return "Світле"
        case .blue: return "Синє"
        case .face: return "З циферблата"
        }
    }

    private func swatch(_ key: String, title: String) -> some View {
        let cs = ShotComposer.background(project, key).map { Color($0) }
        let on = shots.background == key
        return Button { shots.background = key } label: {
            VStack(spacing: 6) {
                Circle().fill(LinearGradient(colors: cs.count > 1 ? cs : [cs[0], cs[0]], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                    .frame(width: 30, height: 30)
                    .padding(2.5)
                    .overlay(Circle().strokeBorder(on ? Color.accentColor : .clear, lineWidth: 2))
                Text(loc(title)).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    static func hex(_ c: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(max(0, min(1, r)) * 255), Int(max(0, min(1, g)) * 255), Int(max(0, min(1, b)) * 255))
    }

    private var textSection: some View {
        Section {
            textRow("Назва", $shots.title, auto: ShotComposer.autoTitle(project), field: .title)
            textRow("Над назвою", $shots.above, auto: ShotComposer.autoAbove(project), field: .above)
            textRow("Під назвою", $shots.below, auto: ShotComposer.autoBelow(project), field: .below)
        } header: { Text(loc("Текст")) } footer: {
            Text(loc("Порожнє поле — без рядка. Змахніть уліво, щоб повернути автоматичний текст."))
        }
    }

    /// Рядок тексту: редагується прямо в рядку (список сам прокручує його над клавіатуру).
    /// Такий самий, як автоматичний, — автоматичний; порожній — без рядка
    private func textRow(_ title: String, _ value: Binding<String?>, auto: String, field: Field) -> some View {
        HStack {
            Text(loc(title))
            Spacer(minLength: 15)
            TextField(loc("Без рядка"), text: Binding(get: { value.wrappedValue ?? auto },
                                                      set: { value.wrappedValue = $0 == auto ? nil : $0 }))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(focus == field ? Color.primary : Color.secondary)
                .focused($focus, equals: field)
                .submitLabel(.done)
            if focus == field, !(value.wrappedValue ?? auto).isEmpty {
                Button { value.wrappedValue = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(loc("Очистити")))
            }
        }
        .swipeActions {
            if value.wrappedValue != "" { Button(loc("Прибрати")) { value.wrappedValue = "" }.tint(.red) }
            if value.wrappedValue != nil { Button(loc("Авто")) { value.wrappedValue = nil } }
        }
    }

    private var lookSection: some View {
        Section(loc("Вигляд")) {
            Toggle(loc("Закруглені кути"), isOn: $shots.rounded).disabled(shots.band)
            Toggle(loc("Підписи під екранами"), isOn: $shots.captions)
            Toggle(loc("Тінь під екранами"), isOn: $shots.shadow)
            Toggle(loc("«Зроблено в BandFace»"), isOn: $shots.credit)
        }
    }

    // MARK: Готово

    private var doneMenu: some View {
        Menu {
            Section(preview.map { String(format: loc("Готова картинка · %d × %d"), Int($0.size.width * $0.scale), Int($0.size.height * $0.scale)) } ?? loc("Готова картинка")) {
                Button { finish { ShotShare.present(ShotShare(image: $0, title: title)) } } label: { Label(loc("Поділитися…"), systemImage: "square.and.arrow.up") }
                Button { finish { UIImageWriteToSavedPhotosAlbum($0, nil, nil, nil) } } label: { Label(loc("Зберегти у Фото"), systemImage: "photo") }
                Button { finish { saveToFiles($0) } } label: { Label(loc("Зберегти у Файли"), systemImage: "folder") }
            }
        } label: {
            Image(systemName: "checkmark")
        }
        .disabled(shots.screens.isEmpty)
        .accessibilityLabel(Text(loc("Готово")))
    }

    private var title: String { (shots.title ?? ShotComposer.autoTitle(project)).isEmpty ? loc("Набір знімків") : (shots.title ?? ShotComposer.autoTitle(project)) }

    /// Картинка PNG (без EXIF, як і звичайний знімок) — у дію; набір запам'ятовується й вікно закривається
    private func finish(_ action: @escaping (UIImage) -> Void) {
        guard let img = ShotComposer.compose(project, shots), let png = ShotShare.png(img), let pic = UIImage(data: png) else { return }
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { action(pic) }
    }

    private func saveToFiles(_ img: UIImage) {
        guard let png = ShotShare.png(img) else { return }
        let name = title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name + ".png")
        guard (try? png.write(to: url, options: .atomic)) != nil else { return }
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        guard let root = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        top.present(picker, animated: true)
    }

    private func close() {
        project.meta.shots = shots.remember ? shots : nil
        project.save()
        dismiss()
    }
}

/// Готова картинка на весь екран: масштаб пальцями, подвійний дотик — увесь / удвічі
private struct ShotZoomView: View {
    let image: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image {
                // після змахування вже все сховано — закрити без анімації аркуша
                ZoomableImage(image: image, onClose: {
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { dismiss() }
                }).ignoresSafeArea()
            } else { Color.black.ignoresSafeArea() }
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .padding(16)
            .accessibilityLabel(Text(loc("Закрити")))
        }
        .statusBarHidden()
        .background(ClearCoverBackground())
    }
}

/// Прозоре тло повноекранного аркуша: під час змахування видно набір, як у «Фото»
private struct ClearCoverBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        DispatchQueue.main.async {
            var p = v.superview
            while let x = p, !(x is UIWindow) { x.backgroundColor = .clear; p = x.superview }
        }
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct ZoomableImage: UIViewRepresentable {
    let image: UIImage
    /// Змахнули вгору чи вниз (коли картинка не збільшена) — закрити
    var onClose: () -> Void = {}

    func makeUIView(context: Context) -> UIScrollView {
        let s = UIScrollView()
        s.backgroundColor = .black
        s.delegate = context.coordinator
        s.showsHorizontalScrollIndicator = false
        s.showsVerticalScrollIndicator = false
        s.contentInsetAdjustmentBehavior = .never
        let iv = UIImageView(image: image)
        iv.contentMode = .scaleAspectFit
        s.addSubview(iv)
        context.coordinator.imageView = iv
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        s.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = context.coordinator
        s.addGestureRecognizer(pan)
        context.coordinator.onClose = onClose
        return s
    }

    func updateUIView(_ s: UIScrollView, context: Context) {
        DispatchQueue.main.async { context.coordinator.fit(s) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        weak var imageView: UIImageView?
        var onClose: () -> Void = {}
        private var fitted = CGSize.zero

        /// Уся картинка в екрані; більше — пальцями (до 100 % пікселів × 2)
        func fit(_ s: UIScrollView) {
            guard let iv = imageView, let img = iv.image, s.bounds.width > 0, s.bounds.size != fitted else { return }
            fitted = s.bounds.size
            let px = CGSize(width: img.size.width * img.scale / UIScreen.main.scale, height: img.size.height * img.scale / UIScreen.main.scale)
            iv.frame = CGRect(origin: .zero, size: px)
            s.contentSize = px
            let minZ = min(s.bounds.width / px.width, s.bounds.height / px.height)
            s.minimumZoomScale = minZ
            s.maximumZoomScale = max(minZ * 4, 2)
            s.zoomScale = minZ
            center(s)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ s: UIScrollView) { center(s) }

        private func center(_ s: UIScrollView) {
            guard let iv = imageView else { return }
            let dx = max(0, (s.bounds.width - iv.frame.width) / 2), dy = max(0, (s.bounds.height - iv.frame.height) / 2)
            s.contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
        }

        /// Змахування вгору/вниз — лише коли картинка не збільшена (інакше це прокрутка)
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer, let s = pan.view as? UIScrollView else { return true }
            let v = pan.velocity(in: s)
            return s.zoomScale <= s.minimumZoomScale * 1.01 && abs(v.y) > abs(v.x)
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let s = g.view as? UIScrollView, let iv = imageView else { return }
            let ty = g.translation(in: s).y
            switch g.state {
            case .changed:
                iv.transform = CGAffineTransform(translationX: 0, y: ty)
                s.backgroundColor = UIColor.black.withAlphaComponent(max(0.3, 1 - abs(ty) / 400))
            case .ended, .cancelled:
                let v = g.velocity(in: s).y
                if abs(ty) > 120 || abs(v) > 900 {
                    UIView.animate(withDuration: 0.2, animations: {
                        iv.transform = CGAffineTransform(translationX: 0, y: ty > 0 || v > 0 ? s.bounds.height : -s.bounds.height)
                        s.backgroundColor = .clear
                    }, completion: { _ in self.onClose() })
                } else {
                    UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
                        iv.transform = .identity
                        s.backgroundColor = .black
                    }
                }
            default: break
            }
        }

        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let s = g.view as? UIScrollView else { return }
            if s.zoomScale > s.minimumZoomScale * 1.01 { s.setZoomScale(s.minimumZoomScale, animated: true); return }
            let p = g.location(in: imageView)
            let z = min(s.maximumZoomScale, s.minimumZoomScale * 2.5)
            let size = CGSize(width: s.bounds.width / z, height: s.bounds.height / z)
            s.zoom(to: CGRect(x: p.x - size.width / 2, y: p.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}
