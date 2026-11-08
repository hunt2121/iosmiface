// SPDX-License-Identifier: MIT
// Редактор циферблата: полотно з вибором і перетягуванням шарів, панель властивостей, додавання елементів,
// шари, фон, попередній перегляд і збирання .bin.

import SwiftUI
import PhotosUI
import FaceCompiler

struct EditorView: View {
    @ObservedObject var project: FaceProject
    @Environment(\.dismiss) private var dismiss
    /// «Встановити на пристрій» — лише в BandFace
    @Environment(\.faceInstall) private var install

    @State private var theme = 0
    /// Циферблат має елементи, не перевірені на браслеті (Б-1) — питаємо перед встановленням
    @State private var askUntested = false
    /// Який кольоровий варіант показує полотно (0 — основний)
    @State private var variant = 0
    @State private var selected: XNode?
    @State private var tab: InspectorTab = .look
    @State private var sheet: EditorSheet?
    @State private var showPreview = false
    @State private var confirmDiscard = false
    @State private var alert: String?
    @State private var share: ShareItem?
    @State private var initial: (Data, [String: Data], ProjectMeta)?
    @AppStorage("editorSnap") private var snap = true
    @AppStorage("editorGrid") private var grid = 1

    @State private var showXml = false
    /// Масштаб полотна: 100 / 150 / 200 %
    @State private var zoom: CGFloat = 1
    /// Замок: елементи не пересуваються, палець рухає полотно
    @State private var locked = false
    @Environment(\.scenePhase) private var scenePhase

