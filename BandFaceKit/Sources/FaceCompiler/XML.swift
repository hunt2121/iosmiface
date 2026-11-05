// SPDX-License-Identifier: MIT
// Мінімальний XML у стилі tinyxml2: розбір із номерами рядків і друк з відступом 4 пробіли.
// Значення атрибутів зберігаються як байти UTF-8 без перетворень (exe теж працює з сирими байтами).

final class XNode {
    let tag: String
    var attrs: [(String, [UInt8])] = []
    var kids: [XNode] = []
    var line: Int = 0
    var isComment = false

    init(_ tag: String, line: Int = 0) { self.tag = tag; self.line = line }

    static func comment(_ text: String) -> XNode { let e = XNode(text); e.isComment = true; return e }

    // доступ (tinyxml2 Attribute(name))
    func raw(_ k: String) -> [UInt8]? { attrs.first(where: { $0.0 == k })?.1 }
    func string(_ k: String) -> String? { raw(k).map(str) }
    func has(_ k: String) -> Bool { raw(k) != nil }
    /// IntAttribute(name, default)
    func int(_ k: String, _ d: Int32 = 0) -> Int32 { toInt(raw(k)) ?? d }
    /// BoolAttribute(name, default)
    func bool(_ k: String, _ d: Bool = false) -> Bool { toBool(raw(k)) ?? d }
    var elements: [XNode] { kids.filter { !$0.isComment } }
    func first(_ tag: String) -> XNode? { kids.first { !$0.isComment && $0.tag == tag } }
    func all(_ tag: String) -> [XNode] { kids.filter { !$0.isComment && $0.tag == tag } }

    // побудова
    @discardableResult func add(_ tag: String) -> XNode { let e = XNode(tag); kids.append(e); return e }
    @discardableResult func set(_ k: String, _ v: [UInt8]) -> XNode {
        if let i = attrs.firstIndex(where: { $0.0 == k }) { attrs[i].1 = v } else { attrs.append((k, v)) }
        return self
    }
    @discardableResult func set(_ k: String, _ v: String) -> XNode { set(k, Array(v.utf8)) }
    @discardableResult func set(_ k: String, int v: Int) -> XNode { set(k, String(v)) }
    @discardableResult func set(_ k: String, uint v: UInt32) -> XNode { set(k, String(v)) }
    @discardableResult func set(_ k: String, bool v: Bool) -> XNode { set(k, v ? "true" : "false") }
}

enum XML {
    // MARK: Друк (XMLPrinter)

    static func escape(_ v: [UInt8], into out: inout [UInt8]) {
        for c in v {
            switch c {
            case 0x26: out += Array("&amp;".utf8)
            case 0x3C: out += Array("&lt;".utf8)
            case 0x3E: out += Array("&gt;".utf8)
            case 0x22: out += Array("&quot;".utf8)
            case 0x27: out += Array("&apos;".utf8)
            default: out.append(c)
            }
        }
    }

    static func print(_ root: XNode) -> [UInt8] {
        var out = Array("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n".utf8)
        func write(_ e: XNode, _ depth: Int) {
            let ind = [UInt8](repeating: 0x20, count: depth * 4)
            out += ind
            if e.isComment { out += Array("<!--\(e.tag)-->\n".utf8); return }
            out.append(0x3C); out += Array(e.tag.utf8)
            for (k, v) in e.attrs {
                out.append(0x20); out += Array(k.utf8); out += [0x3D, 0x22]
                escape(v, into: &out); out.append(0x22)
            }
            if e.kids.isEmpty { out += [0x2F, 0x3E, 0x0A]; return }
            out += [0x3E, 0x0A]
            for k in e.kids { write(k, depth + 1) }
            out += ind; out += [0x3C, 0x2F]; out += Array(e.tag.utf8); out += [0x3E, 0x0A]
        }
        write(root, 0)
        return out
    }

    // MARK: Розбір

    struct ParseError: Error { let message: String }

