import SwiftUI
import UIKit
import UniformTypeIdentifiers
import BandFaceKit

struct ContentView: View {
    enum Tab: Hashable { case faces, store, settings }
    enum SettingsRoute: Hashable { case key, log }

    @EnvironmentObject var ble: BLEManager

    @State private var authKey: String = KeychainStore.load(account: "authKey") ?? ""
    @State private var showImporter = false
    @State private var importingFolder = false
    @State private var foundDevices: [MiFitnessKey.Device] = []
    @State private var keyStatus: String?
    @State private var keyStatusIsError = false
    @State private var showKeyHelp = false
    @State private var tab: Tab = .faces
    @State private var settingsPath: [SettingsRoute] = []
    @AppStorage("appTheme") private var appTheme = "system"
    @AppStorage("storeLayout") private var storeLayout = 0  // тимчасовий експеримент
    // Магазин
    @State private var storeFaces: [StoreFace] = StoreCatalog.cached
    @State private var installingID: String?
    @State private var syncing = false
    @State private var lastSync = Date.distantPast
    /// ID циферблата, який зараз на екрані браслета (з останньої перевірки)
    @State private var activeFaceID: String?
    /// Циферблати на браслеті не з магазину (з останньої перевірки)
    @State private var otherFaces: [BandFace] = []
    /// Заряд і прошивка браслета (з останньої перевірки)
    @State private var bandInfo = BandInfo()
    @AppStorage("installedFaceVersions") private var installedRaw = ""
    @State private var storeAlert: String?
    @State private var storeAlertGoTo: Tab?
    @State private var storeAlertOpensKey = false
    @State private var face: FaceFile?
    @State private var fileName: String?
    @State private var progress: Double = 0
    @State private var progressText = ""
    @State private var busy = false
    @State private var message: String?
    @State private var messageIsError = false
    @State private var filePreview: UIImage?
    @AppStorage("verboseLog") private var verboseLog = false
    @Environment(\.scenePhase) private var scenePhase

    private var keyValid: Bool {
        Hex.decode(authKey)?.count == 16
    }

    private var canOperate: Bool {
        keyValid && ble.connectedID != nil && ble.servicesReady && !busy
    }

    private static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    private static var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        TabView(selection: $tab) {
            facesTab
                .tabItem { Label("Циферблати", image: "TabWatch") }
                .tag(Tab.faces)

            StoreView(faces: storeFaces,
                      installed: InstalledFaces.parse(installedRaw),
                      installingID: installingID,
                      busy: busy,
                      progress: progress,
                      progressText: progressText,
                      onInstall: { storeInstall($0) },
                      onRefresh: { await syncDeviceFaces(force: true) },
                      activeID: activeFaceID,
                      onActivate: { await bandFaceAction($0, delete: false) },
                      onDelete: { await bandFaceAction($0, delete: true) },
                      onCheck: { await syncDeviceFaces() },
                      onPickFile: {
                          tab = .faces
                          Task { @MainActor in
                              try? await Task.sleep(nanoseconds: 350_000_000)
                              pickFace()
                          }
                      },
                      otherFaces: otherFaces,
                      onBandAction: { id, name, delete in await bandFaceAction(id: id, name: name, delete: delete) },
                      bandStatus: ble.connectedName.map { Self.shortBandModel($0) } ?? String(localized: "Браслет не підключено"),
                      bandBattery: ble.connectedName == nil ? nil : bandInfo.battery,
                      bandFirmware: ble.connectedName == nil ? nil : bandInfo.firmware)
                .equatable()
                .tabItem { Label("Магазин", image: "TabStore") }
                .tag(Tab.store)

            settingsTab
                .tabItem { Label("Налаштування", image: "TabSettings") }
                // Ключа немає — на іконці червоний знак «!»
                .badge(keyValid ? nil : Text("!"))
                .tag(Tab.settings)
        }
        .preferredColorScheme(appTheme == "light" ? .light : (appTheme == "dark" ? .dark : nil))
        .onChange(of: tab) { newTab in
            if newTab == .store { Task { await syncDeviceFaces() } }
        }
        .onChange(of: ble.servicesReady) { ready in
            if ready && tab == .store { Task { await syncDeviceFaces() } }
        }
        .onChange(of: scenePhase) { phase in
            // Відпускаємо браслет, щоб він вільно працював з Mi Fitness
            if phase == .background && !busy && (ble.connectedID != nil || ble.isConnecting) {
                ble.disconnect(byUser: false)
            }
            // Повернулися в застосунок — знову підключаємося до запам'ятованого браслета
            if phase == .active { ble.reconnectLast() }
            // Ключ міг змінитися в Mi Fitness (наприклад, після нового спарювання)
            if phase == .active { autoFindKey() }
        }
        .onAppear {
            autoFindKey()
        }
        .alert(storeAlert ?? "", isPresented: Binding(get: { storeAlert != nil },
                                                      set: { if !$0 { storeAlert = nil } })) {
            Button("Гаразд") {
                if storeAlertOpensKey { openKey(search: false) }
                else if let target = storeAlertGoTo { tab = target }
                storeAlertGoTo = nil
                storeAlertOpensKey = false
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: importingFolder ? [.folder] : [.data]) { result in
            if importingFolder { folderPicked(result) } else { loadFace(result) }
        }
        .alert("Пошук ключа", isPresented: $showKeyHelp) {
            Button("Вибрати папку") {
                Task { @MainActor in
                    // Даємо алерту закритися, інакше вікно вибору може не відкритися
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    importingFolder = true
                    showImporter = true
                }
            }
            Button("Скасувати", role: .cancel) {}
        } message: {
            Text("У вікні, що відкриється, перейдіть у розділ «На iPhone», виберіть папку «Mi Fitness» і натисніть «Відкрити». Застосунок сам знайде ключ і запам'ятає папку.")
        }
    }