    enum EditorSheet: Identifiable { case add, layers, background, source, properties
        var id: Int { hashValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            CanvasView(project: project, theme: theme, variant: variant, selected: $selected, snap: snap, grid: grid, zoom: zoom, locked: locked)
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                .overlay(alignment: .topTrailing) { canvasButtons }
                .overlay(alignment: .topLeading) {
                    // знімок циферблата: картинка → «Поділитися» (Файли, Фото, месенджери)
                    roundButton("camera", "Знімок циферблата") { shareShot() }.padding(12)
                }
                .overlay(alignment: .bottomLeading) { zoomChips }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            panel
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            if initial == nil { initial = (Data(XML.print(project.root)), project.files, project.meta) }
            if project.themes.isEmpty { project.edit { $0.root.add("Theme").set("type", "normal").set("name", "").set("bgColor", "#000000") } }
            // тека проєкту могла змінитися в «Файлах»
            if project.reloadFromDisk() { dropMissingSelection() }
        }
        .onChange(of: scenePhase) { ph in if ph == .active, project.reloadFromDisk() { dropMissingSelection() } }
        .fullScreenCover(isPresented: $showXml) { XmlEditorView(project: project, theme: theme).onDisappear { dropMissingSelection() } }
        .sheet(item: $sheet) { s in
            switch s {
            case .add:
                AddElementSheet(project: project, theme: theme) { layout in selected = layout; tab = .look }
                    .presentationDetents([.large])
            case .layers:
                LayersSheet(project: project, theme: theme, selected: $selected)
                    .presentationDetents([.medium, .large])
            case .background:
                BackgroundSheet(project: project, theme: theme)
                    .presentationDetents([.medium])
            case .properties:
                FacePropertiesSheet(project: project, theme: $theme)
                    .presentationDetents([.large])
            case .source:
                if let sel = selected, let res = project.element(of: sel) {
                    NavigationStack {
                        DataSourcePicker(current: res.string("source")) { src in
                            project.edit { _ in res.set("source", src) }
                        }
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showPreview) { PreviewView(project: project, theme: theme) }
        // стандартне вікно «Поділитися» (показ UIKit, як в інших застосунках), а не SwiftUI-аркуш
        .onChange(of: share?.id) { _ in
            guard let item = share else { return }
            share = nil
            ShotShare.present(items: [item.url])
        }
        .confirmationDialog("Відкинути зміни, зроблені після відкриття?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Відкинути зміни", role: .destructive) { discard() }
            Button("Зберегти й закрити") { dismiss() }
        }
        .alert("Не перевірено на браслеті", isPresented: $askUntested) {
            Button("Встановити все одно", role: .destructive) { installOnBand(force: true) }
            Button("Скасувати", role: .cancel) {}
        } message: {
            Text("У циферблаті є текст, який малює сам браслет. Його немає в жодному відомому циферблаті Smart Band 10, тож на браслеті він не перевірений і може зламати прошивку. Для чисел і дати безпечніше взяти «Цифри».")
        }
        .alert(alert ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
            Button("Гаразд", role: .cancel) {}
        }
    }

    // MARK: Верхня панель

    private var topBar: some View {
        // назва — рівно по центру екрана, незалежно від ширини кнопок з боків
        ZStack {
            titleButton.padding(.horizontal, 110)
            HStack {
            Button { confirmDiscard = true } label: {
                Image(systemName: "xmark").font(.system(size: 16, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color(.secondarySystemGroupedBackground)))
            }
            .accessibilityLabel("Закрити")
            Spacer()
            Menu {
                if install != nil {
                    Button { installOnBand() } label: { Label("Встановити на пристрій", systemImage: "arrow.down.to.line") }
                }
                Button { exportBin() } label: { Label("Зберегти .bin", systemImage: "square.and.arrow.up") }
                Section {
                    Button { showXml = true } label: { Label("Редагувати XML", systemImage: "chevron.left.forwardslash.chevron.right") }
                    Button { share = ShareItem(url: project.folder) } label: { Label("Поділитися текою проєкту", systemImage: "folder") }
                }
                Button { dismiss() } label: { Label("Готово", systemImage: "checkmark") }
            } label: {
                Text("Готово").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 40)
                    .background(Capsule().fill(Color.accentColor))
            } primaryAction: { dismiss() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// назва → властивості циферблата (назва, ID, екрани, розмір)
    private var titleButton: some View {
        Button { sheet = .properties } label: {
            HStack(spacing: 4) {
                Text(project.displayName).font(.headline).foregroundStyle(.primary).lineLimit(1)
                Image(systemName: "chevron.down.circle.fill").font(.system(size: 15)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Властивості циферблата"))
    }

    private var canvasButtons: some View {
        VStack(spacing: 8) {
            roundButton("arrow.uturn.backward", "Скасувати") { project.undo(); dropMissingSelection() }
                .disabled(!project.canUndo)
            roundButton("arrow.uturn.forward", "Повторити") { project.redo(); dropMissingSelection() }
                .disabled(!project.canRedo)
            roundButton("eye", "Попередній перегляд") { showPreview = true }
            if project.themes.count > 1 {
                roundButton(theme == 0 ? "sun.max" : "moon", "Тема") { theme = (theme + 1) % project.themes.count; selected = nil }
            }
            Button { locked.toggle() } label: {
                Image(systemName: locked ? "lock.fill" : "lock.open").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(locked ? Color.white : Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(locked ? Color.accentColor : Color(.tertiarySystemGroupedBackground)))
            }
            .accessibilityLabel(Text(loc(locked ? "Розблокувати переміщення елементів" : "Заблокувати переміщення елементів")))
        }
        .padding(12)
    }

    /// «Циферблат» — назва, фон, кольори (те саме, що дотик поза циферблатом)
    /// Знімок поточного екрана циферблата (з вибраним кольором) у 2× і стандартне вікно «Поділитися», як в інших застосунках:
    /// картинка (а не файл), тож є «Зберегти зображення» в Фото; назва й мініатюра — з циферблата.
    private func shareShot() {
        let rd = FaceRenderer(project)
        rd.colorVariant = variant
        let (img, _) = rd.render(theme: theme, scale: 2)
        guard let png = img.pngData(), let pic = UIImage(data: png) else { return }
        ShotShare.present(ShotShare(image: pic, title: project.displayName.isEmpty ? loc("Знімок циферблата") : project.displayName))
    }

    private var zoomChips: some View {
        // колонкою в лівому нижньому куті — поруч із корпусом, а не поверх нього
        VStack(alignment: .leading, spacing: 6) {
            ForEach([100, 150, 200], id: \.self) { z in
                let on = abs(zoom * 100 - CGFloat(z)) < 1
                Button { withAnimation(.easeInOut(duration: 0.2)) { zoom = CGFloat(z) / 100 } } label: {
                    Text(verbatim: "\(z)%").font(.caption.weight(.semibold)).monospacedDigit()
                        .frame(width: 52, height: 28)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(Capsule().fill(on ? Color.accentColor : Color(.tertiarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }

    private func dropMissingSelection() {
        if let s = selected, !project.layouts(theme).contains(where: { $0 === s }) { selected = nil }
    }

    private func roundButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(.tertiarySystemGroupedBackground)))
        }
        .accessibilityLabel(Text(loc(label)))
    }

    // MARK: Нижня панель

    private var panel: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(.systemGray4)).frame(width: 36, height: 5).padding(.top, 10).padding(.bottom, 10)
            ScrollView {
                if let sel = selected, project.layouts(theme).contains(where: { $0 === sel }) {
                    InspectorView(project: project, theme: theme, layout: sel, tab: $tab, snap: $snap, grid: $grid,
                                  onSource: { sheet = .source },
                                  onDuplicate: {
                                      project.edit { ElementFactory.duplicate($0, layout: sel, theme: theme) }
                                      selected = project.layouts(theme).last
                                  },
                                  onDelete: {
                                      project.edit { ElementFactory.delete($0, layout: sel, theme: theme) }
                                      selected = nil
                                  })
                } else {
                    faceInfo
                }
            }
            HStack(spacing: 10) {
                bottomButton("Елемент", icon: "plus", prominent: true) { sheet = .add }
                bottomButton("Шари", icon: nil) { sheet = .layers }
                bottomButton("Фон", icon: nil) { sheet = .background }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedCorners(radius: 28).fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.08), radius: 10, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
        .padding(.top, 14)
    }

    private func bottomButton(_ title: String, icon: String?, prominent: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .bold)) }
                Text(loc(title)).font(.subheadline.weight(.semibold)).lineLimit(1).fixedSize()
            }
            .frame(maxWidth: .infinity).frame(height: 44)
            .foregroundStyle(prominent ? Color.accentColor : .primary)
            .background(Capsule().fill(prominent ? Color.accentColor.opacity(0.14) : Color(.tertiarySystemGroupedBackground)))
        }
        .buttonStyle(.plain)
    }

    private var faceInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Циферблат").font(.title3.weight(.bold))
            Text("Торкніться елемента на полотні, щоб змінити його, або перетягніть, щоб пересунути. «Елемент» додає час, дату, кроки, пульс, погоду та інше.")
                .font(.subheadline).foregroundStyle(.secondary)
            if project.themes.count < 2 {
                Button {
                    project.edit { p in
                        let t = p.root.add("Theme")
                        t.set("type", "AOD").set("name", "").set("bgColor", "#000000")
                        // у режимі «завжди на екрані» — лише час, без секундних і кольорових деталей
                        for l in p.layouts(0) where ElementKind.of(p.element(of: l)) == .digits { t.kids.append(l.copy()) }
                    }
                    theme = 1; selected = nil
                } label: {
                    Label("Додати екран «Завжди на екрані»", systemImage: "moon")
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemGroupedBackground)))
                }
                .buttonStyle(.plain)
            } else {
                Text(loc(theme == 0 ? "Зараз: основний екран" : "Зараз: «Завжди на екрані»")).font(.footnote).foregroundStyle(.secondary)
            }
            ColorVariantsPanel(project: project, variant: $variant)
                .padding(.top, 6)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Дії

