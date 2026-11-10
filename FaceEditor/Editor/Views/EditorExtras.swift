// SPDX-License-Identifier: MIT
// Колір у рядку, набори цифр (П-2), вибір шрифту з бібліотеки.

import SwiftUI
import UniformTypeIdentifiers
import FaceCompiler

// MARK: - Колір прямо в рядку

/// Колір у рядку: квадратик + поле «#RRGGBB». Палітра відкривається лише по натисканню на квадратик;
/// останній квадратик палітри — системний вибір кольору. Окремого екрана немає.
struct ColorRow: View {
    let title: String
    let hex: String
    var onCommit: (String) -> Void
    @State private var text = ""
    @State private var palette = false
    @FocusState private var focused: Bool

    static let suggested = ["#FFFFFF", "#000000", "#8E8E93", "#FF453A", "#FF9F0A", "#FFD60A",
                            "#30D158", "#64D2FF", "#0A84FF", "#5E5CE6", "#BF5AF2", "#FF375F"]

    var body: some View {
        HStack(spacing: 10) {
            Text(loc(title)).font(.subheadline).lineLimit(2)
            Spacer(minLength: 6)
            Button { palette = true } label: {
                RoundedRectangle(cornerRadius: 8).fill(Color(AssetFactory.color(hex)))
                    .frame(width: 32, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(loc("Палітра")))
            .compactPopover(isPresented: $palette) {
                PaletteGrid(current: hex) { h, close in if close { palette = false }; if h != hex { onCommit(h) } }
            }
            TextField("#RRGGBB", text: $text)
                .font(.system(.subheadline, design: .monospaced))
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .focused($focused)
                .onSubmit(commit)
                .frame(width: 96).padding(.horizontal, 8).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.editorTile))
        }
        .onAppear { text = hex }
        .onChange(of: hex) { v in if !focused { text = v } }
        .onChange(of: focused) { f in if !f { commit() } }
    }

    /// «fff», «#ffaa00», «FFAA00» → «#FFAA00»; неправильне — повертаємо як було
    private func commit() {
        var t = text.trimmingCharacters(in: .whitespaces).uppercased()
        if t.hasPrefix("#") { t.removeFirst() }
        if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
        guard t.count == 6, t.allSatisfy({ $0.isHexDigit }) else { text = hex; return }
        let h = "#" + t
        text = h
        if h != hex { DispatchQueue.main.async { onCommit(h) } }
    }
}

struct PaletteGrid: View {
    let current: String
    /// close: готовий колір з палітри закриває поповер; системний вибір (повзунки, поле HEX) лишається відкритим
    var pick: (String, Bool) -> Void
    @State private var custom: Color = .white
    @State private var started = false
    @State private var pending: Task<Void, Never>?

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 10), count: 5), spacing: 10) {
            ForEach(ColorRow.suggested, id: \.self) { h in
                Button { pick(h, true) } label: {
                    Circle().fill(Color(AssetFactory.color(h))).frame(width: 36, height: 36)
                        .overlay(Circle().stroke(h == current ? Color.accentColor : Color.primary.opacity(0.2), lineWidth: h == current ? 3 : 1))
                }
                .buttonStyle(.plain)
            }
            // системний вибір кольору — останній кружечок. Власний стан не підміняємо значенням з проєкту:
            // інакше від кожного руху повзунка чи символу в полі HEX вибір кольору скидається, а клавіатура закривається
            ColorPicker("", selection: $custom, supportsOpacity: false)
                .labelsHidden().frame(width: 36, height: 36)
                .onChange(of: custom) { c in
                    guard started else { return }
                    let h = DebouncedColor.hex(UIColor(c))
                    pending?.cancel()
                    pending = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        if !Task.isCancelled { pick(h, false) }
                    }
                }
        }
        .padding(14)
        .onAppear {
            custom = Color(AssetFactory.color(current))
            DispatchQueue.main.async { started = true }
        }
    }
}

extension View {
    /// Поповер, що на iPhone лишається поповером (iOS 16.4+), а на старіших — аркуш
    @ViewBuilder func compactPopover<C: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> C) -> some View {
        if #available(iOS 16.4, *) {
            popover(isPresented: isPresented) { content().presentationCompactAdaptation(.popover) }
        } else {
            sheet(isPresented: isPresented) { content().presentationDetents([.height(220)]) }
        }
    }
}

