import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var ble: BLEManager

    @State private var authKey: String = KeychainStore.load(account: "authKey") ?? ""
    @State private var showImporter = false
    @State private var faceName: String?
    @State private var faceData: Data?
    @State private var selected: UUID?
    @State private var progress: Double = 0
    @State private var busy = false
    @State private var message: String?

    private var keyValid: Bool {
        if let d = Data(hex: authKey) { return d.count == 16 }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
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

                Section("2. Файл циферблата") {
                    Button(faceName ?? "Вибрати .face файл") { showImporter = true }
                    if let d = faceData {
                        Text("\(d.count) байт").font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("3. Браслет") {
                    if let name = ble.connectedName {
                        HStack {
                            Label(name, systemImage: "applewatch")
                            Spacer()
                            Button("Відключити", role: .destructive) { ble.disconnect() }
                        }
                    } else {
                        Button(ble.isScanning ? "Зупинити пошук" : "Шукати пристрої") {
                            ble.isScanning ? ble.stopScan() : ble.startScan()
                        }
                        ForEach(ble.devices) { d in
                            Button {
                                ble.connect(d.id)
                            } label: {
                                HStack {
                                    Text(d.name)
                                    Spacer()
                                    Text("\(d.rssi) dBm").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if ble.state == .unauthorized {
                        Text("Дозвольте Bluetooth для застосунку в Налаштуваннях iOS.")
                            .font(.footnote).foregroundStyle(.red)
                    }
                }

                Section("4. Встановлення") {
                    Button("Встановити на браслет") { install() }
                        .disabled(!keyValid || faceData == nil || ble.connectedID == nil || busy)
                    if busy { ProgressView(value: progress) }
                    if let message { Text(message).font(.footnote) }
                }

                Section("Журнал") {
                    ForEach(Array(ble.log.suffix(40).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption2, design: .monospaced))
                    }
                }
            }
            .navigationTitle("BandFace")
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data]) { result in
                loadFace(result)
            }
        }
    }

    private func loadFace(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let e):
            message = e.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                faceData = try Data(contentsOf: url)
                faceName = url.lastPathComponent
                message = nil
            } catch {
                message = error.localizedDescription
            }
        }
    }

    @MainActor
    private func install() {
        guard let data = faceData, let name = faceName else { return }
        busy = true
        progress = 0
        message = nil
        Task {
            do {
                let session = try XiaomiBandSession(ble: ble, authKeyHex: authKey)
                try await session.installWatchface(data, name: name) { p in
                    Task { @MainActor in progress = p }
                }
                message = "Готово"
            } catch {
                message = error.localizedDescription
            }
            busy = false
        }
    }
}
