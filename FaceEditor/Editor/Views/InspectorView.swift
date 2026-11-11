// SPDX-License-Identifier: MIT
// Властивості вибраного шару: вкладки «Вигляд», «Колір», «Позиція».

import SwiftUI
import PhotosUI
import FaceCompiler

struct InspectorView: View {
    @ObservedObject var project: FaceProject
    let theme: Int
    let layout: XNode
    @Binding var tab: InspectorTab
    @Binding var snap: Bool
    @Binding var grid: Int
    var onSource: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    /// Сам елемент (для обгортки «дія при натисканні» — те, що всередині)
    private var res: XNode? { project.element(of: layout) }
    private var kind: ElementKind { ElementKind.of(res, in: project) }
    private var resName: String { res?.string("name") ?? "" }
    private var gen: Generator? { project.meta.generators[resName] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title).font(.title3.weight(.bold))
                    if let s = res?.string("source") { Text(SampleData.title(s)).font(.footnote).foregroundStyle(.secondary) }
                }
                Spacer()
                circle("plus.square.on.square", "Дублювати", .secondary, onDuplicate)
                circle("trash", "Видалити", .red, onDelete)
            }
            Picker("", selection: $tab) {
                ForEach(InspectorTab.allCases) { t in Text(loc(t.rawValue)).tag(t) }
            }
            .pickerStyle(.segmented)
            switch tab {
            case .look: look
            case .color: colors
            case .position: PositionPane(project: project, theme: theme, layout: layout, snap: $snap, grid: $grid)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func circle(_ icon: String, _ label: String, _ tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 36, height: 36).background(Circle().fill(Color.editorTile))
        }
        .accessibilityLabel(Text(loc(label)))
    }

    /// x числа — точка прив'язки (лівий край / середина / правий край), тож при зміні вирівнювання
    /// переносимо її так, щоб число лишилося на місці.
    private func setNumberAlign(_ r: XNode, _ v: String) {
        let b = FaceRenderer(project).boxes(theme: theme).first { $0.layout === layout }?.rect
        project.edit { _ in
            r.set("align", v)
            guard let b else { return }
            let x = v == "center" ? b.midX : v == "right" ? b.maxX : b.minX
            layout.set("x", int: Int(x.rounded()))
        }
    }

    private func edit(_ f: @escaping (XNode) -> Void) {
        guard let r = res else { return }
        project.edit { _ in f(r) }
    }

    private func regen(_ change: (inout Generator) -> Void) {
        guard var g = gen else { return }
        change(&g)
        let name = resName
        let gg = g
        project.edit { ElementFactory.regenerate($0, element: name, gen: gg) }
    }

    // MARK: Вигляд

    @ViewBuilder private var look: some View {
        if let r = res {
            if r.has("source") {
                SourceButton(source: r.string("source") ?? "", action: onSource)
                DemoSection(project: project, source: r.string("source") ?? "")
            }
            switch kind {
            case .digits: digitsLook(r)
            case .label: labelLook()
            case .text:
                Text("Текст, який малює сам браслет, редактор не підтримує: на Smart Band 10 він не перевірений і може зламати прошивку. Видаліть його й додайте «Напис» — рядок картинкою.")
                    .font(.footnote).foregroundStyle(.secondary)
            case .pointer, .arc, .line: gaugeLook(r)
            case .animation:
                CommitSlider(title: "Інтервал кадрів, мс", value: Double(r.int("interval")), range: 30...2000, step: 10) { v in edit { $0.set("interval", int: Int(v)) } }
                StepperRow(title: "Повтори (0 — без кінця)", value: Int(r.int("repeatCount")), range: 0...50) { v in edit { $0.set("repeatCount", int: v) } }
            case .values:
                ValuesLook(project: project, res: r)
            case .image:
                EmptyView()
            case .widget where WidgetSlots.isUserWidget(project, r):
                WidgetPane(project: project, theme: theme, widget: r, origin: CGPoint(x: CGFloat(layout.int("x")), y: CGFloat(layout.int("y"))), ownLayout: layout)
            case .slot:
                SlotPane(project: project, theme: theme, slot: r, layout: layout)
            default:
                Text("Цей елемент можна пересувати, дублювати й видаляти. Його вміст редактор поки не змінює.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if kind != .slot && !WidgetSlots.isUserWidget(project, r) {
                ElementImages(project: project, res: r, layout: layout)
                if r.tag.hasPrefix("DataItem") { renderRuleRow(r) }
                tapRow
            }
        }
    }

    /// Коли ховати елемент (правило браслета)
    @ViewBuilder private func renderRuleRow(_ r: XNode) -> some View {
        Chips(title: "Показувати", hint: nil,
              items: [("alwaysShow", "Завжди"), ("hideWhenOutRange", "Є дані"), ("hideWhenUnitMismatch", "Та сама одиниця")],
              selected: r.string("renderRule") ?? "alwaysShow") { v in edit { $0.set("renderRule", v) } }
    }

    /// Натискання на елемент на браслеті відкриває застосунок
    private var tapRow: some View {
        let current = ElementFactory.tapApp(project, layout: layout)
        let apps = FaceCatalog.jumpApps.filter { ElementFactory.appTitles[$0] != nil }
        return HStack {
            Text("Натискання відкриває").font(.subheadline)
            Spacer()
            Menu {
                Button { setTap(nil) } label: { if current == nil { Label(loc("Нічого"), systemImage: "checkmark") } else { Text(loc("Нічого")) } }
                ForEach(apps.sorted { loc(ElementFactory.appTitles[$0] ?? $0) < loc(ElementFactory.appTitles[$1] ?? $1) }, id: \.self) { a in
                    Button { setTap(a) } label: {
                        if a == current { Label(loc(ElementFactory.appTitles[a] ?? a), systemImage: "checkmark") }
                        else { Text(loc(ElementFactory.appTitles[a] ?? a)) }
                    }
                }
            } label: {
                Text(current.map { loc(ElementFactory.appTitles[$0] ?? $0) } ?? loc("Нічого"))
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.editorTile))
    }

    private func setTap(_ app: String?) {
        let l = layout, t = theme
        project.edit { ElementFactory.setTapApp($0, layout: l, theme: t, app: app) }
    }

    @ViewBuilder private func digitsLook(_ r: XNode) -> some View {
        if let g = gen {
            // шрифт, розмір і ефекти — в «Намалювати шрифтом» (блок «Зображення»); тут — швидкий колір
            Text(String(format: loc("Шрифт: %@, %d px. Змінити — «Намалювати шрифтом…» нижче."), g.font.isEmpty ? loc(styleTitle(g.style)) : g.font, Int(g.fontSize)))
                .font(.caption).foregroundStyle(.secondary)
            ColorRow(title: "Колір", hex: g.color) { h in regen { $0.color = h } }
        } else {
            Text("Цифри — це картинки 0–9. Замінюйте їх по одній у блоці «Зображення» нижче.").font(.caption).foregroundStyle(.secondary)
        }
        // «Число росте»: діє лише коли кількість цифр змінюється (без нулів попереду)
        let fixedWidth = r.bool("leadingZero") && r.int("totalDigits") > 0
        GrowChips(selected: r.string("align") ?? "left", enabled: !fixedWidth, digits: Int(r.int("totalDigits"))) { v in setNumberAlign(r, v) }
        if gen != nil { UnitField(unit: gen?.unit ?? "") { u in regen { $0.unit = u } } }
        StepperRow(title: "Кількість цифр", value: max(1, Int(r.int("totalDigits"))), range: 1...9) { v in edit { $0.set("totalDigits", int: v) } }
        StepperRow(title: "Відступ між цифрами", value: Int(r.int("space")), range: -20...40) { v in edit { $0.set("space", int: v) } }
        Toggle("Нулі попереду", isOn: Binding(get: { r.bool("leadingZero") }, set: { v in edit { $0.set("leadingZero", bool: v) } }))
            .font(.subheadline)
    }

    private func styleTitle(_ s: String) -> String {
        switch s { case "default": return "Прямий"; case "condensed": return "Вузький"; case "mono": return "Моно"; default: return "Округлий" }
    }

    /// Напис: рядок, шрифт, розмір, товщина (колір — на вкладці «Колір»)
    @ViewBuilder private func labelLook() -> some View {
        if let g = gen {
            LabelField(text: g.text) { t in regen { $0.text = t } }
            ColorRow(title: "Колір", hex: g.color) { h in regen { $0.color = h } }
        }
    }

    @ViewBuilder private func gaugeLook(_ r: XNode) -> some View {
        if kind == .arc, let g0 = gen { arcLook(r, ElementFactory.synced(r, g0)) }
        else if kind == .line, let g0 = gen { lineLook(r, ElementFactory.synced(r, g0)) }
        else {
            if kind == .arc || kind == .pointer {
                CommitSlider(title: "Кут початку", value: Double(r.int("angleStart")), range: -360...360, step: 1) { v in edit { $0.set("angleStart", int: Int(v)) } }
            }
            if kind == .arc {
                CommitSlider(title: "Довжина дуги, °", value: Double(r.int("angleRange")), range: -360...360, step: 1) { v in edit { $0.set("angleRange", int: Int(v)) } }
            }
            if kind == .pointer {
                CommitSlider(title: "Поворот за діапазон, °", value: Double(r.int("angleRange")), range: -1440...1440, step: 5) { v in edit { $0.set("angleRange", int: Int(v)) } }
                HStack(spacing: 8) {
                    NumberField(title: "Вісь X", value: Int(r.int("pivotX"))) { v in edit { $0.set("pivotX", int: v) } }
                    NumberField(title: "Вісь Y", value: Int(r.int("pivotY"))) { v in edit { $0.set("pivotY", int: v) } }
                }
                Text("Вісь — точка картинки стрілки, навколо якої вона обертається.").font(.caption).foregroundStyle(.secondary)
                HandImageRow(project: project, res: r)
            }
            if kind == .arc || kind == .line { endsChips(r.string("endingStyle") != "normal") { v in edit { $0.set("endingStyle", v ? "round" : "normal") } } }
            maxValueRow(r)
            if let g = gen, kind == .pointer {
                CommitSlider(title: "Довжина", value: g.length, range: 10...400, step: 1) { v in regen { $0.length = v } }
                CommitSlider(title: "Товщина", value: g.width, range: 2...60, step: 1) { v in regen { $0.width = v } }
            }
        }
    }

    @ViewBuilder private func maxValueRow(_ r: XNode) -> some View {
        if !r.has("valueRangeSource") {
            StepperRow(title: "Найбільше значення", value: Int(r.int("valueRange")), range: 1...100000) { v in edit { $0.set("valueRange", int: v) } }
        }
    }

    private func endsChips(_ round: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Chips(title: "Кінці", hint: nil, items: [("round", "Круглі"), ("normal", "Прямі")], selected: round ? "round" : "normal") { v in set(v == "round") }
    }

    /// Регенерація з уже синхронізованих параметрів (кути беруться з маніфесту)
    private func regen(from base: Generator, _ change: (inout Generator) -> Void) {
        var g = base
        change(&g)
        let name = resName, gg = g
        project.edit { ElementFactory.regenerate($0, element: name, gen: gg) }
    }

    private static func norm(_ a: Double) -> Double { let m = a.truncatingRemainder(dividingBy: 360); return m < 0 ? m + 360 : m }

    @ViewBuilder private func arcLook(_ r: XNode, _ g: Generator) -> some View {
        // Довжина — повзунком; розріз лишається на місці (дуга розтягується симетрично).
        // Середина дуги = start + range/2, розріз — навпроти неї.
        let sign: Double = g.range < 0 ? -1 : 1
        let mid = Self.norm(g.start + g.range / 2)
        CommitSlider(title: "Довжина дуги, °", value: abs(g.range), range: 10...360, step: 1) { v0 in
            let v = v0
            regen(from: g) { $0.range = sign * v; $0.start = Self.norm(mid - sign * v / 2) }
        }
        Text("Розріз лишається на місці (спочатку — угорі).").font(.caption).foregroundStyle(.secondary)
        let gap = abs(abs(g.range) - 360) < 0.5 ? Self.norm(g.start) : Self.norm(mid + 180)
        DirectionPad(title: "Розріз дуги", selected: gap) { d in
            regen(from: g) { x in
                let len = abs(x.range)
                x.start = len >= 359.5 ? d : Self.norm(d + 180 - sign * len / 2)
            }
        }
        HStack(spacing: 8) {
            NumberField(title: "Початок, °", value: Int(Self.norm(g.start).rounded())) { v in regen(from: g) { $0.start = Self.norm(Double(v)) } }
            Button("−15°") { regen(from: g) { $0.start = Self.norm($0.start - 15) } }.buttonStyle(.bordered)
            Button("+15°") { regen(from: g) { $0.start = Self.norm($0.start + 15) } }.buttonStyle(.bordered)
        }
        Chips(title: "Напрямок заповнення", hint: nil, items: [("cw", "За годинниковою"), ("ccw", "Проти")], selected: g.range < 0 ? "ccw" : "cw") { v in
            // зміна напрямку не зсуває дугу: та сама середина, інший бік заповнення
            regen(from: g) { x in
                let len = abs(x.range), s2: Double = v == "ccw" ? -1 : 1
                x.range = s2 * len; x.start = Self.norm(mid - s2 * len / 2)
            }
        }
        Text("Кінці дуги можна тягнути на полотні. Кут прилипає до 45°, 90°, 180°…, довжина — до 90/180/270/360°. Притримайте палець перед рухом — без прив'язки.")
            .font(.caption).foregroundStyle(.secondary)
        CommitSlider(title: "Радіус", value: g.radius, range: 10...300, step: 1) { v in regen(from: g) { $0.radius = v } }
        CommitSlider(title: "Товщина", value: g.width, range: 2...60, step: 1) { v in regen(from: g) { $0.width = v } }
        endsChips(g.round) { v in regen(from: g) { $0.round = v } }
        Toggle("Крапка на кінці заповнення", isOn: Binding(get: { r.has("indicatorImage") }, set: { v in
            project.edit { p in ElementFactory.setIndicator(p, element: r, on: v, size: g.width) }
        }))
        .font(.subheadline)
        maxValueRow(r)
    }

    private static let lineDirs: [(String, Double)] = [("→", 0), ("←", 180), ("↑", -90), ("↓", 90)]

    @ViewBuilder private func lineLook(_ r: XNode, _ g: Generator) -> some View {
        let ang = (g.angle * 10).rounded() / 10
        let dir = Self.lineDirs.first { abs(Self.norm($0.1) - Self.norm(ang)) < 0.05 }?.0 ?? "custom"
        Chips(title: "Напрямок", hint: nil, items: Self.lineDirs.map { ($0.0, $0.0) } + [("custom", "Свій кут")], selected: dir) { v in
            if v == "custom" { regen(from: g) { $0.angle = Self.norm(ang).truncatingRemainder(dividingBy: 90) < 0.05 ? 45 : ang }; return }
            if let d = Self.lineDirs.first(where: { $0.0 == v }) { regen(from: g) { $0.angle = d.1 } }
        }
        if dir == "custom" {
            CommitSlider(title: "Кут, °", value: ang > 180 ? ang - 360 : ang, range: -180...180, step: 1) { v in regen(from: g) { $0.angle = v } }
        }
        CommitSlider(title: "Довжина", value: g.length, range: 4...600, step: 1) { v in regen(from: g) { $0.length = v } }
        CommitSlider(title: "Товщина", value: g.width, range: 2...60, step: 1) { v in regen(from: g) { $0.width = v } }
        endsChips(g.round) { v in regen(from: g) { $0.round = v } }
        if Self.norm(ang).truncatingRemainder(dividingBy: 180) > 0.05 {
            Label("Похилі й вертикальні лінії ще не перевірені на Smart Band 10: на браслеті заповнення може йти інакше, ніж на полотні.", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
        let x1 = Int(layout.int("x") + r.int("startX")), y1 = Int(layout.int("y") + r.int("startY"))
        let x2 = Int(layout.int("x") + r.int("endX")), y2 = Int(layout.int("y") + r.int("endY"))
        Text("Кінці лінії").font(.subheadline)
        HStack(spacing: 6) {
            NumberField(title: "X1", value: x1) { v in place(r, g, v, y1, x2, y2) }
            NumberField(title: "Y1", value: y1) { v in place(r, g, x1, v, x2, y2) }
            NumberField(title: "X2", value: x2) { v in place(r, g, x1, y1, v, y2) }
            NumberField(title: "Y2", value: y2) { v in place(r, g, x1, y1, x2, v) }
        }
        Text("Кінці лінії можна тягнути на полотні. Кут прилипає до 0°, 45°, 90°…; притримайте палець перед рухом — без прив'язки.")
            .font(.caption).foregroundStyle(.secondary)
        maxValueRow(r)
    }

    private func place(_ r: XNode, _ g: Generator, _ x1: Int, _ y1: Int, _ x2: Int, _ y2: Int) {
        let l = layout
        project.edit { p in ElementFactory.placeLine(p, res: r, layout: l, gen: g, from: CGPoint(x: x1, y: y1), to: CGPoint(x: x2, y: y2)) }
    }

    // MARK: Колір

    @ViewBuilder private var colors: some View {
        if let r = res { variantRow(r) }
        if let g = gen, g.kind != .image, g.kind != .frames {
            ColorRow(title: "Колір", hex: g.color) { h in regen { $0.color = h } }
            if g.kind == .arc || g.kind == .line {
                ColorRow(title: "Колір фону шкали", hex: g.bgColor) { h in regen { $0.bgColor = h } }
            }
        } else {
            Text("Колір цього елемента задається його картинками.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// Чи змінюється елемент разом із кольором циферблата (лише там, де це можливо)
    @ViewBuilder private func variantRow(_ r: XNode) -> some View {
        let avail = ColorVariants.availability(project, element: r)
        let on = ColorVariants.isOn(project, element: r) || project.meta.colorFollow.contains(r.string("name") ?? "")
        // галочка — у кожного елемента; де неможливо, видно чому
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Змінюється з кольором циферблата", isOn: Binding(get: { on }, set: { v in
                project.edit { ColorVariants.set($0, element: r, on: v) }
            }))
            .font(.subheadline)
            // недоступний елемент можна лише вимкнути (якщо варіанти вже були в готовому циферблаті)
            .disabled(!avail.isAvailable && !on)
            if case .unavailable(let why) = avail {
                Text(why).font(.footnote).foregroundStyle(.secondary)
            } else if !ColorVariants.isEnabled(project) {
                Text("Варіанти намалюються, щойно ви додасте кольори на панелі «Циферблат» — торкніться порожнього місця на полотні.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if on {
                Text("У кожному кольорі циферблата цей елемент буде відповідного кольору.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Позиція

struct PositionPane: View {
    @ObservedObject var project: FaceProject
    let theme: Int
    let layout: XNode
    @Binding var snap: Bool
    @Binding var grid: Int

    private var box: CGRect {
        FaceRenderer(project).boxes(theme: theme).first { $0.layout === layout }?.rect ?? .zero
    }

    var body: some View {
        let b = box
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                NumberField(title: "X", value: Int(layout.int("x"))) { v in project.edit { _ in layout.set("x", int: v) } }
                NumberField(title: "Y", value: Int(layout.int("y"))) { v in project.edit { _ in layout.set("y", int: v) } }
                InfoField(title: "Ш", value: Int(b.width))
                InfoField(title: "В", value: Int(b.height))
            }
            HStack(alignment: .top, spacing: 12) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    align("align.horizontal.left", "По лівому краю") { (0, nil) }
                    align("align.horizontal.center", "По центру") { (Int((CGFloat(project.meta.device.width) - b.width) / 2), nil) }
                    align("align.horizontal.right", "По правому краю") { (project.meta.device.width - Int(b.width), nil) }
                    align("align.vertical.top", "По верху") { (nil, 0) }
                    align("align.vertical.center", "По середині") { (nil, Int((CGFloat(project.meta.device.height) - b.height) / 2)) }
                    align("align.vertical.bottom", "По низу") { (nil, project.meta.device.height - Int(b.height)) }
                }
                nudgePad
            }
            VStack(spacing: 0) {
                Toggle("Прив'язка до центру й країв", isOn: $snap).font(.subheadline).padding(.horizontal, 14).frame(height: 44)
                Divider().padding(.leading, 14)
                HStack {
                    Text("Сітка").font(.subheadline)
                    Spacer()
                    Picker("Сітка", selection: $grid) {
                        Text("1").tag(1); Text("4").tag(4); Text("8").tag(8)
                    }
                    .pickerStyle(.segmented).frame(width: 150)
                }
                .padding(.horizontal, 14).frame(height: 44)
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.editorTile))
        }
    }

    /// Вирівнювання відносно екрана: зсув шару так, щоб його рамка стала на місце.
    private func align(_ icon: String, _ label: String, _ target: @escaping () -> (Int?, Int?)) -> some View {
        Button {
            let b = box
            let (tx, ty) = target()
            let dx = tx.map { $0 - Int(b.minX) } ?? 0, dy = ty.map { $0 - Int(b.minY) } ?? 0
            project.edit { _ in
                layout.set("x", int: Int(layout.int("x")) + dx).set("y", int: Int(layout.int("y")) + dy)
            }
        } label: {
            Image(systemName: icon).font(.system(size: 16)).frame(maxWidth: .infinity).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.editorTile))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(loc(label)))
    }

    private func nudge(_ dx: Int, _ dy: Int) {
        let step = max(1, grid)
        project.edit { _ in layout.set("x", int: Int(layout.int("x")) + dx * step).set("y", int: Int(layout.int("y")) + dy * step) }
    }

    private func key(_ icon: String, _ label: String, _ dx: Int, _ dy: Int) -> some View {
        Button { nudge(dx, dy) } label: {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).frame(width: 32, height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.editorTile))
        }
        .buttonStyle(.plain).accessibilityLabel(Text(loc(label)))
    }

    private var nudgePad: some View {
        VStack(spacing: 4) {
            key("chevron.up", "Вгору", 0, -1)
            HStack(spacing: 4) {
                key("chevron.left", "Ліворуч", -1, 0)
                Text(verbatim: "\(max(1, grid)) px").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.accentColor).frame(width: 32)
                key("chevron.right", "Праворуч", 1, 0)
            }
            key("chevron.down", "Вниз", 0, 1)
        }
    }
}