// MARK: - Шрифт і набір цифр

/// Шрифт для цифр і написів: стилі системного шрифту або свої файли (.ttf / .otf / .ttc)
struct FontRow: View {
    let gen: Generator
    var apply: ((inout Generator) -> Void) -> Void
    @State private var library = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chips(title: "Шрифт", hint: gen.font.isEmpty ? "перетворюється на картинки" : nil,
                  items: [("rounded", "Округлий"), ("default", "Прямий"), ("condensed", "Вузький"), ("mono", "Моно")],
                  selected: gen.font.isEmpty ? gen.style : "") { s in apply { $0.style = s; $0.font = "" } }
            Button { library = true } label: {
                HStack {
                    Image(systemName: "textformat")
                    Text(gen.font.isEmpty ? loc("Мої шрифти…") : gen.font).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .font(.subheadline)
                .padding(.horizontal, 12).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(gen.font.isEmpty ? Color.editorTile : Color.accentColor.opacity(0.18)))
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $library) {
            FontLibraryView(selected: gen.font) { name in library = false; apply { $0.font = name } }
        }
    }
}

/// Бібліотека шрифтів: додати з «Файлів», видалити гортанням, видно, які символи є
struct FontLibraryView: View {
    var selected: String = ""
    var onPick: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var fonts: [FontLibrary.Entry] = []
    @State private var importing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if fonts.isEmpty {
                    Text("Додайте файл шрифту (.ttf, .otf або .ttc) із «Файлів» — він буде доступний для цифр і написів у всіх проєктах.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(fonts) { f in
                    Button { onPick?(f.name) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: "0123 Aa Яя").font(Font(FontLibrary.font(f.name, size: 22) ?? .systemFont(ofSize: 22)))
                                Text(verbatim: f.family + (f.style.isEmpty ? "" : " · " + f.style)).font(.subheadline)
                                Text(verbatim: FontLibrary.coverage(f.name)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if f.name == selected { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) { FontLibrary.remove(f); fonts = FontLibrary.all() } label: { Label("Видалити", systemImage: "trash") }
                    }
                }
                if onPick != nil, !selected.isEmpty {
                    Button("Повернути системний шрифт") { onPick?("") }
                }
            }
            .navigationTitle(loc("Шрифти"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Готово") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button { importing = true } label: { Label("Додати шрифт", systemImage: "plus") } }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.font, UTType(filenameExtension: "ttf") ?? .data, UTType(filenameExtension: "otf") ?? .data, UTType(filenameExtension: "ttc") ?? .data],
                          allowsMultipleSelection: true) { r in
                if case .success(let urls) = r {
                    for u in urls { do { try FontLibrary.add(u) } catch { self.error = error.localizedDescription } }
                    fonts = FontLibrary.all()
                }
            }
            .alert(loc("Шрифт не додано"), isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
            .onAppear { fonts = FontLibrary.all() }
        }
    }
}

