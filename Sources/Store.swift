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
/// а не при кожному оновленні головного екрана (наприклад, під час анімації пошуку).
struct StoreView: View, Equatable {
    static func == (a: StoreView, b: StoreView) -> Bool {
        a.faces.map(\.id) == b.faces.map(\.id) && a.installed == b.installed
            && a.installingID == b.installingID && a.busy == b.busy
            && a.progress == b.progress && a.progressText == b.progressText
            && a.activeID == b.activeID
            && a.otherFaces == b.otherFaces && a.bandStatus == b.bandStatus
            && a.bandBattery == b.bandBattery && a.bandFirmware == b.bandFirmware
    }

    let faces: [StoreFace]
    let installed: [String: Int]
    let installingID: String?
    let busy: Bool
    let progress: Double
    let progressText: String
    let onInstall: (StoreFace) -> Void
    let onRefresh: () async -> Void
    /// Тестова функція «Встановлені»: який циферблат на екрані, увімкнути, видалити (nil — успіх, інакше текст помилки)
    var activeID: String? = nil
    var onActivate: (StoreFace) async -> String? = { _ in nil }
    var onDelete: (StoreFace) async -> String? = { _ in nil }
    /// Звичайна (не примусова) перевірка браслета: пропускається, якщо була менш ніж 20 с тому
    var onCheck: () async -> Void = {}
    /// F: «З файлу» — перейти до вибору файлу на вкладці «Циферблати»
    var onPickFile: () -> Void = {}
    /// F: циферблати на браслеті не з магазину (назви з браслета; превью браслет не віддає)
    var otherFaces: [BandFace] = []
    /// F: вибрати/видалити будь-який циферблат за ID (id, назва, видалити?)
    var onBandAction: (String, String, Bool) async -> String? = { _, _, _ in nil }
    /// F: назва браслета або «Браслет не підключено»; заряд і прошивка (nil — невідомо)
    var bandStatus: String = ""
    var bandBattery: Int? = nil
    var bandFirmware: String? = nil

    @State private var query = ""
    /// Тимчасовий експеримент: 0 — A (кнопка фільтрів і пошук угорі), 1 — B (мітки фільтрів, без пошуку),
    /// 2 — C (системна панель: фільтр зліва, оновлення справа),
    /// 3 — D (фільтр + «Встановлені» у спливаючому вікні), 4 — E (фільтр + «Встановлені» на аркуші знизу)
    @AppStorage("storeLayout") private var layout = 0
    /// Пошук відкрито (лупа розгорнулась у рядок)
    @State private var searchOpen = false
    /// Шлях навігації: змінюється на самому початку переходу до картки й назад,
    /// тож панель пошуку згасає й з'являється синхронно зі сторінкою
    @State private var path: [String] = []
    @State private var filter = "all"
    /// C: іде перевірка браслета, запущена кнопкою оновлення
    @State private var refreshing = false
    /// D/E: відкрито вікно «Встановлені»
    @State private var installedShown = false
    /// F: циферблат, який просять видалити з меню (підтвердження), і помилка дії з меню
    @State private var menuDelete: BandFace?
    @State private var menuError: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private var kinds: [String] {
        var seen: [String] = []
        for f in faces where !seen.contains(f.kind) { seen.append(f.kind) }
        return seen
    }

    private var shown: [StoreFace] {
        faces.filter { f in
            switch filter {
            case "all": break
            case "new": if !f.isNew { return false }
            case "free": if !f.isFree { return false }
            default: if f.kind != filter { return false }
            }
            let q = query.trimmingCharacters(in: .whitespaces)
            return q.isEmpty || f.name.localizedCaseInsensitiveContains(q)
                || f.kind.localizedCaseInsensitiveContains(q)
        }
    }

