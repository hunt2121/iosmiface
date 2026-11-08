// SPDX-License-Identifier: MIT
// «Значення для перегляду»: що показують елементи в редакторі й попередньому перегляді.
// Однакове для всіх елементів з тим самим джерелом; на браслет не записується.

import SwiftUI

struct DemoSection: View {
    @ObservedObject var project: FaceProject
    let source: String

    private var demo: DemoValues { project.meta.demo }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if source.hasPrefix("time") { timeView }
            else if source.hasPrefix("date") { dateView }
            else { valueView }
        }
    }

    // MARK: Число (кроки, пульс, % для шкал…)

    private var valueView: some View {
        let r = SampleData.demoRange(source)
        let cur = SampleData.value(source, demo: demo)
        return VStack(alignment: .leading, spacing: 8) {
            CommitSlider(title: "Значення для перегляду", value: Double(min(max(cur, r.lowerBound), r.upperBound)),
                         range: Double(r.lowerBound)...Double(r.upperBound), step: 1) { v in set(Int(v)) }
            HStack(alignment: .bottom) {
                NumberField(title: "Точно", value: cur) { v in set(v) }
                    .frame(width: 130)
                Spacer()
                if demo.values[source] != nil {
                    Button(loc("Типове")) { project.edit { $0.meta.demo.values[source] = nil } }
                        .font(.subheadline.weight(.semibold))
                }
            }
            hint("Лише для редактора, на браслет не записується. Однакове для всіх елементів із цим джерелом.")
        }
    }

    private func set(_ v: Int) {
        guard demo.values[source] != v else { return }
        project.edit { $0.meta.demo.values[source] = v }
    }

    // MARK: Час

    private var timeView: some View {
        let real = demo.realTime
        let (h, m) = demo.hm ?? (10, 24)
        return VStack(alignment: .leading, spacing: 8) {
            Text(loc("Час для перегляду")).font(.subheadline)
            modePicker(real) { r in project.edit { $0.meta.demo.realTime = r } }
            if !real {
                HStack(spacing: 8) {
                    NumberField(title: "Години", value: h) { v in setTime(min(max(v, 0), 23), m) }
                    NumberField(title: "Хвилини", value: m) { v in setTime(h, min(max(v, 0), 59)) }
                }
            }
            hint(real ? "Справжній час телефона." : "Один час для всього циферблата: години, хвилини, стрілки.")
        }
    }

    private func setTime(_ h: Int, _ m: Int) {
        let t = String(format: "%02d:%02d", h, m)
        guard demo.time != t else { return }
        project.edit { $0.meta.demo.time = t }
    }

    // MARK: Дата

    private var dateView: some View {
        let real = demo.realDate
        let (d, mo, y) = demo.dmy ?? (30, 5, 2026)
        return VStack(alignment: .leading, spacing: 8) {
            Text(loc("Дата для перегляду")).font(.subheadline)
            modePicker(real) { r in project.edit { $0.meta.demo.realDate = r } }
            if !real {
                HStack(spacing: 8) {
                    NumberField(title: "День", value: d) { v in setDate(min(max(v, 1), 31), mo, y) }
                    NumberField(title: "Місяць", value: mo) { v in setDate(d, min(max(v, 1), 12), y) }
                    NumberField(title: "Рік", value: y) { v in setDate(d, mo, min(max(v, 2000), 2099)) }
                }
            }
            hint(real ? "Справжня дата телефона." : "Одна дата для всього циферблата; день тижня рахується з неї.")
        }
    }

    private func setDate(_ d: Int, _ m: Int, _ y: Int) {
        let t = String(format: "%04d-%02d-%02d", y, m, d)
        guard demo.date != t else { return }
        project.edit { $0.meta.demo.date = t }
    }

    // MARK: Спільне

    /// «Мої» — введені значення, «Реальні» — справжні з телефона
    private func modePicker(_ real: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Picker("", selection: Binding(get: { real }, set: { if $0 != real { set($0) } })) {
            Text(loc("Мої")).tag(false)
            Text(loc("Реальні")).tag(true)
        }
        .pickerStyle(.segmented)
    }

    private func hint(_ s: String) -> some View {
        Text(loc(s)).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
