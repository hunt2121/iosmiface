import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    enum Tab: Hashable { case faces, key, gallery, log }

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
    @State private var bandFaces: [BandWatchface]?
    @State private var faceToDelete: BandWatchface?
    @State private var selectedFace: BandWatchface?
    @State private var previews: [String: UIImage] = [:]
    @State private var filePreview: UIImage?
    @State private var previewSearched: Set<String> = []
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
                .navigationTitle("Встановити")
            }
            .tabItem { Label("Встановити", image: "TabInstall") }
            .tag(Tab.faces)

            NavigationStack {
                galleryView
                    .navigationTitle("Циферблати")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button { run(.list) } label: { Image(systemName: "arrow.clockwise") }
                                .disabled(!canOperate)
                        }
                    }
            }
            .tabItem { Label("Циферблати", image: "TabWatch") }
            .tag(Tab.gallery)

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
            if phase == .background && !busy && ble.connectedID != nil {
                ble.disconnect()
                bandFaces = nil
            }
            // Ключ міг змінитися в Mi Fitness (наприклад, після нового спарювання)
            if phase == .active { autoFindKey() }
        }
        .onAppear {
            autoFindKey()
        }
        .onChange(of: tab) { t in
            // Відкрили галерею вперше за підключення — одразу завантажуємо список
            if t == .gallery && bandFaces == nil && canOperate { run(.list, quiet: true) }
        }
        .confirmationDialog(selectedFace.map { $0.name.isEmpty ? "Циферблат \($0.id)" : $0.name } ?? "",
                            isPresented: Binding(get: { selectedFace != nil },
                                                 set: { if !$0 { selectedFace = nil } }),
                            titleVisibility: .visible,
                            presenting: selectedFace) { f in
            if !f.active {
                Button("Активувати") { run(.activate(f.id)) }
            }
            if f.canDelete {
                Button("Видалити", role: .destructive) {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        faceToDelete = f
                    }
                }
            }
        } message: { f in
            Text(f.active ? "Цей циферблат зараз активний" : (f.canDelete ? "ID \(f.id)" : "Системний циферблат, його не можна видалити"))
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: importingFolder ? [.folder] : [.data]) { result in
            if importingFolder { folderPicked(result) } else { loadFace(result) }
        }
        .confirmationDialog("Видалити циферблат з браслета?",
                            isPresented: Binding(get: { faceToDelete != nil },
                                                 set: { if !$0 { faceToDelete = nil } }),
                            titleVisibility: .visible,
                            presenting: faceToDelete) { f in
            Button("Видалити «\(f.name.isEmpty ? f.id : f.name)»", role: .destructive) {
                run(.delete(f.id))
            }
        } message: { _ in
            Text("Цю дію не можна скасувати.")
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
                    .overlay(Capsule(style: .continuous)
                        .stroke(Color.gray.opacity(0.35), lineWidth: 1))
                    Text(face.name ?? "Циферблат \(face.id)").font(.headline)
                    Text("ID \(face.id) · \(face.data.count / 1024) КБ")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
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
                        bandFaces = nil
                    }
                    .buttonStyle(.borderless)
                }
                if !ble.servicesReady {
                    HStack { ProgressView(); Text("Підготовка…").font(.footnote) }
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

    @ViewBuilder
    private func faceActions(_ f: BandWatchface) -> some View {
        if f.canDelete {
            Button(role: .destructive) { faceToDelete = f } label: {
                Label("Видалити", systemImage: "trash")
            }
            .disabled(!canOperate)
        }
        if !f.active {
            Button { run(.activate(f.id)) } label: {
                Label("Активувати", systemImage: "checkmark")
            }
            .tint(.green)
            .disabled(!canOperate)
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

    // MARK: - Галерея

    @ViewBuilder
    private var galleryView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !keyValid {
                    galleryHint("Спершу додайте ключ браслета", button: "Перейти до ключа") { tab = .key }
                } else if ble.connectedID == nil {
                    galleryHint("Браслет не підключено", button: "Підключити") {
                        tab = .faces
                        if !ble.isScanning { ble.startScan() }
                    }
                }

                if busy || message != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        if busy { ProgressView(value: progress); Text(progressText) }
                        if let message {
                            Text(message).foregroundStyle(messageIsError ? Color.errorText : Color.okText)
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                if let bandFaces {
                    if bandFaces.isEmpty {
                        Text("На браслеті немає циферблатів").foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 14)], spacing: 18) {
                        ForEach(bandFaces) { f in faceCard(f) }
                    }
                } else if canOperate {
                    Button("Показати циферблати на браслеті") { run(.list) }
                        .buttonStyle(.borderedProminent)
                }

                if bandFaces != nil {
                    Text("Натисніть на циферблат, щоб активувати чи видалити його. Вигляд показується для циферблатів, встановлених через BandFace.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .refreshable { await MainActor.run { if canOperate { run(.list) } } }
    }

    private func galleryHint(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(.headline)
            Button(button, action: action).buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func faceCard(_ f: BandWatchface) -> some View {
        Button {
            if canOperate { selectedFace = f }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Capsule(style: .continuous).fill(Color.black)
                    if let img = previews[f.id] {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else {
                        Image("TabWatch")
                            .resizable().scaledToFit()
                            .frame(width: 34)
                            .foregroundStyle(.gray)
                    }
                }
                .aspectRatio(212.0 / 520.0, contentMode: .fit)
                .clipShape(Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(f.active ? Color.okText : Color.gray.opacity(0.3), lineWidth: f.active ? 3 : 1)
                )
                Text(f.name.isEmpty ? "Без назви" : f.name)
                    .font(.caption).lineLimit(1)
                    .foregroundStyle(.primary)
                if f.active {
                    Text("Активний").font(.caption2).foregroundStyle(Color.okText)
                } else if !f.canDelete {
                    Text("Системний").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu { faceActions(f) }
    }

    private func loadPreviews(for list: [BandWatchface]) {
        var known: [String: UIImage] = [:]
        for f in list { if let img = FacePreview.saved(for: f.id) { known[f.id] = img } }
        previews = known
        // Кожен циферблат шукаємо в даних Mi Fitness лише раз за запуск — пошук не швидкий
        let missing = list.map(\.id).filter { known[$0] == nil && !previewSearched.contains($0) }
        guard !missing.isEmpty else { return }
        previewSearched.formUnion(missing)
        // Решту шукаємо в даних Mi Fitness (якщо папку вже вибрано)
        Task {
            let found = await Task.detached(priority: .utility) {
                await MiFitnessPreviews.search(ids: missing)
            }.value
            await MainActor.run {
                for line in found.log.dropLast() { ble.debug(line) }
                if let summary = found.log.last { ble.addLog(summary) }
                for (id, img) in found.images {
                    FacePreview.save(img, for: id)
                    previews[id] = img
                }
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
            s.onWatchfaces = { list in
                bandFaces = list
                loadPreviews(for: list)
            }
            session = s
            busy = true
            progress = 0
            progressText = "Старт…"
            if !quiet { message = nil }
            let refreshAfter: Bool
            switch operation {
            case .list: refreshAfter = false
            default: refreshAfter = bandFaces != nil || tab == .gallery
            }
            s.run(operation, progress: { value, text in
                progress = value
                progressText = text
            }, completion: { result in
                busy = false
                session = nil
                switch result {
                case .success(let text):
                    if !quiet { show(text, error: false) }
                    switch operation {
                    case .install(let f):
                        // Запам'ятовуємо вигляд циферблата для вкладки «Циферблати»
                        if let img = FacePreview.image(fromFace: f.data) {
                            FacePreview.save(img, for: f.id)
                            previews[f.id] = img
                        }
                    case .delete(let id):
                        FacePreview.remove(for: id)
                        previews[id] = nil
                    default:
                        break
                    }
                    if refreshAfter {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            if canOperate { run(.list, quiet: true) }
                        }
                    }
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
