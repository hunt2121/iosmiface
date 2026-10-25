import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    enum Tab: Hashable { case faces, key, log }

    @EnvironmentObject var ble: BLEManager

    @State private var authKey: String = KeychainStore.load(account: "authKey") ?? ""
    @State private var showImporter = false
    @State private var importingFolder = false
    @State private var foundDevices: [MiFitnessKey.Device] = []
    @State private var keyStatus: String?
    @State private var keyStatusIsError = false
    @State private var showKeyHelp = false
    @State private var tab: Tab = .faces
    @State private var face: FaceFile?
    @State private var fileName: String?
    @State private var progress: Double = 0
    @State private var progressText = ""
    @State private var busy = false
    @State private var message: String?
    @State private var messageIsError = false
    @State private var session: XiaomiBandSession?
    @State private var filePreview: UIImage?
    @AppStorage("verboseLog") private var verboseLog = false
    @Environment(\.scenePhase) private var scenePhase

    private var keyValid: Bool {
        if let d = Data(hex: authKey) { return d.count == 16 }
        return false
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
            NavigationStack {
                Form {
                    if !keyValid {
                        Section {
                            Button {
                                // Переходимо у вкладку «Ключ» і одразу починаємо пошук там
                                tab = .key
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 350_000_000)
                                    findKey()
                                }
                            } label: {
                                Label("Додати ключ браслета", systemImage: "key")
                            }
                        } footer: {
                            Text("Без ключа застосунок не зможе підключитися до браслета. Його можна знайти автоматично в даних Mi Fitness.")
                        }
                    }
                    bandSection
                    installSection
                    statusSection
                }
                .navigationTitle("Циферблати")
            }
            .tabItem { Label("Циферблати", image: "TabWatch") }
            .tag(Tab.faces)

            NavigationStack {
                Form { authSection }
                    .navigationTitle("Ключ")
            }
            // Ключа немає — на іконці червоний знак «!»
            .tabItem { Label("Ключ", image: "TabKey") }
            .badge(keyValid ? nil : Text("!"))
            .tag(Tab.key)

            NavigationStack {
                Form {
                    logSection
                    Section {
                        Text("Збірка №\(Self.buildNumber) · версія \(Self.versionString)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Журнал")
            }
            .tabItem { Label("Журнал", image: "TabLog") }
            .tag(Tab.log)
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

    // MARK: - Розділи

    private var authSection: some View {
        Section {
            TextField("32 hex-символи", text: $authKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .onChange(of: authKey) { KeychainStore.save($0, account: "authKey") }
            Text(keyValid ? "Ключ виглядає коректно" : "Введіть ключ вручну або знайдіть його автоматично")
                .font(.footnote)
                .foregroundStyle(keyValid ? Color.okText : Color.secondary)
            Button {
                findKey()
            } label: {
                Label("Знайти автоматично", systemImage: "key.viewfinder")
            }
            if foundDevices.count > 1 {
                ForEach(foundDevices, id: \.self) { d in
                    Button {
                        authKey = d.key
                        keyStatus = "Ключ для «\(d.name)» вибрано"
                        keyStatusIsError = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.name.isEmpty ? "Пристрій без назви" : d.name)
                                if let mac = d.mac { Text(mac).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            if d.key == authKey.lowercased() {
                                Image(systemName: "checkmark").foregroundStyle(Color.okText)
                            }
                        }
                    }
                }
            }
            if let keyStatus {
                Text(keyStatus).font(.footnote)
                    .foregroundStyle(keyStatusIsError ? Color.errorText : Color.okText)
            }
        } header: {
            Text("Auth key браслета")
        } footer: {
            Text(MiFitnessKey.hasSavedFolder
                 ? "Папку Mi Fitness запам'ятовано: ключ перевіряється автоматично при кожному вході в застосунок."
                 : "«Знайти автоматично» один раз попросить вибрати папку Mi Fitness, далі ключ шукатиметься сам.")
        }
    }

    private var installSection: some View {
        Section("Встановлення циферблата") {
            Button(fileName ?? "Вибрати файл .bin або .face") {
                importingFolder = false
                showImporter = true
            }
            if let face {
                // Передогляд циферблата, який будемо встановлювати
                VStack(spacing: 10) {
                    ZStack {
                        Capsule(style: .continuous).fill(Color.black)
                        if let filePreview {
                            Image(uiImage: filePreview).resizable().scaledToFill()
                        } else {
                            VStack(spacing: 8) {
                                Image("TabWatch").resizable().scaledToFit().frame(width: 36)
                                Text("Передогляд недоступний").font(.caption2)
                            }
                            .foregroundStyle(.gray)
                        }
                    }
                    .frame(width: 112, height: 275)
                    .clipShape(Capsule(style: .continuous))
                    // Рамка ззовні передогляду (картинка не перекривається), як корпус браслета
                    .padding(3)
                    .background(Capsule(style: .continuous).fill(Color.gray.opacity(0.45)))
                    Text(face.name ?? "Циферблат \(face.id)").font(.headline)
                    Text("ID \(face.id) · \(face.data.count / 1024) КБ")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                // Лінія над «Встановити на браслет» починається на рівні тексту кнопки,
                // як інші роздільники, а не від тексту по центру
                .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] }
            }
            Button("Встановити на браслет") {
                if let face { run(.install(face)) }
            }
            .disabled(!canOperate || face == nil)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if busy || message != nil {
            Section {
                if busy {
                    ProgressView(value: progress)
                    Text(progressText).font(.footnote).foregroundStyle(.secondary)
                }
                if let message {
                    Text(message).font(.footnote)
                        .foregroundStyle(messageIsError ? Color.errorText : Color.okText)
                }
            }
        }
    }

    private var bandSection: some View {
        Section("Браслет") {
            if let name = ble.connectedName {
                HStack {
                    Label { Text(name) } icon: { Image("TabWatch").foregroundStyle(Color.accentColor) }
                    Spacer()
                    Button("Відключити", role: .destructive) {
                        ble.disconnect()
                    }
                    .buttonStyle(.borderless)
                }
                if !ble.servicesReady {
                    HStack { ProgressView(); Text("Підготовка…").font(.footnote) }
                }
            } else if ble.isConnecting {
                // Автоматичне (або ручне) підключення до браслета
                HStack {
                    ProgressView()
                    Text("Підключення до \(ble.connectingName ?? "браслета")…")
                        .padding(.leading, 6)
                    Spacer()
                    Button("Скасувати") { ble.disconnect() }
                        .buttonStyle(.borderless)
                }
            } else {
                Button(ble.isScanning ? "Зупинити пошук" : "Шукати браслет") {
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
                                Text("\(d.rssi) dBm").foregroundStyle(.secondary)
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
        Section("Журнал") {
            Toggle("Детальний журнал", isOn: $verboseLog)
            HStack {
                Button("Копіювати") {
                    UIPasteboard.general.string = ble.log.joined(separator: "\n")
                }
                .buttonStyle(.borderless)
                Spacer()
                ShareLink(item: ble.log.joined(separator: "\n")) {
                    Label("Поділитися", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Очистити", role: .destructive) { ble.log.removeAll() }
                    .buttonStyle(.borderless)
            }
            ForEach(Array(ble.log.suffix(200).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
            }
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
                filePreview = FacePreview.image(fromFace: parsed.data)
                fileName = url.lastPathComponent
                message = nil
            } catch {
                face = nil
                filePreview = nil
                fileName = nil
                show("Некоректний файл циферблата: \(error.localizedDescription)", error: true)
            }
        }
    }

    /// Після першого вибору папки Mi Fitness ключ шукається сам при кожному вході.
    private func autoFindKey() {
        guard !busy, let folder = MiFitnessKey.savedFolder() else { return }
        searchKey(in: folder, isNewFolder: false, quiet: true)
    }

    private func findKey() {
        // Папку вже вибирали — шукаємо одразу, інакше показуємо коротку інструкцію
        guard let folder = MiFitnessKey.savedFolder() else {
            showKeyHelp = true
            return
        }
        searchKey(in: folder, isNewFolder: false)
    }

    private func folderPicked(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e):
            keyStatus = e.localizedDescription
            keyStatusIsError = true
        case .success(let url):
            MiFitnessKey.saveFolder(url)
            searchKey(in: url, isNewFolder: true)
        }
    }

    /// `quiet`: автоматична перевірка, коли ключ уже є — показуємо лише зміни й помилки.
    private func searchKey(in folder: URL, isNewFolder: Bool, quiet: Bool = false) {
        if !quiet {
            keyStatus = "Пошук…"
            keyStatusIsError = false
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try MiFitnessKey.findDevices(in: folder) }
            DispatchQueue.main.async {
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
                    if quiet && !changed { return }
                    keyStatus = devices.count == 1
                        ? "Ключ знайдено\(match.name.isEmpty ? "" : " для «\(match.name)»")"
                        : "Знайдено \(devices.count) пристрої, вибрано «\(match.name)». За потреби виберіть інший"
                    keyStatusIsError = false
                    if changed { ble.addLog("Auth key оновлено з даних Mi Fitness") }
                case .failure(let error):
                    let folderLost = (error as? MiFitnessKey.SearchError).map { $0 != .noKey } ?? false
                    if folderLost {
                        // Папка недоступна (наприклад, iOS скинула дозвіл) — попросимо вибрати знову
                        MiFitnessKey.forgetFolder()
                    }
                    if quiet && folderLost {
                        keyStatus = "Доступ до папки Mi Fitness втрачено. Натисніть «Знайти автоматично», щоб вибрати її знову"
                    } else {
                        keyStatus = error.localizedDescription
                    }
                    keyStatusIsError = true
                }
            }
        }
    }

    @MainActor
    private func run(_ operation: XiaomiBandSession.Operation, quiet: Bool = false) {
        do {
            let s = try XiaomiBandSession(ble: ble, authKeyHex: authKey)
            session = s
            busy = true
            progress = 0
            progressText = "Старт…"
            if !quiet { message = nil }
            s.run(operation, progress: { value, text in
                progress = value
                progressText = text
            }, completion: { result in
                busy = false
                session = nil
                switch result {
                case .success(let text):
                    if !quiet { show(text, error: false) }
                case .failure(let error):
                    show(error.localizedDescription, error: true)
                }
            })
        } catch {
            show(error.localizedDescription, error: true)
        }
    }

    private func show(_ text: String, error: Bool) {
        message = text
        messageIsError = error
    }
}
