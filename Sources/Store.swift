import SwiftUI
import UIKit
import BandFaceKit

/// Циферблат у магазині. Поки каталог локальний: файли лежать у застосунку.
/// Одне зображення в картці циферблата.
struct FacePreview: Identifiable {
    let id = UUID()
    let title: String
    let image: UIImage?
}

struct StoreFace: Identifiable {
    let id: String          // ID циферблата з файла
    let name: String
    let kind: String        // «Цифровий», «Гумор» — для фільтра
    let version: Int        // версія в каталозі; більша за встановлену — з'являється «Оновити»
    let about: String
    let price: String?      // nil — безкоштовний
    let face: FaceFile
    let preview: UIImage?
    var bands: [Int] = [10]   // підтримувані моделі Smart Band
    var previews: [FacePreview] = []   // зображення в картці (Always On додамо, коли буде справжній скріншот)

    var isFree: Bool { price == nil }
    var sizeKB: Int { face.size / 1024 }
    var bandsText: String { bands.map { "Band \($0)" }.joined(separator: ", ") }
    var meta: String { "\(kind) · \(sizeKB) KB" }
    var added: Date?   // коли з'явився в магазині
    /// Додано за останні 28 днів
    var isNew: Bool {
        guard let added else { return false }
        return Date().timeIntervalSince(added) < 28 * 24 * 3600
    }
}

enum StoreCatalog {
    private struct Entry {
        let resource: String
        let name: String
        let kind: String
        let version: Int
        let about: String
        let added: String   // дата додавання в магазин, «рррр-мм-дд»
    }

    private static let entries = [
        Entry(resource: "BigWatch_UA", name: "BigWatch", kind: "Цифровий", version: 1,
              about: "Великий цифровий час на весь екран. Знизу дата та кількість кроків.",
              added: "2026-10-31"),
        Entry(resource: "WhatTime_UA", name: "WhatTime", kind: "Гумор", version: 1,
              about: "Цифровий час, дата та кроки на тлі відомого коміксу.",
              added: "2026-10-31")
    ]

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Каталог читається з файлів один раз за запуск.
    static let cached: [StoreFace] = load()

    private static func load() -> [StoreFace] {
        entries.compactMap { e in
            guard let url = Bundle.main.url(forResource: e.resource, withExtension: "bin"),
                  let data = try? Data(contentsOf: url),
                  let face = try? FaceFile(data: data) else { return nil }
            // Зменшуємо превью один раз під розмір на екрані (3x), щоб прокрутка й анімації не витрачали час на великі зображення
            let full = (try? face.decodePreview()?.makeCGImage()).map(UIImage.init(cgImage:))
            let image = full.map { $0.preparingThumbnail(of: CGSize(width: 330, height: 780)) ?? $0 }
            var item = StoreFace(id: face.id, name: e.name, kind: e.kind, version: e.version,
                                 about: e.about, price: nil, face: face, preview: image)
            item.added = dayFormatter.date(from: e.added)
            item.previews = [
                FacePreview(title: String(localized: "Звичайний"), image: image)
            ]
            return item
        }
    }
}

/// Записи про встановлені циферблати: «ID=версія», через кому.
enum InstalledFaces {
    static func parse(_ raw: String) -> [String: Int] {
        var map: [String: Int] = [:]
        for part in raw.split(separator: ",") {
            let pair = part.split(separator: "=")
            if pair.count == 2, let v = Int(pair[1]) { map[String(pair[0])] = v }
            else if pair.count == 1 { map[String(pair[0])] = 1 } // старий запис без версії
        }
        return map
    }

    static func encode(_ map: [String: Int]) -> String {
        map.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }
}

/// Передогляд циферблата в капсулі з рамкою ззовні, як корпус браслета.
/// Той самий вигляд на вкладці «Циферблати», в магазині й на сторінці циферблата.
struct FaceCapsule: View {
    let image: UIImage?
    /// Циферблат зараз на екрані браслета — рамка зелена
    var active = false

