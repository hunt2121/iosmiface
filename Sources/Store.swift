import SwiftUI
import UIKit
import BandFaceKit

/// Одне зображення на сторінці циферблата.
struct FacePreview: Identifiable {
    let id = UUID()
    let title: String
    let image: UIImage?
}

/// Варіант циферблата для перемикача на сторінці («Англійська · 12 год»)
struct StoreVariantOption: Equatable {
    let key: String
    let label: String
}

/// Циферблат у магазині з сервера — вибраним варіантом (пристрій, мова, формат часу).
/// Файл варіанта завантажується лише під час встановлення.
struct StoreFace: Identifiable {
    let id: String          // ID циферблата на браслеті (вибраного варіанта)
    let name: String
    let kinds: [String]     // назви категорій мовою інтерфейсу
    let version: String     // «1.1»; вища за встановлену — з'являється «Оновити»
    let about: String
    let price: String?      // nil — безкоштовний; інакше ID покупки App Store
    var preview: UIImage?
    var added: Date?          // коли з'явився в магазині (для сортування за датою)
    var bands: [Int] = [10]   // підтримувані моделі Smart Band
    var previews: [FacePreview] = []   // зображення на сторінці: основний екран і «Завжди на екрані»
    /// Анімація основного екрана (GIF), спільна для картки й сторінки
    var animation: Data?
    /// ID запису магазину: незмінний при зміні варіанта
    var key = ""
    /// Розмір файла варіанта з сервера
    var size = 0
    /// Варіант із сервера: звідки завантажити файл і превʼю
    var remote: RemoteCatalog.Variant?
    /// ID усіх варіантів запису на браслеті
    var allIDs: Set<String> = []
    var variantKey: String?
    var variantOptions: [StoreVariantOption] = []
    /// Ключі категорій (для фільтра)
    var kindKeys: [String] = []
    /// Коли опубліковано поточну версію
    var updated: Date?
    /// Кольори циферблата («#RRGGBB») і стилі з превʼю для кожного кольору
    var colors: [String] = []
    var styles: [StoreStyle] = []
    /// «Що нового» в поточній версії (мовою телефона)
    var whatsNew = ""
    /// Ціна з App Store («39,99 ₴»); nil — товару немає (застосунок не з App Store)
    var priceText: String?
    /// Платний і вже куплений
    var owned = false

    var storeKey: String { key.isEmpty ? id : key }
    var ids: Set<String> { allIDs.isEmpty ? [id] : allIDs }
    var isFree: Bool { price == nil }
    /// Платний і ще не куплений: на кнопці — ціна
    var needsPurchase: Bool { price != nil && !owned }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) }
    /// «Band 10 · 11»
    var bandsText: String { "Band " + bands.map(String.init).joined(separator: " · ") }
    /// «1,2 MB · v1.1»
    var meta: String { "\(sizeText) · v\(version)" }
    /// Що показати на кнопці замість «Встановити»
    var buyText: String? { needsPurchase ? (priceText ?? String(localized: "Платний")) : nil }
}

extension FaceFile {
    /// Превью з файла, один раз зменшене під капсулу на екрані (3x),
    /// щоб прокрутка й анімації не працювали з великим зображенням
    func previewImage() -> UIImage? {
        guard let cg = try? decodePreview()?.makeCGImage() else { return nil }
        let full = UIImage(cgImage: cg)
        return full.preparingThumbnail(of: CGSize(width: 330, height: 780)) ?? full
    }
}

/// Каталог магазину — з сервера (StoreRemote.swift)
enum StoreCatalog {}

/// Записи про встановлені циферблати: «ID=версія», через кому.
enum InstalledFaces {
    /// «ID=версія» через кому; старі записи — ціле число або без версії
    static func parse(_ raw: String) -> [String: String] {
        var map: [String: String] = [:]
        for part in raw.split(separator: ",") {
            let pair = part.split(separator: "=")
            if pair.count == 2 { map[String(pair[0])] = String(pair[1]) }
            else if pair.count == 1 { map[String(pair[0])] = "1" }
        }
        return map
    }

    static func encode(_ map: [String: String]) -> String {
        map.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }
}