// MARK: - Дрібні елементи

/// Повзунок, що зберігає значення лише після відпускання (одна зміна в історії).
struct CommitSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    var onCommit: (Double) -> Void
    /// Значення під час руху повзунка (для живого перегляду); записується лише onCommit
    var onLive: ((Double) -> Void)? = nil
    @State private var local: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(loc(title)).font(.subheadline)
                Spacer()
                Text(verbatim: "\(Int(local ?? value))").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { local ?? value }, set: { local = $0; onLive?($0) }), in: range, step: step) { editing in
                if !editing, let v = local { onCommit(v); local = nil }
            }
        }
    }
}

struct StepperRow: View {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    var onChange: (Int) -> Void
    var body: some View {
        Stepper(value: Binding(get: { value }, set: { onChange($0) }), in: range) {
            HStack { Text(loc(title)).font(.subheadline); Spacer(); Text(verbatim: "\(value)").font(.subheadline).monospacedDigit().foregroundStyle(.secondary) }
        }
    }
}

/// «Число росте»: праворуч / від центру / ліворуч — кнопки зі схемою (червона риска — точка X,
/// пунктир — цифра, що додається, коли «5» стає «15») і стрілками; сіре з поясненням, коли не діє.
struct GrowChips: View {
    let selected: String
    let enabled: Bool
    let digits: Int
    var onSelect: (String) -> Void

