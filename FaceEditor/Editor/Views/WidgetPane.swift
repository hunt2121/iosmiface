// SPDX-License-Identifier: MIT
// Налаштування віджета і слота в інспекторі (макет погоджено 9 листопада).

import SwiftUI
import FaceCompiler

/// Мініатюра ресурсу (як він виглядає на циферблаті) на чорному тлі
struct ResourceThumb: View {
    let project: FaceProject
    let res: XNode?
    var body: some View {
        ZStack {
            Color.black
            if let img = Self.image(project, res) {
                Image(uiImage: img).resizable().interpolation(.high).scaledToFit().padding(3)
            }
        }
        .frame(width: 46, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    static func image(_ p: FaceProject, _ res: XNode?) -> UIImage? {
        guard let res else { return nil }
        let r = FaceRenderer(p)
        guard let b = r.measure(res), b.width >= 1, b.height >= 1 else { return nil }
        let f = UIGraphicsImageRendererFormat()
        f.scale = 1
        return UIGraphicsImageRenderer(size: b.size, format: f).image { ctx in
            r.draw(res, at: CGPoint(x: -b.minX, y: -b.minY), in: ctx.cgContext, depth: 0)
        }
    }
}

private func appTitle(_ a: String?) -> String {
    guard let a, !a.isEmpty else { return loc("Нічого") }
    return loc(ElementFactory.appTitles[a] ?? a)
}

private func itemTitle(_ p: FaceProject, _ r: XNode?) -> String {
    guard let r else { return "?" }
    if WidgetSlots.isUserWidget(p, r) { return r.string("widgetName") ?? loc("Віджет") }
    return ElementKind.of(r, in: p).title
}

private func itemSub(_ p: FaceProject, _ r: XNode?) -> String {
    if let s = r?.string("source") { return SampleData.title(s) }
    return r?.string("name") ?? ""
}

/// Рядок-картка: мініатюра, назва, підпис, меню ⋯
private struct CardRow<M: View>: View {
    let project: FaceProject
    let res: XNode?
    let title: String
    let sub: String
    var badge: String? = nil
    var selected = false
    @ViewBuilder let menu: () -> M

    var body: some View {
        HStack(spacing: 12) {
            ResourceThumb(project: project, res: res)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(verbatim: title).font(.body).lineLimit(1)
                    if let badge {
                        Text(verbatim: badge).font(.caption2).foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .overlay(Capsule().stroke(Color.accentColor, lineWidth: 1))
                    }
                }
                Text(verbatim: sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Menu { menu() } label: {
                Image(systemName: "ellipsis").font(.body.weight(.semibold)).foregroundStyle(.secondary).frame(width: 32, height: 32)
            }
        }
        .padding(.horizontal, 12).frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.editorTile))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Налаштування віджета. origin — де стоїть віджет (для «Додати у віджет» і «Вийняти»); ownLayout — шар віджета (для «Розгрупувати»)
struct WidgetPane: View {
    @ObservedObject var project: FaceProject
    let theme: Int
    let widget: XNode
    let origin: CGPoint
    let ownLayout: XNode?
    /// Розташування слота, якщо віджет відкрито всередині слота
    var slotLayout: XNode? = nil
    @State private var name = ""
    @Environment(\.inputBar) private var bar

    var body: some View {
        let w = widget
        let arr = WidgetSlots.arrange(w)
        let items = w.all("Item")
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Назва").font(.subheadline)
                Spacer()
                Button {
                    bar?.begin("Назва", w.string("widgetName") ?? "") { t in name = t; commitName() }
                } label: {
                    Text(verbatim: w.string("widgetName") ?? loc("Віджет")).font(.subheadline).foregroundStyle(.primary)
                        .lineLimit(1).frame(maxWidth: 200, alignment: .trailing)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.editorTile))
            HStack {
                Text("Дія при натисканні").font(.subheadline)
                Spacer()
                Menu {
                    let cur = w.string("jumpApp")
                    Button { project.edit { _ in WidgetSlots.setTap(w, "") } } label: {
                        if cur == nil { Label(loc("Нічого"), systemImage: "checkmark") } else { Text(loc("Нічого")) }
                    }
                    ForEach(FaceCatalog.jumpApps.filter { ElementFactory.appTitles[$0] != nil }.sorted { appTitle($0) < appTitle($1) }, id: \.self) { a in
                        Button { project.edit { _ in WidgetSlots.setTap(w, a) } } label: {
                            if a == cur { Label(appTitle(a), systemImage: "checkmark") } else { Text(appTitle(a)) }
                        }
                    }
                } label: {
                    Text(verbatim: appTitle(w.string("jumpApp"))).font(.subheadline.weight(.semibold))
                }
            }
            .padding(.horizontal, 14).frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.editorTile))