    // MARK: - Магазин і налаштування

    private var facesTab: some View {
        NavigationStack {
            Form {
                if !keyValid {
                    Section {
                        Button {
                            // Ключ додається в налаштуваннях: переходимо туди й одразу починаємо пошук
                            openKey(search: true)
                        } label: {
                            Label("Додати ключ браслета", systemImage: "key")
                        }
                    } header: {
                        // Стандартний відступ першої секції — як «Браслет» і «Auth key» під заголовком екрана
                        Text("Ключ")
                    } footer: {
                        Text("Без ключа застосунок не зможе підключитися до браслета. Його можна знайти автоматично в даних Mi Fitness.")
                    }
                }
                bandSection
                installSection
            }
            .navigationTitle("Циферблати")
        }
    }

    private var settingsTab: some View {
        NavigationStack(path: $settingsPath) {
            Form {
                Section("Пристрій") {
                    NavigationLink(value: SettingsRoute.key) {
                        HStack {
                            SettingsLabel("Ключ", tile: .key)
                            Spacer()
                            // Та сама позначка, що всередині сторінки «Ключ»
                            Image(systemName: keyValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(keyValid ? Color.okIcon : Color.errorText)
                                .font(.title3)
                        }
                    }
                    NavigationLink(value: SettingsRoute.log) {
                        SettingsLabel("Журнал", tile: .log)
                    }
                }
                Section("Застосунок") {
                    Picker(selection: $appTheme) {
                        Text("Системна").tag("system")
                        Text("Світла").tag("light")
                        Text("Темна").tag("dark")
                    } label: {
                        SettingsLabel("Тема", tile: .theme)
                    }
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            SettingsLabel("Мова", tile: .language)
                            Spacer()
                            Text(Self.languageName).foregroundStyle(Color(.secondaryLabel))
                            // Стрілка переходу назовні (у системні налаштування), в стилі Apple
                            Image(systemName: "arrow.up.right")
                                .font(.body)
                                .foregroundStyle(Color(.secondaryLabel))
                        }
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    HStack {
                        SettingsLabel("Версія", tile: .version)
                        Spacer()
                        Text(verbatim: "\(Self.versionString).\(Self.buildNumber)")
                            .foregroundStyle(.secondary)
                    }
                }
                // Тимчасово: як фільтрувати циферблати в магазині
                Section {
                    Picker(selection: $storeLayout) {
                        Text(verbatim: "A · Кнопка фільтрів і пошук").tag(0)
                        Text(verbatim: "B · Мітки фільтрів без пошуку").tag(1)
                        Text(verbatim: "C · Системна панель: фільтр і оновлення").tag(2)
                        Text(verbatim: "D · Встановлені: спливаюче вікно").tag(3)
                        Text(verbatim: "E · Встановлені: аркуш знизу").tag(4)
                        Text(verbatim: "F · Встановлені: системне меню").tag(5)
                    } label: {
                        Text(verbatim: "Магазин")
                    }
                } header: {
                    Text(verbatim: "Експеримент")
                }
            }
            .navigationTitle("Налаштування")
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .key:
                    Form { authSection }
                        .navigationTitle("Ключ")
                        .navigationBarTitleDisplayMode(.inline)
                case .log:
                    Form {
                        logSection
                    }
                    .navigationTitle("Журнал")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    /// «Xiaomi Smart Band 10 E3B4» → «Xiaomi Smart Band 10»: без службового суфікса.
    /// «Smart Band 10» — без «Xiaomi», щоб вміщалось у меню
    static func shortBandModel(_ name: String) -> String {
        let model = bandModel(name)
        return model.hasPrefix("Xiaomi ") ? String(model.dropFirst("Xiaomi ".count)) : model
    }

    static func bandModel(_ name: String) -> String {
        if let r = name.range(of: #"^.*?Band\s*\d+"#, options: .regularExpression) { return String(name[r]) }
        return name
    }

    private static var languageName: String {
        let code = Locale.preferredLanguages.first ?? "uk"
        return (Locale.current.localizedString(forLanguageCode: code) ?? code).capitalized
    }

    /// Відкриває «Налаштування → Ключ»; `search` — одразу шукати ключ.
    private func openKey(search: Bool) {
        settingsPath = [.key]
        tab = .settings
        guard search else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            findKey()
        }
    }

    /// Звіряє циферблати магазину з тими, що зараз є на браслеті (за ID): видалений на браслеті
    /// знову отримує кнопку «Встановити», а встановлений поза застосунком позначається як наявний.
    @MainActor
    private func syncDeviceFaces(force: Bool = false) async {
        guard keyValid, ble.connectedID != nil, ble.servicesReady, !busy, !syncing,
              let key = Hex.decode(authKey), key.count == 16 else { return }
        if !force && Date().timeIntervalSince(lastSync) < 20 { return }
        syncing = true
        defer { syncing = false }
        guard let state = try? await FaceInstaller(ble: ble).bandState(authKey: key) else { return }
        bandInfo = state.info
        applyDeviceList(state.faces)
    }

    /// Запам'ятовує, що зараз на браслеті: які циферблати магазину встановлені й який на екрані.
    private func applyDeviceList(_ list: [WatchfaceInfo]) {
        lastSync = Date()
        // Стандартний циферблат браслет інколи не повертає в списку (зокрема коли він активний).
        // Він є на браслеті завжди, тож якщо в списку немає жодного активного — активний саме він
        let standardMissing = !list.contains { $0.id == BandFace.standardID }
        activeFaceID = list.first(where: \.isActive)?.id ?? (standardMissing ? BandFace.standardID : nil)
        let ids = Set(list.map(\.id))
        let storeIDs = Set(storeFaces.map(\.id))
        otherFaces = list.filter { !storeIDs.contains($0.id) }.map { f in
            // Стандартний циферблат Smart Band 10 вбудований: назви браслет не передає, видалити його не можна.
            // Решту видаляти можна (прапорцю з браслета не довіряємо — Band 10 його не надсилає)
            if f.id == BandFace.standardID {
                return BandFace(id: f.id, name: String(localized: "Стандартний"), isActive: f.isActive,
                                canDelete: false, note: String(localized: "Вбудований"))
            }
            return BandFace(id: f.id, name: f.name?.isEmpty == false ? f.name! : String(localized: "Циферблат \(f.id)"),
                            isActive: f.isActive, canDelete: true)
        }
        if standardMissing && !list.isEmpty {
            otherFaces.insert(BandFace(id: BandFace.standardID, name: String(localized: "Стандартний"),
                                       isActive: activeFaceID == BandFace.standardID, canDelete: false,
                                       note: String(localized: "Вбудований")), at: 0)
        }
        var map = InstalledFaces.parse(installedRaw)
        for f in storeFaces {
            if ids.contains(f.id) {
                if map[f.id] == nil { map[f.id] = f.version }
            } else {
                map[f.id] = nil
            }
        }
        installedRaw = InstalledFaces.encode(map)
    }

    /// Тестова функція «Встановлені»: увімкнути або видалити циферблат на браслеті.
    /// Повертає текст помилки для користувача або nil, якщо все вдалося.
    @MainActor
    private func bandFaceAction(_ item: StoreFace, delete: Bool) async -> String? {
        await bandFaceAction(id: item.id, name: item.name, delete: delete)
    }

    /// Те саме для будь-якого циферблата на браслеті (зокрема з Mi Fitness)
    @MainActor
    private func bandFaceAction(id: String, name: String, delete: Bool) async -> String? {
        guard keyValid, let key = Hex.decode(authKey), key.count == 16 else {
            return String(localized: "Спершу додайте ключ браслета")
        }
        guard ble.connectedID != nil, ble.servicesReady else {
            return String(localized: "Спершу підключіть браслет на вкладці «Циферблати»")
        }
        guard !busy else { return String(localized: "Зачекайте, поки завершиться встановлення") }
        // Фонова перевірка браслета могла ще не закінчитись — дві сесії одночасно не можна
        while syncing { try? await Task.sleep(nanoseconds: 100_000_000) }
        syncing = true
        defer { syncing = false }
        ble.addLog(delete ? String(localized: "Видалення циферблата \(name)…")
                          : String(localized: "Увімкнення циферблата \(name)…"))
        do {
            let installer = FaceInstaller(ble: ble)
            let list = delete ? try await installer.deleteFace(id: id, authKey: key)
                              : try await installer.activateFace(id: id, authKey: key)
            applyDeviceList(list)
            if delete {
                if list.contains(where: { $0.id == id }) {
                    ble.addLog(String(localized: "Браслет не видалив циферблат"))
                    return String(localized: "Браслет не видалив циферблат")
                }
                ble.addLog(String(localized: "Циферблат видалено"))
            } else {
                guard activeFaceID == id else {
                    ble.addLog(String(localized: "Браслет не увімкнув циферблат"))
                    return String(localized: "Браслет не увімкнув циферблат")
                }
                ble.addLog(String(localized: "Циферблат увімкнено"))
            }
            return nil
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            ble.addLog(text)
            return text
        }
    }

    private func storeInstall(_ item: StoreFace) {
        if syncing {
            storeAlert = String(localized: "Йде перевірка циферблатів на браслеті. Спробуйте за кілька секунд")
            return
        }
        guard keyValid else {
            storeAlert = String(localized: "Спершу додайте ключ браслета")
            storeAlertOpensKey = true
            return
        }
        guard ble.connectedID != nil && ble.servicesReady else {
            storeAlert = String(localized: "Спершу підключіть браслет на вкладці «Циферблати»")
            storeAlertGoTo = .faces
            return
        }
        if let n = ble.connectedName, let r = n.range(of: #"Band\s*(\d+)"#, options: .regularExpression),
           let model = Int(n[r].filter(\.isNumber)), !item.bands.contains(model) {
            storeAlert = String(localized: "Цей циферблат не підтримує ваш браслет")
            return
        }
        install(item.face, store: item)
    }

    // MARK: - Розділи

    /// Текст під кнопкою «Знайти автоматично»: результат пошуку або підказка, якщо ключа немає.
    private var keyStatusLine: (text: String, color: Color)? {
        if let keyStatus { return (keyStatus, keyStatusIsError ? Color.errorText : Color.okText) }
        if !keyValid { return (String(localized: "Введіть ключ вручну або знайдіть його автоматично"), Color.secondary) }
        return (String(localized: "Ключ введено вручну"), Color.okText)
    }

    private var authSection: some View {
        Section {
            // Поле, кнопка й статус в одному рядку картки з однаковими відступами.
            // Статус має фіксоване місце на два рядки, тож поява тексту нічого не зсуває.
            VStack(alignment: .leading, spacing: 14) {
                // Поле ключа з позначкою: зелена галочка — ключ коректний
                HStack(spacing: 10) {
                    TextField("32 hex-символи", text: $authKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: authKey) { key in
                            KeychainStore.save(key, account: "authKey")
                            // Ключ змінили вручну — старе «Ключ знайдено…» вже не про нього
                            if !foundDevices.contains(where: { $0.key == key.lowercased() }) { keyStatus = nil }
                        }
                    Image(systemName: keyValid ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(keyValid ? Color.okIcon : Color.secondary)
                        .font(.title3)
                }
                // Відступ від ключа до кнопки такий самий, як від верху картки до ключа
                .padding(.bottom, 7)
                Button {
                    findKey()
                } label: {
                    Text("Знайти автоматично").buttonText()
                }
                .glassProminentStyle()
                .buttonBorderShape(.capsule)
                // Статус — по центру місця між кнопкою і низом картки; висота фіксована
                Text(keyStatusLine?.text ?? " ")
                    .font(.footnote)
                    .foregroundStyle(keyStatusLine?.color ?? Color.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36, alignment: .center)
                    .padding(.bottom, 0)
            }
            .padding(.top, 6)
            if foundDevices.count > 1 {
                ForEach(foundDevices, id: \.self) { d in
                    Button {
                        authKey = d.key
                        keyStatus = String(localized: "Ключ для «\(d.name)» вибрано")
                        keyStatusIsError = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.name.isEmpty ? String(localized: "Пристрій без назви") : d.name)
                                if let mac = d.mac { Text(mac).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if d.key == authKey.lowercased() {
                                Image(systemName: "checkmark").foregroundStyle(Color.okIcon)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Auth key браслета")
        } footer: {
            // Обидва варіанти підпису займають місце, видно один — висота не змінюється
            ZStack(alignment: .topLeading) {
                Text("Папку Mi Fitness запам'ятовано: ключ перевіряється автоматично при кожному вході в застосунок.")
                    .opacity(MiFitnessKey.hasSavedFolder ? 1 : 0)
                Text("«Знайти автоматично» один раз попросить вибрати папку Mi Fitness, далі ключ шукатиметься сам.")
                    .opacity(MiFitnessKey.hasSavedFolder ? 0 : 1)
            }
        }
    }

    private var installSection: some View {
        Section("Встановлення циферблата") {
            HStack(alignment: .center, spacing: 18) {
                previewCapsule
                // Права колонка має фіксовані «слоти»: інформація, кнопки, прогрес.
                // Їхня висота не змінюється, тож нічого не стрибає.
                VStack(alignment: .leading, spacing: 8) {
                    infoBlock
                        .frame(height: 70, alignment: .topLeading)
                        .padding(.horizontal, 14)

                    // Перша кнопка завжди на тому самому місці; змінюються лише текст і стиль
                    Group {
                        if face == nil {
                            Button { pickFace() } label: { Text("Вибрати файл").buttonText() }
                                .glassProminentStyle()
                        } else {
                            Button { pickFace() } label: { Text("Вибрати інший файл").buttonText() }
                                .glassSecondaryStyle()
                                .disabled(busy)
                        }
                    }
                    Button {
                        if let face { install(face) }
                    } label: {
                        Text("Встановити").buttonText()
                    }
                    .glassProminentStyle()
                    .disabled(!canOperate || face == nil)

                    progressBlock
                        .frame(height: 36, alignment: .top)
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                }
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
            }
            .padding(.vertical, 8)
        }
    }

    /// Назва, ID і файл — завжди три рядки однакової висоти.
    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(face.map { $0.name ?? String(localized: "Циферблат \($0.id)") } ?? String(localized: "Файл не вибрано"))
                .font(.title3.bold())
            Text(face.map { String(localized: "ID \($0.id) · \(String($0.size / 1024)) КБ") } ?? String(localized: "Формат: .bin або .face"))
                .font(.footnote).foregroundStyle(.secondary)
            Text(face == nil ? String(localized: "Натисніть «Вибрати файл»") : (fileName ?? " "))
                .font(.caption).foregroundStyle(.secondary)
                .truncationMode(.middle)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    /// Смужка прогресу під час встановлення, інакше — результат; місце зарезервоване завжди.
    @ViewBuilder
    private var progressBlock: some View {
        if busy {
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.3))
                        Capsule().fill(Color.accentColor)
                            .frame(width: max(12, geo.size.width * progress))
                    }
                }
                .frame(height: 12)
                HStack {
                    Text(progressText).lineLimit(1)
                    Spacer()
                    Text(verbatim: "\(Int(progress * 100))%")
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
        } else if let message {
            Text(message).font(.footnote)
                .foregroundStyle(messageIsError ? Color.errorText : Color.okText)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Color.clear
        }
    }

    /// Передогляд циферблата: та сама капсула, що в магазині.
    private var previewCapsule: some View {
        FaceCapsule(image: filePreview)
    }

    private func pickFace() {
        importingFolder = false
        showImporter = true
    }


    private var bandSection: some View {
        Section("Пристрій") {
            if let name = ble.connectedName {
                HStack {
                    Label { Text(Self.bandModel(name)).lineLimit(1).minimumScaleFactor(0.75) } icon: { Image("TabWatch").foregroundStyle(Color.accentColor) }
                    Spacer()
                    Button(role: .destructive) {
                        ble.disconnect()
                    } label: {
                        Image("IconDisconnect")
                            .renderingMode(.template)
                            .foregroundStyle(Color.errorText)
                    }
                    .accessibilityLabel(Text("Відключити"))
                    .buttonStyle(.plain)
                    // Правий відступ такий самий, як зліва до значка браслета (в значку є власні поля)
                    .padding(.trailing, 8)
                }
                if !ble.servicesReady {
                    HStack { ProgressView(); Text("Підготовка…").font(.footnote) }
                }
            } else if ble.isConnecting {
                // Автоматичне (або ручне) підключення до браслета
                HStack {
                    ProgressView()
                    Text("Підключення до \(ble.connectingName ?? String(localized: "браслета"))…")
                        .padding(.leading, 6)
                    Spacer()
                    Button("Скасувати") { ble.disconnect() }
                        .buttonStyle(.borderless)
                }
            } else {
                Button(ble.isScanning ? String(localized: "Зупинити пошук") : String(localized: "Шукати браслет")) {
                    ble.isScanning ? ble.stopScan() : ble.startScan()
                }
                ForEach(ble.devices) { d in
                    Button {
                        ble.connect(d.id)
                    } label: {
                        HStack {
                            Text(d.name)
                            Spacer()
                            if d.rssi != 0 {
                                Text(verbatim: "\(d.rssi) dBm").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if ble.state == .unauthorized {
                Text("Дозвольте Bluetooth для застосунку в Налаштуваннях iOS.")
                    .font(.footnote).foregroundStyle(Color.errorText)
            }
        }
    }

    private var logSection: some View {
        Section {
            Toggle("Режим розробника", isOn: $verboseLog)
            HStack(spacing: 12) {
                Button {
                    UIPasteboard.general.string = ble.logStore.lines.joined(separator: "\n")
                } label: {
                    Text("Копіювати").buttonText()
                }
                .glassSecondaryStyle()
                Button(role: .destructive) {
                    ble.logStore.clear()
                } label: {
                    Text("Очистити").buttonText()
                }
                .glassSecondaryStyle()
                .tint(Color.errorText)
            }
            .buttonBorderShape(.capsule)
            .padding(.top, 4)
            .padding(.bottom, 1)
            // Усі записи в одному рядку списку — щільно, без стандартної висоти рядків
            LogLinesView(store: ble.logStore)
        } header: {
            // Заголовок секції — на тій самій висоті й з тими самими параметрами, що «Браслет» і «Auth key браслета»
            Text("Активність")
        }
    }

    // MARK: - Дії

    private func loadFace(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e):
            show(e.localizedDescription, error: true)
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let parsed = try FaceFile(data: data)
                face = parsed
                filePreview = (try? parsed.decodePreview()?.makeCGImage()).map(UIImage.init(cgImage:))
                fileName = url.lastPathComponent
                message = nil
            } catch {
                face = nil
                filePreview = nil
                fileName = nil
                show(error is BandError ? error.localizedDescription
                     : String(localized: "Некоректний файл циферблата: \(error.localizedDescription)"), error: true)
            }
        }
    }

    /// Після першого вибору папки Mi Fitness ключ шукається сам при кожному вході.
    /// Пошук ключа вже йде — при запуску onAppear і повернення в застосунок спрацьовують майже одночасно
    private static var keyScanInFlight = false

    private func autoFindKey() {
        guard !busy, !Self.keyScanInFlight, let folder = MiFitnessKey.savedFolder() else { return }
        searchKey(in: folder, quiet: true)
    }

    private func findKey() {
        // Папку вже вибирали — шукаємо одразу, інакше показуємо коротку інструкцію
        guard let folder = MiFitnessKey.savedFolder() else {
            showKeyHelp = true
            return
        }
        searchKey(in: folder)
    }

    private func folderPicked(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e):
            keyStatus = e.localizedDescription
            keyStatusIsError = true
        case .success(let url):
            MiFitnessKey.saveFolder(url)
            searchKey(in: url)
        }
    }

    /// `quiet`: автоматична перевірка, коли ключ уже є — показуємо лише зміни й помилки.
    private func searchKey(in folder: URL, quiet: Bool = false) {
        if !quiet {
            keyStatus = String(localized: "Пошук…")
            keyStatusIsError = false
        }
        Self.keyScanInFlight = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try MiFitnessKey.findDevices(in: folder) }
            let scanLines = MiFitnessKey.lastScanLines
            DispatchQueue.main.async {
                Self.keyScanInFlight = false
                // Повне сканування папки (нестандартна структура даних) — лише в «Режимі розробника»
                for line in scanLines { ble.debug(line) }
                switch result {
                case .success(let devices):
                    foundDevices = devices
                    // Якщо браслет підключено, беремо ключ саме для нього
                    let connected = ble.connectedName?.lowercased()
                    // Ключ, який уже вибрано й досі є в Mi Fitness, не перебиваємо
                    let match = devices.first { $0.key == authKey.lowercased() }
                        ?? devices.first { !$0.name.isEmpty && $0.name.lowercased() == connected }
                        ?? devices.first { $0.name.lowercased().contains("band") }
                        ?? devices[0]
                    let changed = match.key != authKey.lowercased()
                    authKey = match.key
                    keyStatus = devices.count == 1
                        ? (match.name.isEmpty ? String(localized: "Ключ знайдено") : String(localized: "Ключ знайдено для «\(match.name)»"))
                        : String(localized: "Знайдено пристроїв: \(String(devices.count)), вибрано «\(match.name)». За потреби виберіть інший")
                    keyStatusIsError = false
                    if changed { ble.addLog(String(localized: "Auth key оновлено з даних Mi Fitness")) }
                case .failure(let error):
                    let folderLost = (error as? MiFitnessKey.SearchError).map { $0 != .noKey } ?? false
                    if folderLost {
                        // Папка недоступна (наприклад, iOS скинула дозвіл) — попросимо вибрати знову
                        MiFitnessKey.forgetFolder()
                    }
                    if quiet && folderLost {
                        keyStatus = String(localized: "Доступ до папки Mi Fitness втрачено. Натисніть «Знайти автоматично», щоб вибрати її знову")
                    } else {
                        keyStatus = error.localizedDescription
                    }
                    keyStatusIsError = true
                }
            }
        }
    }

    @MainActor
    private func install(_ face: FaceFile, store: StoreFace? = nil) {
        guard let key = Hex.decode(authKey), key.count == 16 else {
            show(BandError.invalidAuthKey.localizedDescription, error: true)
            return
        }
        busy = true
        installingID = store?.id
        progress = 0
        progressText = String(localized: "Старт…")
        message = nil
        Task { @MainActor in
            do {
                // Оновлюємо екран лише при зміні на 1% або зміні етапу:
                // частин сотні-тисячі, і кожне оновлення перемальовує вкладки
                let throttle = ProgressThrottle()
                let text = try await FaceInstaller(ble: ble).install(face, authKey: key) { value, text in
                    guard throttle.shouldUpdate(value: value, text: text) else { return }
                    progress = value
                    progressText = text
                }
                ble.addLog(String(localized: "Готово: \(text)"))
                show(text, error: false)
                if let store {
                    var map = InstalledFaces.parse(installedRaw)
                    map[store.id] = store.version
                    installedRaw = InstalledFaces.encode(map)
                }
            } catch {
                ble.addLog(String(localized: "Помилка: \(error.localizedDescription)"))
                show(error.localizedDescription, error: true)
                if store != nil { storeAlert = error.localizedDescription }
            }
            busy = false
            installingID = nil
        }
    }

    private func show(_ text: String, error: Bool) {
        message = text
        messageIsError = error
    }
}

private extension Text {
    /// Текст кнопки в блоці встановлення: один рядок, компактний шрифт, на всю ширину.
    func buttonText() -> some View {
        self.font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }
}


/// Рядок налаштувань зі значком у кольоровому квадраті (фіксована ширина — однакові відступи й роздільники).
/// Плитки налаштувань: колір (градієнт згори донизу) і значок.
/// Профіль градієнта виміряно з прикладу: світлий довше тримається вгорі, темніє ближче до низу.
/// Кольори однакові для світлої й темної теми; масиви створюються один раз.
enum SettingsTile {
    case key, log, theme, language, version

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    private static let keyColors = [rgb(0x31D059), rgb(0x31C857), rgb(0x2BAD4C)]
    private static let logColors = [rgb(0x2D94FF), rgb(0x2690FF), rgb(0x057FFF)]
    private static let themeColors = [rgb(0xFCBB30), rgb(0xF9AB2C), rgb(0xF89004)]   // яскравіший помаранчевий (насиченість +25%)
    private static let languageColors = [rgb(0xC777EF), rgb(0xC473EC), rgb(0xB756E8)]
    private static let versionColors = [rgb(0x9D9DA0), rgb(0x9A9A9C), rgb(0x89898C)]

    var colors: [Color] {
        switch self {
        case .key: return Self.keyColors
        case .log: return Self.logColors
        case .theme: return Self.themeColors
        case .language: return Self.languageColors
        case .version: return Self.versionColors
        }
    }

    /// Значок у плитці 30 pt; розміри в пікселях (3x) парні, тож він стоїть рівно по центру
    @ViewBuilder var glyph: some View {
        switch self {
        case .key: KeyGlyph().frame(width: 28.0 / 3, height: 58.0 / 3)
        case .log: DocGlyph().frame(width: 46.0 / 3, height: 58.0 / 3)
        case .theme: ThemeGlyph().frame(width: 20, height: 20)
        case .language: GlobeGlyph().frame(width: 20, height: 20)
        case .version: InfoGlyph().frame(width: 20, height: 20)
        }
    }
}

struct SettingsLabel: View {
    let title: LocalizedStringKey
    let tile: SettingsTile
    @Environment(\.displayScale) private var displayScale

    init(_ title: LocalizedStringKey, tile: SettingsTile) {
        self.title = title; self.tile = tile
    }

    private static let strokeGradient = LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.22)],
                                                       startPoint: .top, endPoint: .bottom)

