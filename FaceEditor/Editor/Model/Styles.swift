// SPDX-License-Identifier: MIT
// Стилі циферблата: кожен стиль — тема (екран), за якою може йти її власний «Завжди на екрані» (тема type="AOD").
// Порядок тем у файлі: стиль 1, [AOD стилю 1], стиль 2, [AOD стилю 2]… — так його читають браслет, Studio й BandFace.

import Foundation
import FaceCompiler

extension FaceProject {
    /// Старі файли без типів тем: дві теми — основна й AOD
    private var legacyAod: Bool {
        let t = themes
        return t.count == 2 && t.allSatisfy { !$0.has("type") }
    }

    /// Тема — «Завжди на екрані» якогось стилю
    func isAOD(_ i: Int) -> Bool {
        guard i > 0, let t = theme(i) else { return false }
        return t.string("type") == "AOD" || (legacyAod && i == 1)
    }

    /// Номери тем-стилів (без AOD) у порядку файла
    var styleThemes: [Int] { themes.indices.filter { !isAOD($0) } }

    /// Усі теми «Завжди на екрані»
    var aodThemes: [Int] { themes.indices.filter { isAOD($0) } }

    /// AOD стилю (тема одразу за ним) або nil
    func aodTheme(forStyle s: Int) -> Int? { isAOD(s + 1) ? s + 1 : nil }

    /// Стиль, до якого належить тема (для AOD — стиль перед ним)
    func styleTheme(of i: Int) -> Int {
        var j = i
        while j > 0 && isAOD(j) { j -= 1 }
        return j
    }

    /// Номер стилю для людей: 1, 2, 3…
    func styleNumber(of i: Int) -> Int { (styleThemes.firstIndex(of: styleTheme(of: i)) ?? 0) + 1 }

    /// Назва стилю в меню: «Стиль 2 · Спорт»
    func styleTitle(_ s: Int) -> String {
        let n = String(format: loc("Стиль %d"), styleNumber(of: s))
        let name = theme(s)?.string("name") ?? ""
        return name.isEmpty ? n : n + " · " + name
    }
}

extension ElementFactory {
    /// Новий стиль у кінці. copyOf — копія шарів і кольору фону стилю: шари посилаються на ті самі ресурси,
    /// тож жодна картинка не дублюється. Повертає номер нової теми.
    @discardableResult
    static func addStyle(_ p: FaceProject, copyOf src: Int?) -> Int {
        let t: XNode
        if let src, let st = p.theme(src) {
            t = st.copy()
            t.remove("preview")           // превʼю для браслета малюється заново під час збирання
        } else {
            t = XNode("Theme")
            t.set("bgColor", p.theme(0)?.string("bgColor") ?? "#000000")
        }
        t.set("type", "normal").set("name", "")
        let last = p.root.kids.lastIndex { $0.tag == "Theme" }.map { $0 + 1 } ?? p.root.kids.count
        p.root.kids.insert(t, at: last)
        return p.themes.count - 1
    }

    /// «Завжди на екрані» для стилю — одразу після нього; спершу там лише цифри часу стилю (ті самі ресурси).
    /// Повертає номер теми AOD.
    @discardableResult
    static func addAod(_ p: FaceProject, style s: Int) -> Int {
        if let a = p.aodTheme(forStyle: s) { return a }
        guard let st = p.theme(s) else { return s }
        let t = XNode("Theme")
        t.set("type", "AOD").set("name", "").set("bgColor", "#000000")
        for l in p.layouts(s) where ElementKind.of(p.element(of: l)) == .digits { t.kids.append(l.copy()) }
        let at = (p.root.kids.firstIndex { $0 === st } ?? p.root.kids.count - 1) + 1
        p.root.kids.insert(t, at: at)
        return s + 1
    }

    /// Видаляє стиль разом з його AOD (останній стиль лишається завжди)
    static func deleteStyle(_ p: FaceProject, style s: Int) {
        guard p.styleThemes.count > 1, !p.isAOD(s) else { return }
        if let a = p.aodTheme(forStyle: s) { deleteTheme(p, index: a) }
        deleteTheme(p, index: s)
    }
}