    private func state(_ f: StoreFace) -> StoreAction {
        if busy && installingID == f.id { return .installing }
        if let v = installed[f.id] { return v < f.version ? .update : .installed }
        return .install
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                // Фільтр рахуємо один раз за оновлення екрана
                let items = shown
                VStack(alignment: .leading, spacing: 14) {
                if layout == 1 { chips }
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
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .refreshable { await onRefresh() }
            .background(Color(.systemGroupedBackground))
            // Великий і маленький заголовки — системні: системна панель навігації лишається порожньою
            .navigationTitle("Магазин")
            .navigationBarTitleDisplayMode(.large)
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
            // Поки відкритий пошук, маленький системний заголовок ховаємо; великий лишається
            .modifier(HideInlineTitle(hidden: layout == 0 && searchOpen))
            // C: звичайні системні кнопки панелі — скло, перехід до картки й маленький заголовок робить iOS
            .modifier(SystemBarButtons(mode: layout, filter: $filter, filters: filterOptions,
                                       refreshing: refreshing, onRefresh: refresh,
                                       panelShown: $installedShown,
                                       panel: { popover in installedPanel(popover: popover) },
                                       menuFaces: faces.filter { installed[$0.id] != nil },
                                       activeID: activeID,
                                       onOpen: { path.append($0.id) },
                                       onSelect: { face in menuAction { await onBandAction(face.id, face.name, false) } },
                                       onDeleteRequest: { menuDelete = $0 },
                                       onPickFile: onPickFile,
                                       otherFaces: otherFaces,
                                       bandStatus: bandStatus,
                                       bandBattery: bandBattery,
                                       bandFirmware: bandFirmware))
            .alert(menuDelete.map { String(localized: "Видалити \($0.name) з браслета?") } ?? "",
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
            // Щойно вікно «Встановлені» відкрилось — уточнюємо в браслета, що на ньому і що на екрані
            // Вікно «Встановлені» відкрилось: браслет перепитуємо лише після анімації появи
            // і лише якщо давно не перевіряли — сесія Bluetooth не гальмує відкриття й закриття
            .onChange(of: installedShown) { shown in
                guard shown else { return }
                Task {
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    await onCheck()
                }
            }
            .onChange(of: layout) { _ in searchOpen = false; query = "" }
        }
        // Наша панель (фільтр, лупа, що «перетікає» в рядок пошуку, хрестик) — поверх системної панелі,
        // у рядку її кнопок. Під час переходу до картки згасає і з'являється при поверненні
        .overlay(alignment: .top) {
            if layout == 0 {
                LiquidSearchBar(query: $query, active: $searchOpen, filter: $filter, filters: filterOptions)
                    .padding(.horizontal, Self.barMargin)
                    .padding(.top, 2)
                    .opacity(path.isEmpty ? 1 : 0)
                    .allowsHitTesting(path.isEmpty)
                    .animation(.easeInOut(duration: 0.25), value: path.isEmpty)
            } else if layout == 3 {
                // D: власні кнопки й власне вікно — скло кнопки «перетікає» у вікно і назад
                InstalledBar(filter: $filter, filters: filterOptions, shown: $installedShown,
                             panel: { installedPanel(popover: true) })
                    .padding(.horizontal, Self.barMargin)
                    .padding(.top, 2)
                    .opacity(path.isEmpty ? 1 : 0)
                    .allowsHitTesting(path.isEmpty)
                    .animation(.easeInOut(duration: 0.25), value: path.isEmpty)
            }
        }
    }

    /// Бічні відступи, як у системної панелі навігації: 20 pt на великих iPhone (Plus, Pro Max), інакше 16
    private static let barMargin: CGFloat = UIScreen.main.bounds.width >= 414 ? 20 : 16

    /// Пункти фільтра: (ідентифікатор, назва)
    private var filterOptions: [(String, String)] {
        [("all", String(localized: "Усі")), ("new", String(localized: "Нові")),
         ("free", String(localized: "Безкоштовні"))] + kinds.map { ($0, $0) }
    }

    /// C: кнопка оновлення — та сама перевірка браслета, що й потягування вниз
    /// F: дія з меню (вибрати, видалити); помилку показуємо окремим вікном
    private func menuAction(_ work: @escaping () async -> String?) {
        Task { @MainActor in
            if let error = await work() { menuError = error }
        }
    }

    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            await onRefresh()
            refreshing = false
        }
    }

    /// D/E: вміст вікна «Встановлені» — циферблати магазину, що зараз є на браслеті
    private func installedPanel(popover: Bool) -> InstalledFacesPanel {
        InstalledFacesPanel(faces: faces.filter { installed[$0.id] != nil },
                            activeID: activeID,
                            popover: popover,
                            onSelect: onActivate,
                            onOpen: openFromPanel)
    }

    /// Картка у вікні «Встановлені»: вікно закривається, відкривається сторінка циферблата
    private func openFromPanel(_ item: StoreFace) {
        installedShown = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            path.append(item.id)
        }
    }

    private var chips: some View {
        // Усі мітки будує один цикл. «Вибрана» входить у дані кожної мітки, тож при виборі
        // змінюються самі дані — і SwiftUI гарантовано перемальовує саме ті мітки, що змінились
        let current = filter
        let items = filterOptions.map { ChipItem(id: $0.0, title: $0.1, on: $0.0 == current) }
        return ScrollView(.horizontal, showsIndicators: false) {
            ChipRow {
                ForEach(items) { c in
                    FilterChip(title: c.title, on: c.on) { filter = c.id }
                }
            }
            // Запас навколо міток: при натисканні скло розширюється й не обрізається краєм прокрутки
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        // Компенсуємо запас, щоб розкладка залишилась тією самою
        .padding(.horizontal, -16)
        .padding(.vertical, -14)
    }

    private func card(_ item: StoreFace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                FaceCapsule(image: item.preview, active: item.id == activeID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
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
        .alert(String(localized: "Видалити \(item.name) з браслета?"), isPresented: $askDelete) {
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
            Text("Видалити з браслета")
                .opacity(working == .delete ? 0 : 1)
                .overlay { if working == .delete { ProgressView() } }
                .foregroundStyle(Color(.systemRed))
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













/// Натискання в проміжках між кнопками панелі не проходять до карток під нею.
private struct BlocksTouchesBehind: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {}
        )
    }
}



/// Скло з ідентифікатором: однакові id у GlassEffectContainer плавно перетікають одне в одне.
/// Без .interactive(), щоб скло не перехоплювало натискання кнопок.
private struct MorphGlass: ViewModifier {
    let id: String
    let ns: Namespace.ID
    let circle: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if circle {
                content.glassEffect(.regular, in: Circle())
                    .glassEffectID(id, in: ns)
                    .glassEffectTransition(.matchedGeometry)
            } else {
                content.glassEffect(.regular, in: Capsule())
                    .glassEffectID(id, in: ns)
                    .glassEffectTransition(.matchedGeometry)
            }
        } else {
            if circle { content.background(Circle().fill(Color(.tertiarySystemFill))) }
            else { content.background(Capsule().fill(Color(.tertiarySystemFill))) }
        }
    }
}

