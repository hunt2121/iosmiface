// SPDX-License-Identifier: MIT
// Поле введення над клавіатурою: панель редактора (і полотно) лишаються на місці, а текст видно в маленькому рядку
// одразу над клавіатурою. Без підказок і автовиправлення.

import SwiftUI

final class InputBarModel: ObservableObject {
    struct Request: Identifiable {
        let id = UUID()
        var title: String
        var text: String
        var numeric = false
        var caps = false
        var commit: (String) -> Void
    }
    @Published var request: Request?

    func begin(_ title: String, _ text: String, numeric: Bool = false, caps: Bool = false, commit: @escaping (String) -> Void) {
        request = Request(title: title, text: text, numeric: numeric, caps: caps, commit: commit)
    }
}

private struct InputBarKey: EnvironmentKey { static let defaultValue: InputBarModel? = nil }

extension EnvironmentValues {
    /// Поле над клавіатурою найближчого екрана (редактор чи аркуш з .inputBarHost())
    var inputBar: InputBarModel? {
        get { self[InputBarKey.self] }
        set { self[InputBarKey.self] = newValue }
    }
}

struct InputBarView: View {
    @ObservedObject var model: InputBarModel
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        if let r = model.request {
            // як рядок повідомлення в месенджерах: скляна капсула з полем і кругла скляна кнопка ✓ над клавіатурою
            HStack(spacing: 10) {
                // поточне значення — сірою підказкою; що вводиш, те й замінює його
                TextField(r.text, text: $text)
                    .font(.body)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(r.caps ? .characters : .never)
                    .keyboardType(r.numeric ? .numbersAndPunctuation : .default)
                    .submitLabel(.done)
                    .onSubmit { finish() }
                    .padding(.horizontal, 16).frame(height: 44)
                    .glass(in: Capsule())
                Button { finish() } label: {
                    Image(systemName: "checkmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .glass(in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(loc("Готово")))
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .id(r.id)
            .onAppear { text = "" }
            // фокус — коли поле вже на екрані (одразу після появи iOS іноді його ігнорує)
            .task(id: r.id) {
                try? await Task.sleep(nanoseconds: 60_000_000)
                focused = true
            }
            .onChange(of: focused) { f in if !f { finish() } }
        }
    }

    private func finish() {
        guard let r = model.request else { return }
        model.request = nil
        focused = false
        let t = text
        // нічого не ввели — значення лишається як було
        guard !t.isEmpty else { return }
        // запис — після закриття поля (інакше перемальовування панелі збиває клавіатуру)
        DispatchQueue.main.async { r.commit(t) }
    }
}

/// Екран із полем над клавіатурою: вміст не рухається, коли відкривається клавіатура
struct InputBarHost: ViewModifier {
    // @State, а не @StateObject: хост не стежить за моделлю — інакше кожен дотик перемальовує весь редактор (полотно)
    @State private var model = InputBarModel()
    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content.environment(\.inputBar, model).ignoresSafeArea(.keyboard, edges: .bottom)
            InputBarView(model: model)
        }
    }
}

extension View {
    func inputBarHost() -> some View { modifier(InputBarHost()) }
}

/// Рядок зі значенням: дотик — введення в полі над клавіатурою
struct InputRow: View {
    let title: String
    let value: String
    var placeholder = ""
    var numeric = false
    var caps = false
    var onCommit: (String) -> Void
    @Environment(\.inputBar) private var bar
    var body: some View {
        Button { bar?.begin(title, value, numeric: numeric, caps: caps, commit: onCommit) } label: {
            HStack {
                Text(verbatim: value.isEmpty ? loc(placeholder) : value)
                    .foregroundStyle(value.isEmpty ? Color.secondary : Color.primary)
                    .lineLimit(2)
                Spacer()
                Image(systemName: "pencil").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    /// Liquid Glass на iOS 26; на старіших — матове скло
    @ViewBuilder func glass<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(shape.fill(.ultraThinMaterial)).overlay(shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}
