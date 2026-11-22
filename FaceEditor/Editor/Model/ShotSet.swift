// SPDX-License-Identifier: MIT
// «Набір знімків»: кілька екранів циферблата (стилі, кольори, AOD, стани) на одній оформленій картинці.
// Формат спільний з Windows (поле shots у параметрах редактора).

import Foundation
import FaceCompiler

/// Один екран набору
struct ShotScreen: Codable, Equatable, Identifiable {
    var id = UUID()
    /// Номер стилю з 0 (за порядком стилів, без AOD)
    var style = 0
    /// «Завжди на екрані» цього стилю
    var aod = false
    /// Кольоровий варіант: 0 — основний
    var color = 0
    /// Свій підпис; порожньо — «Стиль 1 · Колір 2»
    var name = ""
    /// Стани на цьому екрані: Bluetooth від'єднано, заряд 15 % (обидва — два окремі екрани)
    var bluetooth = false
    var battery = false
    /// Віджети в слотах: назва слота → номер віджета (без запису — як у редакторі)
    var widgets: [String: Int] = [:]

    init(style: Int = 0, aod: Bool = false, color: Int = 0) { self.style = style; self.aod = aod; self.color = color }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        style = (try? c.decodeIfPresent(Int.self, forKey: .style)) ?? 0
        aod = (try? c.decodeIfPresent(Bool.self, forKey: .aod)) ?? false
        color = (try? c.decodeIfPresent(Int.self, forKey: .color)) ?? 0
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        bluetooth = (try? c.decodeIfPresent(Bool.self, forKey: .bluetooth)) ?? false
        battery = (try? c.decodeIfPresent(Bool.self, forKey: .battery)) ?? false
        widgets = (try? c.decodeIfPresent([String: Int].self, forKey: .widgets)) ?? [:]
    }
}

struct ShotSet: Codable, Equatable {
    enum Format: String, Codable, CaseIterable { case auto, square, story, wide }
    enum Background: String, CaseIterable { case dark, black, white, light, blue, face }

    var screens: [ShotScreen] = []
    var format = Format.auto
    /// 0 — великі, 1 — середні, 2 — малі
    var size = 1
    /// Рамка «Браслет» замість капсули
    var band = false
    /// Свій час на екранах "HH:mm"; nil — як у циферблаті
    var time: String?
    /// Тло: dark, black, white, light, blue, face або свій колір "#RRGGBB"
    var background = Background.dark.rawValue
    /// Тексти; nil — автоматичні (назва циферблата, «Циферблат для …», «2 стилі · 3 кольори»), "" — без рядка
    var title: String?
    var above: String?
    var below: String?
    var rounded = true
    var captions = true
    var shadow = true
    var credit = false
    var remember = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        screens = (try? c.decodeIfPresent([ShotScreen].self, forKey: .screens)) ?? []
        format = (try? c.decodeIfPresent(Format.self, forKey: .format)) ?? .auto
        size = (try? c.decodeIfPresent(Int.self, forKey: .size)) ?? 1
        band = (try? c.decodeIfPresent(Bool.self, forKey: .band)) ?? false
        time = try? c.decodeIfPresent(String.self, forKey: .time)
        background = (try? c.decodeIfPresent(String.self, forKey: .background)) ?? Background.dark.rawValue
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        above = try? c.decodeIfPresent(String.self, forKey: .above)
        below = try? c.decodeIfPresent(String.self, forKey: .below)
        rounded = (try? c.decodeIfPresent(Bool.self, forKey: .rounded)) ?? true
        captions = (try? c.decodeIfPresent(Bool.self, forKey: .captions)) ?? true
        shadow = (try? c.decodeIfPresent(Bool.self, forKey: .shadow)) ?? true
        credit = (try? c.decodeIfPresent(Bool.self, forKey: .credit)) ?? false
        remember = (try? c.decodeIfPresent(Bool.self, forKey: .remember)) ?? true
    }

    /// Новий набір: поточний стиль у поточному кольорі
    static func start(style: Int, color: Int) -> ShotSet {
        var s = ShotSet()
        s.screens = [ShotScreen(style: style, color: color)]
        return s
    }

    /// Скільки екранів буде на картинці: стан — на самому екрані, обидва стани — два екрани
    var count: Int { screens.reduce(0) { $0 + ($1.bluetooth && $1.battery ? 2 : 1) } }
}

extension FaceProject {
    /// Слоти теми (місця, де віджет вибирають на браслеті) у порядку шарів
    func slots(_ theme: Int) -> [XNode] {
        layouts(theme).compactMap { resource(ref: $0.string("ref")) }.filter { $0.tag == "Slot" }
    }

    /// Є елемент, що показує стан Bluetooth / заряд батареї (тоді є сенс у знімках із цими станами)
    func usesSource(_ key: String) -> Bool {
        func scan(_ n: XNode) -> Bool {
            if let s = n.string("source"), s.lowercased().contains(key) { return true }
            return n.kids.contains { scan($0) }
        }
        return scan(root)
    }
}
