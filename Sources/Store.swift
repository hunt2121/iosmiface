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
    /// Тимчасовий експеримент: 0 — кнопка пошуку біля заголовка, 1 — пошук унизу, 2 — пошук унизу з кнопкою фільтрів
    @AppStorage("storeSearchMode") private var searchMode = 0
    @State private var searchOpen = false
    @Namespace private var searchSpace
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
        // «Режим розробника»: у журнал пишеться кожне перемальовування сторінки магазину
        BLEManager.noteRedraw("Магазин")
        return NavigationStack {
            ScrollView {
                // Фільтр рахуємо один раз за оновлення екрана
                let items = shown
                VStack(alignment: .leading, spacing: 14) {
                    if searchMode == 3 && !searchOpen {
                        // D: рядок пошуку на звичному місці, у стилі iOS 26 ще до натискання
                        SearchPill(text: query)
                            .matchedGeometryEffect(id: "search", in: searchSpace)
                            .onTapGesture { withAnimation(.snappy(duration: 0.35)) { searchOpen = true } }
                    }
                    if searchMode == 0 && searchOpen {
                        StoreSearchField(text: $query) {
                            withAnimation(.snappy) { searchOpen = false }
                            query = ""
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if ![0, 2, 4, 6].contains(searchMode) { chips }
                    if items.isEmpty {
                        Text("Нічого не знайдено")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(items) { item in
                                NavigationLink {
                                    StoreDetailView(item: item,
                                                    state: state(item),
                                                    installedVersion: installed[item.id],
                                                    busy: busy,
                                                    progress: progress,
                                                    progressText: progressText,
                                                    onInstall: onInstall)
                                } label: {
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
            .navigationTitle("Магазин")
            .modifier(StoreSearchMode(mode: searchMode, query: $query, searchOpen: $searchOpen,
                                      filter: $filter, filters: filterOptions))
            // E: власна нижня панель — фільтр і пошук над вкладками; під час набору — над клавіатурою
            .safeAreaInset(edge: .bottom) {
                if searchMode == 4 {
                    BottomSearchBar(query: $query, filter: $filter, filters: filterOptions)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            // D: після натискання рядок пошуку переїжджає вниз, над клавіатуру
            .safeAreaInset(edge: .bottom) {
                if searchMode == 3 && searchOpen {
                    StoreSearchField(text: $query) {
                        withAnimation(.snappy(duration: 0.35)) { searchOpen = false }
                    }
                    .matchedGeometryEffect(id: "search", in: searchSpace)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
    }

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

/// Тимчасовий експеримент із пошуком магазину.
private struct StoreSearchMode: ViewModifier {
    let mode: Int
    @Binding var query: String
    @Binding var searchOpen: Bool
    @Binding var filter: String
    let filters: [(String, String)]

    func body(content: Content) -> some View {
        switch mode {
        case 0:
            // Кнопка-лупа біля заголовка; рядок пошуку з'являється над мітками
            content.toolbar {
                // Кнопка фільтрів ліворуч (мітки під заголовком у цьому варіанті сховані)
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker(selection: $filter) {
                            ForEach(filters, id: \.0) { f in Text(f.1).tag(f.0) }
                        } label: { EmptyView() }
                    } label: {
                        Image(systemName: filter == "all" ? "line.3.horizontal.decrease"
                                                          : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel(Text("Фільтр"))
                }
                if !searchOpen {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            withAnimation(.snappy) { searchOpen = true }
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel(Text("Пошук циферблатів"))
                    }
                }
            }
        case 2:
            if #available(iOS 26, *) {
                // Пошук унизу і поруч кнопка фільтрів, як у системних застосунках
                content
                    .searchable(text: $query, prompt: Text("Пошук циферблатів"))
                    .toolbar {
                        ToolbarItem(placement: .bottomBar) {
                            Menu {
                                Picker(selection: $filter) {
                                    ForEach(filters, id: \.0) { f in Text(f.1).tag(f.0) }
                                } label: { EmptyView() }
                            } label: {
                                Image(systemName: filter == "all"
                                      ? "line.3.horizontal.decrease"
                                      : "line.3.horizontal.decrease.circle.fill")
                            }
                        }
                        ToolbarSpacer(.fixed, placement: .bottomBar)
                        DefaultToolbarItem(kind: .search, placement: .bottomBar)
                    }
            } else {
                content.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic),
                                   prompt: Text("Пошук циферблатів"))
            }
        case 3, 4:
            content
        case 5, 6:
            // F / G: власний скляний рядок угорі, завжди видимий; заголовок ховається над ним при гортанні
            content.modifier(PinnedTopBar {
                TopSearchBar(query: $query, filter: $filter, filters: filters, showFilter: mode == 6)
            })
        default:
            if #available(iOS 26, *) {
                content.searchable(text: $query, prompt: Text("Пошук циферблатів"))
            } else {
                content.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic),
                                   prompt: Text("Пошук циферблатів"))
            }
        }
    }
}

/// Рядок пошуку для варіанта з кнопкою: скляний (iOS 26) з першої миті, одразу з клавіатурою.
struct StoreSearchField: View {
    @Binding var text: String
    let onClose: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color(.secondaryLabel))
                TextField("Пошук циферблатів", text: $text)
                    .focused($focused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { focused = false }
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color(.tertiaryLabel))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .modifier(FieldGlass())

            // Спершу ховаємо клавіатуру, потім закриваємо пошук — інакше анімації заважають одна одній
            CloseCircleButton(size: 44) {
                focused = false
                onClose()
            }
        }
        .onAppear { focused = true }
    }
}

private struct FieldGlass: ViewModifier {
    var circle = false
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            if circle { content.glassEffect(.regular.interactive(), in: Circle()) }
            else { content.glassEffect(.regular, in: Capsule()) }
        } else {
            if circle { content.background(Circle().fill(Color(.tertiarySystemFill))) }
            else { content.background(Capsule().fill(Color(.tertiarySystemFill))) }
        }
    }
}

