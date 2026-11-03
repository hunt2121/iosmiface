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
        .background(Capsule(style: .continuous).fill(Color.gray.opacity(0.45)))
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
    }

    let faces: [StoreFace]
    let installed: [String: Int]
    let installingID: String?
    let busy: Bool
    let progress: Double
    let progressText: String
    let onInstall: (StoreFace) -> Void
    let onRefresh: () async -> Void

    @State private var query = ""
    /// Тимчасовий експеримент: 0 — A (кнопка фільтрів і пошук угорі), 1 — B (мітки фільтрів, без пошуку)
    @AppStorage("storeLayout") private var layout = 0
    /// Пошук відкрито (лупа розгорнулась у рядок)
    @State private var searchOpen = false
    /// Шлях навігації: змінюється на самому початку переходу до картки й назад,
    /// тож панель пошуку згасає й з'являється синхронно зі сторінкою
    @State private var path: [String] = []
    @State private var filter = "all"

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
                                    onInstall: onInstall)
                }
            }
            // Поки відкритий пошук, маленький системний заголовок ховаємо; великий лишається
            .modifier(HideInlineTitle(hidden: layout == 0 && searchOpen))
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

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            ChipRow {
                chip("all", String(localized: "Усі"))
                chip("new", String(localized: "Нові"))
                chip("free", String(localized: "Безкоштовні"))
                ForEach(kinds, id: \.self) { k in chip(k, k) }
            }
            // Запас навколо міток: при натисканні скло розширюється й не обрізається краєм прокрутки
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        // Компенсуємо запас, щоб розкладка залишилась тією самою
        .padding(.horizontal, -16)
        .padding(.vertical, -14)
    }

    private func chip(_ id: String, _ title: String) -> some View {
        let on = filter == id
        return Button { filter = id } label: {
            // Ширину задає жирний варіант тексту (невидимий), тож при виборі мітки не змінюють розмір
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

    private func card(_ item: StoreFace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                FaceCapsule(image: item.preview)
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
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.3))
                        Capsule().fill(Color.accentColor)
                            .frame(width: max(8, geo.size.width * progress))
                    }
                }
                .frame(height: 6)
                HStack {
                    Text(progressText).lineLimit(1)
                    Spacer()
                    Text(verbatim: "\(Int(progress * 100))%")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
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

                FaceActionButton(state: state, price: item.price, busy: busy,
                                 progress: progress, progressText: progressText, height: 52) {
                    onInstall(item)
                }

                Text(item.about)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
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

/// Мітки фільтра: на iOS 26 усі скляні, вибрана — скло з акцентним відтінком (як кнопки .glassProminent).
/// На старіших версіях вибрана зафарбована акцентним кольором.
/// Вибрана й звичайна — різні гілки: скло перестворюється, і відтінок гарантовано оновлюється
/// (інакше в GlassEffectContainer мітки категорій могли лишатися без підсвітки).
private struct ChipGlass: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if on {
                content.glassEffect(.regular.tint(Color.accentColor).interactive(), in: Capsule())
            } else {
                content.glassEffect(.regular.interactive(), in: Capsule())
            }
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
