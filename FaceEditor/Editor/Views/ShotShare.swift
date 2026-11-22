// SPDX-License-Identifier: MIT
// Знімок циферблата у стандартному вікні «Поділитися»: для Фото й «Скопіювати» — сама картинка (UIImage), тоді iOS показує
// «Зберегти зображення», а в шапці — назву циферблата й мініатюру; іншим застосункам (Telegram тощо) — файл PNG:
// з картинкою UIImage Telegram заповнював прозорі кути сміттям (смуги), файл він перетворює сам, як звичайне фото. Вікно відкривається звичайним
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
    func activityViewController(_ c: UIActivityViewController, itemForActivityType t: UIActivity.ActivityType?) -> Any? {
        if t == .saveToCameraRoll || t == .copyToPasteboard { return image }
        return file ?? image
    }

    /// PNG у тимчасовій теці з назвою циферблата
    private lazy var file: URL? = {
        guard let data = image.pngData() else { return nil }
        let name = title.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Shot", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent((name.isEmpty ? "Face" : name) + ".png")
        return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
    }()
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