    var body: some View {
        ZStack {
            Capsule(style: .continuous).fill(Color.black)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image("TabWatch").resizable().scaledToFit()
                    .frame(width: 30)
                    .foregroundStyle(Color(white: 0.4))
            }
        }
        .frame(width: 96, height: 236)
        .clipShape(Capsule(style: .continuous))
        .padding(3)
        .background(Capsule(style: .continuous).fill(active ? Color.okIcon : Color.gray.opacity(0.45)))
    }
}

/// Стан кнопки циферблата.
enum StoreAction {
    case install, update, installed, installing
}

/// Сторінка магазину. Equatable: SwiftUI перемальовує її лише при зміні даних,
/// а не при кожному оновленні головного екрана.
struct StoreView: View, Equatable {
    static func == (a: StoreView, b: StoreView) -> Bool {
        a.faces.map(\.id) == b.faces.map(\.id) && a.installed == b.installed
            && a.installingID == b.installingID && a.busy == b.busy
            && a.progress == b.progress && a.progressText == b.progressText
            && a.activeID == b.activeID && a.otherFaces == b.otherFaces
            && a.deviceName == b.deviceName && a.deviceInfo == b.deviceInfo
    }

    let faces: [StoreFace]
    let installed: [String: Int]
    let installingID: String?
    let busy: Bool
    let progress: Double
    let progressText: String
    let onInstall: (StoreFace) -> Void
    let onRefresh: () async -> Void
    /// Який циферблат зараз на екрані пристрою
    var activeID: String? = nil
    /// Вибрати / видалити циферблат магазину (nil — успіх, інакше текст помилки)
    var onActivate: (StoreFace) async -> String? = { _ in nil }
    var onDelete: (StoreFace) async -> String? = { _ in nil }
    /// Меню «Встановлено»: «З файлу» — до вибору файлу на вкладці «Циферблати»
    var onPickFile: () -> Void = {}
    /// Циферблати на пристрої не з магазину
    var otherFaces: [BandFace] = []
    /// Вибрати / видалити будь-який циферблат за ID (id, назва, видалити?)
    var onBandAction: (String, String, Bool) async -> String? = { _, _, _ in nil }
    /// Назва пристрою або «Пристрій не підключено»; стан батареї
    var deviceName: String = ""
    var deviceInfo = BandInfo()

    @State private var path: [String] = []
    @State private var filter = "all"
    /// Сортування запам'ятовується між запусками; reversed — протилежний до звичного напрямок
    @AppStorage("storeSortKey") private var sortKey = StoreSort.date.rawValue
    @AppStorage("storeSortReversed") private var sortReversed = false
    /// Циферблат, який просять видалити з меню (підтвердження), і помилка дії з меню
    @State private var menuDelete: BandFace?
    @State private var menuError: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var kinds: [String] {
        var seen: [String] = []
        for f in faces where !seen.contains(f.kind) { seen.append(f.kind) }
        return seen
    }

    private var shown: [StoreFace] {
        let filtered = faces.filter { f in
            switch filter {
            case "all": return true
            case "new": return f.isNew
            case "free": return f.isFree
            default: return f.kind == filter
            }
        }
        return StoreSort(rawValue: sortKey)?.sorted(filtered, reversed: sortReversed) ?? filtered
    }