/// Панель пошуку з «рідким склом». Усі скляні форми в одному GlassEffectContainer:
/// коли кнопки наближаються до рядка пошуку, скло притягується й зливається з ним,
/// а при закритті так само роз'єднується.
/// - collapsedButton (A): ліворуч фільтр, праворуч лупа, яка розтягується в рядок пошуку
/// - field (F): лише рядок пошуку
/// - fieldWithFilter (G): фільтр і рядок; під час пошуку фільтр вливається в рядок
struct LiquidSearchBar: View {
    @Binding var query: String
    @Binding var active: Bool
    @Binding var filter: String
    let filters: [(String, String)]
    @FocusState private var focused: Bool
    @Namespace private var glass

    private let size: CGFloat = 44
    /// Проміжок між склом у спокої більший за відстань злиття контейнера (10),
    /// тож у спокої форми окремі, а під час руху назустріч — зливаються
    private let gap: CGFloat = 12
    private let animation = Animation.bouncy(duration: 0.5, extraBounce: 0.1)

    private var searchExpanded: Bool { active }

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 10) { row }
        } else {
            row
        }
    }

    private var row: some View {
        // Кнопки додаються й прибираються цілком (а не стискаються до нуля):
        // так GlassEffectContainer «видавлює» нове скло з сусіднього і вбирає його назад
        HStack(spacing: gap) {
            filterButton
            if !searchExpanded { Spacer(minLength: 0) }
            searchField
            if active {
                closeButton
                    .transition(.identity)
            }
        }
        .modifier(BlocksTouchesBehind())
        .onChange(of: focused) { f in
            // Клавіатуру сховали гортанням — порожній пошук закривається з тією ж анімацією
            if !f && active && query.isEmpty { withAnimation(animation) { active = false } }
        }
    }

    private var filterButton: some View {
        ZStack {
        Menu {
            Picker(selection: $filter) {
                ForEach(filters, id: \.0) { f in Text(f.1).tag(f.0) }
            } label: { EmptyView() }
        } label: {
            Image(systemName: filter == "all" ? "line.3.horizontal.decrease"
                                              : "line.3.horizontal.decrease.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(filter == "all" ? Color.primary : Color.accentColor)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        }
        .frame(width: size, height: size)
        .modifier(MorphGlass(id: "filter", ns: glass, circle: true))
        .accessibilityLabel(Text("Фільтр"))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(searchExpanded ? .body : .body.weight(.semibold))
                .foregroundStyle(searchExpanded ? Color(.secondaryLabel) : Color.primary)
            if searchExpanded {
                TextField("Пошук циферблатів", text: $query)
                    .focused($focused)
                    // Поле з'являється лише після натискання лупи; у панелі навігації (B) воно
                    // вбудовується на мить пізніше, тож фокус ставимо, коли поле вже на екрані
                    .onAppear {
                        if active {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
                        }
                    }
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { focused = false }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color(.tertiaryLabel))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, searchExpanded ? 14 : 0)
        .frame(width: searchExpanded ? nil : size, height: size)
        .frame(maxWidth: searchExpanded ? .infinity : size)
        .modifier(MorphGlass(id: "search", ns: glass, circle: false))
        .contentShape(Capsule())
        .onTapGesture {
            if !active { withAnimation(animation) { active = true } }
            focused = true
        }
        .accessibilityAddTraits(.isButton)
    }

    private var closeButton: some View {
        Button {
            focused = false
            query = ""
            withAnimation(animation) { active = false }
        } label: {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.primary)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(MorphGlass(id: "close", ns: glass, circle: true))
        .accessibilityLabel(Text("Закрити"))
    }
}

/// C/D/E: системна панель. Зліва — фільтр (меню); справа — оновлення (C) або «Встановлені» (D — спливаюче вікно,
/// E — аркуш знизу). Поки браслет перевіряється, замість стрілки оновлення крутиться системний індикатор.
private struct SystemBarButtons<Panel: View>: ViewModifier {
    let mode: Int
    @Binding var filter: String
    let filters: [(String, String)]
    let refreshing: Bool
    let onRefresh: () -> Void
    @Binding var panelShown: Bool
    let panel: (_ popover: Bool) -> Panel
    /// F: системне меню «Встановлено»
    let menuFaces: [StoreFace]
    let activeID: String?
    let onOpen: (StoreFace) -> Void
    let onSelect: (BandFace) -> Void
    let onDeleteRequest: (BandFace) -> Void
    let onPickFile: () -> Void
    let otherFaces: [BandFace]
    let bandStatus: String
    let bandBattery: Int?
    let bandFirmware: String?

    func body(content: Content) -> some View {
        content
            .toolbar {
                if mode == 2 || mode == 4 || mode == 5 {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Menu {
                            Picker(selection: $filter) {
                                ForEach(filters, id: \.0) { f in Text(f.1).tag(f.0) }
                            } label: { EmptyView() }
                        } label: {
                            Image(systemName: filter == "all" ? "line.3.horizontal.decrease"
                                                              : "line.3.horizontal.decrease.circle.fill")
                                .foregroundStyle(filter == "all" ? Color.primary : Color.accentColor)
                        }
                        .accessibilityLabel(Text("Фільтр"))
                    }
                }
                if mode == 2 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: onRefresh) {
                            if refreshing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(refreshing)
                        .accessibilityLabel(Text("Оновити"))
                    }
                }
                if mode == 5 {
                    // F: системне меню — анімацію відкриття робить iOS
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            // Швидкі дії — ряд маленьких кнопок угорі меню
                            ControlGroup {
                                Button { onRefresh() } label: { Label("Оновити", systemImage: "arrow.clockwise") }
                                Button { onPickFile() } label: { Label("З файлу", systemImage: "doc.badge.plus") }
                            }

                            // Циферблати з магазину: у кожного підменю з діями
                            Section("Встановлено") {
                                if menuFaces.isEmpty {
                                    Text("Циферблатів з магазину на браслеті немає")
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
                                            Label("Видалити з браслета", systemImage: "trash")
                                        }
                                    } label: {
                                        Text(item.name)
                                        Text(face.isActive ? String(localized: "Активний · \(item.meta)") : item.meta)
                                        Image(uiImage: MenuThumb.image(key: item.id, preview: item.preview, active: face.isActive))
                                            .renderingMode(.original)
                                    }
                                }
                            }

                            // Інші циферблати на браслеті (з Mi Fitness): назва з браслета, превью немає
                            if !otherFaces.isEmpty {
                                Section("Інші на браслеті") {
                                    ForEach(otherFaces) { face in
                                        Menu {
                                            if !face.isActive {
                                                Button { onSelect(face) } label: {
                                                    Label("Вибрати", systemImage: "checkmark.circle")
                                                }
                                            }
                                            if face.canDelete {
                                                Button(role: .destructive) { onDeleteRequest(face) } label: {
                                                    Label("Видалити з браслета", systemImage: "trash")
                                                }
                                            }
                                        } label: {
                                            Text(face.name)
                                            Text(face.isActive ? String(localized: "Активний · \(face.note)") : face.note)
                                            Image(uiImage: MenuThumb.image(key: "other", preview: nil, active: face.isActive))
                                                .renderingMode(.original)
                                        }
                                    }
                                }
                            }

                            // Браслет — з тією ж іконкою, що на головній
                            // Підменю браслета: версія прошивки
                            Section {
                                Menu {
                                    Text(bandFirmware.map { String(localized: "Прошивка \($0)") }
                                         ?? String(localized: "Прошивка невідома"))
                                } label: {
                                    Text(verbatim: bandStatus)
                                    if let bandBattery {
                                        Text("Заряд \(bandBattery)%")
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
                if mode == 4 {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { panelShown = true } label: {
                            Image("IconInstalled")
                                .resizable()
                                .frame(width: 23, height: 23)
                        }
                        .accessibilityLabel(Text("Встановлені"))
                        .modifier(InstalledPopover(enabled: mode == 3, shown: $panelShown) { panel(true) })
                    }
                }
            }
            .sheet(isPresented: Binding(get: { mode == 4 && panelShown }, set: { panelShown = $0 })) {
                InstalledSheet { panel(false) }
            }
    }
}

