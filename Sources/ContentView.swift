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
    // Магазин
    @State private var storeFaces: [StoreFace] = StoreCatalog.cached
    @State private var installingID: String?
    @State private var syncing = false
    @State private var lastSync = Date.distantPast
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
                      onRefresh: { await syncDeviceFaces(force: true) })
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
                            SettingsLabel("Ключ", icon: "key.fill", color: Color(red: 43 / 255, green: 173 / 255, blue: 76 / 255))  // #2BAD4C — середина systemGreen обох тем, темніша на 15%
                            Spacer()
                            // Та сама позначка, що всередині сторінки «Ключ»
                            Image(systemName: keyValid ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                .foregroundStyle(keyValid ? Color.okIcon : Color.errorText)
                                .font(.title3)
                        }
                    }
                    NavigationLink(value: SettingsRoute.log) {
                        SettingsLabel("Журнал", icon: "doc.text.fill", color: Color(red: 5 / 255, green: 127 / 255, blue: 255 / 255))  // #057FFF — середина systemBlue обох тем
                    }
                }
                Section("Застосунок") {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            SettingsLabel("Мова", icon: "custom.globe", color: Color(red: 183 / 255, green: 86 / 255, blue: 232 / 255))  // #B756E8 — середина systemPurple обох тем
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
                    Picker(selection: $appTheme) {
                        Text("Системна").tag("system")
                        Text("Світла").tag("light")
                        Text("Темна").tag("dark")
                    } label: {
                        SettingsLabel("Тема", icon: "custom.theme", color: Color(red: 68 / 255, green: 173 / 255, blue: 219 / 255))  // #44ADDB — середина systemCyan обох тем, темніша на 10%
                    }
                    HStack {
                        SettingsLabel("Версія", icon: "custom.info", color: Color(red: 137 / 255, green: 137 / 255, blue: 140 / 255))  // #89898C — середина між systemGray2 світлої й темної тем
                        Spacer()
                        Text(verbatim: "\(Self.versionString).\(Self.buildNumber)")
                            .foregroundStyle(.secondary)
                    }
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
        guard let ids = try? await FaceInstaller(ble: ble).listFaces(authKey: key) else { return }
        lastSync = Date()
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
                            .foregroundStyle(Color(red: 0.878, green: 0.267, blue: 0.227))
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
                .tint(.red)
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
    private func autoFindKey() {
        guard !busy, let folder = MiFitnessKey.savedFolder() else { return }
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
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try MiFitnessKey.findDevices(in: folder) }
            let scanLines = MiFitnessKey.lastScanLines
            DispatchQueue.main.async {
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
                let text = try await FaceInstaller(ble: ble).install(face, authKey: key) { value, text in
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
struct SettingsLabel: View {
    let title: LocalizedStringKey
    let icon: String
    let color: Color
    init(_ title: LocalizedStringKey, icon: String, color: Color) {
        self.title = title; self.icon = icon; self.color = color
    }
    /// Видимий розмір значка в плитці 30 pt: ≈19–20 pt, як у системних налаштуваннях.
    private var glyphBox: CGFloat {
        switch icon {
        case "key.fill", "doc.text.fill": return 19
        default: return 20
        }
    }
    var body: some View {
        Label {
            Text(title)
        } icon: {
            ZStack {
                // Плитка: колір із м'яким градієнтом (світліше вгорі, темніше внизу)
                // і тонким світлим обведенням усередині, сильнішим зверху
                RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                    .fill(color)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                            .fill(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0)],
                                                 startPoint: .top, endPoint: .bottom))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.1)],
                                                         startPoint: .top, endPoint: .bottom),
                                          lineWidth: 0.5)
                    )
                Group {
                    if icon == "custom.theme" {
                        ThemeGlyph().frame(width: 20, height: 20)
                    } else if icon == "custom.info" {
                        InfoGlyph().frame(width: 20, height: 20)
                    } else if icon == "custom.globe" {
                        GlobeGlyph().frame(width: 20, height: 20)  // 60 px на 3x, рівно по центру плитки 90 px
                    } else if icon.hasPrefix("Tab") || icon.hasPrefix("Icon") {
                        Image(icon).renderingMode(.template)
                    } else {
                        Image(systemName: icon)
                            .resizable()
                            .scaledToFit()
                            .fontWeight(.semibold)
                            .frame(width: glyphBox, height: glyphBox)
                    }
                }
                .foregroundStyle(.white)
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