            Text("Розташування").font(.subheadline)
            Picker("", selection: Binding(get: { arr }, set: { v in
                project.edit { WidgetSlots.setLayout($0, w, arrange: v, align: WidgetSlots.align(w), gap: v == "free" ? 0 : max(WidgetSlots.gap(w), 4), layout: ownLayout) }
            })) {
                Text("В ряд").tag("row"); Text("Стовпчиком").tag("column"); Text("Вільно").tag("free")
            }
            .pickerStyle(.segmented)
            if arr != "free" {
                Text("Вирівнювання").font(.subheadline)
                Picker("", selection: Binding(get: { WidgetSlots.align(w) }, set: { v in
                    project.edit { WidgetSlots.setLayout($0, w, arrange: arr, align: v, gap: WidgetSlots.gap(w), layout: ownLayout) }
                })) {
                    Text("Ліворуч").tag("start"); Text("По центру").tag("center"); Text("Праворуч").tag("end")
                }
                .pickerStyle(.segmented)
                CommitSlider(title: "Проміжок, px", value: Double(WidgetSlots.gap(w)), range: 0...40, step: 1) { v in
                    let g = Int(v.rounded())
                    if g != WidgetSlots.gap(w) { project.edit { WidgetSlots.setLayout($0, w, arrange: arr, align: WidgetSlots.align(w), gap: g, layout: ownLayout) } }
                }
            }

            SizeRow(project: project, widgets: [w], layout: ownLayout)