    private func state(_ f: StoreFace) -> StoreAction {
        if busy && installingID == f.id { return .installing }
        if let v = installed[f.id] { return v < f.version ? .update : .installed }
        return .install
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                let items = shown
                Group {
                    if items.isEmpty {
                        Text("Нічого не знайдено")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(items) { item in
                                NavigationLink(value: item.id) {
                                    card(item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .refreshable { await onRefresh() }
            .background(Color(.systemGroupedBackground))
            // Без фільтра — «Магазин», з фільтром — його назва («Нові», «Безкоштовні», «Цифровий»…)
            .navigationTitle(filter == "all" ? String(localized: "Магазин")
                             : filterOptions.first { $0.0 == filter }?.1 ?? String(localized: "Магазин"))
            .navigationBarTitleDisplayMode(.large)
            // Під заголовком — поточне сортування («Спочатку нові», «А–Я»…), з iOS 26
            .modifier(NavigationSubtitle(text: StoreSort(rawValue: sortKey)?.direction(reversed: sortReversed) ?? ""))
            .navigationDestination(for: String.self) { id in
                if let item = faces.first(where: { $0.id == id }) {
                    StoreDetailView(item: item,
                                    state: state(item),
                                    installedVersion: installed[item.id],
                                    busy: busy,
                                    progress: progress,
                                    progressText: progressText,
                                    onInstall: onInstall,
                                    isActive: item.id == activeID,
                                    onSelect: { await onActivate(item) },
                                    onDelete: { await onDelete(item) })
                }
            }
            .modifier(StoreToolbar(filter: $filter, filters: filterOptions,
                                   sortKey: $sortKey, sortReversed: $sortReversed,
                                   onRefresh: { Task { await onRefresh() } },
                                   menuFaces: faces.filter { installed[$0.id] != nil },
                                   activeID: activeID,
                                   onOpen: { path.append($0.id) },
                                   onSelect: { face in menuAction { await onBandAction(face.id, face.name, false) } },
                                   onDeleteRequest: { menuDelete = $0 },
                                   onPickFile: onPickFile,
                                   otherFaces: otherFaces,
                                   deviceName: deviceName,
                                   deviceInfo: deviceInfo))
            .alert(menuDelete.map { String(localized: "Видалити \($0.name) з пристрою?") } ?? "",
                   isPresented: Binding(get: { menuDelete != nil }, set: { if !$0 { menuDelete = nil } }),
                   presenting: menuDelete) { item in
                Button("Видалити", role: .destructive) { menuAction { await onBandAction(item.id, item.name, true) } }
                Button("Скасувати", role: .cancel) {}
            } message: { _ in
                Text("Встановити його знову можна з магазину.")
            }
            .alert(menuError ?? "", isPresented: Binding(get: { menuError != nil }, set: { if !$0 { menuError = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    /// Пункти фільтра: (ідентифікатор, назва)
    private var filterOptions: [(String, String)] {
        [("all", String(localized: "Усі")), ("new", String(localized: "Нові")),
         ("free", String(localized: "Безкоштовні"))] + kinds.map { ($0, $0) }
    }

    /// Дія з меню (вибрати, видалити); помилку показуємо окремим вікном
    private func menuAction(_ work: @escaping () async -> String?) {
        Task { @MainActor in
            if let error = await work() { menuError = error }
        }
    }

    private func card(_ item: StoreFace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FaceCapsule(image: item.preview, active: item.id == activeID)
                .frame(maxWidth: .infinity)
                .frame(height: 266)

            VStack(alignment: .leading, spacing: 0) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                subtitleView(item)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)

            FaceActionButton(state: state(item), price: item.price, busy: busy,
                             progress: progress, progressText: progressText) {
                onInstall(item)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    @ViewBuilder private func subtitleView(_ item: StoreFace) -> some View {
        if item.isFree, !(installed[item.id].map { $0 < item.version } ?? false) {
            (Text("Безкоштовно").fontWeight(.semibold).foregroundColor(Color.okText)
             + Text(verbatim: " · \(item.sizeKB) KB"))
        } else {
            Text(subtitle(item))
        }
    }

    private func subtitle(_ item: StoreFace) -> String {
        if let v = installed[item.id], v < item.version {
            return String(localized: "Оновлення \(v).0 → \(item.version).0")
        }
        return item.meta
    }
}

/// Кнопка внизу картки: «Встановити», прогрес, «Встановлено», «Оновити».
struct FaceActionButton: View {
    let state: StoreAction
    let price: String?
    let busy: Bool
    let progress: Double
    let progressText: String
    var height: CGFloat = 36
    let action: () -> Void

    var body: some View {
        switch state {
        case .installing:
            // На сторінці циферблата (велика кнопка) смужка й текст такі самі, як на головній:
            // смужка 12 pt, текст footnote на 4 pt нижче, відступи 14 pt. У картці магазину — 8 pt і відступи 6 pt
            let large = height >= 50
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.3))
                        Capsule().fill(Color.accentColor)
                            .frame(width: max(large ? 12 : 8, geo.size.width * progress))
                    }
                }
                .frame(height: large ? 12 : 8)
                HStack {
                    Text(progressText).lineLimit(1)
                    Spacer()
                    Text(verbatim: "\(Int(progress * 100))%")
                }
                .font(large ? .footnote : .caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, large ? 14 : 6)
            .frame(height: height)
        case .installed:
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                Text("Встановлено")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Capsule().fill(Color(.systemGroupedBackground)))
        case .update:
            Button(action: action) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.to.line")
                    Text("Оновити")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .foregroundStyle(.white)
                .background(Capsule().fill(Color.accentColor))
                .capsuleGlass(tint: Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(busy)
        case .install:
            Button(action: action) {
                Text(price ?? String(localized: "Встановити"))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color.accentColor))
                    .capsuleGlass(tint: Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
    }
}

/// Сторінка циферблата: назва в панелі, кілька зображень, відомості, кнопка й опис.
struct StoreDetailView: View {
    let item: StoreFace
    let state: StoreAction
    let installedVersion: Int?
    let busy: Bool
    let progress: Double
    let progressText: String
    let onInstall: (StoreFace) -> Void
    /// Циферблат зараз на екрані браслета
    var isActive = false
    /// «Вибрати» (зробити активним) і «Видалити з браслета»: nil — успіх, інакше текст помилки
    var onSelect: () async -> String? = { nil }
    var onDelete: () async -> String? = { nil }

    private enum Work { case select, delete }
    @State private var working: Work?
    @State private var askDelete = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                previews

                HStack(spacing: 0) {
                    infoColumn("Розмір", "\(item.sizeKB) KB")
                    Divider().frame(height: 34)
                    infoColumn("Пристрої", item.bandsText)
                    Divider().frame(height: 34)
                    infoColumn("Категорія", item.kind)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground)))

                actions

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Color.errorText)
                        .padding(.horizontal, 4)
                }

                Text(item.about)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                // Видалення — окремо внизу, далеко від основних кнопок; лише для встановленого
                if installedVersion != nil && state != .installing {
                    deleteRow
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "Видалити \(item.name) з пристрою?"), isPresented: $askDelete) {
            Button("Видалити", role: .destructive) { run(.delete) }
            Button("Скасувати", role: .cancel) {}
        } message: {
            Text("Встановити його знову можна з магазину.")
        }
    }

    /// Не встановлено — «Встановити»; встановлено — «✓ Встановлено» і поруч «Вибрати» або «✓ На екрані»
    @ViewBuilder private var actions: some View {
        if state == .installed {
            HStack(spacing: 10) {
                slot(Label("Встановлено", systemImage: "checkmark"))
                    .foregroundStyle(.secondary)
                if isActive {
                    slot(Label("На екрані", systemImage: "checkmark"))
                        .foregroundStyle(Color.okText)
                } else {
                    Button { run(.select) } label: {
                        Text("Вибрати")
                            .font(.subheadline.weight(.semibold))
                            .opacity(working == .select ? 0 : 1)
                            .overlay { if working == .select { ProgressView().tint(.white) } }
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundStyle(.white)
                            .background(Capsule().fill(Color.accentColor))
                            .capsuleGlass(tint: Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(working != nil || busy)
                }
            }
        } else {
            FaceActionButton(state: state, price: item.price, busy: busy,
                             progress: progress, progressText: progressText, height: 52) {
                onInstall(item)
            }
        }
    }

    private func slot(_ label: some View) -> some View {
        label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))
    }

    private var deleteRow: some View {
        Button { askDelete = true } label: {
            Text("Видалити з пристрою")
                .opacity(working == .delete ? 0 : 1)
                .overlay { if working == .delete { ProgressView() } }
                .foregroundStyle(Color.errorText)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground)))
                .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(working != nil || busy)
    }

