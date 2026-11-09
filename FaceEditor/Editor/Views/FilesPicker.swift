// SPDX-License-Identifier: MIT
// Вибір кількох картинок у «Файлах» — стандартним вікном UIKit поверх поточного екрана
// (не конфліктує з іншими .fileImporter у тому самому інспекторі).

import UIKit
import UniformTypeIdentifiers

final class FilesPicker: NSObject, UIDocumentPickerDelegate {
    private let done: ([URL]) -> Void
    private static var current: FilesPicker?

    private init(_ done: @escaping ([URL]) -> Void) { self.done = done }

    /// Картинки за назвою файла (як кадри) — у completion уже відсортовані
    @MainActor static func pickImages(_ completion: @escaping ([URL]) -> Void) {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: [.png, .jpeg, .image], asCopy: true)
        vc.allowsMultipleSelection = true
        let p = FilesPicker(completion)
        current = p
        vc.delegate = p
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController else { return }
        var top = root
        while let t = top.presentedViewController { top = t }
        top.present(vc, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let sorted = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        done(sorted)
        FilesPicker.current = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { FilesPicker.current = nil }
}