            Text(verbatim: loc("СКЛАД ВІДЖЕТА") + " · \(items.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
            if items.isEmpty {
                Text("Віджет порожній. Додайте в нього шари циферблата.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                let child = project.resource(ref: it.string("ref"))
                CardRow(project: project, res: child, title: itemTitle(project, child), sub: itemSub(project, child)) {
                    if i > 0 { Button { project.edit { _ in WidgetSlots.moveItem(w, i, -1) } } label: { Label(loc("Вище"), systemImage: "arrow.up") } }
                    if i < items.count - 1 { Button { project.edit { _ in WidgetSlots.moveItem(w, i, 1) } } label: { Label(loc("Нижче"), systemImage: "arrow.down") } }
                    Button { let o = origin, t = theme; project.edit { WidgetSlots.takeOut($0, w, index: i, origin: o, theme: t, own: ownLayout) } } label: {
                        Label(loc("Вийняти з віджета"), systemImage: "arrow.up.right.square")
                    }
                }
            }
            HStack(spacing: 8) {
                Menu {
                    let cands = project.layouts(theme).filter { l in
                        l !== ownLayout && !AodDim.isDim(project, l, theme: theme) && project.element(of: l) !== w
                            && ElementKind.of(project.element(of: l), in: project) != .slot
                    }.reversed()
                    if cands.isEmpty { Text("На цьому екрані немає інших шарів") }
                    ForEach(Array(cands.enumerated()), id: \.offset) { _, l in
                        let r = project.element(of: l)
                        Button(itemTitle(project, r) + " — " + itemSub(project, r)) {
                            let o = origin, t = theme
                            project.edit { WidgetSlots.addToWidget($0, w, origin: o, layout: l, theme: t, own: ownLayout, slotLayout: slotLayout) }
                        }
                    }
                } label: {
                    Text("+ Додати у віджет").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 40)
                        .background(Capsule().fill(Color.editorTile))
                }
                if let own = ownLayout {
                    Button { let t = theme; project.edit { WidgetSlots.ungroup($0, layout: own, theme: t) } } label: {
                        Text("Розгрупувати").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 40)
                            .background(Capsule().fill(Color.editorTile))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Віджет — кілька шарів одним блоком: рухаються разом, спільне натискання. Його можна поставити в слот, щоб вибирати на браслеті.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { name = w.string("widgetName") ?? "" }
        .onChange(of: ObjectIdentifier(w)) { _ in name = w.string("widgetName") ?? "" }
    }

    private func commitName() {
        let v = name.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty, v != widget.string("widgetName") else { return }
        let w = widget
        project.edit { _ in w.set("widgetName", v) }
    }
}

/// Налаштування слота: віджети на вибір (або відкритий віджет слота)
struct SlotPane: View {
    @ObservedObject var project: FaceProject
    let theme: Int
    let slot: XNode
    let layout: XNode
    @State private var open: XNode?

    var body: some View {
        let ws = WidgetSlots.widgets(project, slot)
        let origin = CGPoint(x: CGFloat(layout.int("x")), y: CGFloat(layout.int("y")))
        VStack(alignment: .leading, spacing: 10) {
            if let o = open, ws.contains(where: { $0 === o }) {
                Button { open = nil } label: { Label(loc("До слота"), systemImage: "chevron.left").font(.subheadline.weight(.semibold)) }
                WidgetPane(project: project, theme: theme, widget: o, origin: origin, ownLayout: nil, slotLayout: layout)
            } else {
                let shownIdx = min(WidgetSlots.shown(project, slot), max(0, ws.count - 1))
                SizeRow(project: project, widgets: ws, layout: layout, isSlot: true)
                Text(verbatim: loc("ЩО МОЖНА ВИБРАТИ НА БРАСЛЕТІ") + " · \(ws.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(Array(ws.enumerated()), id: \.offset) { i, w in
                    let sub = String(format: loc("натискання: %@"), appTitle(w.string("jumpApp"))) + (i == shownIdx ? " · " + loc("на полотні") : "")
                    CardRow(project: project, res: w, title: w.string("widgetName") ?? loc("Віджет"), sub: sub,
                            badge: i == 0 ? loc("типовий") : nil, selected: i == shownIdx) {
                        if i > 0 { Button { project.edit { _ in WidgetSlots.moveItem(slot, i, -1) } } label: { Label(loc("Вище"), systemImage: "arrow.up") } }
                        if i < ws.count - 1 { Button { project.edit { _ in WidgetSlots.moveItem(slot, i, 1) } } label: { Label(loc("Нижче"), systemImage: "arrow.down") } }
                        Button { open = nil; project.edit { WidgetSlots.slotTakeOut($0, slot, i) } } label: { Label(loc("Вийняти зі слота"), systemImage: "rectangle.portrait.and.arrow.right") }
                        if ws.count > 1 {
                            Button(role: .destructive) { project.edit { WidgetSlots.slotRemove($0, slot, i) } } label: { Label(loc("Прибрати зі слота"), systemImage: "trash") }
                        }
                    }
                    .onTapGesture {
                        WidgetSlots.show(project, slot, i)
                        open = w
                        project.objectWillChange.send()
                    }
                }
                HStack(spacing: 8) {
                    Button {
                        var made: XNode?
                        project.edit { made = WidgetSlots.slotNewWidget($0, slot, title: loc("Віджет")) }
                        WidgetSlots.show(project, slot, WidgetSlots.widgets(project, slot).count - 1)
                        open = made
                    } label: {
                        Text("+ Новий віджет").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 40)
                            .background(Capsule().fill(Color.editorTile))
                    }
                    .buttonStyle(.plain)
                    Menu {
                        let cands = WidgetSlots.candidates(project, slot)
                        if cands.isEmpty { Text("У циферблаті немає інших віджетів") }
                        ForEach(Array(cands.enumerated()), id: \.offset) { _, c in
                            Button((c.string("widgetName") ?? c.string("name") ?? "") + " · \(c.all("Item").count)") {
                                project.edit { WidgetSlots.slotAddExisting($0, slot, c) }
                            }
                        }
                    } label: {
                        Text("+ Вибрати з готових").font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(Capsule().fill(Color.editorTile))
                    }
                }
                Text("Торкніться віджета — він з'явиться на полотні, і його можна налаштувати. Перший — типовий; порядок — через меню ⋯.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("На браслеті: утримуйте циферблат → «Налаштувати» → торкніться цього місця й виберіть, що показувати. Мініатюри для вибору застосунок робить сам.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                SlotFramePanel(project: project, slot: slot)
            }
        }
    }
}

/// Вигляд рамки вибору слота на браслеті: швидкі стилі, колір, прозорість, товщина, заливка, форма, кути, запас від елементів
struct SlotFramePanel: View {
    @ObservedObject var project: FaceProject
    let slot: XNode
    /// Вигляд під час руху повзунка — перегляд оновлюється одразу, у проєкт пишеться після відпускання
    @State private var draft: SlotFrame?

    private var name: String { slot.string("name") ?? "" }

    private func slider(_ title: String, _ v: Int, _ r: ClosedRange<Double>, _ step: Double, _ st: SlotFrame, _ set: @escaping (inout SlotFrame, Int) -> Void) -> some View {
        CommitSlider(title: title, value: Double(v), range: r, step: step, onCommit: { x in draft = nil; update { set(&$0, Int(x)) } },
                     onLive: { x in var d = st; set(&d, Int(x)); draft = d })
    }

    private func update(_ f: @escaping (inout SlotFrame) -> Void) {
        let n = name
        project.edit { p in
            var s = p.meta.slotFrames[n] ?? SlotFrame()
            let pad = s.pad
            f(&s)
            p.meta.slotFrames[n] = s == SlotFrame() ? nil : s
            // запас від елементів змінює розмір віджетів «За вмістом»
            if s.pad != pad { WidgetSlots.repadSlot(p, slot, by: s.pad - pad) }
        }
    }

    var body: some View {
        let st = project.meta.slotFrames[name] ?? SlotFrame()
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: loc("РАМКА ВИБОРУ НА БРАСЛЕТІ")).font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 6)
            if let pv = WidgetSlots.framePreview(project, slot: slot, style: draft ?? st), let cg = pv.cgImage {
                // як на браслеті: віджет і рамка в масштабі екрана налаштувань циферблата (збільшено для зручності)
                Image(decorative: cg, scale: 1).interpolation(.high).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 150)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.11)))
            }
            HStack(spacing: 6) {
                ForEach(Array(SlotFrame.presets.enumerated()), id: \.offset) { _, pr in
                    let on = pr.1 == st
                    Button { update { $0 = pr.1 } } label: {
                        Text(verbatim: loc(pr.0)).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(on ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(Capsule().fill(on ? Color.accentColor : Color.editorTile))
                    }
                    .buttonStyle(.plain)
                }
            }
            Picker("", selection: Binding(get: { st.shape }, set: { v in update { $0.shape = v } })) {
                Text(verbatim: loc("За віджетом")).tag(0)
                Text(verbatim: loc("Без рамки")).tag(1)
            }
            .pickerStyle(.segmented)
            if st.shape == 0 {
                ColorRow(title: "Колір", hex: st.color) { h in update { $0.color = h } }
                slider("Прозорість, %", st.alpha, 0...100, 5, st) { $0.alpha = $1 }
                slider("Товщина, px", st.width, 1...8, 1, st) { $0.width = $1 }
                slider("Заливка, %", st.fill, 0...50, 2, st) { $0.fill = $1 }
                slider("Заокруглення кутів, px", st.radius, 0...40, 1, st) { $0.radius = $1 }
            }
            CommitSlider(title: "Запас від елементів, px", value: Double(st.pad), range: 0...20, step: 1) { v in update { $0.pad = Int(v) } }
            Text("Запас діє, коли розмір слота — «За вмістом». Рамку видно на браслеті, коли вибираєш віджет у слоті.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if st != SlotFrame() {
                Button { update { $0 = SlotFrame() } } label: {
                    Text("Скинути до стандартних").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 40)
                        .background(Capsule().fill(Color.editorTile))
                }
                .buttonStyle(.plain)
            }
        }
    }
}


