// SPDX-License-Identifier: MIT
// Пробні значення джерел для полотна редактора й зрозумілі назви джерел для вибору.

import Foundation
import FaceCompiler

enum SampleData {
    /// Значення для перегляду; `live` — поточний час і дата.
    static func value(_ source: String, live: Bool = false, demo: DemoValues? = nil) -> Int {
        let now = Date()
        let cal = Calendar.current
        let s = source
        let liveTime = live || demo?.realTime == true, liveDate = live || demo?.realDate == true
        var v: Int
        if s.hasPrefix("time") {
            let own = demo?.hm
            if s.contains("Hour") { v = liveTime ? cal.component(.hour, from: now) : own?.0 ?? 10; if s.contains("12") { v = v % 12 == 0 ? 12 : v % 12 } }
            else if s.contains("Minute") { v = liveTime ? cal.component(.minute, from: now) : own?.1 ?? 24 }
            else if s.contains("Second") { v = liveTime ? cal.component(.second, from: now) : 36 }
            else { v = 0 }
            if s.hasSuffix("High") { return v / 10 }
            if s.hasSuffix("Low") { return v % 10 }
            return v
        }
        if s.hasPrefix("date") {
            // своя дата: день тижня рахується з неї
            var day = 30, month = 5, year = 2026, week = 6 // браслет рахує з неділі: 0 — неділя, 6 — субота
            if liveDate {
                day = cal.component(.day, from: now); month = cal.component(.month, from: now); year = cal.component(.year, from: now)
                week = cal.component(.weekday, from: now) - 1
            } else if let t = demo?.dmy {
                day = t.0; month = t.1; year = t.2
                if let dt = cal.date(from: DateComponents(year: t.2, month: t.1, day: t.0)) { week = cal.component(.weekday, from: dt) - 1 }
            }
            if s.contains("Week") { return week }
            if s.contains("Year") { return year % (s.contains("Low") ? 100 : 10000) }
            if s.contains("Month") { v = month }
            else if s.contains("Day") { v = day }
            else { return 1 }
            if s.hasSuffix("High") { return v / 10 }
            if s.hasSuffix("Low") { return v % 10 }
            return v
        }
        if let own = demo?.values[s] { return own }
        let l = s.lowercased()
        // стани як у звичайному вигляді: «не турбувати» вимкнено, Bluetooth підключено
        if l.contains("disturb") { return 0 }
        if l.contains("bluetooth") { return 1 }
        if l.contains("step") { return l.contains("progress") ? 84 : 8412 }
        if l.contains("heart") { return 72 }
        if l.contains("battery") { return 80 }
        if l.contains("calorie") { return l.contains("progress") ? 46 : 320 }
        if l.contains("stand") { return 7 }
        if l.contains("sleep") { return 7 }
        if l.contains("oxygen") || l.contains("spo") { return 98 }
        if l.contains("pressure") || l.contains("stress") { return 32 }
        if l.contains("temperature") || l.contains("weather") { return 18 }
        if l.contains("distance") { return 6 }
        if l.contains("progress") { return 65 }
        return 42
    }

    /// Межі повзунка «Значення для перегляду»
    static func demoRange(_ source: String) -> ClosedRange<Int> {
        let l = source.lowercased()
        if l.contains("disturb") || l.contains("bluetooth") { return 0...1 }
        if l.contains("progress") || l.contains("percent") || l.contains("battery") || l.contains("stress") { return 0...100 }
        if l.contains("step") { return 0...30000 }
        if l.contains("heart") { return 30...220 }
        if l.contains("calorie") { return 0...2000 }
        if l.contains("oxygen") || l.contains("spo") { return 70...100 }
        if l.contains("temperature") || l.contains("weather") { return -30...45 }
        if l.contains("distance") { return 0...50 }
        if l.contains("stand") || l.contains("sleep") { return 0...12 }
        return 0...100
    }

    /// Назви джерел українською (решта показуються як є).
    static let titles: [String: String] = [
        "timeHour": "Година (24 год)", "timeHour12": "Година (12 год)", "timeMinute": "Хвилина", "timeSecond": "Секунда",
        "timeHourHigh": "Година, десятки", "timeHourLow": "Година, одиниці", "timeMinuteHigh": "Хвилина, десятки",
        "timeMinuteLow": "Хвилина, одиниці", "timeSecondHigh": "Секунда, десятки", "timeSecondLow": "Секунда, одиниці",
        "dateDay": "День", "dateMonth": "Місяць", "dateYear": "Рік", "dateWeek": "День тижня",
        "healthStepCount": "Кроки", "healthStepProgress": "Кроки, % мети", "healthHeartRate": "Пульс",
        "healthCalorieValue": "Калорії", "healthCalorieProgress": "Калорії, % мети", "healthBloodOxygen": "Кисень (SpO₂)",
        "healthStress": "Стрес", "healthStandCount": "Розминки", "healthSleepScore": "Сон",
        "systemStatusBattery": "Батарея", "systemStatusBluetooth": "Bluetooth",
        "weatherCurrentTemperature": "Температура", "weatherCurrentWeather": "Погода",
    ]

    static func title(_ source: String) -> String { titles[source].map(loc) ?? source }

    /// Група джерела за префіксом (time, date, health…; інакше other)
    static func groupOf(_ s: String) -> String {
        for p in ["time", "date", "health", "weather", "system", "app", "dualtime"] where s.hasPrefix(p) { return p }
        return "other"
    }

    /// Значок групи (SF Symbols)
    static func symbol(_ group: String) -> String {
        switch group {
        case "time": return "clock"
        case "date": return "calendar"
        case "health": return "heart"
        case "weather": return "cloud.sun"
        case "system": return "battery.75"
        case "app": return "square.grid.2x2"
        case "dualtime": return "globe"
        default: return "ellipsis.circle"
        }
    }

    struct Group: Identifiable {
        let id: String
        let title: String
        let sources: [String]
    }

    /// Усі джерела компілятора, згруповані за префіксом.
    static let groups: [Group] = {
        let names = FaceCatalog.sources.map { $0.0 }
        var seen = Set<String>()
        let unique = names.filter { seen.insert($0).inserted }
        let prefixes: [(String, String)] = [("time", "Час"), ("date", "Дата"), ("health", "Здоров'я"), ("weather", "Погода"),
                                            ("system", "Система"), ("app", "Застосунки")]
        var out: [Group] = []
        var rest = unique
        for (p, t) in prefixes {
            let g = unique.filter { $0.hasPrefix(p) }
            rest.removeAll { $0.hasPrefix(p) }
            if !g.isEmpty { out.append(Group(id: p, title: t, sources: g)) }
        }
        if !rest.isEmpty { out.append(Group(id: "other", title: "Інше", sources: rest)) }
        return out
    }()
}