/// Передогляд циферблата в капсулі з рамкою ззовні, як корпус браслета.
/// Той самий вигляд на вкладці «Циферблати», в магазині й на сторінці циферблата.
struct FaceCapsule: View {
    let image: UIImage?
    /// Циферблат зараз на екрані браслета — рамка зелена
    var active = false
    /// Анімоване превʼю (GIF) — програється замість картинки
    var animation: Data? = nil

    var body: some View {
        ZStack {
            Capsule(style: .continuous).fill(Color.black)
            if let animation {
                FaceAnimationView(gif: animation)
            } else if let image {
                // UIImageView: програє й анімовані превʼю
                FaceImageView(image: image)
            } else {
                Image("TabWatch").resizable().scaledToFit()
                    .frame(width: 30)
                    .foregroundStyle(Color(white: 0.4))
            }
        }
        .frame(width: 96, height: 236)
        .clipShape(Capsule(style: .continuous))
        .padding(3)
        .background(Capsule(style: .continuous).fill(active ? Color.okGreen : Color.gray.opacity(0.45)))
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
            && a.faces.map(\.preview).elementsEqual(b.faces.map(\.preview), by: { $0 === $1 })
            && a.faces.map { $0.animation?.count } == b.faces.map { $0.animation?.count }
            && a.installingID == b.installingID && a.busy == b.busy
            && a.progress == b.progress && a.progressText == b.progressText
            && a.activeID == b.activeID && a.otherFaces == b.otherFaces
            && a.deviceName == b.deviceName && a.deviceInfo == b.deviceInfo
    }

    let faces: [StoreFace]
    let installed: [String: String]
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
    /// «Змінити в редакторі»: копія циферблата відкривається на вкладці «Редактор»
    var onEdit: (StoreFace) -> Void = { _ in }
    /// Інший варіант циферблата (мова, формат часу) — ключ варіанта
    var onVariant: (StoreFace, String) -> Void = { _, _ in }
    /// Категорії каталогу (ключ, назва) — у порядку з сервера
    var categories: [(String, String)] = []