/// Розмір області віджета (або всіх віджетів слота): за вмістом або вручну — незалежно від прозорих країв картинок.
/// Точно: поле, «−»/«+» по 1 px (довге натискання повторює), пропорції; на полотні — рамка з ручками.
struct SizeRow: View {
    @ObservedObject var project: FaceProject
    let widgets: [XNode]
    let layout: XNode?
    var isSlot = false
    @State private var lock = false

    private func apply(_ v: Int, horizontal: Bool) {
        let w0 = Int(widgets.map { $0.int("w") }.max() ?? 8), h0 = Int(widgets.map { $0.int("h") }.max() ?? 8)
        var nw = horizontal ? v : w0, nh = horizontal ? h0 : v
        if lock, w0 > 0, h0 > 0 {
            if horizontal { nh = max(8, Int((Double(v) * Double(h0) / Double(w0)).rounded())) }
            else { nw = max(8, Int((Double(v) * Double(w0) / Double(h0)).rounded())) }
        }
        // змінюючи висоту, тримаємо нижній край на місці: рамка росте й зменшується зверху, вміст не зсувається
        let up = h0 - nh
        project.edit { p in
            for x in widgets {
                WidgetSlots.setSize(p, x, width: nw, height: nh)
                if up != 0, layout != nil, WidgetSlots.arrange(x) == "free" {
                    for it in x.all("Item") { it.set("y", int: Int(it.int("y")) - up) }
                }
            }
            if up != 0, let l = layout { l.set("y", int: Int(l.int("y")) + up) }
        }
    }

