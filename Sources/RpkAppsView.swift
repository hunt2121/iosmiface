import SwiftUI
import UniformTypeIdentifiers
import BandFaceKit

struct RpkAppsView: View {
    @EnvironmentObject var ble: BLEManager
    let authKey: String
    @Binding var busy: Bool
    let syncing: Bool
    @Binding var selectedFile: RpkFile?
    @State private var apps: [RpkInfo] = []
    @State private var loaded = false
    @State private var importing = false
    @State private var deleting: RpkInfo?
    @State private var message = ""
    @State private var failed = false
    @State private var fraction: Double = 0
    @State private var working = false

    private var ready: Bool {
        !busy && !syncing && Hex.decode(authKey)?.count == 16 && ble.connectedID != nil && ble.servicesReady
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(ble.connectedName ?? "Подключите браслет на главной вкладке")
                    if Hex.decode(authKey)?.count != 16 { Text("Добавьте ключ браслета в настройках").foregroundStyle(.secondary) }
                    Text("RPK — приложения для браслета. Поддержка конкретного пакета зависит от модели и ПО браслета.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Установка .rpk") {
                    Button { importing = true } label: { Label("Выбрать RPK-файл", systemImage: "doc.badge.plus") }
                        .disabled(busy || syncing)
                    if let file = selectedFile {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(file.name).font(.headline)
                            Text(file.id).font(.caption).textSelection(.enabled)
                            Text("Версия \(file.versionName) (\(file.versionCode)) · \(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Установить на браслет") { perform(.install(file)) }
                            .disabled(!ready)
                    }
                    if working { ProgressView(value: fraction) }
                    if !message.isEmpty {
                        Text(message).font(.callout).foregroundStyle(failed ? Color.red : Color.secondary)
                            .accessibilityIdentifier("rpkStatus")
                    }
                }
                Section {
                    Button { perform(.refresh) } label: { Label("Обновить список", systemImage: "arrow.clockwise") }.disabled(!ready)
                    if !loaded { Text("Нажмите «Обновить список» после подключения").foregroundStyle(.secondary) }
                    else if apps.isEmpty { Text("На браслете нет RPK-приложений").foregroundStyle(.secondary) }
                    ForEach(apps) { app in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(app.name).font(.headline)
                                Text(app.id).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) { deleting = app } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless).disabled(!ready || app.sha.isEmpty)
                                .accessibilityLabel("Удалить \(app.name)")
                        }
                    }
                } header: { Text("Приложения на браслете") }
                footer: { Text("Для замены установленного приложения сначала удалите его. Удаление может стереть его данные на браслете.") }
            }
            .navigationTitle("Приложения")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
                do {
                    let url = try result.get(), scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    selectedFile = try Self.readFile(url); message = "Файл готов к установке"; failed = false
                } catch { message = error.localizedDescription; failed = true }
            }
            .confirmationDialog("Удалить приложение?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { app in
                Button("Удалить \(app.name)", role: .destructive) { perform(.delete(app)); deleting = nil }
                Button("Отмена", role: .cancel) { deleting = nil }
            } message: { app in Text("\(app.id) будет удалено с браслета вместе с данными приложения.") }
            .onChange(of: ble.connectedID) { _ in apps = []; loaded = false }
        }
    }

    static func readFile(_ url: URL) throws -> RpkFile {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 64 * 1024 * 1024 else { throw RpkError.invalidFile("размер должен быть не больше 64 МБ") }
        return try RpkFile(data: Data(contentsOf: url))
    }

    private enum Operation { case refresh, install(RpkFile), delete(RpkInfo) }

    @MainActor private func perform(_ operation: Operation) {
        guard ready, let key = Hex.decode(authKey) else { return }
        busy = true; working = true; failed = false; fraction = 0
        message = "Подключение к службе приложений…"
        let deviceID = ble.connectedID
        Task { @MainActor in
            let oldIdle = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            defer { busy = false; working = false; UIApplication.shared.isIdleTimerDisabled = oldIdle }
            do {
                let installer = FaceInstaller(ble: ble)
                let result: [RpkInfo]
                switch operation {
                case .refresh:
                    ble.addLog("Чтение списка RPK-приложений…")
                    result = try await installer.rpkList(authKey: key)
                    message = "Список приложений обновлён"
                case .install(let file):
                    ble.addLog("Установка RPK \(file.name) (\(file.id)), \(file.size) байт…")
                    result = try await installer.installRpk(file, authKey: key) { sent, total in
                        Task { @MainActor in
                            fraction = Double(sent) / Double(max(total, 1))
                            message = sent == total ? "Файл передан. Проверяю установку…" : "Передача RPK: \(sent) из \(total) частей"
                        }
                    }
                    message = "Установка подтверждена списком браслета"
                case .delete(let app):
                    ble.addLog("Удаление RPK \(app.name) (\(app.id))…")
                    result = try await installer.deleteRpk(app, authKey: key)
                    message = "Удаление подтверждено списком браслета"
                }
                guard ble.connectedID == deviceID else { throw BandError.disconnected }
                apps = result; loaded = true; fraction = 1
                ble.addLog(message)
            } catch {
                message = error.localizedDescription; failed = true; loaded = false; apps = []
                ble.addLog("Ошибка RPK: \(message)")
            }
        }
    }
}
