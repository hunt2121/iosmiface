// SPDX-License-Identifier: MIT
// Режим XML: manifest.xml з підсвіткою й номерами рядків, рядок з помилкою червоним, мініатюра превʼю.
// «Застосувати» — одна зміна в історії (кнопка «Скасувати» в редакторі повертає).

import SwiftUI
import UIKit
import FaceCompiler

struct XmlEditorView: View {
    @ObservedObject var project: FaceProject
    let theme: Int
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var base = ""
    @State private var errorLine = 0
    @State private var status = ""
    @State private var isError = false
    @State private var preview: UIImage?
    @State private var check: Task<Void, Never>?
    @State private var askLeave = false
    @State private var showPreview = false

    private var dirty: Bool { text != base }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CodeTextView(text: $text, errorLine: errorLine)
                Divider()
                HStack(spacing: 10) {
                    Button { showPreview = true } label: {
                        Group {
                            if let preview { Image(uiImage: preview).resizable().scaledToFit() } else { Color.black }
                        }
                        .frame(width: 26, height: 64)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.gray, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Превʼю"))
                    Text(verbatim: status).font(.caption).foregroundStyle(isError ? Color.red : Color.secondary)
                        .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            .navigationTitle("manifest.xml")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрити") { if dirty { askLeave = true } else { dismiss() } }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Застосувати") { apply() }.disabled(!dirty || isError).fontWeight(.semibold)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Скасувати зміни") { load() }.disabled(!dirty)
                }
            }
            .confirmationDialog("Застосувати зміни в XML?", isPresented: $askLeave, titleVisibility: .visible) {
                Button("Застосувати") { if apply() { dismiss() } }
                Button("Відкинути", role: .destructive) { dismiss() }
                Button("Скасувати", role: .cancel) {}
            }
            .sheet(isPresented: $showPreview) {
                VStack {
                    if let preview { Image(uiImage: preview).resizable().scaledToFit().clipShape(Capsule()).padding(30) }
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear(perform: load)
            .onChange(of: text) { _ in
                check?.cancel()
                check = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if !Task.isCancelled { validate() }
                }
            }
        }
    }

    private func load() {
        let t = String(decoding: XML.print(project.root), as: UTF8.self)
        base = t; text = t
        validate()
    }

    @discardableResult private func validate() -> XNode? {
        do {
            guard let root = try XML.parse(Array(text.utf8)) else {
                errorLine = 0; isError = true; status = loc("Порожній документ"); return nil
            }
            guard root.tag == "Watchface" else {
                errorLine = 1; isError = true
                status = String(format: loc("Кореневий тег має бути <Watchface>, а не <%@>"), root.tag)
                return nil
            }
            errorLine = 0; isError = false
            status = loc(dirty ? "XML правильний. Натисніть «Застосувати», щоб зберегти." : "XML правильний. Змін немає.")
            let p = FaceProject(id: "xml", folder: FileManager.default.temporaryDirectory, root: root, files: project.files, meta: project.meta)
            preview = FaceRenderer(p).render(theme: min(theme, max(0, p.themes.count - 1)), scale: 2).0
            return root
        } catch {
            var msg = (error as? XML.ParseError)?.message ?? "\(error)"
            isError = true
            if let r = msg.range(of: #"[Ll]ine (number=)?(\d+)"#, options: .regularExpression),
               let n = Int(msg[r].filter(\.isNumber)) {
                errorLine = n
                msg = String(msg[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                status = String(format: loc("Рядок %d: %@"), n, msg)
            } else { errorLine = 0; status = msg }
            return nil
        }
    }

    @discardableResult private func apply() -> Bool {
        guard let root = validate() else { return false }
        project.edit { $0.setRoot(root) }
        load()
        return true
    }
}

/// Текст із підсвіткою XML, номерами рядків і червоним рядком помилки
struct CodeTextView: UIViewRepresentable {
    @Binding var text: String
    var errorLine: Int

    func makeUIView(context: Context) -> GutterTextView {
        let v = GutterTextView()
        v.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        v.autocorrectionType = .no
        v.autocapitalizationType = .none
        v.smartQuotesType = .no
        v.smartDashesType = .no
        v.spellCheckingType = .no
        v.keyboardType = .asciiCapable
        v.delegate = context.coordinator
        v.text = text
        v.highlight(errorLine: errorLine)
        return v
    }

    func updateUIView(_ v: GutterTextView, context: Context) {
        if v.text != text { v.text = text }
        v.highlight(errorLine: errorLine)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeTextView
        init(_ p: CodeTextView) { parent = p }
        func textViewDidChange(_ tv: UITextView) { parent.text = tv.text }
    }
}

final class GutterTextView: UITextView {
    private let gutter = Gutter()
    static let gutterWidth: CGFloat = 38

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        textContainerInset = UIEdgeInsets(top: 8, left: Self.gutterWidth + 4, bottom: 8, right: 8)
        gutter.textView = self
        gutter.backgroundColor = .secondarySystemBackground
        gutter.contentMode = .redraw
        addSubview(gutter)
        // довгі рядки не переносимо — як у редакторі коду
        textContainer?.widthTracksTextView = false
        textContainer?.size = CGSize(width: 4000, height: CGFloat.greatestFiniteMagnitude)
        alwaysBounceHorizontal = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        gutter.frame = CGRect(x: contentOffset.x, y: 0, width: Self.gutterWidth, height: max(contentSize.height, bounds.height))
        bringSubviewToFront(gutter)
        gutter.setNeedsDisplay()
    }

    private var lastHighlighted = ""
    private var lastError = -1

    func highlight(errorLine: Int) {
        guard text != lastHighlighted || errorLine != lastError else { return }
        lastHighlighted = text; lastError = errorLine
        let sel = selectedRange
        let s = textStorage
        let full = NSRange(location: 0, length: s.length)
        s.beginEditing()
        s.setAttributes([.font: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: UIColor.label], range: full)
        func paint(_ pattern: String, _ color: UIColor) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return }
            for m in re.matches(in: s.string, range: full) { s.addAttribute(.foregroundColor, value: color, range: m.range) }
        }
        paint(#"</?[\w:.\-]+|/?>"#, .systemBlue)
        paint(#"[\w:.\-]+(?=\s*=)"#, .systemOrange)
        paint(#""[^"]*""#, .systemGreen)
        paint(#"<\?.*?\?>"#, .systemPurple)
        paint(#"<!--.*?-->"#, .secondaryLabel)
        if errorLine > 0 {
            var line = 1, start = 0
            let ns = s.string as NSString
            while line < errorLine && start < ns.length {
                let r = ns.range(of: "\n", range: NSRange(location: start, length: ns.length - start))
                if r.location == NSNotFound { break }
                start = r.location + 1; line += 1
            }
            if line == errorLine {
                let lr = ns.lineRange(for: NSRange(location: min(start, max(0, ns.length - 1)), length: 0))
                s.addAttribute(.backgroundColor, value: UIColor.systemRed.withAlphaComponent(0.25), range: lr)
            }
        }
        s.endEditing()
        selectedRange = sel
        gutter.setNeedsDisplay()
    }

    final class Gutter: UIView {
        weak var textView: GutterTextView?
        override func draw(_ rect: CGRect) {
            guard let tv = textView else { return }
            let lm = tv.layoutManager
            let ns = tv.text as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: UIColor.secondaryLabel]
            var line = 1
            var idx = 0
            let top = tv.textContainerInset.top
            while idx < ns.length || (idx == 0 && ns.length == 0) {
                let pr = ns.paragraphRange(for: NSRange(location: idx, length: 0))
                let g = lm.glyphIndexForCharacter(at: min(pr.location, max(0, ns.length - 1)))
                let frag = ns.length == 0 ? .zero : lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
                let y = frag.minY + top
                if y > rect.maxY { break }
                if y + frag.height >= rect.minY {
                    let s = "\(line)" as NSString
                    let w = s.size(withAttributes: attrs).width
                    s.draw(at: CGPoint(x: GutterTextView.gutterWidth - 6 - w, y: y + 1), withAttributes: attrs)
                }
                if ns.length == 0 { break }
                line += 1
                idx = NSMaxRange(pr)
            }
        }
    }
}