    var body: some View {
        Label {
            Text(title)
        } icon: {
            ZStack {
                let shape = RoundedRectangle(cornerRadius: 8.3, style: .continuous)
                shape
                    .fill(LinearGradient(colors: tile.colors, startPoint: .top, endPoint: .bottom))
                    // Обводка в 1 фізичний піксель, майже рівномірна (як у прикладі)
                    .overlay(shape.strokeBorder(Self.strokeGradient, lineWidth: 1 / displayScale))
                tile.glyph
            }
            .frame(width: 30, height: 30)
        }
    }
}

/// Останні рядки журналу; сам стежить за змінами, тож решта екрана не перемальовується.
struct LogLinesView: View {
    @ObservedObject var store: BandLog

    var body: some View {
        if !store.lines.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(store.lines.suffix(200).enumerated()), id: \.offset) { _, line in
                    Text(line)
                }
            }
            .font(.system(.caption2, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, -14.6)
            .padding(.bottom, 2)
            .listRowSeparator(.hidden)
        }
    }
}

/// Суцільний глобус із прорізами (дві паралелі й меридіан) для плитки «Мова».
struct GlobeGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let gap = d * 0.085
            ZStack {
                Circle().fill(Color.white)
                // Паралелі
                ForEach([-0.19, 0.19], id: \.self) { k in
                    Rectangle()
                        .frame(width: d, height: gap)
                        .offset(y: d * k)
                        .blendMode(.destinationOut)
                }
                // Меридіан: вузький еліпс, ширший за висоту кола, щоб дуги йшли майже прямо
                Ellipse()
                    .stroke(lineWidth: gap)
                    .frame(width: d * 0.46, height: d * 1.16)
                    .blendMode(.destinationOut)
            }
            .frame(width: d, height: d)
            .compositingGroup()
        }
    }
}

