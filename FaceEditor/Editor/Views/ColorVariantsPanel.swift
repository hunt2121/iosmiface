// SPDX-License-Identifier: MIT
// Кольори циферблата: список кольорів (перший — основний вигляд), показ варіанта на полотні,
// зміна, додавання й видалення кольорів. Які елементи змінюють колір — вирішується в інспекторі елемента.

import SwiftUI
import FaceCompiler

struct ColorVariantsPanel: View {
    @ObservedObject var project: FaceProject
    /// Варіант, який зараз показує полотно
    @Binding var variant: Int

    /// Кольори, що пропонуються для нового варіанта (перший ще не використаний)
    private static let palette = ["#FF9500", "#30B455", "#0A84FF", "#FF375F", "#BF5AF2", "#FFD60A",
                                  "#64D2FF", "#FF453A", "#AC8E68", "#8E8E93"]

    private var colors: [String] { ColorVariants.colors(project) }
    private var enabled: Bool { ColorVariants.isEnabled(project) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Кольори циферблата").font(.headline)
            if !enabled {
                Text("На браслеті можна буде вибрати колір циферблата. Для кожного елемента окремо вмикається, чи змінюється він разом із кольором.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    let base = firstGeneratorColor ?? "#FFFFFF"
                    let next = Self.palette.first { $0 != base } ?? "#FF9500"
                    project.edit { ColorVariants.enable($0, base: base, first: next) }
                    variant = 0
                } label: {
                    Label("Додати кольорові варіанти", systemImage: "paintpalette")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.editorTile))
                }
                .buttonStyle(.plain)
            } else {
                // як у Windows: кожен колір — рядок; квадратик (дотик — палітра) і поле з кодом, дотик по назві — показати на полотні
                ForEach(Array(colors.enumerated()), id: \.offset) { i, c in
                    HStack(spacing: 8) {
                        Button { variant = i } label: {
                            Image(systemName: i == variant ? "eye.fill" : "eye").font(.system(size: 14))
                                .foregroundStyle(i == variant ? Color.accentColor : Color.secondary).frame(width: 26)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("Показати на полотні"))
                        ColorRow(title: i == 0 ? "Основний колір" : String(format: loc("Колір %d"), i), hex: c) { h in setColor(i, h) }
                        if i > 0 {
                            Button(role: .destructive) {
                                var list = colors
                                list.remove(at: i)
                                project.edit { ColorVariants.setColors($0, list) }
                                variant = min(variant, list.count - 1)
                            } label: { Image(systemName: "trash").font(.system(size: 14)) }
                            .buttonStyle(.plain).foregroundStyle(.red)
                            .accessibilityLabel(Text("Видалити цей колір"))
                        } else {
                            Color.clear.frame(width: 14)
                        }
                    }
                }
                if colors.count < ColorVariants.maxColors {
                    Button {
                        let next = Self.palette.first { !colors.contains($0) } ?? "#FFFFFF"
                        let list = colors + [next]
                        project.edit { ColorVariants.setColors($0, list) }
                        variant = list.count - 1
                    } label: {
                        Label("Додати колір", systemImage: "plus").font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
                Text("Основний — вигляд, як намальовано; він показується у виборі кольору на браслеті. Око — показати колір на полотні.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Елементам, які мають змінювати колір, увімкніть «Змінюється з кольором циферблата» на вкладці «Колір».")
                    .font(.footnote).foregroundStyle(.secondary)
                Button(role: .destructive) {
                    project.edit { ColorVariants.disable($0) }
                    variant = 0
                } label: {
                    Text("Вимкнути кольорові варіанти").font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        .onChange(of: colors.count) { n in if variant >= n { variant = max(0, n - 1) } }
    }

    private func setColor(_ i: Int, _ hex: String) {
        var list = colors
        guard list.indices.contains(i), !list.contains(ColorVariants.normalize(hex)) else { return }
        list[i] = hex
        project.edit { ColorVariants.setColors($0, list) }
    }

    /// Колір першого елемента, намальованого редактором (зазвичай колір цифр) — як основний
    private var firstGeneratorColor: String? {
        for l in project.layouts(0) {
            if let n = project.resource(ref: l.string("ref"))?.string("name"), let g = project.meta.generators[n],
               g.kind != .image, g.kind != .frames { return ColorVariants.normalize(g.color) }
        }
        return nil
    }
}
