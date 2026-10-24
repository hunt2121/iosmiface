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
    @AppStorage("expAck") private var expAck = 0
    @AppStorage("expCrypt") private var expCrypt = 0
    @AppStorage("expDelay") private var expDelay = 1.5
    @AppStorage("expSkip") private var expSkip = false
    @AppStorage("expBond") private var expBond = true

    private var keyValid: Bool {
        if let d = Data(hex: authKey) { return d.count == 16 }
        return false
    }

    private var canInstall: Bool {
        keyValid && face != nil && ble.connectedID != nil && ble.servicesReady && !busy
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

                Section("2. Файл циферблата") {
                    Button(fileName ?? "Вибрати .face файл") { showImporter = true }
                    if let face {
                        Text("ID \(face.id)\(face.name.map { " · \($0)" } ?? "") · \(face.data.count) байт")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("3. Браслет") {
                    if let name = ble.connectedName {
                        HStack {
                            Label(name, systemImage: "applewatch")
                            Spacer()
                            Button("Відключити", role: .destructive) { ble.disconnect() }
                        }
                        if !ble.servicesReady {
                            HStack { ProgressView(); Text("Виявлення сервісів…").font(.footnote) }
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
                        .disabled(!canInstall)
                    if busy {
                        ProgressView(value: progress)
                        Text(progressText).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let message {
                        Text(message).font(.footnote)
                            .foregroundStyle(messageIsError ? .red : .green)
                    }
                }

                Section("Діагностика (експерименти)") {
                    Picker("Підтвердження (ack)", selection: $expAck) {
                        Text("seq пакета").tag(0)
                        Text("seq+1").tag(1)
                        Text("не слати").tag(2)
                    }
                    Picker("Шифрування команд", selection: $expCrypt) {
                        Text("ключ шифр.").tag(0)
                        Text("ключ дешифр.").tag(1)
                        Text("без шифр.").tag(2)
                    }
                    Picker("Пауза після входу", selection: $expDelay) {
                        Text("1.5 с").tag(1.5)
                        Text("5 с").tag(5.0)
                    }
                    Toggle("Без device info/battery", isOn: $expSkip)
                    Toggle("Створювати пару перед сесією", isOn: $expBond)
                    Button("Створити пару зараз") { ble.probeBonding { ble.addLog("Перевірку пари завершено") } }
                        .disabled(ble.connectedID == nil || !ble.servicesReady || busy)
                }

                Section("Журнал") {
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
                    ForEach(Array(ble.log.suffix(150).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
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
    private func install() {
        guard let face else { return }
        do {
            let s = try XiaomiBandSession(ble: ble, authKeyHex: authKey)
            s.experiment = BandExperiment(ackMode: expAck, cryptMode: expCrypt, delay: expDelay, skipProbe: expSkip, bonding: expBond)
            session = s
            busy = true
            progress = 0
            progressText = "Старт…"
            message = nil
            s.install(face: face, progress: { value, text in
                progress = value
                progressText = text
            }, completion: { result in
                busy = false
                switch result {
                case .success(let text): show(text, error: false)
                case .failure(let error): show(error.localizedDescription, error: true)
                }
                session = nil
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
