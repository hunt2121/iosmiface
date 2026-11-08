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
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)
            } else {
                swatches
                let v = min(variant, colors.count - 1)
                if v == 0 {
                    DebouncedColor(title: "Основний колір", hex: colors[0]) { h in setColor(0, h) }
                    Text("Основний — вигляд, як намальовано. Цей колір показується у виборі кольору на браслеті.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    DebouncedColor(title: "Колір варіанта", hex: colors[v]) { h in setColor(v, h) }
                    Button(role: .destructive) {
                        var list = colors
                        list.remove(at: v)
                        project.edit { ColorVariants.setColors($0, list) }
                        variant = max(0, v - 1)
                    } label: {
                        Label("Видалити цей колір", systemImage: "trash").font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
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

    private var swatches: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(colors.enumerated()), id: \.offset) { i, c in
                    Button { variant = i } label: {
                        VStack(spacing: 4) {
                            Circle().fill(Color(AssetFactory.color(c)))
                                .frame(width: 34, height: 34)
                                .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 1))
                                .padding(3)
                                .overlay(Circle().stroke(i == variant ? Color.accentColor : Color.clear, lineWidth: 2.5))
                            Text(i == 0 ? loc("Основний") : "\(i)")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(i == 0 ? loc("Основний колір") : c))
                }
                if colors.count < ColorVariants.maxColors {
                    Button {
                        let next = Self.palette.first { !colors.contains($0) } ?? "#FFFFFF"
                        let list = colors + [next]
                        project.edit { ColorVariants.setColors($0, list) }
                        variant = list.count - 1
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 15, weight: .bold))
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color(.tertiarySystemGroupedBackground)))
                            Text("Додати").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Додати колір"))
                }
            }
            .padding(.vertical, 2)
        }
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
               g.drawn { return ColorVariants.normalize(g.color) }
        }
        return nil
    }
}