    private let keys: [(String, String)] = [("left", "праворуч"), ("center", "від центру"), ("right", "ліворуч")]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc("Число росте")).font(.subheadline)
            HStack(spacing: 6) {
                ForEach(keys, id: \.0) { k in
                    let on = k.0 == selected
                    let fg: Color = on ? .white : .primary
                    Button { onSelect(k.0) } label: {
                        VStack(spacing: 5) {
                            schema(k.0, fg)
                            HStack(spacing: 3) {
                                if k.0 != "left" { Image(systemName: "arrow.left").font(.system(size: 9, weight: .semibold)) }
                                Text(loc(k.1)).font(.caption2.weight(on ? .semibold : .medium)).lineLimit(1).minimumScaleFactor(0.7)
                                if k.0 != "right" { Image(systemName: "arrow.right").font(.system(size: 9, weight: .semibold)) }
                            }
                        }
                        .foregroundStyle(fg)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 9).fill(on ? Color.accentColor : Color.editorTile))
                    }
                    .buttonStyle(.plain)
                }
            }
            .disabled(!enabled).opacity(enabled ? 1 : 0.4)
            Text(enabled ? loc("Червона риска — точка X. Пунктир — цифра, що додається, коли «5» стає «15».")
                         : String(format: loc("Не діє: з нулями попереду цифр завжди %d, число не росте. Вимкніть «Нулі попереду», щоб це мало сенс."), digits))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// дві цифри 12×18 з проміжком 2; риска — точка X
    private func schema(_ key: String, _ fg: Color) -> some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 2) {
                ForEach(0..<2, id: \.self) { d in
                    let added = key == "left" ? d == 1 : d == 0
                    if added {
                        RoundedRectangle(cornerRadius: 2).strokeBorder(fg, style: StrokeStyle(lineWidth: 1, dash: [2, 2])).frame(width: 12, height: 18)
                    } else {
                        RoundedRectangle(cornerRadius: 2).fill(fg).frame(width: 12, height: 18)
                    }
                }
            }
            RoundedRectangle(cornerRadius: 1).fill(Color.red).frame(width: 2, height: 22)
                .offset(x: CGFloat(key == "left" ? 0 : key == "center" ? 13 : 26) - 1)
        }
        .frame(width: 26, height: 22)
    }
}

