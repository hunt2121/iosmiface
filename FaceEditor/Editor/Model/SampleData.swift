// SPDX-License-Identifier: MIT
// Пробні значення джерел для полотна редактора й зрозумілі назви джерел для вибору.

import Foundation
import FaceCompiler

enum SampleData {
    /// Значення для перегляду; `live` — поточний час і дата.
    static func value(_ source: String, live: Bool = false) -> Int {
        let now = Date()
        let cal = Calendar.current
        let s = source
        func time(_ c: Calendar.Component, _ fallback: Int) -> Int { live ? cal.component(c, from: now) : fallback }
        var v: Int
        if s.hasPrefix("time") {
            if s.contains("Hour") { v = time(.hour, 10); if s.contains("12") { v = v % 12 == 0 ? 12 : v % 12 } }
            else if s.contains("Minute") { v = time(.minute, 24) }
            else if s.contains("Second") { v = time(.second, 36) }
            else { v = 0 }
            if s.hasSuffix("High") { return v / 10 }
            if s.hasSuffix("Low") { return v % 10 }
            return v
        }
        if s.hasPrefix("date") {
            if s.contains("Week") { return (time(.weekday, 6) + 5) % 7 }
            if s.contains("Year") { return time(.year, 2026) % (s.contains("Low") ? 100 : 10000) }
            if s.contains("Month") { v = time(.month, 5) }
            else if s.contains("Day") { v = time(.day, 30) }
            else { return 1 }
            if s.hasSuffix("High") { return v / 10 }
            if s.hasSuffix("Low") { return v % 10 }
            return v
        }
        let l = s.lowercased()
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

    static func title(_ source: String) -> String { titles[source] ?? source }

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