/// Рядок пошуку в спокої (варіант D): виглядає як поле, натискання відкриває пошук.
struct SearchPill: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(.secondaryLabel))
            Text(text.isEmpty ? String(localized: "Пошук циферблатів") : text)
                .foregroundStyle(text.isEmpty ? Color(.placeholderText) : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .modifier(FieldGlass())
        .contentShape(Capsule())
        .accessibilityAddTraits(.isButton)
    }
}

/// Варіант E: нижня скляна панель як у «Пошті» — кнопка фільтрів і рядок пошуку.
/// Вигляд однаковий до й після натискання; під час набору панель стоїть над клавіатурою.
struct BottomSearchBar: View {
    @Binding var query: String
    @Binding var filter: String
    let filters: [(String, String)]
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Menu {
                Picker(selection: $filter) {
                    ForEach(filters, id: \.0) { f in Text(f.1).tag(f.0) }
                } label: { EmptyView() }
            } label: {
                Image(systemName: filter == "all" ? "line.3.horizontal.decrease"
                                                  : "line.3.horizontal.decrease.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(filter == "all" ? Color.primary : Color.accentColor)
                    .frame(width: 48, height: 48)
            }
            .modifier(FieldGlass(circle: true))

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color(.secondaryLabel))
                TextField("Пошук циферблатів", text: $query)
                    .focused($focused)
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
            .padding(.horizontal, 16)
            .frame(height: 48)
            .modifier(FieldGlass())
            .contentShape(Capsule())
            .onTapGesture { focused = true }

            if focused {
                CloseCircleButton(size: 48) { focused = false }
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: focused)
    }
}

/// Кругла кнопка закриття. На iOS 26 — системна скляна кнопка: iOS сама обробляє дотик,
/// тож натискання не «провалюються» до того, що під кнопкою, і не губляться.
struct CloseCircleButton: View {
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        if #available(iOS 26, *) {
            Button(action: action) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: size - 16, height: size - 16)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text("Закрити"))
        } else {
            Button(action: action) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color(.tertiarySystemFill)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Закрити"))
        }
    }
}

/// Панель, закріплена під заголовком. На iOS 26 — safeAreaBar: вміст під нею
/// плавно розмивається (як під системною панеллю), а великий заголовок ховається над нею при гортанні.
private struct PinnedTopBar<Bar: View>: ViewModifier {
    @ViewBuilder let bar: Bar
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.safeAreaBar(edge: .top) {
                bar.padding(.horizontal, 16).padding(.bottom, 8)
            }
        } else {
            content.safeAreaInset(edge: .top) {
                bar.padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.bar)
            }
        }
    }
}

/// Варіанти F і G: скляний рядок пошуку (і кнопка фільтрів) — однаковий вигляд до й після натискання.
struct TopSearchBar: View {
    @Binding var query: String
    @Binding var filter: String
    let filters: [(String, String)]
    let showFilter: Bool
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            if showFilter { FilterMenuButton(filter: $filter, filters: filters, size: 44) }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Color(.secondaryLabel))
                TextField("Пошук циферблатів", text: $query)
                    .focused($focused)
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
            .padding(.horizontal, 14)
            .frame(height: 44)
            .modifier(FieldGlass())
            .contentShape(Capsule())
            .onTapGesture { focused = true }

            if focused {
                CloseCircleButton(size: 44) { focused = false }
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: focused)
    }
}

/// Кругла кнопка фільтрів із меню. На iOS 26 — системна скляна кнопка.
struct FilterMenuButton: View {
    @Binding var filter: String
    let filters: [(String, String)]
    let size: CGFloat

    var body: some View {
        let menu = Menu {
            Picker(selection: $filter) {
                ForEach(filters, id: \.0) { f in Text(f.1).tag(f.0) }
            } label: { EmptyView() }
        } label: {
            Image(systemName: filter == "all" ? "line.3.horizontal.decrease"
                                              : "line.3.horizontal.decrease.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(filter == "all" ? Color.primary : Color.accentColor)
                .frame(width: size - 16, height: size - 16)
        }
        .accessibilityLabel(Text("Фільтр"))
        if #available(iOS 26, *) {
            menu.buttonStyle(.glass).buttonBorderShape(.circle)
        } else {
            menu.frame(width: size, height: size)
                .background(Circle().fill(Color(.tertiarySystemFill)))
        }
    }
}