/// F: мініатюра циферблата для рядка системного меню — капсула в квадраті, щоб iOS не розтягувала її
/// Циферблат на браслеті для меню F (з магазину чи ні)
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
        let key = id + (active ? ":a" : "")
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
            if active {
                let badge = CGRect(x: side - 13, y: side - 13, width: 12, height: 12)
                UIColor.systemBackground.setFill()
                UIBezierPath(ovalIn: badge.insetBy(dx: -1.2, dy: -1.2)).fill()
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

/// D: спливаюче вікно біля кнопки (на iPhone саме вікно, а не аркуш — з iOS 16.4)
private struct InstalledPopover<Panel: View>: ViewModifier {
    let enabled: Bool
    @Binding var shown: Bool
    @ViewBuilder let panel: () -> Panel
    func body(content: Content) -> some View {
        content.popover(isPresented: Binding(get: { enabled && shown }, set: { shown = $0 }),
                        arrowEdge: .top) {
            if #available(iOS 16.4, *) {
                panel().presentationCompactAdaptation(.popover)
            } else {
                panel()
            }
        }
    }
}

/// E: системний аркуш на пів екрана з хрестиком і заголовком «Встановлені»
private struct InstalledSheet<Panel: View>: View {
    @ViewBuilder let panel: () -> Panel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            panel()
                .navigationTitle("Встановлені")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if #available(iOS 26, *) {
                            Button(role: .close) { dismiss() } label: { Image(systemName: "xmark") }
                        } else {
                            Button { dismiss() } label: { Image(systemName: "xmark") }
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .modifier(SheetGlass())
    }
}

