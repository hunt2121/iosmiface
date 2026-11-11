// SPDX-License-Identifier: MIT
// «Намалювати шрифтом»: окремий екран, що перемальовує ВСІ картинки елемента одним шрифтом —
// цифри, дні тижня, місяці, AM/PM, значки за значенням (свій рядок на кожну картинку), напис.
// Шрифт, розмір, товщина, колір, набори й ефекти живуть тут, а не в інспекторі.

import SwiftUI
import FaceCompiler

struct FontArtSheet: View {
    @ObservedObject var project: FaceProject
    let res: XNode
    /// Скасували (для щойно доданого елемента — прибрати його)
    var onCancel: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var g = Generator(kind: .texts)
    @State private var textsLine = ""
    @State private var ready = false

    private var kind: Generator.Kind {
        let k = ElementKind.of(res, in: project)
        return k == .digits ? .digits : k == .label ? .label : .texts
    }
    private var slots: Int { ElementFactory.slotCount(project, res) }

    static let presets: [(String, [String])] = [
        ("Дні тижня Пн…Нд", ["ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ", "НД"]),
        ("Дні тижня Нд…Сб", ["НД", "ПН", "ВТ", "СР", "ЧТ", "ПТ", "СБ"]),
        ("Дні тижня MON…SUN", ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]),
        ("Дні тижня SUN…SAT", ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]),
        ("Дні тижня повністю", ["Понеділок", "Вівторок", "Середа", "Четвер", "Пʼятниця", "Субота", "Неділя"]),
        ("Місяці (СІЧ…ГРУ)", ["СІЧ", "ЛЮТ", "БЕР", "КВІ", "ТРА", "ЧЕР", "ЛИП", "СЕР", "ВЕР", "ЖОВ", "ЛИС", "ГРУ"]),
        ("Місяці (JAN…DEC)", ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]),
        ("AM / PM", ["AM", "PM"]),
        ("Числа від 0", (0..<60).map { "\($0)" }),
        ("Числа від 1", (1...60).map { "\($0)" }),
    ]

    private func fit(_ items: [String], _ n: Int) -> [String] {
        var l = Array(items.prefix(max(1, n)))
        while l.count < n { l.append("") }
        return l
    }

    private func defaultTexts() -> [String] {
        let s = (res.string("source") ?? "").lowercased()
        let pick = s.contains("week") ? Self.presets[0].1 : s.contains("month") ? Self.presets[5].1
                 : (s.contains("ampm") || s.contains("isam") || s.contains("ispm")) ? Self.presets[7].1 : Self.presets[8].1
        return fit(pick, slots)
    }

    private var frames: [RGBAImage] {
        switch kind {
        case .digits: return AssetFactory.digitFrames(g)
        case .label: return AssetFactory.labelImage(g).map { [$0] } ?? []
        default: return AssetFactory.textFrames(g, g.texts)
        }
    }

    var body: some View {
        NavigationStack { formBody.inputBarHost() }
    }

    /// Скільки цифр показати в перегляді числа
    private var previewDigits: Int { let n = Int(res.int("totalDigits")); return n > 0 ? n : 4 }

    private func slider(_ title: String, _ v: Double, _ r: ClosedRange<Double>, _ step: Double, _ set: @escaping (inout Generator, Double) -> Void) -> some View {
        CommitSlider(title: title, value: v, range: r, step: step, onCommit: { x in set(&g, x) }, onLive: { x in set(&g, x) })
    }

    private var formBody: some View {
        Group {
          VStack(spacing: 0) {
            // перегляд завжди видно — закріплений під панеллю, форма прокручується під ним
            FontArtPreview(g: g, kind: kind, digits: previewDigits, screenWidth: project.meta.device.width)
            Form {
                if kind == .texts {
                    Section {
                        Menu {
                            ForEach(Self.presets, id: \.0) { p in
                                Button(loc(p.0)) { g.texts = fit(p.1, slots); textsLine = g.texts.joined(separator: ", ") }
                            }
                        } label: { Label("Готовий список…", systemImage: "list.bullet") }
                        InputRow(title: "Що написати на картинках", value: textsLine, placeholder: "ПН, ВТ, СР…") { t in
                            textsLine = t
                            g.texts = fit(t.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }, slots)
                        }
                    } header: { Text("Що написати на картинках") } footer: {
                        Text(String(format: loc("Через кому, по одному на кожну з %d картинок, по порядку."), slots))
                    }
                } else if kind == .label {
                    Section("Текст напису") { InputRow(title: "Текст напису", value: g.text) { t in g.text = t } }
                }
                Section {
                    FontRow(gen: g) { f in f(&g) }
                    slider("Розмір шрифту", g.fontSize, 8...200, 1) { $0.fontSize = $1 }
                } header: { Text("Шрифт") }
                Section {
                    StyleGrid(gen: g) { f in f(&g) }
                } header: { Text("Стиль") }
                Section {
                    ColorRow(title: "Колір", hex: g.color) { h in g.color = h }
                    slider("Прозорість заливки, %", g.fillAlpha, 0...100, 5) { $0.fillAlpha = $1 }
                    // градієнт — лише діагональний, вмикається перемикачем
                    Toggle("Градієнт", isOn: Binding(get: { !g.color2.isEmpty }, set: { on in
                        if on { if g.color2.isEmpty { g.color2 = ColorRow.suggested.first { $0 != g.color && $0 != "#FFFFFF" } ?? "#FF375F" }; g.gradDir = 1 }
                        else { g.color2 = "" }
                    }))
                    if !g.color2.isEmpty { ColorRow(title: "Колір унизу", hex: g.color2) { h in g.color2 = h; g.gradDir = 1 } }
                } header: { Text("Заливка") }
                Section {
                    slider("Товщина обведення, px", g.outline, 0...12, 0.5) { $0.outline = $1 }
                    if g.outline > 0 {
                        ColorRow(title: "Колір обведення", hex: g.outlineColor) { h in g.outlineColor = h }
                        slider("Прозорість обведення, %", g.outlineAlpha, 0...100, 5) { $0.outlineAlpha = $1 }
                        Chips(title: "Положення", hint: nil, items: [("0", "Зовні"), ("1", "Посередині"), ("2", "Всередині")], selected: "\(g.outlinePos)") { v in g.outlinePos = Int(v) ?? 0 }
                    }
                } header: { Text("Обведення") }
                Section {
                    slider(kind == .digits ? "Відстань між цифрами, px" : "Інтервал між літерами, px", g.tracking, -5...20, kind == .digits ? 1 : 0.5) { $0.tracking = $1 }
                    slider("Ширина літер, %", g.widthPct, 50...150, 1) { $0.widthPct = $1 }
                } header: { Text("Розкладка") }
                Section {
                    slider("Тінь праворуч, px", g.shadowX, -8...8, 1) { $0.shadowX = $1 }
                    slider("Тінь донизу, px", g.shadowY, -8...8, 1) { $0.shadowY = $1 }
                    if g.shadowX != 0 || g.shadowY != 0 {
                        ColorRow(title: "Колір тіні", hex: g.shadowColor) { h in g.shadowColor = h }
                        slider("Прозорість тіні, %", g.shadowAlpha, 0...100, 5) { $0.shadowAlpha = $1 }
                    }
                } header: { Text("Тінь") }
                Section {
                    // одна фігура навколо всього напису / числа
                    Chips(title: "Фігура", hint: nil,
                          items: [("", "Без"), ("capsule", "Капсула"), ("square", "Прямокутник"), ("circle", "Коло")],
                          selected: g.badge) { v in g.badge = v }
                    if !g.badge.isEmpty { ColorRow(title: "Колір фігури", hex: g.badgeColor) { h in g.badgeColor = h } }
                } header: { Text("Форма") } footer: {
                    Text(kind == .digits ? "Одна фігура під усім числом (на всю кількість цифр)." : "Одна фігура навколо всього напису.")
                }
            }
          }
            .navigationTitle("Намалювати шрифтом")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { onCancel?(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Намалювати") {
                        let name = res.string("name") ?? "", gg = g, r = res
                        project.edit { p in
                            ElementFactory.regenerate(p, element: name, gen: gg)
                            ColorVariants.refresh(p, element: r)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard !ready else { return }
                ready = true
                if let s = project.meta.generators[res.string("name") ?? ""], s.drawn { g = s }
                else {
                    g = Generator(kind: kind, color: "#FFFFFF", fontSize: 40, weight: 700, style: "rounded")
                    // розмір шрифту — під висоту наявних картинок
                    if let t = ElementFactory.mainImages(project, res),
                       let src = t.tag == "Image" ? t.string("src") : t.all("Image").first?.string("src"),
                       let u = project.file(src).flatMap({ UIImage(data: $0) }) {
                        g.fontSize = min(160, max(10, (u.size.height * u.scale * 1.25).rounded()))
                    }
                }
                g.kind = kind
                // для числа «інтервал» — це відстань між цифрами елемента
                if kind == .digits { g.tracking = Double(Int8(truncatingIfNeeded: Int(res.int("space")))) }
                if kind == .label, g.text.isEmpty { g.text = loc("Напис") }
                if kind == .texts, g.texts.isEmpty { g.texts = defaultTexts() }
                textsLine = g.texts.joined(separator: ", ")
            }
        }
    }
}

/// Обгортка вузла для .sheet(item:)
struct NodeBox: Identifiable {
    let node: XNode
    var id: ObjectIdentifier { ObjectIdentifier(node) }
}
