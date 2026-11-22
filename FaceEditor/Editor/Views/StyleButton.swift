// SPDX-License-Identifier: MIT
// Кнопка стилів на полотні: два браслети (наша іконка TabWatch) і номер поточного стилю на діагоналі кнопки.

import SwiftUI
import UIKit

/// Два браслети: задній блідий, вище й правіше; передній повністю закриває задній (у його «екрані» заднього не видно)
struct StyleBandsIcon: View {
    /// Розмір одного браслета (картинка TabWatch 26×26)
    var size: CGFloat = 16

    var body: some View {
        let k = size / 26
        let dx = 3 * k, dy = 2 * k
        ZStack {
            band
                // вирізаємо з заднього силует переднього (передній зсунутий на −2dx, +2dy відносно заднього)
                .mask {
                    Rectangle()
                        .overlay(BandSilhouette().offset(x: -2 * dx, y: 2 * dy).blendMode(.destinationOut))
                        .compositingGroup()
                }
                .opacity(0.45)
                .offset(x: dx, y: -dy)
            band.offset(x: -dx, y: dy)
        }
        .frame(width: size + 2 * dx, height: size + 2 * dy)
    }

    private var band: some View {
        Image("TabWatch").renderingMode(.template).resizable().frame(width: size, height: size)
    }
}

/// Суцільний силует браслета TabWatch (ремінці й корпус без вирізу екрана) — у тих самих координатах, що й картинка
struct BandSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        // TabWatch.svg: translate(13 13) scale(0.88889) translate(−15 −15) у полі 26×26
        let s = rect.width / 26
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + ((x - 15) * 0.88889 + 13) * s, y: rect.minY + ((y - 15) * 0.88889 + 13) * s)
        }
        var p = Path()
        p.addLines([pt(11.3, 1.5), pt(18.7, 1.5), pt(19.4, 6.6), pt(10.6, 6.6)]); p.closeSubpath()
        p.addLines([pt(10.6, 23.4), pt(19.4, 23.4), pt(18.7, 28.5), pt(11.3, 28.5)]); p.closeSubpath()
        let a = pt(8, 5.6), b = pt(22, 24.4)
        p.addRoundedRect(in: CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y),
                         cornerSize: CGSize(width: 5.5 * 0.88889 * s, height: 5.4 * 0.88889 * s))
        return p
    }
}

/// Номер стилю: синій кружечок (для двох цифр — капсула) з білим обідком;
/// цифра стоїть за своєю «вагою» (центр мас по горизонталі, середина висоти по вертикалі) — 1, 4, 7 не здаються зсунутими
struct StyleNumberBadge: View {
    let number: Int
    /// Колір обідка — фон під кнопкою (картка полотна)
    var ring = Color(.secondarySystemGroupedBackground)

    var body: some View {
        let font = UIFont.systemFont(ofSize: 10, weight: .bold)
        let text = "\(number)"
        let off = GlyphCenter.offset(text, font: font)
        Text(verbatim: text)
            .font(Font(font as CTFont))
            .foregroundStyle(.white)
            .fixedSize()
            .offset(x: -off.x, y: -off.y)
            .frame(minWidth: 16, minHeight: 16)
            .padding(.horizontal, text.count > 1 ? 4 : 0)
            .background(Capsule().fill(Color.accentColor))
            .background(Capsule().fill(ring).padding(-2))
            .accessibilityHidden(true)
    }
}

/// Зсув оптичного центру тексту від центру його рамки (рамка — як у SwiftUI Text: ширина рядка × висота рядка шрифту)
enum GlyphCenter {
    private static var cache: [String: CGPoint] = [:]

    static func offset(_ text: String, font: UIFont) -> CGPoint {
        let key = "\(text)|\(font.fontName)|\(font.pointSize)"
        if let c = cache[key] { return c }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
        let size = (text as NSString).size(withAttributes: attrs)
        let w = Int(ceil(size.width)), h = Int(ceil(size.height))
        guard w > 0, h > 0 else { return .zero }
        let scale: CGFloat = 8
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { _ in
            (text as NSString).draw(at: .zero, withAttributes: attrs)
        }
        guard let cg = img.cgImage, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return .zero }
        let bpp = cg.bitsPerPixel / 8, row = cg.bytesPerRow
        var sum = 0.0, sx = 0.0, minY = Int.max, maxY = -1
        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let p = y * row + x * bpp
                var a = 0
                for b in 0..<bpp { a = max(a, Int(bytes[p + b])) }   // чорне на прозорому: ненульовий лише альфа
                guard a > 0 else { continue }
                sum += Double(a); sx += Double(a) * (Double(x) + 0.5)
                if a > 40 { minY = min(minY, y); maxY = max(maxY, y) }
            }
        }
        guard sum > 0, maxY >= 0 else { return .zero }
        let cx = sx / sum / Double(scale), cy = Double(minY + maxY + 1) / 2 / Double(scale)
        let r = CGPoint(x: cx - Double(size.width) / 2, y: cy - Double(size.height) / 2)
        cache[key] = r
        return r
    }
}

/// Кнопка стилів на полотні: 36 pt, як сусідні; номер — на діагоналі кнопки (під 45° на її краю)
struct StyleButtonLabel: View {
    let number: Int

    var body: some View {
        ZStack {
            Circle().fill(Color.editorTile)
            StyleBandsIcon(size: 16).foregroundStyle(Color.accentColor)
            StyleNumberBadge(number: number)
                .offset(x: 18 * 0.70711, y: 18 * 0.70711)
        }
        .frame(width: 36, height: 36)
        // рамка з запасом під номер: меню при натисканні обрізає мітку по її рамці (зовні запас знімається — див. EditorView)
        .padding(Self.pad)
        .contentShape(Rectangle())
    }

    static let pad: CGFloat = 8
}