/// Вісім кнопок-стрілок 3×3 (центр порожній): 0° — угору, за годинниковою
struct DirectionPad: View {
    let title: String
    let selected: Double
    var onPick: (Double) -> Void
    private let angles: [Double?] = [315, 0, 45, 270, nil, 90, 225, 180, 135]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc(title)).font(.subheadline)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 6), count: 3), spacing: 6) {
                ForEach(0..<9, id: \.self) { i in
                    if let a = angles[i] {
                        let on = abs((((selected - a).truncatingRemainder(dividingBy: 360)) + 540).truncatingRemainder(dividingBy: 360) - 180) < 0.5
                        Button { onPick(a) } label: {
                            Image(systemName: "arrow.up").font(.system(size: 15, weight: .semibold)).rotationEffect(.degrees(a))
                                .frame(width: 44, height: 44)
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .background(RoundedRectangle(cornerRadius: 9).fill(on ? Color.accentColor : Color.editorTile))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(width: 44, height: 44)
                    }
                }
            }
        }
    }
}

struct Chips: View {
    let title: String
    let hint: String?
    let items: [(String, String)]
    let selected: String
    var onSelect: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(loc(title)).font(.subheadline)
                if let hint { Text(verbatim: "· " + loc(hint)).font(.footnote).foregroundStyle(.secondary) }
            }
            HStack(spacing: 6) {
                ForEach(items, id: \.0) { item in
                    Button { onSelect(item.0) } label: {
                        Text(loc(item.1)).font(.caption.weight(item.0 == selected ? .semibold : .medium))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .foregroundStyle(item.0 == selected ? Color.white : Color.primary)
                            .background(RoundedRectangle(cornerRadius: 9).fill(item.0 == selected ? Color.accentColor : Color.editorTile))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct NumberField: View {
    let title: String
    let value: Int
    var onCommit: (Int) -> Void
    @Environment(\.inputBar) private var bar
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(loc(title)).font(.caption).foregroundStyle(.secondary)
            // введення — у полі над клавіатурою
            Button {
                bar?.begin(title, "\(value)", numeric: true) { t in
                    if let v = Int(t.trimmingCharacters(in: .whitespaces)), v != value { onCommit(v) }
                }
            } label: {
                Text(verbatim: "\(value)").font(.system(size: 17, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.editorTile))
    }
}

struct InfoField: View {
    let title: String
    let value: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(loc(title)).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: "\(value)").font(.system(size: 17, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.editorTile))
    }
}

/// Вибір кольору: зміна застосовується через мить після останнього руху (без сотні записів в історії).
struct DebouncedColor: View {
    let title: String
    let hex: String
    var onCommit: (String) -> Void
    @State private var pending: Task<Void, Never>?

    var body: some View {
        ColorPicker(loc(title), selection: Binding(get: { Color(AssetFactory.color(hex)) }, set: { c in
            let h = Self.hex(UIColor(c))
            pending?.cancel()
            pending = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                if !Task.isCancelled, h != hex { onCommit(h) }
            }
        }), supportsOpacity: false)
        .font(.subheadline)
    }

    static func hex(_ c: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        func v(_ x: CGFloat) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", v(r), v(g), v(b))
    }
}