/// E: на iOS 26 аркуш і так скляний; на старіших (з 16.4) — напівпрозорий матеріал замість суцільного фону
private struct SheetGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
        } else if #available(iOS 16.4, *) {
            content.presentationBackground(.ultraThinMaterial)
        } else {
            content
        }
    }
}

/// Вікно «Встановлені»: циферблати магазину, що зараз є на браслеті. Картка відкриває сторінку циферблата
/// (там «Видалити з браслета»); на самій картці одна дія — «Вибрати» або позначка «✓ На екрані».
struct InstalledFacesPanel: View {
    let faces: [StoreFace]
    let activeID: String?
    /// true — компактне спливаюче вікно, false — аркуш знизу
    let popover: Bool
    let onSelect: (StoreFace) async -> String?
    let onOpen: (StoreFace) -> Void

    @Environment(\.colorScheme) private var colorScheme
    /// ID циферблата, який зараз вмикається
    @State private var working: String?
    @State private var error: String?

    var body: some View {
        if popover {
            VStack(alignment: .leading, spacing: 10) {
                Text("Встановлено")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                list
            }
            .padding(10)
            .frame(width: 276)
        } else {
            // Без власного фону: видно прозоре скло системного аркуша
            ScrollView {
                VStack(spacing: 12) { list }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    @ViewBuilder private var list: some View {
        if faces.isEmpty {
            Text("Циферблатів з магазину на браслеті немає")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        ForEach(faces) { item in card(item) }
        if let error {
            Text(error)
                .font(.footnote)
                .foregroundStyle(Color.errorText)
                .padding(.horizontal, 8)
        }
    }

    private func card(_ item: StoreFace) -> some View {
        let thumb = popover ? CGSize(width: 68, height: 160) : CGSize(width: 117, height: 278)
        return HStack(spacing: popover ? 14 : 16) {
            MiniCapsule(image: item.preview, size: thumb)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.name)
                            .font(popover ? .headline : .title3.bold())
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    Text(verbatim: item.meta)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if item.id == activeID {
                    Label("На екрані", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.okText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .modifier(PlainGlassCapsule())
                } else {
                    Button { select(item) } label: {
                        Text("Вибрати")
                            .font(.subheadline.weight(.semibold))
                            .opacity(working == item.id ? 0 : 1)
                            .overlay { if working == item.id { ProgressView() } }
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                    }
                    .glassProminentStyle()
                    .buttonBorderShape(.capsule)
                    .disabled(working != nil)
                }
            }
        }
        .padding(popover ? 12 : 14)
        .background(cardBackground)
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .onTapGesture { onOpen(item) }
    }

    /// Матова картка — напівпрозорий шар поверх системного скла вікна: у темній темі світліша за скло,
    /// у світлій — темніша. Скло під нею системне, тож прозорість іде за налаштуваннями iOS
    /// («Рідке скло: прозоре/тоноване», «Зменшення прозорості»), а картка — разом із ним
    @ViewBuilder private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: popover ? 22 : 26, style: .continuous)
        if colorScheme == .dark {
            shape.fill(Color.white.opacity(0.12))
                .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
        } else {
            shape.fill(Color.black.opacity(0.055))
                .overlay(shape.strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5))
        }
    }

