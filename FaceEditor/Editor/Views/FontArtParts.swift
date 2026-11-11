// SPDX-License-Identifier: MIT
// Частини «Намалювати шрифтом»: перегляд у масштабі браслета (закріплений угорі) і плитки стилів,
// намальовані вибраним шрифтом.

import SwiftUI
import FaceCompiler

/// Перегляд шириною екрана браслета, 1 px картинки = 1 pt. Число — цифрами з відстанню між ними й
/// однією фігурою навколо, як на браслеті; написи й дні тижня — першою картинкою.
struct FontArtPreview: View {
    let g: Generator
    let kind: Generator.Kind
    let digits: Int
    let screenWidth: Int

    private var image: RGBAImage? {
        switch kind {
        case .digits:
            let fr = AssetFactory.digitFrames(g)
            guard let f0 = fr.first else { return nil }
            let sample = Array("8412907536".prefix(max(1, digits))).compactMap { $0.wholeNumberValue }
            let space = CGFloat(g.tracking.rounded())
            let cw = CGFloat(sample.count * f0.w) + CGFloat(sample.count - 1) * space
            let badge = AssetFactory.badgeImage(g, w: cw, h: CGFloat(f0.h))
            let W = max(Int(cw.rounded(.up)), badge?.w ?? 0), H = max(f0.h, badge?.h ?? 0)
            return AssetFactory.render(W, H) { _ in
                if let b = badge, let cg = b.cgImage { UIImage(cgImage: cg).draw(at: CGPoint(x: CGFloat(W - b.w) / 2, y: CGFloat(H - b.h) / 2)) }
                var x = (CGFloat(W) - cw) / 2
                for d in sample {
                    if let cg = fr[d].cgImage { UIImage(cgImage: cg).draw(at: CGPoint(x: x, y: CGFloat(H - f0.h) / 2)) }
                    x += CGFloat(f0.w) + space
                }
            }
        case .label: return AssetFactory.labelImage(g)
        default: return AssetFactory.textFrames(g, Array(g.texts.prefix(1))).first
        }
    }

    var body: some View {
        let w = CGFloat(max(100, screenWidth))
        VStack(spacing: 6) {
            Group {
                if let img = image, let cg = img.cgImage {
                    // ширше за екран браслета — зменшується, щоб було видно цілком
                    let k = min(1, (w - 16) / CGFloat(max(1, img.w)))
                    Image(decorative: cg, scale: 1).resizable().interpolation(.high)
                        .frame(width: CGFloat(img.w) * k, height: CGFloat(img.h) * k)
                } else { Color.clear.frame(height: 30) }
            }
            .frame(width: w).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 26).fill(Color.black))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4).padding(.bottom, 10)
        .background(Color(.systemGroupedBackground))
    }
}

/// Плитки стилів, кожна — вибраним шрифтом. Дотик — застосувати; довге натискання — видалити (і вбудовані теж).
struct StyleGrid: View {
    let gen: Generator
    var apply: ((inout Generator) -> Void) -> Void
    @Environment(\.inputBar) private var bar
    @State private var sets: [DigitSets.DigitSet] = []

    private func look(_ s: Generator) -> Generator { var c = gen; c.applyLook(s); return c }
    private func isCurrent(_ s: Generator) -> Bool { look(s) == gen }

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(sets) { s in
                    Button { apply { $0.applyLook(s.style) } } label: {
                        VStack(spacing: 3) {
                            StyleSample(style: look(s.style)).frame(height: 30)
                            Text(verbatim: s.name).font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.tail)
                        }
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity).frame(height: 62)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isCurrent(s.style) ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { DigitSets.remove(s); sets = DigitSets.all() } label: { Label("Видалити стиль", systemImage: "trash") }
                    }
                }
            }
            .padding(.vertical, 4)
            Divider().padding(.vertical, 8)
            Button {
                bar?.begin("Назва стилю", loc("Мій") + " \(DigitSets.user().count + 1)") { t in
                    let n = t.trimmingCharacters(in: .whitespaces)
                    if !n.isEmpty { DigitSets.add(n, style: gen); sets = DigitSets.all() }
                }
            } label: {
                Text("Зберегти поточний стиль").frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { sets = DigitSets.all() }
    }
}

/// «12» вибраним шрифтом і стилем
struct StyleSample: View {
    let style: Generator
    var body: some View {
        let g: Generator = { var c = style; c.fontSize = 26; c.badge = ""; c.outline = min(c.outline, 1.5); c.shadowX = min(c.shadowX, 2); c.shadowY = min(c.shadowY, 2); return c }()
        if let img = AssetFactory.textFrames(g, ["12"]).first, let cg = img.cgImage {
            Image(decorative: cg, scale: 1).resizable().scaledToFit()
        }
    }
}
