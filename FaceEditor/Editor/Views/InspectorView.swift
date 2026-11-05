// SPDX-License-Identifier: MIT
// Властивості вибраного шару: вкладки «Вигляд», «Колір», «Позиція».

import SwiftUI
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

    private var res: XNode? { project.resource(ref: layout.string("ref")) }
    private var kind: ElementKind { ElementKind.of(res) }
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
                ForEach(InspectorTab.allCases) { t in Text(t.rawValue).tag(t) }
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
                .frame(width: 36, height: 36).background(Circle().fill(Color(.tertiarySystemGroupedBackground)))
        }
        .accessibilityLabel(label)
    }

    /// x числа — точка прив'язки (лівий край / середина / правий край), тож при зміні вирівнювання
    /// переносимо її так, щоб число лишилося на місці.
    private func setNumberAlign(_ r: XNode, _ v: String) {
        let b = FaceRenderer(project).render(theme: theme, scale: 1).1.first { $0.layout === layout }?.rect
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
            if r.has("source") { Row(title: "Що показує", value: SampleData.title(r.string("source") ?? ""), action: onSource) }
            switch kind {
            case .digits: digitsLook(r)
            case .text: TextLook(project: project, res: r)
            case .pointer, .arc, .line: gaugeLook(r)
            case .animation:
                CommitSlider(title: "Інтервал кадрів, мс", value: Double(r.int("interval")), range: 30...2000, step: 10) { v in edit { $0.set("interval", int: Int(v)) } }
            case .image:
                ImageReplaceRow(project: project, res: r)
            default:
                Text("Цей елемент можна пересувати, дублювати й видаляти. Його вміст редактор поки не змінює.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func digitsLook(_ r: XNode) -> some View {
        if let g = gen {
            CommitSlider(title: "Розмір шрифту", value: g.fontSize, range: 12...160, step: 1) { v in regen { $0.fontSize = v } }
            Chips(title: "Шрифт", hint: "перетворюється на картинки цифр",
                  items: [("rounded", "Округлий"), ("default", "Прямий"), ("condensed", "Вузький"), ("mono", "Моно")],
                  selected: g.style) { s in regen { $0.style = s } }
            Chips(title: "Товщина", hint: nil,
                  items: [100, 300, 400, 500, 600, 700, 900].map { ("\($0)", "\($0)") },
                  selected: "\(g.weight)") { s in regen { $0.weight = Int(s) ?? 700 } }
        } else {
            Button {
                let g = Generator(kind: .digits, color: "#FFFFFF", fontSize: 48, weight: 700, style: "rounded")
                let name = resName
                project.edit { ElementFactory.regenerate($0, element: name, gen: g) }
            } label: {
                Label("Намалювати цифри шрифтом", systemImage: "textformat.123").font(.subheadline.weight(.semibold))
            }
        }
        Chips(title: "Вирівнювання", hint: "куди росте число",
              items: [("left", "Ліворуч"), ("center", "Центр"), ("right", "Праворуч")],
              selected: r.string("align") ?? "left") { v in setNumberAlign(r, v) }
        StepperRow(title: "Кількість цифр", value: Int(r.int("totalDigits")), range: 0...9) { v in edit { $0.set("totalDigits", int: v) } }
        StepperRow(title: "Відступ між цифрами", value: Int(r.int("space")), range: -20...40) { v in edit { $0.set("space", int: v) } }
        Toggle("Нулі попереду", isOn: Binding(get: { r.bool("leadingZero") }, set: { v in edit { $0.set("leadingZero", bool: v) } }))
            .font(.subheadline)
    }

    @ViewBuilder private func gaugeLook(_ r: XNode) -> some View {
        if kind == .arc {
            CommitSlider(title: "Кут початку", value: Double(r.int("angleStart")), range: -360...360, step: 1) { v in edit { $0.set("angleStart", int: Int(v)) } }
            CommitSlider(title: "Довжина дуги, °", value: Double(r.int("angleRange")), range: -360...360, step: 1) { v in edit { $0.set("angleRange", int: Int(v)) } }
        }
        if kind == .pointer {
            CommitSlider(title: "Кут початку", value: Double(r.int("angleStart")), range: -360...360, step: 1) { v in edit { $0.set("angleStart", int: Int(v)) } }
            CommitSlider(title: "Поворот за діапазон, °", value: Double(r.int("angleRange")), range: -1440...1440, step: 5) { v in edit { $0.set("angleRange", int: Int(v)) } }
        }
        if !r.has("valueRangeSource") {
            StepperRow(title: "Найбільше значення", value: Int(r.int("valueRange")), range: 1...100000) { v in edit { $0.set("valueRange", int: v) } }
        }
        if let g = gen {
            switch kind {
            case .arc:
                CommitSlider(title: "Радіус", value: g.radius, range: 10...300, step: 1) { v in regen { $0.radius = v } }
                CommitSlider(title: "Товщина", value: g.width, range: 2...60, step: 1) { v in regen { $0.width = v } }
            case .line, .pointer:
                CommitSlider(title: "Довжина", value: g.length, range: 10...400, step: 1) { v in regen { $0.length = v } }
                CommitSlider(title: "Товщина", value: g.width, range: 2...60, step: 1) { v in regen { $0.width = v } }
            default: EmptyView()
            }
        }
    }

    // MARK: Колір

    @ViewBuilder private var colors: some View {
        if kind == .text, let r = res {
            DebouncedColor(title: "Колір тексту", hex: r.string("color") ?? "#FFFFFF") { h in edit { $0.set("color", h) } }
            CommitSlider(title: "Непрозорість, %", value: Double(r.int("opacity", 100)), range: 0...100, step: 1) { v in edit { $0.set("opacity", int: Int(v)) } }
        } else if let g = gen, g.kind != .image {
            DebouncedColor(title: "Колір", hex: g.color) { h in regen { $0.color = h } }
            if g.kind == .arc || g.kind == .line {
                DebouncedColor(title: "Колір фону шкали", hex: g.bgColor) { h in regen { $0.bgColor = h } }
            }
        } else if let r = res, r.tag == "Image" || r.tag == "ImageArray" {
            Toggle("Перефарбовування браслетом", isOn: Binding(get: { r.bool("recolorEnable") }, set: { v in edit { $0.set("recolorEnable", bool: v) } }))
                .font(.subheadline)
            Text("Колір готової картинки не змінюється. Якщо увімкнути перефарбовування, браслет зможе підставити колір теми.")
                .font(.footnote).foregroundStyle(.secondary)
        } else {
            Text("Колір цього елемента задається його картинками.").font(.footnote).foregroundStyle(.secondary)
        }
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
        FaceRenderer(project).render(theme: theme, scale: 1).1.first { $0.layout === layout }?.rect ?? .zero
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
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.tertiarySystemGroupedBackground)))
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
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func nudge(_ dx: Int, _ dy: Int) {
        let step = max(1, grid)
        project.edit { _ in layout.set("x", int: Int(layout.int("x")) + dx * step).set("y", int: Int(layout.int("y")) + dy * step) }
    }

    private func key(_ icon: String, _ label: String, _ dx: Int, _ dy: Int) -> some View {
        Button { nudge(dx, dy) } label: {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).frame(width: 32, height: 26)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemGroupedBackground)))
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    private var nudgePad: some View {
        VStack(spacing: 4) {
            key("chevron.up", "Вгору", 0, -1)
            HStack(spacing: 4) {
                key("chevron.left", "Ліворуч", -1, 0)
                Text("\(max(1, grid)) px").font(.system(size: 10, weight: .bold)).foregroundStyle(Color.accentColor).frame(width: 32)
                key("chevron.right", "Праворуч", 1, 0)
            }
            key("chevron.down", "Вниз", 0, 1)
        }
    }
}