    private func select(_ item: StoreFace) {
        guard working == nil else { return }
        working = item.id
        error = nil
        Task {
            let result = await onSelect(item)
            working = nil
            error = result
        }
    }
}

/// Неінтерактивна скляна капсула (позначка «✓ На екрані»)
private struct PlainGlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(Capsule().fill(Color(.tertiarySystemFill)))
        }
    }
}

/// D: фільтр зліва, «Встановлені» справа і власне вікно. На iOS 26 скло кнопки «перетікає» у вікно
/// (glassEffectID у спільному GlassEffectContainer) і назад; вікно закривається дотиком будь-де поза ним.
/// Скло системне — прозорість іде за налаштуваннями iOS.
private struct InstalledBar<Panel: View>: View {
    @Binding var filter: String
    let filters: [(String, String)]
    @Binding var shown: Bool
    @ViewBuilder let panel: () -> Panel
    private let size: CGFloat = 44
    /// Розмір вікна (вимірюється з вмісту)
    @State private var panelSize = CGSize(width: 276, height: 420)
    @State private var morph = Morph()
    /// Поки йде рух, TimelineView перемальовує кожен кадр
    @State private var animating = false

    var body: some View {
        HStack(alignment: .top) {
            filterButton
            Spacer()
            installed
        }
        .background(alignment: .top) {
            // Дотик поза вікном закриває його
            if shown {
                Color.black.opacity(0.001)
                    .frame(width: 2000, height: 3000)
                    .onTapGesture { close() }
            }
        }
    }

    private func close() { shown = false }