/// Одиниця біля числа: «%», «°», «км»… (тим самим шрифтом, що й цифри)
/// Рядок напису: записується після «Готово» на клавіатурі
struct LabelField: View {
    let text: String
    var onCommit: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Текст напису").font(.subheadline)
            InputRow(title: "Текст напису", value: text, placeholder: "Напис") { t in
                let v = t.trimmingCharacters(in: .whitespacesAndNewlines)
                if !v.isEmpty && v != text { onCommit(v) }
            }
            .padding(.horizontal, 10).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.editorTile))
            Text("Будь-яка мова, зокрема кирилиця: напис малюється шрифтом телефона й іде на браслет картинкою.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct UnitField: View {
    let unit: String
    var onCommit: (String) -> Void
    @Environment(\.inputBar) private var bar
    var body: some View {
        HStack(spacing: 6) {
            Text("Одиниця").font(.subheadline)
            Spacer()
            Button {
                bar?.begin("Одиниця", unit) { t in
                    let v = t.trimmingCharacters(in: .whitespacesAndNewlines)
                    if v != unit { onCommit(v) }
                }
            } label: {
                Text(unit.isEmpty ? loc("немає") : unit)
                    .font(.subheadline)
                    .foregroundStyle(unit.isEmpty ? Color.secondary : Color.primary)
                    .frame(minWidth: 52)
            }
            .buttonStyle(.bordered)
            ForEach(["%", "°", "км"], id: \.self) { u in
                Button(u) { onCommit(u) }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
            }
            if !unit.isEmpty {
                Button { onCommit("") } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Прибрати одиницю"))
            }
        }
    }
}