    /// Документ -> корінь (перший елемент верхнього рівня).
    static func parse(_ data: [UInt8]) throws -> XNode? {
        var p = 0, line = 1
        let n = data.count
        if n >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF { p = 3 }
        func fail(_ m: String) -> ParseError { ParseError(message: "\(m) Line number=\(line)") }
        func adv(_ k: Int = 1) { for _ in 0..<k { if p < n { if data[p] == 0x0A { line += 1 }; p += 1 } } }
        func starts(_ s: String) -> Bool {
            let b = Array(s.utf8)
            return p + b.count <= n && Array(data[p..<(p + b.count)]) == b
        }
        func skipWS() { while p < n, [0x20, 0x09, 0x0A, 0x0D].contains(data[p]) { adv() } }
        func skipUntil(_ s: String) throws {
            while p < n, !starts(s) { adv() }
            guard p < n else { throw fail("Error=XML_ERROR_PARSING") }
            adv(s.utf8.count)
        }
        func isNameChar(_ c: UInt8) -> Bool {
            c >= 0x80 || (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
                || c == 0x5F || c == 0x3A || c == 0x2E || c == 0x2D
        }
        func name() -> String {
            let s = p
            while p < n, isNameChar(data[p]) { p += 1 }
            return String(decoding: data[s..<p], as: UTF8.self)
        }
        func unescape(_ v: ArraySlice<UInt8>) -> [UInt8] {
            var out: [UInt8] = []
            var i = v.startIndex
            while i < v.endIndex {
                if v[i] == 0x26, let semi = v[i...].firstIndex(of: 0x3B), semi - i <= 12 {
                    let ent = String(decoding: v[(i + 1)..<semi], as: UTF8.self)
                    var rep: [UInt8]?
                    switch ent {
                    case "amp": rep = [0x26]; case "lt": rep = [0x3C]; case "gt": rep = [0x3E]
                    case "quot": rep = [0x22]; case "apos": rep = [0x27]
                    default:
                        if ent.hasPrefix("#x") || ent.hasPrefix("#X"), let u = UInt32(ent.dropFirst(2), radix: 16), let sc = Unicode.Scalar(u) {
                            rep = Array(String(Character(sc)).utf8)
                        } else if ent.hasPrefix("#"), let u = UInt32(ent.dropFirst()), let sc = Unicode.Scalar(u) {
                            rep = Array(String(Character(sc)).utf8)
                        }
                    }
                    if let rep { out += rep; i = semi + 1; continue }
                }
                // нормалізація кінців рядків як у tinyxml2: CR LF -> LF, CR -> LF
                if v[i] == 0x0D {
                    out.append(0x0A); i += 1
                    if i < v.endIndex, v[i] == 0x0A { i += 1 }
                    continue
                }
                out.append(v[i]); i += 1
            }
            return out
        }
        var root: XNode?
        var stack: [XNode] = []
        while true {
            // текст між тегами ігнорується
            while p < n, data[p] != 0x3C { adv() }
            if p >= n { break }
            if starts("<?") { try skipUntil("?>"); continue }
            if starts("<!--") {
                adv(4); let s = p
                while p < n, !starts("-->") { adv() }
                guard p < n else { throw fail("Error=XML_ERROR_PARSING_COMMENT") }
                let c = XNode.comment(String(decoding: data[s..<p], as: UTF8.self))
                stack.last?.kids.append(c)
                adv(3); continue
            }
            if starts("<![CDATA[") { try skipUntil("]]>"); continue }
            if starts("<!") { try skipUntil(">"); continue }
            if starts("</") {
                adv(2)
                let nm = name(); skipWS()
                guard p < n, data[p] == 0x3E else { throw fail("Error=XML_ERROR_PARSING_ELEMENT") }
                adv()
                guard let top = stack.popLast(), top.tag == nm else { throw fail("Error=XML_ERROR_MISMATCHED_ELEMENT") }
                continue
            }
            adv()
            let el = XNode(name(), line: line)
            guard !el.tag.isEmpty else { throw fail("Error=XML_ERROR_PARSING_ELEMENT") }
            while true {
                skipWS()
                guard p < n else { throw fail("Error=XML_ERROR_PARSING_ELEMENT") }
                if data[p] == 0x2F {
                    adv(); guard p < n, data[p] == 0x3E else { throw fail("Error=XML_ERROR_PARSING_ELEMENT") }
                    adv()
                    if let top = stack.last { top.kids.append(el) } else if root == nil { root = el }
                    break
                }
                if data[p] == 0x3E {
                    adv()
                    if let top = stack.last { top.kids.append(el) } else if root == nil { root = el }
                    stack.append(el)
                    break
                }
                let k = name()
                guard !k.isEmpty else { throw fail("Error=XML_ERROR_PARSING_ATTRIBUTE") }
                skipWS()
                guard p < n, data[p] == 0x3D else { throw fail("Error=XML_ERROR_PARSING_ATTRIBUTE") }
                adv(); skipWS()
                guard p < n, data[p] == 0x22 || data[p] == 0x27 else { throw fail("Error=XML_ERROR_PARSING_ATTRIBUTE") }
                let q = data[p]; adv()
                let s = p
                while p < n, data[p] != q { adv() }
                guard p < n else { throw fail("Error=XML_ERROR_PARSING_ATTRIBUTE") }
                let v = unescape(data[s..<p]); adv()
                if el.raw(k) != nil { throw fail("Error=XML_ERROR_PARSING_ATTRIBUTE") }
                el.attrs.append((k, v))
            }
        }
        guard stack.isEmpty else { throw fail("Error=XML_ERROR_MISMATCHED_ELEMENT") }
        return root
    }
}