    private var filterButton: some View {
        Menu {
            Picker(selection: $filter) {
                ForEach(filters, id: \.0) { f in Text(f.1).tag(f.0) }
            } label: { EmptyView() }
        } label: {
            Image(systemName: filter == "all" ? "line.3.horizontal.decrease"
                                              : "line.3.horizontal.decrease.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(filter == "all" ? Color.primary : Color.accentColor)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .modifier(PlainGlassCircle())
        .accessibilityLabel(Text("Фільтр"))
    }

    /// Одна скляна форма, що плавно росте з кола кнопки у вікно і стискається назад (як системні меню iOS 26):
    /// вміст живе всередині скла, обрізаний його формою, і виростає з кута кнопки — розмитий і прозорий на
    /// початку, чіткий у кінці. При закритті вміст зникає першим, потім скло стікає в кнопку і проступає іконка.
    // MARK: Морфінг кнопки у вікно
    //
    // SwiftUI-анімація розміру тут не спрацьовувала (скло стрибало одразу до кінцевого розміру), тому рух
    // рахується власноруч: TimelineView перемальовує кожен кадр (до 120 Гц), а ширина, висота, прозорість і
    // розмиття вмісту — це функції часу від окремих пружин. Скло й обрізання щокадру отримують новий розмір
    // і форму (DropletShape), тож деформація в краплю видна по-справжньому.

    private struct Morph {
        var start = Date.distantPast
        var opening = false
        var fromW: Double = 0
        var fromH: Double = 0
    }

    /// Крок пружини від 0 до 1 (response — період, damping — загасання, як у SwiftUI .spring)
    private static func spring(_ t: Double, _ response: Double, _ damping: Double) -> Double {
        guard t > 0 else { return 0 }
        let w0 = 2 * Double.pi / response
        if damping < 1 {
            let wd = w0 * (1 - damping * damping).squareRoot()
            return 1 - exp(-damping * w0 * t) * (cos(wd * t) + damping * w0 / wd * sin(wd * t))
        }
        return 1 - exp(-w0 * t) * (1 + w0 * t)
    }

    private static func clamp(_ v: Double) -> Double { min(1, max(0, v)) }

    /// Стан у момент `date`: прогрес ширини й висоти (0 — кнопка, 1 — вікно) і час від початку руху
    private func state(at date: Date) -> (pw: Double, ph: Double, t: Double) {
        let t = date.timeIntervalSince(morph.start)
        let to: Double = morph.opening ? 1 : 0
        // Відкриття: вшир швидше, ніж униз; закриття: спершу вузьке, потім коротке — звідси крапля
        let (rw, dw, rh, dh) = morph.opening ? (0.34, 0.76, 0.48, 0.80) : (0.24, 0.92, 0.40, 0.88)
        let pw = morph.fromW + (to - morph.fromW) * Self.spring(t, rw, dw)
        let ph = morph.fromH + (to - morph.fromH) * Self.spring(t, rh, dh)
        return (pw, ph, t)
    }

    private func startMorph(opening: Bool) {
        let now = Date()
        let current = state(at: now)
        morph = Morph(start: now, opening: opening, fromW: current.pw, fromH: current.ph)
        animating = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            if morph.start == now { animating = false }
        }
    }

    private var installed: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !animating)) { context in
            let st = state(at: animating ? context.date : .distantFuture)
            morphView(pw: st.pw, ph: st.ph, t: st.t)
        }
        .onChange(of: shown) { open in
            if open != morph.opening { startMorph(opening: open) }
        }
    }

    private func morphView(pw: Double, ph: Double, t: Double) -> some View {
        let w = max(size * 0.7, size + (panelSize.width - size) * pw)
        let h = max(size * 0.7, size + (panelSize.height - size) * ph)
        let p = Self.clamp((pw + ph) / 2)
        // Вміст проступає, коли скло вже розтеклось, і гасне першим при закритті; іконка — навпаки
        let content = morph.opening ? Self.clamp((t - 0.1) / 0.26) : Self.clamp(1 - t / 0.11)
        let iconAlpha = morph.opening ? Self.clamp(1 - t / 0.09) : Self.clamp((t - 0.22) / 0.2)
        let shape = DropletShape(closed: size, open: panelSize)
        return ZStack(alignment: .topTrailing) {
            panel()
                .fixedSize()
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { panelSize = g.size }
                        .onChange(of: g.size) { panelSize = $0 }
                })
                .scaleEffect(0.35 + 0.65 * p, anchor: .topTrailing)
                .blur(radius: 10 * (1 - content))
                .opacity(content)
                .allowsHitTesting(shown)
            icon
                .blur(radius: 6 * (1 - iconAlpha))
                .opacity(iconAlpha)
                .allowsHitTesting(!shown)
        }
        .frame(width: w, height: h, alignment: .topTrailing)
        .clipShape(shape)
        .modifier(MorphingGlass(shape: shape, interactive: !shown))
        .contentShape(shape)
        .onTapGesture { if !shown { shown = true } }
        .accessibilityAddTraits(.isButton)
    }

    private var icon: some View {
        Image("IconInstalled")
            .resizable()
            .frame(width: 23, height: 23)
            .foregroundStyle(Color.primary)
            .frame(width: size, height: size)
            .contentShape(Circle())
            .accessibilityLabel(Text("Встановлені"))
    }
}