// MARK: - Дрібні елементи

struct Row: View {
    let title: String
    let value: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(value).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }
}

/// Повзунок, що зберігає значення лише після відпускання (одна зміна в історії).
struct CommitSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    var onCommit: (Double) -> Void
    @State private var local: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text("\(Int(local ?? value))").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { local ?? value }, set: { local = $0 }), in: range, step: step) { editing in
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
            HStack { Text(title).font(.subheadline); Spacer(); Text("\(value)").font(.subheadline).monospacedDigit().foregroundStyle(.secondary) }
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
                Text(title).font(.subheadline)
                if let hint { Text("· \(hint)").font(.footnote).foregroundStyle(.secondary) }
            }
            HStack(spacing: 6) {
                ForEach(items, id: \.0) { item in
                    Button { onSelect(item.0) } label: {
                        Text(item.1).font(.caption.weight(item.0 == selected ? .semibold : .medium))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .foregroundStyle(item.0 == selected ? Color.white : Color.primary)
                            .background(RoundedRectangle(cornerRadius: 9).fill(item.0 == selected ? Color.accentColor : Color(.tertiarySystemGroupedBackground)))
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
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField("", text: $text)
                .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                .keyboardType(.numbersAndPunctuation)
                .focused($focused)
                .onSubmit { if let v = Int(text) { onCommit(v) } }
                .onChange(of: focused) { f in if !f, let v = Int(text), v != value { onCommit(v) } }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemGroupedBackground)))
        .onAppear { text = "\(value)" }
        .onChange(of: value) { v in if !focused { text = "\(v)" } }
    }
}

struct InfoField: View {
    let title: String
    let value: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(value)").font(.system(size: 17, weight: .semibold)).monospacedDigit().foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemGroupedBackground)))
    }
}

/// Вибір кольору: зміна застосовується через мить після останнього руху (без сотні записів в історії).
struct DebouncedColor: View {
    let title: String
    let hex: String
    var onCommit: (String) -> Void
    @State private var pending: Task<Void, Never>?

    var body: some View {
        ColorPicker(title, selection: Binding(get: { Color(AssetFactory.color(hex)) }, set: { c in
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
