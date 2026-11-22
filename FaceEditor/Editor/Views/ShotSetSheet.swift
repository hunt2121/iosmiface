// SPDX-License-Identifier: MIT
// «Набір знімків»: які екрани потрапляють на картинку (кожен — свій стиль, колір, AOD, стани) і як вона оформлена.
// Дотик до екрана — меню (назва, стиль, колір, дублювати, прибрати); «Додати» — меню стилів і їхніх кольорів.

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ShotSetSheet: View {
    let project: FaceProject
    let initial: ShotSet
    // поле над клавіатурою — для назв екранів, текстів і часу
    var body: some View { ShotSetContent(project: project, set: initial).inputBarHost() }
}

private struct ShotSetContent: View {
    @ObservedObject var project: FaceProject
    @State var set: ShotSet
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inputBar) private var bar
    @State private var preview: UIImage?
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
                    Toggle(loc("Запам'ятати для циферблата"), isOn: $set.remember)
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
        .task(id: set) {
            // перегляд — трохи згодом, щоб не малювати на кожен дотик
            try? await Task.sleep(nanoseconds: 250_000_000)
            preview = ShotComposer.compose(project, set)
        }
    }

    // MARK: Перегляд

    private var previewSection: some View {
        Section {
            ZStack {
                if let preview {
                    Image(uiImage: preview).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity).frame(height: 220)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } footer: {
            if let preview {
                Text(verbatim: "\(Int(preview.size.width * preview.scale)) × \(Int(preview.size.height * preview.scale))")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Екрани

    private var screensSection: some View {
        Section {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach($set.screens) { $sc in card($sc) }
                addCard
            }
            .padding(.vertical, 6)
        } header: {
            HStack {
                Text(loc("Екрани"))
                Spacer()
                Text(String(format: loc("на картинці: %d"), set.count)).textCase(nil)
            }
        } footer: {
            Text(loc("Торкніться екрана: назва, стиль, колір, дублювати, прибрати. Значки під ним додають екран зі станом: Bluetooth від'єднано, заряд 15 %."))
        }
    }

    private var styles: [Int] { project.styleThemes }
    private var colors: [String] { ColorVariants.isEnabled(project) ? ColorVariants.colors(project) : [] }
    private var hasBluetooth: Bool { project.usesSource("bluetooth") }
    private var hasBattery: Bool { project.usesSource("battery") }

    private func thumb(_ sc: ShotScreen) -> UIImage? {
        let key = "\(ShotComposer.theme(project, sc))-\(sc.color)-\(project.revision)-" + sc.widgets.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        if let t = thumbs[key] { return t }
        let r = FaceRenderer(project)
        r.colorVariant = sc.color
        r.slotChoice = sc.widgets
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
            Text(verbatim: ShotComposer.name(project, sc.wrappedValue))
                .font(.footnote.weight(.medium)).lineLimit(1).padding(.top, 8)
            HStack(spacing: 5) {
                if !colors.isEmpty { Circle().fill(ProjectColorDots.color(colors[min(sc.wrappedValue.color, colors.count - 1)])).frame(width: 12, height: 12) }
                if sc.wrappedValue.aod {
                    Text(verbatim: "AOD").font(.system(size: 9, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(.systemGray4)))
                }
            }
            .frame(height: 14).padding(.top, 4)
            if hasBluetooth || hasBattery {
                HStack(spacing: 6) {
                    if hasBluetooth { chip("bluetooth.slash", on: sc.bluetooth, label: "Bluetooth від'єднано") }
                    if hasBattery { chip("battery.25percent", on: sc.battery, label: "Заряд 15 %") }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func chip(_ icon: String, on: Binding<Bool>, label: String) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(on.wrappedValue ? Color.white : Color.secondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(on.wrappedValue ? Color.accentColor : Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(loc(label)))
        .accessibilityAddTraits(on.wrappedValue ? .isSelected : [])
    }

    @ViewBuilder private func cardMenu(_ sc: Binding<ShotScreen>) -> some View {
        Button {
            bar?.begin(loc("Назва екрана"), sc.wrappedValue.name.isEmpty ? ShotComposer.defaultName(project, sc.wrappedValue) : sc.wrappedValue.name) { sc.wrappedValue.name = $0 }
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
            if let i = set.screens.firstIndex(where: { $0.id == sc.wrappedValue.id }) { set.screens.insert(copy, at: i + 1) }
        } label: { Label(loc("Дублювати екран"), systemImage: "plus.square.on.square") }
        Button(role: .destructive) {
            set.screens.removeAll { $0.id == sc.wrappedValue.id }
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
            Button(title) { set.screens.append(ShotScreen(style: i, aod: aod)) }
        } else {
            Menu(title) {
                ForEach(colors.indices, id: \.self) { c in
                    Button { set.screens.append(ShotScreen(style: i, aod: aod, color: c)) } label: {
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
                formatButton(.story, "9 : 16", CGSize(width: 13, height: 22))
                formatButton(.wide, "16 : 9", CGSize(width: 24, height: 14))
            }
            .padding(.vertical, 4)
        } header: { Text(loc("Формат")) } footer: {
            Text(loc("Авто — розмір за кількістю екранів. Інші — під Instagram, Stories, обкладинки."))
        }
    }

    private func formatButton(_ f: ShotSet.Format, _ title: String, _ icon: CGSize) -> some View {
        let on = set.format == f
        return Button { set.format = f } label: {
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
                Text(loc("Розмір"))
                Picker("", selection: $set.size) {
                    Text(loc("Великі")).tag(0); Text(loc("Середні")).tag(1); Text(loc("Малі")).tag(2)
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 10) {
                Text(loc("Рамка"))
                Picker("", selection: $set.band) {
                    Text(loc("Капсула")).tag(false); Text(loc("Браслет")).tag(true)
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)
            HStack {
                Text(loc("Час на екранах"))
                Spacer()
                Button {
                    bar?.begin(loc("Час на екранах"), timeText, numeric: true) { t in
                        let p = t.split(whereSeparator: { ":. ".contains($0) }).compactMap { Int($0) }
                        if p.count == 2, (0..<24).contains(p[0]), (0..<60).contains(p[1]) { set.time = String(format: "%02d:%02d", p[0], p[1]) }
                    }
                } label: { Text(verbatim: timeText).foregroundStyle(.secondary) }
                .buttonStyle(.plain)
            }
            .swipeActions { if set.time != nil { Button(loc("Як у циферблаті")) { set.time = nil } } }
        }
    }

    private var timeText: String { set.time ?? project.meta.demo.time ?? "09:55" }

    private var backgroundSection: some View {
        Section(loc("Тло")) {
            HStack(spacing: 0) {
                ForEach(ShotSet.Background.allCases, id: \.self) { b in
                    swatch(b.rawValue, title: bgTitle(b))
                }
                VStack(spacing: 6) {
                    ColorPicker("", selection: Binding(get: { customColor }, set: { c in
                        customColor = c
                        set.background = Self.hex(UIColor(c))
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
        let on = set.background == key
        return Button { set.background = key } label: {
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
            textRow("Назва", $set.title, auto: ShotComposer.autoTitle(project))
            textRow("Над назвою", $set.above, auto: ShotComposer.autoAbove(project))
            textRow("Під назвою", $set.below, auto: ShotComposer.autoBelow(project))
        } header: { Text(loc("Текст")) } footer: {
            Text(loc("Змахніть рядок уліво, щоб прибрати його або повернути автоматичний текст."))
        }
    }

    private func textRow(_ title: String, _ value: Binding<String?>, auto: String) -> some View {
        let v = value.wrappedValue ?? auto
        return HStack {
            Text(loc(title))
            Spacer(minLength: 15)
            Text(verbatim: v.isEmpty ? "—" : v).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
        }
        .contentShape(Rectangle())
        .onTapGesture { bar?.begin(loc(title), v) { value.wrappedValue = $0 } }
        .swipeActions {
            if value.wrappedValue != "" { Button(loc("Прибрати")) { value.wrappedValue = "" }.tint(.red) }
            if value.wrappedValue != nil { Button(loc("Авто")) { value.wrappedValue = nil } }
        }
    }

    private var lookSection: some View {
        Section(loc("Вигляд")) {
            Toggle(loc("Закруглені кути"), isOn: $set.rounded).disabled(set.band)
            Toggle(loc("Підписи під екранами"), isOn: $set.captions)
            Toggle(loc("Тінь під екранами"), isOn: $set.shadow)
            Toggle(loc("«Зроблено в BandFace»"), isOn: $set.credit)
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
        .disabled(set.screens.isEmpty)
        .accessibilityLabel(Text(loc("Готово")))
    }

    private var title: String { (set.title ?? ShotComposer.autoTitle(project)).isEmpty ? loc("Набір знімків") : (set.title ?? ShotComposer.autoTitle(project)) }

    /// Картинка PNG (без EXIF, як і звичайний знімок) — у дію; набір запам'ятовується й вікно закривається
    private func finish(_ action: @escaping (UIImage) -> Void) {
        guard let img = ShotComposer.compose(project, set), let png = ShotShare.png(img), let pic = UIImage(data: png) else { return }
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
        project.meta.shots = set.remember ? set : nil
        project.save()
        dismiss()
    }
}
