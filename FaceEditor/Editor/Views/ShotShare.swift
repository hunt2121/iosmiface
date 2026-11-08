// SPDX-License-Identifier: MIT
// Знімок циферблата у стандартному вікні «Поділитися»: передаємо саму картинку (UIImage) — тоді iOS показує
// «Зберегти зображення» (Фото), а в шапці — назву циферблата й мініатюру. Вікно відкривається звичайним
// показом UIKit (як в інших застосунках), а не всередині SwiftUI-аркуша.

import UIKit
import LinkPresentation

final class ShotShare: NSObject, UIActivityItemSource {
    let image: UIImage
    let title: String

    init(image: UIImage, title: String) {
        self.image = image
        self.title = title
    }

    func activityViewControllerPlaceholderItem(_ c: UIActivityViewController) -> Any { image }
    func activityViewController(_ c: UIActivityViewController, itemForActivityType t: UIActivity.ActivityType?) -> Any? { image }
    func activityViewController(_ c: UIActivityViewController, subjectForActivityType t: UIActivity.ActivityType?) -> String { title }

    func activityViewControllerLinkMetadata(_ c: UIActivityViewController) -> LPLinkMetadata? {
        let m = LPLinkMetadata()
        m.title = title
        let p = NSItemProvider(object: image)
        m.imageProvider = p
        m.iconProvider = p
        return m
    }

    @MainActor static func present(_ item: ShotShare) { present(items: [item]) }

    /// Будь-що (файл .bin, теку проєкту, картинку) — у стандартному вікні «Поділитися» поверх поточного екрана
    @MainActor static func present(items: [Any]) {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        vc.popoverPresentationController?.sourceView = top.view
        top.present(vc, animated: true)
    }
}