    var body: some View {
        let manual = widgets.contains { WidgetSlots.isManual(project, $0) }
        let w = Int(widgets.map { $0.int("w") }.max() ?? 0), h = Int(widgets.map { $0.int("h") }.max() ?? 0)
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: loc(isSlot ? "Розмір слота" : "Розмір віджета")).font(.subheadline)
            SizeStepField(title: "Ширина", value: w) { apply($0, horizontal: true) }
            SizeStepField(title: "Висота", value: h) { apply($0, horizontal: false) }
            HStack(spacing: 8) {
                Button { lock.toggle(); project.sizeRatioLock = lock } label: {
                    Label(loc("Зберігати пропорції"), systemImage: lock ? "link" : "link.badge.plus")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 40)
                        .background(Capsule().fill(lock ? Color.accentColor.opacity(0.18) : Color.editorTile))
                }
                .buttonStyle(.plain)
                Button { project.edit { p in if isSlot, let l = layout { WidgetSlots.setAutoSlot(p, widgets, layout: l) } else { for x in widgets { WidgetSlots.setAuto(p, x, layout: layout) } } } } label: {
                    Text("За вмістом").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 40)
                        .background(Capsule().fill(manual ? Color.accentColor.opacity(0.18) : Color.editorTile))
                }
                .buttonStyle(.plain).disabled(!manual)
            }
            Text(verbatim: loc(manual ? "Розмір задано вручну: елементи його не змінюють." : "Розмір підлаштовується під елементи. Змініть число — і він стане постійним."))
                .font(.caption).foregroundStyle(.secondary)
            Text("Тягніть за точки рамки на полотні — розмір міняється по 1 px, з прилипанням до країв екрана й інших елементів.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { lock = project.sizeRatioLock }
    }
}

/// Поле числа з кнопками «−»/«+»: крок 1 px, довге натискання повторює; записується одним кроком історії
struct SizeStepField: View {
    let title: String
    let value: Int
    var onCommit: (Int) -> Void
    @State private var live: Int?

    var body: some View {
        HStack(spacing: 8) {
            NumberField(title: title, value: live ?? value) { v in live = nil; onCommit(v) }
            StepButton(symbol: "minus", step: { live = max(8, (live ?? value) - 1) }, done: finish)
            StepButton(symbol: "plus", step: { live = min(2000, (live ?? value) + 1) }, done: finish)
        }
    }

    private func finish() {
        if let l = live, l != value { onCommit(l) }
        live = nil
    }
}

struct StepButton: View {
    let symbol: String
    let step: () -> Void
    let done: () -> Void
    @State private var pressing = false
    @State private var repeated = false
    @State private var timer: Timer?

    var body: some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .bold)).foregroundStyle(Color.accentColor)
            .frame(width: 48, height: 48).background(Circle().fill(Color.editorTile))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressing else { return }
                    pressing = true; repeated = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        guard pressing else { return }
                        repeated = true
                        timer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { _ in step() }
                    }
                }
                .onEnded { _ in
                    pressing = false
                    timer?.invalidate(); timer = nil
                    if !repeated { step() }
                    done()
                })
    }
}
