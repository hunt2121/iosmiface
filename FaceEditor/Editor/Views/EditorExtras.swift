// SPDX-License-Identifier: MIT
// Колір у рядку: квадратик + #RRGGBB, палітра по натисканню.

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
                PaletteGrid(current: hex) { h in palette = false; if h != hex { onCommit(h) } }
            }
            TextField("#RRGGBB", text: $text)
                .font(.system(.subheadline, design: .monospaced))
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .focused($focused)
                .onSubmit(commit)
                .frame(width: 96).padding(.horizontal, 8).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color(.tertiarySystemGroupedBackground)))
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
        if h != hex { onCommit(h) }
    }
}

struct PaletteGrid: View {
    let current: String
    var pick: (String) -> Void
    @State private var custom: Color = .white

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 10), count: 5), spacing: 10) {
            ForEach(ColorRow.suggested, id: \.self) { h in
                Button { pick(h) } label: {
                    Circle().fill(Color(AssetFactory.color(h))).frame(width: 36, height: 36)
                        .overlay(Circle().stroke(h == current ? Color.accentColor : Color.primary.opacity(0.2), lineWidth: h == current ? 3 : 1))
                }
                .buttonStyle(.plain)
            }
            // системний вибір кольору — останній кружечок
            ColorPicker("", selection: Binding(get: { Color(AssetFactory.color(current)) }, set: { c in custom = c }), supportsOpacity: false)
                .labelsHidden().frame(width: 36, height: 36)
                .onChange(of: custom) { c in pick(DebouncedColor.hex(UIColor(c))) }
        }
        .padding(14)
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