/// Набір цифр: готові й свої стилі, ефекти (градієнт, обвідка, тінь, ширина), застосування до всіх чисел
struct DigitSetSection: View {
    @ObservedObject var project: FaceProject
    let name: String
    let gen: Generator
    /// у вікні «Намалювати шрифтом»: зміни застосовуються кнопкою «Намалювати», без «До всіх чисел»
    var standalone = false
    var regen: ((inout Generator) -> Void) -> Void
    @State private var saving = false
    @State private var setName = ""
    @State private var sets: [DigitSets.DigitSet] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("НАБІР ЦИФР").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(sets) { s in
                        Button { regen { $0.applyStyle(s.style) } } label: {
                            VStack(spacing: 4) {
                                SetPreview(style: s.style).frame(height: 30)
                                Text(verbatim: s.name).font(.caption2).lineLimit(1)
                            }
                            .frame(width: 84, height: 62)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.editorTile))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if !s.builtIn { Button(role: .destructive) { DigitSets.remove(s.name); sets = DigitSets.all() } label: { Label("Видалити набір", systemImage: "trash") } }
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Button { setName = loc("Мій") + " \(DigitSets.user().count + 1)"; saving = true } label: {
                    Label("Зберегти як набір", systemImage: "square.and.arrow.down").font(.caption.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 34)
                }
                .buttonStyle(.bordered)
                if !standalone { Button {
                    let me = name, g = gen
                    project.edit { p in
                        // інші числа отримують той самий вигляд, розмір кожного лишається своїм
                        for (k, v) in p.meta.generators where v.kind == .digits && k != me {
                            var c = v; c.applyStyle(g); ElementFactory.regenerate(p, element: k, gen: c)
                        }
                    }
                } label: {
                    Label("До всіх чисел", systemImage: "square.stack.3d.up").font(.caption.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 34)
                }
                .buttonStyle(.bordered) }
            }
            Group {
                Text("Заливка тексту").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                CommitSlider(title: "Прозорість заливки, %", value: gen.fillAlpha, range: 0...100, step: 5) { v in regen { $0.fillAlpha = v } }
                Chips(title: "Градієнт", hint: nil, items: [("0", "Без"), ("1", "Вертикальний"), ("2", "Діагональний")],
                      selected: gen.color2.isEmpty ? "0" : (gen.gradDir == 1 ? "2" : "1")) { v in
                    regen {
                        if v == "0" { $0.color2 = "" } else {
                            if $0.color2.isEmpty { $0.color2 = ColorRow.suggested.first { $0 != gen.color && $0 != "#FFFFFF" } ?? "#FF375F" }
                            $0.gradDir = v == "2" ? 1 : 0
                        }
                    }
                }
                if !gen.color2.isEmpty { ColorRow(title: "Колір унизу", hex: gen.color2) { h in regen { $0.color2 = h } } }
                Text("Обведення").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                CommitSlider(title: "Товщина обведення, px", value: gen.outline, range: 0...12, step: 0.5) { v in regen { $0.outline = v } }
                if gen.outline > 0 {
                    ColorRow(title: "Колір обведення", hex: gen.outlineColor) { h in regen { $0.outlineColor = h } }
                    CommitSlider(title: "Прозорість обведення, %", value: gen.outlineAlpha, range: 0...100, step: 5) { v in regen { $0.outlineAlpha = v } }
                    Chips(title: "Положення", hint: nil, items: [("0", "Зовні"), ("1", "Посередині"), ("2", "Всередині")], selected: "\(gen.outlinePos)") { v in regen { $0.outlinePos = Int(v) ?? 0 } }
                }
                Text("Розкладка").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                CommitSlider(title: "Інтервал між літерами, px", value: gen.tracking, range: -5...20, step: 0.5) { v in regen { $0.tracking = v } }
                CommitSlider(title: "Ширина літер, %", value: gen.widthPct, range: 50...150, step: 1) { v in regen { $0.widthPct = v } }
                Text("Тінь").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                CommitSlider(title: "Тінь праворуч, px", value: gen.shadowX, range: -8...8, step: 1) { v in regen { $0.shadowX = v } }
                CommitSlider(title: "Тінь донизу, px", value: gen.shadowY, range: -8...8, step: 1) { v in regen { $0.shadowY = v } }
                if gen.shadowX != 0 || gen.shadowY != 0 {
                    ColorRow(title: "Колір тіні", hex: gen.shadowColor) { h in regen { $0.shadowColor = h } }
                    CommitSlider(title: "Прозорість тіні, %", value: gen.shadowAlpha, range: 0...100, step: 5) { v in regen { $0.shadowAlpha = v } }
                }
            }
        }
        .onAppear { sets = DigitSets.all() }
        .alert(loc("Набір цифр"), isPresented: $saving) {
            TextField(loc("Назва"), text: $setName)
            Button("Скасувати", role: .cancel) {}
            Button("Зберегти") {
                let n = setName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { DigitSets.add(n, style: gen); sets = DigitSets.all() }
            }
        } message: { Text("Набір можна застосувати до будь-якого числа в будь-якому проєкті.") }
    }
}

/// Мініатюра набору: «1234» його стилем
struct SetPreview: View {
    let style: Generator
    var body: some View {
        let g: Generator = { var c = style; c.fontSize = 22; c.outline = min(c.outline, 1.5); return c }()
        let frames = AssetFactory.digitFrames(g)
        HStack(spacing: 0) {
            ForEach([1, 2, 3, 4], id: \.self) { d in
                if d < frames.count, let cg = frames[d].cgImage { Image(decorative: cg, scale: 1).resizable().scaledToFit() }
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black))
    }
}