    private func run(_ work: Work) {
        guard working == nil else { return }
        working = work
        error = nil
        Task {
            let result = work == .select ? await onSelect() : await onDelete()
            working = nil
            error = result
        }
    }

    private var previews: some View {
        HStack(alignment: .top, spacing: 28) {
            ForEach(item.previews) { p in
                VStack(spacing: 10) {
                    FaceCapsule(image: p.image)
                    Text(p.title)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
    }

    private func infoColumn(_ title: LocalizedStringKey, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}













/// Сортування магазину. Звичний напрямок: дата — спочатку нові, назва — А–Я, розмір — спочатку менші.
/// «Завантаження» й «Перегляди» поки не працюють: для них потрібна статистика з сервера.
enum StoreSort: String, CaseIterable {
    case date, name, size, downloads, views

    var title: String {
        switch self {
        case .date: return String(localized: "Дата")
        case .name: return String(localized: "Назва")
        case .size: return String(localized: "Розмір")
        case .downloads: return String(localized: "Завантаження")
        case .views: return String(localized: "Перегляди")
        }
    }

    var isAvailable: Bool { self == .date || self == .name || self == .size }

    func direction(reversed: Bool) -> String {
        switch self {
        case .date: return reversed ? String(localized: "Спочатку старі") : String(localized: "Спочатку нові")
        case .name: return reversed ? "Я–А" : "А–Я"
        case .size: return reversed ? String(localized: "Спочатку більші") : String(localized: "Спочатку менші")
        case .downloads, .views: return ""
        }
    }

    func sorted(_ faces: [StoreFace], reversed: Bool) -> [StoreFace] {
        let result: [StoreFace]
        switch self {
        case .date:
            result = faces.sorted { ($0.added ?? .distantPast) > ($1.added ?? .distantPast) }
        case .name:
            result = faces.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            result = faces.sorted { $0.face.size < $1.face.size }
        case .downloads, .views:
            return faces
        }
        return reversed ? result.reversed() : result
    }
}

/// Підзаголовок під великим заголовком (системний, з iOS 26)
private struct NavigationSubtitle: ViewModifier {
    let text: String
    func body(content: Content) -> some View {
        if #available(iOS 26, *), !text.isEmpty {
            content.navigationSubtitle(text)
        } else {
            content
        }
    }
}

/// Панель магазину: зліва фільтр, справа системне меню «Встановлено» (анімацію відкриття робить iOS).
/// У меню: швидкі дії, циферблати з магазину й інші на пристрої (у кожного підменю з діями), сам пристрій.
private struct StoreToolbar: ViewModifier {
    /// «Останній раз був заряджений 3 дні тому» (українські форми: 1 день, 2–4 дні, 5+ днів)
    static func lastChargeText(_ date: Date?) -> String {
        guard let date else { return String(localized: "Дата останньої зарядки невідома") }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date),
                                                   to: Calendar.current.startOfDay(for: Date())).day ?? 0
        if days <= 0 { return String(localized: "Останній раз був заряджений сьогодні") }
        if days == 1 { return String(localized: "Останній раз був заряджений учора") }
        let n10 = days % 10, n100 = days % 100
        let word: String
        if n10 == 1 && n100 != 11 { word = String(localized: "день") }
        else if (2...4).contains(n10) && !(12...14).contains(n100) { word = String(localized: "дні") }
        else { word = String(localized: "днів") }
        return String(localized: "Останній раз був заряджений \(days) \(word) тому")
    }

    @Binding var filter: String
    let filters: [(String, String)]
    @Binding var sortKey: String
    @Binding var sortReversed: Bool
    let onRefresh: () -> Void
    let menuFaces: [StoreFace]
    let activeID: String?
    let onOpen: (StoreFace) -> Void
    let onSelect: (BandFace) -> Void
    let onDeleteRequest: (BandFace) -> Void
    let onPickFile: () -> Void
    let otherFaces: [BandFace]
    let deviceName: String
    let deviceInfo: BandInfo

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Menu {
                    Section("Показати") {
                        Picker(selection: $filter) {
                            ForEach(filters, id: \.0) { f in Text(f.1).tag(f.0) }
                        } label: { EmptyView() }
                        .pickerStyle(.inline)
                    }
                    // Сортування: дотик до вибраного пункту міняє напрямок; під вибраним — поточний напрямок
                    Section("Сортувати") {
                        ForEach(StoreSort.allCases, id: \.self) { sort in
                            let selected = sort.rawValue == sortKey
                            Toggle(isOn: Binding(get: { selected }, set: { _ in
                                if selected { sortReversed.toggle() } else { sortKey = sort.rawValue; sortReversed = false }
                            })) {
                                Text(sort.title)
                                if !sort.isAvailable {
                                    Text("Тимчасово не працює")
                                } else if selected {
                                    Text(sort.direction(reversed: sortReversed))
                                }
                            }
                            .disabled(!sort.isAvailable)
                        }
                    }
                } label: {
                    Image(systemName: filter == "all" ? "line.3.horizontal.decrease"
                                                      : "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(filter == "all" ? Color.primary : Color.accentColor)
                }
                .accessibilityLabel(Text("Фільтр"))
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // Швидкі дії — ряд кнопок угорі меню
                    ControlGroup {
                        Button { onRefresh() } label: { Label("Оновити", systemImage: "arrow.clockwise") }
                        Button { onPickFile() } label: { Label("З файлу", systemImage: "doc.badge.plus") }
                    }

                    // Циферблати з магазину
                    Section("Встановлено") {
                        if menuFaces.isEmpty {
                            Text("Циферблатів з магазину на пристрої немає")
                        }
                        ForEach(menuFaces) { item in
                            let face = BandFace(id: item.id, name: item.name,
                                                isActive: item.id == activeID, canDelete: true)
                            Menu {
                                Button { onOpen(item) } label: {
                                    Label("Відкрити сторінку", systemImage: "arrow.up.forward.app")
                                }
                                if !face.isActive {
                                    Button { onSelect(face) } label: {
                                        Label("Вибрати", systemImage: "checkmark.circle")
                                    }
                                }
                                Button(role: .destructive) { onDeleteRequest(face) } label: {
                                    Label("Видалити з пристрою", systemImage: "trash")
                                }
                            } label: {
                                Text(item.name)
                                Text(verbatim: item.meta)
                                Image(uiImage: MenuThumb.image(key: item.id, preview: item.preview, active: face.isActive))
                                    .renderingMode(.original)
                            }
                        }
                    }

                    // Інші циферблати на пристрої (з Mi Fitness і вбудований)
                    if !otherFaces.isEmpty {
                        Section("Інші на пристрої") {
                            ForEach(otherFaces) { face in
                                Menu {
                                    if !face.isActive {
                                        Button { onSelect(face) } label: {
                                            Label("Вибрати", systemImage: "checkmark.circle")
                                        }
                                    }
                                    if face.canDelete {
                                        Button(role: .destructive) { onDeleteRequest(face) } label: {
                                            Label("Видалити з пристрою", systemImage: "trash")
                                        }
                                    }
                                } label: {
                                    Text(face.name)
                                    Text(verbatim: face.note)
                                    Image(uiImage: face.id == BandFace.standardID
                                          ? MenuThumb.image(key: "standard", preview: UIImage(named: "StandardFace"), active: face.isActive)
                                          : MenuThumb.image(key: "other", preview: nil, active: face.isActive))
                                        .renderingMode(.original)
                                }
                            }
                        }
                    }

                    // Пристрій: назва й іконка, під ними заряд або «Заряджається»; у підменю — остання зарядка
                    Section {
                        Menu {
                            Text(Self.lastChargeText(deviceInfo.lastCharge))
                        } label: {
                            Text(verbatim: deviceName)
                            if deviceInfo.charging == true {
                                Text("Заряджається")
                            } else if let battery = deviceInfo.battery {
                                Text("Заряд \(battery)%")
                            }
                            Image("TabWatch")
                        }
                    }
                } label: {
                    Image("IconInstalled")
                        .resizable()
                        .frame(width: 23, height: 23)
                }
                .accessibilityLabel(Text("Встановлені"))
            }
        }
    }
}