    @State private var path: [String] = []
    @State private var filter = "all"
    /// Сортування на час роботи застосунку (після перезапуску знову «Спочатку нові»);
    /// reversed — протилежний до звичного напрямок
    @State private var sortKey = StoreSort.date.rawValue
    @State private var sortReversed = false
    /// Перегляди й завантаження всіх записів — для сортування й капсули на картці;
    /// одразу збережені з диска, потім свіжі з сервера (не відповів — лишаються збережені)
    @State private var stats: [String: StoreServer.FaceStats] = StoreServer.cachedStats()
    /// Циферблат, який просять видалити з меню (підтвердження), і помилка дії з меню
    @State private var menuDelete: BandFace?
    @State private var menuError: String?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]


    private var shown: [StoreFace] {
        let filtered = faces.filter { f in
            switch filter {
            case "all": return true
            case "paid": return !f.isFree
            case "free": return f.isFree
            default: return f.kindKeys.contains(filter)
            }
        }
        return (StoreSort(rawValue: sortKey) ?? .date).sorted(filtered, reversed: sortReversed, stats: stats)
    }

    private func state(_ f: StoreFace) -> StoreAction {
        if busy && installingID == f.id { return .installing }
        if let v = installed[f.id] { return StoreVersions.older(v, than: f.version) ? .update : .installed }
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
                                NavigationLink(value: item.storeKey) {
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
            .refreshable { await onRefresh(); await loadStats() }
            .task { await loadStats() }
            .background(Color(.systemGroupedBackground))
            // Без фільтра — «Магазин», з фільтром — його назва («Платні», «Безкоштовні», «Цифровий»…)
            .navigationTitle(filter == "all" ? String(localized: "Магазин")
                             : filterOptions.first { $0.0 == filter }?.1 ?? String(localized: "Магазин"))
            .navigationBarTitleDisplayMode(.large)
            // Під заголовком — поточне сортування («Спочатку нові», «Більше переглядів»…), з iOS 26
            .modifier(NavigationSubtitle(text: (StoreSort(rawValue: sortKey) ?? .date).direction(reversed: StoreSort(rawValue: sortKey) == nil ? false : sortReversed)))
            .navigationDestination(for: String.self) { id in
                if let item = faces.first(where: { $0.storeKey == id }) {
                    StoreDetailView(item: item,
                                    state: state(item),
                                    installedVersion: installed[item.id],
                                    busy: busy,
                                    progress: progress,
                                    progressText: progressText,
                                    onInstall: onInstall,
                                    isActive: item.id == activeID,
                                    onSelect: { await onActivate(item) },
                                    onDelete: { await onDelete(item) },
                                    onEdit: { onEdit(item) },
                                    onVariant: { onVariant(item, $0) })
                }
            }
            .modifier(StoreToolbar(filter: $filter, filters: filterOptions,
                                   sortKey: $sortKey, sortReversed: $sortReversed,
                                   onRefresh: { Task { await onRefresh() } },
                                   menuFaces: faces.filter { installed[$0.id] != nil },
                                   activeID: activeID,
                                   onOpen: { path.append($0.storeKey) },
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

    /// Числа для сортування за переглядами й завантаженнями
    private func loadStats() async {
        stats = await StoreServer.stats()
    }

    /// Пункти фільтра: (ідентифікатор, назва)
    private var filterOptions: [(String, String)] {
        [("all", String(localized: "Усі")), ("paid", String(localized: "Платні")),
         ("free", String(localized: "Безкоштовні"))] + categories.filter { c in faces.contains { $0.kindKeys.contains(c.0) } }
    }

    /// Дія з меню (вибрати, видалити); помилку показуємо окремим вікном
    private func menuAction(_ work: @escaping () async -> String?) {
        Task { @MainActor in
            if let error = await work() { menuError = error }
        }
    }

    private func card(_ item: StoreFace) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // від капсули до букв назви — стільки ж, скільки від верху картки до капсули (12 + 10 відступу картки)
            FaceCapsule(image: item.preview, active: item.id == activeID, animation: item.animation)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, Self.capsuleToName)

            VStack(alignment: .leading, spacing: 0) {
                // кольори циферблата — кружечки праворуч від назви
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    ColorDots(colors: item.colors)
                }
                // розмір і версія — завжди; кількість стилів — праворуч
                HStack(spacing: 6) {
                    Text(verbatim: infoText(item))
                    Spacer(minLength: 0)
                    if item.styles.count > 1 { Text(verbatim: StoreText.styles(item.styles.count)) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 8)

            // перегляди й завантаження — під тонкою лінією, рівно посередині між нею і кнопкою; завжди
            // (ще не відкривали чи чисел немає зовсім — 0); і під час встановлення теж
            Divider().padding(.horizontal, 2)
            StoreStatsCardRow(stats: stats[item.storeKey] ?? StoreServer.FaceStats(views: 0, downloads: 0))
            FaceActionButton(state: state(item), price: item.buyText, busy: busy,
                             progress: progress, progressText: progressText) {
                onInstall(item)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    /// Відступ під капсулою до рамки рядка назви: щоб від капсули до верху великих літер назви було 22 pt —
    /// як від верху картки до капсули. Рядок назви 20 pt заввишки, текст у ньому по центру;
    /// над великими літерами в рамці тексту — ascender − capHeight
    private static let capsuleToName: CGFloat = {
        let f = UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .semibold)
        return max(0, 22 - (f.ascender - f.capHeight))   // як у редакторі: рядок назви — заввишки з текст
    }()

    /// «1,2 MB · v1.1», для оновлення — «1,2 MB · v1.0 → 1.1»
    private func infoText(_ item: StoreFace) -> String {
        if let v = installed[item.id], StoreVersions.older(v, than: item.version) {
            return "\(item.sizeText) · v\(v) → \(item.version)"
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
            InstallProgress(progress: progress, text: progressText, large: large)
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
    let installedVersion: String?
    let busy: Bool
    let progress: Double
    let progressText: String
    let onInstall: (StoreFace) -> Void
    /// Циферблат зараз на екрані браслета
    var isActive = false
    /// «Вибрати» (зробити активним) і «Видалити з браслета»: nil — успіх, інакше текст помилки
    var onSelect: () async -> String? = { nil }
    var onDelete: () async -> String? = { nil }
    /// «Змінити в редакторі»
    var onEdit: () -> Void = {}
    /// Інший варіант (мова, формат часу)
    var onVariant: (String) -> Void = { _ in }

    private enum Work { case select, delete }
    @State private var working: Work?
    /// Вибрані стиль і колір (лише перегляд: на браслеті вибираються після встановлення)
    @State private var style = 0
    @State private var color = 0
    /// Перемальовує превʼю, коли вибраний стиль чи колір завантажився
    @State private var loadedLook = 0
    @State private var askDelete = false
    @State private var error: String?
    /// Перегляди й завантаження запису (з сервера)
    @State private var stats: StoreServer.FaceStats?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                previews

                // «Розмір · Версія · Пристрої», під лінією — завантаження й перегляди (та сама плашка)
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        infoColumn("Розмір", item.sizeText)
                        Divider().frame(height: 34)
                        infoColumn("Версія", item.version)
                        Divider().frame(height: 34)
                        infoColumn("Пристрої", item.bandsText)
                    }
                    .padding(.vertical, 16)
                    Divider().padding(.horizontal, 8)
                    StoreStatsLine(stats: stats ?? StoreServer.FaceStats(views: 0, downloads: 0))
                        .padding(.vertical, 12)
                }
                .padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground)))

                // Кілька варіантів (мови, 12/24 год) — вибір; за замовчуванням підібрано під телефон
                if item.variantOptions.count > 1 {
                    HStack(spacing: 0) {
                        // назва варіанта — завжди в один рядок; якщо тісно — обрізається трикрапкою лише вона
                        Text("Мова")
                            .fixedSize()
                        Spacer(minLength: 15)   // безпечний відступ до назви варіанта
                        Picker("Мова", selection: Binding(get: { item.variantKey ?? "" }, set: { onVariant($0) })) {
                            ForEach(item.variantOptions, id: \.key) { Text($0.label).tag($0.key) }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(state == .installing)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 6)
                    .frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground)))
                }

                actions

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Color.errorRed)
                        .padding(.horizontal, 4)
                }

                // «Що нового» — тим, у кого стара версія
                if state == .update && !item.whatsNew.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Що нового у версії \(item.version)").font(.headline)
                        Text(item.whatsNew).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground)))
                }

                Text(item.about)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                information

                editRow

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
        // відкрили сторінку: +1 перегляд, потім числа (перемикання мови — той самий запис, не рахується вдруге)
        .task(id: item.key) {
            if stats == nil { stats = StoreServer.cachedStats()[item.key] }
            await StoreServer.sendView(item.key)
            stats = await StoreServer.stats()[item.key] ?? StoreServer.FaceStats(views: 0, downloads: 0)
        }
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
                        .foregroundStyle(Color.okGreen)
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
            FaceActionButton(state: state, price: item.buyText, busy: busy,
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

    /// Копія циферблата в редакторі (з власним ID — оригінал на пристрої не зміниться)
    private var editRow: some View {
        Button(action: onEdit) {
            VStack(spacing: 2) {
                Label("Змінити в редакторі", systemImage: "pencil")
                    .font(.body.weight(.semibold))
                Text("Буде створено копію — оригінал не зміниться")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground)))
            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(state == .installing)
    }

    private var deleteRow: some View {
        Button { askDelete = true } label: {
            Text("Видалити з пристрою")
                .opacity(working == .delete ? 0 : 1)
                .overlay { if working == .delete { ProgressView() } }
                .foregroundStyle(Color.errorRed)
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

    /// Є що вибирати: кілька стилів або кольорів
    private var hasLooks: Bool { item.styles.count > 1 || item.colors.count > 1 }

    /// Превʼю вибраного стилю й кольору; на головній завантажено лише основне — решта тут, усі одразу після відкриття
    private var previews: some View {
        let look = item.look(style: style, color: color)
        let cache = StorePreviewCache.shared
        let main = style == 0 && color == 0 ? (item.preview ?? cache.image(look?.main)) : cache.image(look?.main)
        let gif = color == 0 ? (style == 0 ? item.animation : nil) ?? cache.gif(item.styles.indices.contains(style) ? item.styles[style].anim : nil) : nil
        return VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 28) {
                VStack(spacing: 10) {
                    FaceCapsule(image: main, animation: gif)
                    Text("Звичайний").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                }
                if look?.aod != nil || (item.styles.isEmpty && item.previews.count > 1) {
                    VStack(spacing: 10) {
                        FaceCapsule(image: cache.image(look?.aod) ?? (item.previews.count > 1 ? item.previews[1].image : nil))
                        Text("Завжди на екрані").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    }
                }
            }
            // перемальовуються лише превʼю, коли довантажились; перемикачі не створюються заново посеред анімації
            .id(loadedLook)
            // перемикач стилів, кольори й підпис — з однаковими відступами між собою;
            // без вибору стилю й кольору блоку немає зовсім (інакше під превʼю зайвий відступ)
            if hasLooks {
            VStack(spacing: 16) {
                if item.styles.count > 1 {
                    Picker("Стиль", selection: $style) {
                        ForEach(item.styles.indices, id: \.self) { i in
                            Text(item.styles[i].name.isEmpty ? String(localized: "Стиль \(i + 1)") : item.styles[i].name).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    // не на всю картку: близько 110 pt на стиль, по центру
                    .frame(maxWidth: CGFloat(item.styles.count) * 110)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                }
                if item.colors.count > 1 {
                    HStack(spacing: 12) {
                        ForEach(item.colors.indices, id: \.self) { i in
                            Button { color = i } label: {
                                Circle().fill(Color(hex: item.colors[i]))
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(i == color ? Color(hex: item.colors[i]) : .clear, lineWidth: 2.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(verbatim: item.colors[i]))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                if hasLooks {
                    Text("Стиль і колір вибираються на браслеті\nпісля встановлення")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        // порожнє місце над великими літерами в рядку тексту — щоб на око відступ був такий самий
                        .padding(.top, -4)
                }
            }
            }
        }
        .frame(maxWidth: .infinity)
        // знизу від букв останнього рядка до краю картки — стільки ж, скільки зверху до превʼю:
        // рамка рядка тексту нижче букв на висоту виносних елементів шрифту
        .padding(.top, 22)
        .padding(.bottom, 22 + UIFont.preferredFont(forTextStyle: hasLooks ? .caption1 : .footnote).descender)
        .background(RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color(.secondarySystemGroupedBackground)))
        .task(id: "\(item.variantKey ?? "")/\(style)/\(color)") {
            let look = item.look(style: style, color: color)
            let anim = color == 0 && item.styles.indices.contains(style) ? item.styles[style].anim : nil
            if await StorePreviewCache.shared.load(png: [look?.main, look?.aod].compactMap { $0 }, gif: [anim].compactMap { $0 }) {
                loadedLook += 1
            }
        }
        // одразу після відкриття сторінки — усі стилі й кольори, щоб перемикання не чекало завантаження
        .task(id: item.variantKey ?? "") {
            var png: [String] = [], gif: [String] = []
            for s in item.styles.indices {
                if let a = item.styles[s].anim { gif.append(a) }
                for c in item.styles[s].previews.indices {
                    guard let look = item.look(style: s, color: c) else { continue }
                    png.append(look.main)
                    if let a = look.aod { png.append(a) }
                }
            }
            if await StorePreviewCache.shared.load(png: png, gif: gif) {
                loadedLook += 1
            }
        }
    }

    /// «Інформація»: плитки сумісності, вигляду, мови й дати, під ними категорії
    private var information: some View {
        StoreInfoTiles(item: item)
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

/// Сортування магазину (порядок у меню). Звичний напрямок: дата — спочатку нові,
/// перегляди й завантаження — спочатку більше (числа з сервера; при рівних — новіші вище).
enum StoreSort: String, CaseIterable {
    case date, views, downloads

    var title: String {
        switch self {
        case .date: return String(localized: "Дата")
        case .views: return String(localized: "Перегляди")
        case .downloads: return String(localized: "Завантаження")
        }
    }

    func direction(reversed: Bool) -> String {
        switch self {
        case .date: return reversed ? String(localized: "Спочатку старі") : String(localized: "Спочатку нові")
        case .views: return reversed ? String(localized: "Менше переглядів") : String(localized: "Більше переглядів")
        case .downloads: return reversed ? String(localized: "Менше завантажень") : String(localized: "Більше завантажень")
        }
    }

    func sorted(_ faces: [StoreFace], reversed: Bool, stats: [String: StoreServer.FaceStats]) -> [StoreFace] {
        let byDate = faces.sorted { ($0.added ?? .distantPast) > ($1.added ?? .distantPast) }
        let result: [StoreFace]
        switch self {
        case .date:
            result = byDate
        case .views, .downloads:
            func count(_ f: StoreFace) -> Int {
                guard let s = stats[f.storeKey] else { return 0 }
                return self == .views ? s.views : s.downloads
            }
            // стабільне сортування поверх дати: при рівних числах новіші лишаються вище
            result = byDate.enumerated().sorted { a, b in
                let (x, y) = (count(a.element), count(b.element))
                return x != y ? x > y : a.offset < b.offset
            }.map(\.element)
        }
        return reversed ? result.reversed() : result
    }
}

/// Кнопка категорій і сортування на UIKit-меню. SwiftUI-меню не вміє водночас системну галочку й підпис
/// (рядок із галочкою втрачає підпис, а рядок із підписом показує галочку як велику іконку) і не оновлює
/// відкрите меню. UIMenu вміє все: заголовок секції «Категорія», галочку + підпис з напрямком,
/// пункти сортування, після яких меню лишається відкритим і одразу показує новий стан.
private struct FilterSortMenuButton: UIViewRepresentable {
    let filters: [(String, String)]
    @Binding var filter: String
    @Binding var sortKey: String
    @Binding var sortReversed: Bool

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.showsMenuAsPrimaryAction = true
        button.setContentHuggingPriority(.required, for: .horizontal)
        configure(button)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        configure(button)
    }

    private func configure(_ button: UIButton) {
        let active = filter != "all"
        let config = UIImage.SymbolConfiguration(textStyle: .body, scale: .large)
            .applying(UIImage.SymbolConfiguration(weight: .medium))
        button.setImage(UIImage(systemName: active ? "line.3.horizontal.decrease.circle.fill"
                                                   : "line.3.horizontal.decrease", withConfiguration: config),
                        for: .normal)
        button.tintColor = active ? .tintColor : .label
        let menu = makeMenu()
        button.menu = menu
        // Якщо меню відкрите (пункти сортування його не закривають) — показуємо новий стан одразу
        button.contextMenuInteraction?.updateVisibleMenu { _ in menu }
    }

    private func makeMenu() -> UIMenu {
        let categories = filters.map { item in
            UIAction(title: item.1, state: item.0 == filter ? .on : .off) { _ in filter = item.0 }
        }
        let sorts = StoreSort.allCases.map { sort -> UIAction in
            let selected = sort.rawValue == sortKey
            // Напрямок — лише під вибраним пунктом
            let subtitle = selected ? sort.direction(reversed: sortReversed) : nil
            let action = UIAction(title: sort.title, subtitle: subtitle, attributes: [.keepsMenuPresented],
                                  state: selected ? .on : .off) { _ in
                if selected { sortReversed.toggle() } else { sortKey = sort.rawValue; sortReversed = false }
            }
            return action
        }
        return UIMenu(children: [
            UIMenu(title: String(localized: "Категорія"), options: .displayInline, children: categories),
            UIMenu(title: String(localized: "Сортувати"), options: .displayInline, children: sorts)
        ])
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
                FilterSortMenuButton(filters: filters, filter: $filter,
                                     sortKey: $sortKey, sortReversed: $sortReversed)
                    .frame(width: 32, height: 32)
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
        // превʼю може змінитися (намальоване з ресурсів замість вбудованого) — воно теж у ключі
        let key = id + (active ? ":a" : "") + (preview.map { ":\(ObjectIdentifier($0).hashValue)" } ?? "")
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
                UIColor(Color.okGreen).setFill()
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
