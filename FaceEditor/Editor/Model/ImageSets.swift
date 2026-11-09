// SPDX-License-Identifier: MIT
// Набори картинок (ImageArray) усередині циферблата: один набір можуть брати кілька елементів
// (години й хвилини, основний екран і AOD). Тут — пошук, спільне використання і відокремлення.

import Foundation
import FaceCompiler

enum ImageSets {
    // MARK: Покажчик для інтерфейсу — один прохід по циферблату на кожну зміну (а не перебір для кожного набору)

    struct Index {
        /// хто бере ресурс за іменем (ref="@ім'я")
        var users: [String: [XNode]] = [:]
        /// шари кожного ресурсу: (екран, шар)
        var layouts: [ObjectIdentifier: [(Int, XNode)]] = [:]
    }
    private static var cache: (ObjectIdentifier, Int, Int, Index)?

    static func index(_ p: FaceProject) -> Index {
        let key = ObjectIdentifier(p.root)
        let n = p.resources.kids.count
        if let c = cache, c.0 == key, c.1 == p.revision, c.2 == n { return c.3 }
        var ix = Index()
        var byName: [String: XNode] = [:]
        for e in p.resources.elements {
            if let nm = e.string("name"), byName[nm] == nil { byName[nm] = e }
            if let r = e.string("ref"), r.hasPrefix("@") { ix.users[String(r.dropFirst()), default: []].append(e) }
        }
        for t in 0..<p.themes.count {
            for l in p.layouts(t) {
                guard let r = l.string("ref"), r.hasPrefix("@"), let res = byName[String(r.dropFirst())] else { continue }
                // обгортка «дія при натисканні» — шар показує те, що всередині
                let shown = ElementFactory.tapInner(p, res) ?? res
                ix.layouts[ObjectIdentifier(shown), default: []].append((t, l))
            }
        }
        cache = (key, p.revision, n, ix)
        return ix
    }

    /// Хто бере набір — з покажчика (для показу; у змінах — users)
    static func usersFast(_ p: FaceProject, _ arr: XNode) -> [XNode] {
        (index(p).users[arr.string("name") ?? ""] ?? []).filter { $0 !== arr }
    }

    /// Скільки шарів показують елемент (усі екрани) — з покажчика
    static func layoutCount(_ p: FaceProject, _ res: XNode) -> Int { index(p).layouts[ObjectIdentifier(res)]?.count ?? 0 }

    /// Набір, який показує елемент (лише масив картинок; одна картинка — не набір)
    static func setOf(_ p: FaceProject, _ res: XNode?) -> XNode? {
        guard let res, res.tag != "ImageArray", let r = p.resource(ref: res.string("ref")), r.tag == "ImageArray" else { return nil }
        return r
    }

    static func count(_ arr: XNode?) -> Int { arr?.all("Image").count ?? 0 }

    /// Елементи (ресурси), що беруть цей набір
    static func users(_ p: FaceProject, _ arr: XNode) -> [XNode] {
        let key = "@" + (arr.string("name") ?? "")
        return p.resources.elements.filter { $0 !== arr && $0.string("ref") == key }
    }

    /// Скільки місць показує набір: кожен шар кожного елемента на кожному екрані
    static func uses(_ p: FaceProject, _ arr: XNode) -> Int {
        let ix = index(p)
        return usersFast(p, arr).reduce(0) { $0 + max(1, ix.layouts[ObjectIdentifier($1)]?.count ?? 0) }
    }

    /// Набір підходить елементу: для числа — 10 цифр, для інших — стільки ж картинок, скільки зараз
    static func fits(_ p: FaceProject, _ res: XNode, _ arr: XNode) -> Bool {
        if res.tag == "DataItemImageNumber" { return count(arr) >= 10 }
        guard let cur = setOf(p, res) else { return false }
        return count(arr) == count(cur)
    }

    /// Усі набори циферблата, якими хтось користується
    static func all(_ p: FaceProject) -> [XNode] {
        p.resources.elements.filter { $0.tag == "ImageArray" && !usersFast(p, $0).isEmpty }
    }

    /// Набори для нового числа (10 цифр і більше)
    static func forDigits(_ p: FaceProject) -> [XNode] {
        all(p).filter { count($0) >= 10 && usersFast(p, $0).contains { $0.tag == "DataItemImageNumber" } }
    }