/// Коло з лівою зафарбованою половиною (тема), точно 20×20 pt.
struct ThemeGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            let ring = d * 0.1
            let gap = d * 0.09
            ZStack {
                Circle().strokeBorder(Color.white, lineWidth: ring)
                // Ліва половина внутрішнього кола
                Circle()
                    .fill(Color.white)
                    .frame(width: d - 2 * (ring + gap), height: d - 2 * (ring + gap))
                    .mask(
                        HStack(spacing: 0) {
                            Rectangle()
                            Color.clear
                        }
                    )
            }
            .frame(width: d, height: d)
        }
    }
}

/// Суцільне коло з прорізаною літерою «i» (версія), точно 20×20 pt.
struct InfoGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(Color.white)
                // Крапка
                Circle()
                    .frame(width: d * 0.14, height: d * 0.14)
                    .offset(y: -d * 0.22)
                    .blendMode(.destinationOut)
                // Ніжка
                Capsule()
                    .frame(width: d * 0.12, height: d * 0.36)
                    .offset(y: d * 0.1)
                    .blendMode(.destinationOut)
            }
            .frame(width: d, height: d)
            .compositingGroup()
        }
    }
}

/// Ключ: кругла головка з отвором, стрижень і два зубці. Малюється точно у своїй рамці.
struct KeyGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let s = w * 0.36, th = h * 0.085
            ZStack(alignment: .topLeading) {
                Circle().frame(width: w, height: w)
                RoundedRectangle(cornerRadius: s / 2)
                    .frame(width: s, height: h - w * 0.8)
                    .offset(x: w / 2 - s / 2, y: w * 0.8)
                Capsule()
                    .frame(width: w * 0.92 - w / 2, height: th)
                    .offset(x: w / 2, y: h * 0.60)
                Capsule()
                    .frame(width: w * 0.80 - w / 2, height: th)
                    .offset(x: w / 2, y: h * 0.77)
                Circle()
                    .frame(width: w * 0.34, height: w * 0.34)
                    .offset(x: w / 2 - w * 0.17, y: w * 0.42 - w * 0.17)
                    .blendMode(.destinationOut)
            }
            .foregroundStyle(Color.white)
            .frame(width: w, height: h, alignment: .topLeading)
            .compositingGroup()
        }
    }
}