/// Циферблат на пристрої для меню «Встановлено» (з магазину чи ні)
struct BandFace: Identifiable, Equatable {
    let id: String
    let name: String
    let isActive: Bool
    let canDelete: Bool
    /// Другий рядок у меню: «Mi Fitness» або «Вбудований»
    var note: String = "Mi Fitness"

    /// Стандартний циферблат Smart Band 10 (є на браслеті завжди, видалити не можна)
    static let standardID = "120917353510"
}

private enum MenuThumb {
    private static var cache: [String: UIImage] = [:]

    /// Капсула в квадраті 30×30; в активного — зелений кружечок із галочкою в куті
    static func image(key id: String, preview: UIImage?, active: Bool = false) -> UIImage {
        let key = id + (active ? ":a" : "") + ":v4"
        if let cached = cache[key] { return cached }
        let side: CGFloat = 30
        let capsule = CGRect(x: (side - 13) / 2, y: 0, width: 13, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let cg = ctx.cgContext
            cg.saveGState()
            let path = UIBezierPath(roundedRect: capsule, cornerRadius: capsule.width / 2)
            UIColor.black.setFill()
            path.fill()
            path.addClip()
            if let preview {
                let scale = max(capsule.width / preview.size.width, capsule.height / preview.size.height)
                let size = CGSize(width: preview.size.width * scale, height: preview.size.height * scale)
                preview.draw(in: CGRect(x: capsule.midX - size.width / 2, y: capsule.midY - size.height / 2,
                                        width: size.width, height: size.height))
            }
            cg.restoreGState()
            // Обведення в 1 фізичний піксель усередині капсули — як у плиток налаштувань
            // (біле, прозорість 40 % згори → 22 % знизу); активний позначає лише галочка
            let line: CGFloat = 1 / format.scale
            let border = UIBezierPath(roundedRect: capsule.insetBy(dx: line / 2, dy: line / 2),
                                      cornerRadius: (capsule.width - line) / 2)
            cg.saveGState()
            cg.setLineWidth(line)
            cg.addPath(border.cgPath)
            cg.replacePathWithStrokedPath()
            cg.clip()
            let colors = [UIColor.white.withAlphaComponent(0.4).cgColor,
                          UIColor.white.withAlphaComponent(0.22).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: capsule.minY),
                                      end: CGPoint(x: 0, y: capsule.maxY), options: [])
            }
            cg.restoreGState()
            if active {
                let badge = CGRect(x: side - 13, y: side - 13, width: 12, height: 12)
                // Тонший проміжок між галочкою й капсулою
                UIColor.systemBackground.setFill()
                UIBezierPath(ovalIn: badge.insetBy(dx: -0.5, dy: -0.5)).fill()
                UIColor(red: 0.133, green: 0.659, blue: 0.275, alpha: 1).setFill()
                UIBezierPath(ovalIn: badge).fill()
                let check = UIBezierPath()
                check.move(to: CGPoint(x: badge.minX + 3.2, y: badge.midY + 0.2))
                check.addLine(to: CGPoint(x: badge.minX + 5.3, y: badge.midY + 2.2))
                check.addLine(to: CGPoint(x: badge.maxX - 2.9, y: badge.minY + 3.6))
                check.lineWidth = 1.6
                check.lineCapStyle = .round
                check.lineJoinStyle = .round
                UIColor.white.setStroke()
                check.stroke()
            }
        }.withRenderingMode(.alwaysOriginal)
        cache[key] = image
        return image
    }
}