    /// Набори для нових значків за значенням (дні тижня — 7, місяці — 12…)
    static func forValues(_ p: FaceProject, count n: Int) -> [XNode] {
        all(p).filter { count($0) == n && usersFast(p, $0).contains { $0.tag == "DataItemImageValues" } }
    }

    /// Хто показує набір (крім шару except): «Години, Хвилини (AOD)»
    static func usersTitle(_ p: FaceProject, _ arr: XNode, except: XNode? = nil) -> String {
        var names: [String] = []
        let ix = index(p)
        for u in usersFast(p, arr) {
            for (t, l) in ix.layouts[ObjectIdentifier(u)] ?? [] where l !== except {
                let n = u.string("source").map { SampleData.title($0) } ?? ElementKind.of(u, in: p).title
                let s = n + (t == 1 ? " (AOD)" : "")
                if !names.contains(s) { names.append(s) }
            }
        }
        return names.joined(separator: ", ")
    }

    /// Елемент бере інший набір; старий прибирається, якщо більше нікому не потрібен.
    /// Параметри малювання беруться від іншого елемента цього набору.
    static func use(_ p: FaceProject, _ res: XNode, _ arr: XNode) {
        let old = res.string("ref")
        let key = "@" + (arr.string("name") ?? "")
        guard old != key else { return }
        res.set("ref", key)
        let nm = res.string("name") ?? ""
        if let donor = users(p, arr).compactMap({ $0.string("name") }).first(where: { $0 != nm && p.meta.generators[$0] != nil }),
           var g = p.meta.generators[donor] {
            g.unit = p.meta.generators[nm]?.unit ?? ""
            p.meta.generators[nm] = g
        } else {
            p.meta.generators[nm] = nil
        }
        if let old { ElementFactory.collect(p, ref: old) }
        ColorVariants.refresh(p, element: res)
    }

    /// Копія набору з власними файлами; повертає нову назву
    static func copySet(_ p: FaceProject, _ arr: XNode) -> String {
        let name = p.uniqueName(arr.string("name") ?? "images")
        let copy = XNode("ImageArray")
        for (k, v) in arr.attrs { copy.set(k, v) }
        copy.set("name", name)
        for (i, im) in arr.all("Image").enumerated() {
            let src = "\(name)/\(i).png"
            if let s = im.string("src"), let d = p.file(s) { p.setFile(src, d) }
            copy.add("Image").set("src", src)
        }
        p.resources.kids.append(copy)
        return name
    }

    /// Картинки спільні: елемент показано на двох екранах або набір бере ще хтось
    static func isShared(_ p: FaceProject, _ res: XNode) -> Bool {
        if layoutCount(p, res) > 1 { return true }
        guard let arr = setOf(p, res) else { return false }
        return usersFast(p, arr).count > 1
    }

    /// Окремі картинки для цього шару: якщо елемент показано на двох екранах — шар отримує свою копію елемента,
    /// і набір копіюється.
    static func detach(_ p: FaceProject, layout: XNode) {
        guard var res = p.element(of: layout) else { return }
        if ElementFactory.layouts(of: res, in: p).count > 1 {
            let copy = res.copy()
            let old = res.string("name") ?? "copy"
            let nm = p.uniqueName(old)
            copy.set("name", nm)
            p.resources.kids.append(copy)
            if let g = p.meta.generators[old] { p.meta.generators[nm] = g }
            if p.meta.colorFollow.contains(old) { p.meta.colorFollow.insert(nm) }
            layout.set("ref", "@" + nm)
            res = copy
        }
        if let arr = setOf(p, res), users(p, arr).count > 1 {
            res.set("ref", "@" + copySet(p, arr))
            ColorVariants.refresh(p, element: res)
        }
    }

    /// Замінити всі картинки набору (усім, хто його бере). Розмір — як у першої нової картинки.
    static func replaceAll(_ p: FaceProject, _ arr: XNode, _ images: [RGBAImage]) {
        guard let f0 = images.first else { return }
        let slots = arr.all("Image")
        for i in 0..<min(slots.count, images.count) {
            let src = slots[i].string("src") ?? "\(arr.string("name") ?? "images")/\(i).png"
            p.setFile(src, ElementFactory.fit(images[i], w: f0.w, h: f0.h).png)
            slots[i].set("src", src)
        }
        arr.set("format", "indexed8")
        // свої картинки — параметри малювання шрифтом більше не діють
        for u in users(p, arr) {
            p.meta.generators[u.string("name") ?? ""] = nil
            ColorVariants.refresh(p, element: u)
        }
    }
}
