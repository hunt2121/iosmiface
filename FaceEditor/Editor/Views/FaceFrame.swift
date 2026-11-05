// SPDX-License-Identifier: MIT
// Єдина форма циферблата в редакторі — як FaceCapsule у BandFace: капсула, рамка 3 pt ЗЗОВНІ
// (циферблат не перекривається). Однакова на списку, полотні й у перегляді.

import SwiftUI
import ImageIO

enum FaceFrame {
    /// Товщина рамки корпусу
    static let border: CGFloat = 3
    static let color = Color.gray.opacity(0.45)
}

extension View {
    /// Обрізає вміст капсулою і додає рамку корпусу назовні (розмір зростає на 2 × border).
    func faceCapsule(active: Bool = false) -> some View {
        self
            .clipShape(Capsule(style: .continuous))
            .padding(FaceFrame.border)
            .background(Capsule(style: .continuous).fill(active ? Color.accentColor : FaceFrame.color))
    }
}

/// Картинка циферблата, що програє анімацію (UIImage з кадрами); звичайну показує як є.
/// SwiftUI Image анімованих UIImage не відтворює, тому UIImageView.
struct FaceImageView: UIViewRepresentable {
    let image: UIImage?

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFill
        v.clipsToBounds = true
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }

    func updateUIView(_ v: UIImageView, context: Context) {
        guard v.image !== image else { return }
        v.image = image
        if image?.images != nil { v.startAnimating() }
    }
}

/// Програє GIF покадрово (ImageIO декодує кадр перед показом), тож у пам'яті лише поточний кадр.
struct FaceAnimationView: UIViewRepresentable {
    let gif: Data

    final class Coordinator {
        var stopped = false
        var playing: Data?
        var token = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFill
        v.clipsToBounds = true
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }

    func updateUIView(_ v: UIImageView, context: Context) {
        let c = context.coordinator
        guard c.playing != gif else { return }
        c.playing = gif
        c.token += 1
        let token = c.token
        CGAnimateImageDataWithBlock(gif as CFData, nil) { [weak v] _, image, stop in
            // вигляд прибрали або дали інший GIF — зупиняємось
            guard let v, !c.stopped, c.token == token else { stop.pointee = true; return }
            v.image = UIImage(cgImage: image)
        }
    }

    static func dismantleUIView(_ v: UIImageView, coordinator: Coordinator) {
        coordinator.stopped = true
    }
}