/// Аркуш журналу: загнутий куточок і три рядки тексту. Малюється точно у своїй рамці.
struct DocGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let f = w * 0.36, g = w * 0.07, r = w * 0.17
            let lh = h * 0.068, lx = w * 0.24, lw = w * 0.52
            ZStack(alignment: .topLeading) {
                // Аркуш із вирізом під куточок
                Path { p in
                    p.move(to: CGPoint(x: r, y: 0))
                    p.addLine(to: CGPoint(x: w - f - g, y: 0))
                    p.addLine(to: CGPoint(x: w - f - g, y: f + g))
                    p.addLine(to: CGPoint(x: w, y: f + g))
                    p.addLine(to: CGPoint(x: w, y: h - r))
                    p.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: r, y: h))
                    p.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
                    p.addLine(to: CGPoint(x: 0, y: r))
                    p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: 0))
                    p.closeSubpath()
                }
                // Загнутий куточок
                Path { p in
                    p.move(to: CGPoint(x: w - f, y: 0))
                    p.addLine(to: CGPoint(x: w, y: f))
                    p.addLine(to: CGPoint(x: w - f + r * 0.6, y: f))
                    p.addQuadCurve(to: CGPoint(x: w - f, y: f - r * 0.6), control: CGPoint(x: w - f, y: f))
                    p.closeSubpath()
                }
                // Рядки тексту
                ForEach(Array([(0.5, 1.0), (0.66, 1.0), (0.82, 0.62)].enumerated()), id: \.offset) { _, line in
                    Capsule()
                        .frame(width: lw * line.1, height: lh)
                        .offset(x: lx, y: h * line.0 - lh / 2)
                        .blendMode(.destinationOut)
                }
            }
            .foregroundStyle(Color.white)
            .frame(width: w, height: h, alignment: .topLeading)
            .compositingGroup()
        }
    }
}

/// Пропускає дрібні оновлення прогресу: лише нові відсотки або новий етап.
final class ProgressThrottle {
    private var lastPercent = -1
    private var lastStage = ""

    func shouldUpdate(value: Double, text: String) -> Bool {
        let percent = Int(value * 100)
        // Етап — текст без лічильника частин («Передача 12/400» → «Передача»)
        let stage = text.split(separator: " ").first.map(String.init) ?? text
        defer { lastPercent = percent; lastStage = stage }
        return percent != lastPercent || stage != lastStage || value >= 1
    }
}