    private func exportBin() {
        do {
            let (data, warnings) = try project.compile()
            share = ShareItem(url: try ShareItem.write(data, name: project.name))
            // однакові імена — це кольорові варіанти однієї картинки, так і має бути
            let shown = warnings.filter { !$0.contains("same name") }
            if !shown.isEmpty { alert = loc("Зібрано з попередженнями:") + "\n" + shown.prefix(5).joined(separator: "\n") }
        } catch {
            alert = String(localized: "Не вдалося зібрати: \(error.localizedDescription)")
        }
    }

    /// Збирає .bin і передає BandFace: та встановлює його на браслет (або підказує, що спершу підключити).
    private func installOnBand(force: Bool = false) {
        guard let install else { return }
        if !force && !Band10.untested(project.root).isEmpty { askUntested = true; return }
        do {
            let (data, _) = try project.compile()
            FacePreviews.alias(data, from: project)
            let name = project.displayName
            dismiss()
            install(data, name)
        } catch {
            alert = String(localized: "Не вдалося зібрати: \(error.localizedDescription)")
        }
    }

    private func discard() {
        if let snap = initial, let r = try? XML.parse([UInt8](snap.0)) {
            project.edit { p in
                p.root.kids = r.kids; p.root.attrs = r.attrs
                for k in p.files.keys { p.removeFile(k) }
                for (k, v) in snap.1 { p.setFile(k, v) }
                p.meta = snap.2
            }
        }
        dismiss()
    }
}

/// Верхні заокруглені кути панелі (iOS 16 не має UnevenRoundedRectangle).
struct UnevenRoundedCorners: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft, .topRight],
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case look = "Вигляд", color = "Колір", position = "Позиція"
    var id: String { rawValue }
}
