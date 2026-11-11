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
    @State private var palette = false
    @Environment(\.inputBar) private var bar

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
            Button {
                bar?.begin(title, hex, caps: true) { t in commit(t) }
            } label: {
                Text(verbatim: hex).font(.system(.subheadline, design: .monospaced)).foregroundStyle(.primary)
                    .frame(width: 96, alignment: .leading).padding(.horizontal, 8).frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.editorTile))
            }
            .buttonStyle(.plain)
        }
    }

    /// «fff», «#ffaa00», «FFAA00» → «#FFAA00»; неправильне — повертаємо як було
    private func commit(_ s: String) {
        var t = s.trimmingCharacters(in: .whitespaces).uppercased()
        if t.hasPrefix("#") { t.removeFirst() }
        if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
        guard t.count == 6, t.allSatisfy({ $0.isHexDigit }) else { return }
        let h = "#" + t
        if h != hex { onCommit(h) }
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

    /// Накреслення вибраного шрифту — лише ті, що є в його родині (у бібліотеці)
    private var faces: [FontLibrary.Entry] {
        let all = FontLibrary.all()
        guard let cur = all.first(where: { $0.name == gen.font }) else { return [] }
        return all.filter { $0.family == cur.family }
    }
    private var family: String { FontLibrary.all().first { $0.name == gen.font }?.family ?? gen.font }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { library = true } label: {
                HStack {
                    Text("Шрифт").foregroundStyle(.primary)
                    Spacer()
                    Text(verbatim: gen.font.isEmpty ? loc("Вбудований") : family).foregroundStyle(.secondary).lineLimit(1)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if gen.font.isEmpty {
                // вбудований шрифт має ці варіанти й будь-яку товщину
                Chips(title: "Накреслення", hint: nil,
                      items: [("rounded", "Округлий"), ("default", "Прямий"), ("condensed", "Вузький"), ("mono", "Моно")],
                      selected: gen.style) { s in apply { $0.style = s } }
                Chips(title: "Товщина", hint: nil, items: [300, 400, 500, 600, 700, 900].map { ("\($0)", "\($0)") },
                      selected: "\(gen.weight)") { s in apply { $0.weight = Int(s) ?? 700 } }
            } else if faces.count > 1 {
                // свій шрифт: лише накреслення, які справді є у файлах цієї родини
                Chips(title: "Накреслення", hint: nil, items: faces.map { ($0.name, $0.style.isEmpty ? $0.name : $0.style) },
                      selected: gen.font) { s in apply { $0.font = s } }
            }
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

