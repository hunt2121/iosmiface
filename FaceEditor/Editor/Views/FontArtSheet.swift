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
        NavigationStack {
            Form {
                Section {
                    let fr = frames
                    let prm = res.all("Param")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 10) {
                            ForEach(Array(fr.enumerated()), id: \.offset) { i, f in
                                VStack(spacing: 4) {
                                    if let cg = f.cgImage { Image(decorative: cg, scale: 2).interpolation(.high) }
                                    if kind == .texts {
                                        Text(verbatim: i < prm.count ? loc("від") + " \(prm[i].int("value"))" : "#\(i + 1)").font(.caption2).foregroundStyle(.gray)
                                    }
                                }
                            }
                        }
                        .padding(12)
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                } header: { Text("Як це виглядає") } footer: {
                    Text(String(format: loc("Перемальовує всі %d картинок елемента одним шрифтом. Свої картинки замінюйте в блоці «Зображення»."), slots))
                }
                if kind == .texts {
                    Section {
                        Menu {
                            ForEach(Self.presets, id: \.0) { p in
                                Button(loc(p.0)) { g.texts = fit(p.1, slots); textsLine = g.texts.joined(separator: ", ") }
                            }
                        } label: { Label("Готовий список…", systemImage: "list.bullet") }
                        TextField("ПН, ВТ, СР…", text: $textsLine, axis: .vertical)
                            .onSubmit { g.texts = fit(textsLine.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }, slots) }
                            .onChange(of: textsLine) { t in g.texts = fit(t.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }, slots) }
                    } header: { Text("Що написати на картинках") } footer: {
                        Text(String(format: loc("Через кому, по одному на кожну з %d картинок, по порядку."), slots))
                    }
                } else if kind == .label {
                    Section("Текст напису") { TextField("", text: $g.text) }
                }
                Section {
                    FontRow(gen: g) { f in f(&g) }
                    VStack(alignment: .leading) {
                        HStack { Text("Розмір шрифту").font(.subheadline); Spacer(); Text(verbatim: "\(Int(g.fontSize))").font(.subheadline).monospacedDigit().foregroundStyle(.secondary) }
                        Slider(value: $g.fontSize, in: 8...200, step: 1)
                    }
                    if g.font.isEmpty {
                        Chips(title: "Товщина", hint: nil, items: [100, 300, 400, 500, 600, 700, 900].map { ("\($0)", "\($0)") },
                              selected: "\(g.weight)") { s in g.weight = Int(s) ?? 700 }
                    }
                    ColorRow(title: "Колір", hex: g.color) { h in g.color = h }
                } header: { Text("Шрифт") }
                Section {
                    DigitSetSection(project: project, name: res.string("name") ?? "", gen: g, standalone: true) { f in f(&g) }
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
