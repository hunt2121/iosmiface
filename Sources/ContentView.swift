import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var ble: BLEManager

    @State private var authKey: String = KeychainStore.load(account: "authKey") ?? ""
    @State private var showImporter = false
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
        NavigationStack {
            Form {
                Section {
                    Text("Збірка №\(Self.buildNumber) · версія \(Self.versionString)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("1. Auth key") {
                    TextField("32 hex-символи", text: $authKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: authKey) { KeychainStore.save($0, account: "authKey") }
                    Text(keyValid ? "Ключ виглядає коректно" : "Потрібно рівно 16 байт у hex")
                        .font(.footnote)
                        .foregroundStyle(keyValid ? .green : .secondary)
                }

                bandSection

                Section("3. Встановлення циферблата") {
                    Button(fileName ?? "Вибрати .face файл") { showImporter = true }
                    if let face {
                        Text("ID \(face.id)\(face.name.map { " · \($0)" } ?? "") · \(face.data.count / 1024) КБ")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Встановити на браслет") {
                        if let face { run(.install(face)) }
                    }
                    .disabled(!canOperate || face == nil)
                }

                if busy || message != nil {
                    Section {
                        if busy {
                            ProgressView(value: progress)
                            Text(progressText).font(.footnote).foregroundStyle(.secondary)
                        }
                        if let message {
                            Text(message).font(.footnote)
                                .foregroundStyle(messageIsError ? .red : .green)
                        }
                    }
                }

                facesSection

                logSection
            }
            .navigationTitle("BandFace")
            .onChange(of: scenePhase) { phase in
                // Відпускаємо браслет, щоб він вільно працював з Mi Fitness
                if phase == .background && !busy && ble.connectedID != nil {
                    ble.disconnect()
                    bandFaces = nil
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
                loadFace(result)
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
        }
    }

    // MARK: - Розділи

    private var bandSection: some View {
        Section("2. Браслет") {
            if let name = ble.connectedName {
                HStack {
                    Label(name, systemImage: "applewatch")
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
                    .font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var facesSection: some View {
        Section {
            Button(bandFaces == nil ? "Показати циферблати на браслеті" : "Оновити список") {
                run(.list)
            }
            .disabled(!canOperate)

            if let bandFaces {
                if bandFaces.isEmpty {
                    Text("Список порожній").foregroundStyle(.secondary)
                }
                ForEach(bandFaces) { f in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name.isEmpty ? "Без назви" : f.name)
                            Text(f.canDelete ? "ID \(f.id)" : "ID \(f.id) · системний")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if f.active {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                    .contextMenu { faceActions(f) }
                    .swipeActions { faceActions(f) }
                }
            }
        } header: {
            Text("Циферблати на браслеті")
        } footer: {
            if bandFaces != nil {
                Text("Проведіть ліворуч або утримуйте рядок, щоб активувати чи видалити.")
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
                face = try FaceFile(data: data)
                fileName = url.lastPathComponent
                message = nil
            } catch {
                face = nil
                fileName = nil
                show("Некоректний файл циферблата: \(error.localizedDescription)", error: true)
            }
        }
    }

    @MainActor
    private func run(_ operation: XiaomiBandSession.Operation, quiet: Bool = false) {
        do {
            let s = try XiaomiBandSession(ble: ble, authKeyHex: authKey)
            s.onWatchfaces = { list in bandFaces = list }
            session = s
            busy = true
            progress = 0
            progressText = "Старт…"
            if !quiet { message = nil }
            let refreshAfter: Bool
            switch operation {
            case .list: refreshAfter = false
            default: refreshAfter = bandFaces != nil
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