/// Скляне коло без морфінгу (кнопка фільтра в D)
/// Форма вікна D, що виводиться з поточного розміру: коло кнопки (closed) → прямокутник із заокругленнями (open).
/// Поки ширина й висота «не встигають» одна за одною, форма деформується: при закритті — вузька крапля,
/// що звужується до кнопки (верхній лівий кут з'їжджає вправо, низ повністю круглий); при відкритті — м'яка
/// округла пляма. Повністю відкрита чи закрита — звичайна форма без деформації.
private struct DropletShape: Shape {
    let closed: CGFloat
    let open: CGSize

    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        func norm(_ v: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
            b - a < 1 ? 1 : min(1, max(0, (v - a) / (b - a)))
        }
        let pw = norm(w, closed, open.width), ph = norm(h, closed, open.height)
        let lag = ph - pw                    // > 0: вузька й висока (закриття), < 0: широка й низька (відкриття)
        let d = min(1, abs(lag) * 2.4)       // сила деформації
        let base = min(30, w / 2, h / 2)
        let round = min(w / 2, h / 2)
        let soft = base + (round - base) * d
        let taper = lag > 0 ? min(w * 0.42, lag * w * 0.6) : 0

        let tl = CGPoint(x: r.minX + taper, y: r.minY)
        let tr = CGPoint(x: r.maxX, y: r.minY)
        let br = CGPoint(x: r.maxX, y: r.maxY)
        let bl = CGPoint(x: r.minX, y: r.maxY)
        func len(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        let top = len(tl, tr), right = len(tr, br), bottom = len(br, bl), left = len(bl, tl)
        let rTR = min(base, top / 2, right / 2)
        let rBR = min(soft, right / 2, bottom / 2)
        let rBL = min(soft, bottom / 2, left / 2)
        let rTL = min(soft, left / 2, top / 2)

        var p = Path()
        p.move(to: CGPoint(x: (tl.x + tr.x) / 2, y: r.minY))
        p.addArc(tangent1End: tr, tangent2End: br, radius: max(0.1, rTR))
        p.addArc(tangent1End: br, tangent2End: bl, radius: max(0.1, rBR))
        p.addArc(tangent1End: bl, tangent2End: tl, radius: max(0.1, rBL))
        p.addArc(tangent1End: tl, tangent2End: tr, radius: max(0.1, rTL))
        p.closeSubpath()
        return p
    }
}

/// Скло, форма якого анімується разом із розміром (D); на старіших iOS — матеріал
private struct MorphingGlass<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            content.background(shape.fill(.regularMaterial))
        }
    }
}

private struct PlainGlassCircle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(Circle().fill(Color(.tertiarySystemFill)))
        }
    }
}

/// Маленька капсула-мініатюра циферблата для списку «Встановлені»
private struct MiniCapsule: View {
    let image: UIImage?
    let size: CGSize
    /// Обведення ззовні, як у капсул магазину: сама картинка має розмір `size`, рамка 3 pt навколо
    var body: some View {
        ZStack {
            Capsule(style: .continuous).fill(Color.black)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(Capsule(style: .continuous))
        .padding(3)
        .background(Capsule(style: .continuous).fill(Color.gray.opacity(0.45)))
    }
}

/// Ховає маленький (компактний) заголовок панелі навігації, не чіпаючи великого:
/// порожній центральний пункт займає його місце.
private struct HideInlineTitle: ViewModifier {
    let hidden: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.toolbar {
                if hidden {
                    ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
                        .sharedBackgroundVisibility(.hidden)
                }
            }
        } else {
            content.toolbar {
                if hidden {
                    ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
                }
            }
        }
    }
}

/// Мітка фільтра: дані для циклу
private struct ChipItem: Identifiable, Equatable {
    let id: String
    let title: String
    let on: Bool
}

/// Мітка фільтра. Ширину задає жирний варіант тексту (невидимий), тож при виборі мітки не змінюють розмір
private struct FilterChip: View {
    let title: String
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .hidden()
                .overlay(Text(title).font(.subheadline.weight(on ? .semibold : .medium)))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .foregroundStyle(on ? Color.white : Color.primary)
                .modifier(ChipGlass(on: on))
        }
        .buttonStyle(.plain)
    }
}

/// Мітки фільтра: на iOS 26 усі скляні, вибрана — скло з акцентним відтінком (як кнопки .glassProminent).
/// На старіших версіях вибрана зафарбована акцентним кольором.
private struct ChipGlass: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular.tint(on ? Color.accentColor : nil).interactive(), in: Capsule())
        } else {
            content.background(Capsule().fill(on ? Color.accentColor : Color.gray.opacity(0.15)))
        }
    }
}

/// Ряд міток. На iOS 26 — в одному GlassEffectContainer: скло малюється за один прохід,
/// і анімації (пошук, вибір мітки) не втрачають кадрів.
private struct ChipRow<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) { content }
            }
        } else {
            HStack(spacing: 8) { content }
        }
    }
}