/// Своя картинка стрілки (вісь — по центру внизу, потім можна підправити)
struct HandImageRow: View {
    @ObservedObject var project: FaceProject
    let res: XNode
    @State private var item: PhotosPickerItem?
    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            Label("Своя картинка стрілки", systemImage: "photo").font(.subheadline.weight(.semibold))
        }
        .onChange(of: item) { it in
            guard let it else { return }
            Task { @MainActor in
                guard let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) else { return }
                let rgba = AssetFactory.fromUIImage(img, maxSide: 260)
                project.edit { p in
                    guard let target = p.resource(ref: res.string("ref")) else { return }
                    ElementFactory.replaceImage(p, target, rgba)
                    res.set("pivotX", int: rgba.w / 2).set("pivotY", int: rgba.h - rgba.w / 2)
                    // своя картинка — параметри малювання стрілки більше не діють
                    p.meta.generators[res.string("name") ?? ""] = nil
                }
            }
        }
    }
}

/// Значки за значенням: пороги й картинки
struct ValuesLook: View {
    @ObservedObject var project: FaceProject
    let res: XNode
    @State private var items: [PhotosPickerItem] = []

    var body: some View {
        let params = res.all("Param")
        VStack(alignment: .leading, spacing: 8) {
            Text("Картинка змінюється, коли значення досягає порогу.").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(params.enumerated()), id: \.offset) { i, prm in
                NumberField(title: String(format: loc("Поріг %d"), i + 1), value: Int(prm.int("value"))) { v in
                    project.edit { _ in prm.set("value", int: v) }
                }
            }
            PhotosPicker(selection: $items, maxSelectionCount: 30, matching: .images) {
                Label("Замінити картинки", systemImage: "photo.stack").font(.subheadline.weight(.semibold))
            }
        }
        .onChange(of: items) { list in
            guard !list.isEmpty else { return }
            Task { @MainActor in
                var imgs: [RGBAImage] = []
                for it in list {
                    if let d = try? await it.loadTransferable(type: Data.self), let img = UIImage(data: d) {
                        imgs.append(AssetFactory.fromUIImage(img, maxSide: 200))
                    }
                }
                guard !imgs.isEmpty else { return }
                project.edit { p in ElementFactory.replaceValueImages(p, element: res, images: imgs) }
                items = []
            }
        }
    }
}
