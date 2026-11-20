import SwiftUI

struct ControllerSettingsView: View {
    let isVisible: Bool

    @EnvironmentObject private var machine: MachineViewModel
    @FocusState private var focusedSetting: String?
    @State private var draft = ControllerSettingsDraft()
    @State private var draftSource: Source?
    @State private var loadedKey: LoadKey?
    @State private var reloadCount = 0
    @State private var readError: String?
    @State private var notice: String?
    @State private var failed = false
    @State private var writing = false
    @State private var confirmReload = false
    @State private var review: Review?

    private struct Source: Equatable {
        let url: URL
        let epoch: Int
    }

    private struct LoadKey: Equatable {
        let source: Source
        let reloadCount: Int
    }

    private struct Edit: Identifiable {
        let setting: ControllerSetting
        let change: ControllerSettingChange
        var id: String { setting.id }
    }

    private struct Review: Identifiable {
        let id = UUID()
        let key: LoadKey
        let edits: [Edit]

        var needsRestart: Bool { edits.contains { $0.id == "5" || $0.id == "21" } }
    }

    private var source: Source { Source(url: machine.activeServerURL, epoch: machine.serverEpoch) }

    private var loadKey: LoadKey? {
        guard isVisible, machine.connection == .connected else { return nil }
        return LoadKey(source: source, reloadCount: reloadCount)
    }

    private var ready: Bool { loadKey != nil && loadedKey == loadKey }

    private var canWrite: Bool {
        let status = machine.status
        return ready && !writing && !status.program.running && (status.isIdle || status.state == "Alarm")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if writing {
                        ProgressView("Записываем и проверяем параметры…")
                    } else if let notice, draftSource == source {
                        Label(notice, systemImage: failed ? "exclamationmark.circle" : "checkmark.circle")
                            .foregroundStyle(failed ? Color.red : Color.green)
                    }

                    if machine.connection != .connected {
                        Label(machine.connection.title, systemImage: machine.connection.symbol)
                    } else if let readError {
                        Label(readError, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    } else if !ready && !writing {
                        ProgressView("Читаем параметры с платы…")
                    } else if ready && !writing && !canWrite {
                        Text("Для записи дождитесь остановки станка.")
                            .foregroundStyle(.secondary)
                    }

                    Button("Считать с платы", systemImage: "arrow.clockwise") { requestReload() }
                        .disabled(loadKey == nil || writing || (!ready && readError == nil))
                } header: {
                    Text("Makerbase MKS DLC32 · GRBL")
                }

                if ready {
                    ForEach(draft.groups.indices, id: \.self) { index in
                        let group = draft.groups[index]
                        Section {
                            ForEach(group.settings) { setting in
                                settingRow(setting)
                            }
                            .disabled(writing)
                        } header: {
                            Text(group.title)
                        } footer: {
                            if group.settings.contains(where: { $0.id == "23" }) {
                                Text("Маски осей: X = 1, Y = 2, Z = 4. Для нескольких осей сложите их числа. Кнопка «Домой» ищет концевики по Z+, X+ и Y−. Для этого нужны $22=1 и $23=2.")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Сохранить") { prepareReview() }
                        .disabled(!canWrite || draft.edited.isEmpty)
                }
                ConnectionToolbarItem()
            }
            .confirmationDialog("Сбросить правки и считать параметры заново?", isPresented: $confirmReload, titleVisibility: .visible) {
                Button("Считать с платы", role: .destructive) { reload() }
                Button("Отмена", role: .cancel) {}
            }
            .sheet(item: $review) { confirmation($0) }
        }
        .task(id: loadKey) { [key = loadKey] in await read(key) }
    }

    private func settingRow(_ setting: ControllerSetting) -> some View {
        let value = Binding(
            get: { draft.values[setting.id] ?? "" },
            set: { draft.values[setting.id] = $0 }
        )
        return LabeledContent {
            if let current = setting.value {
                if setting.kind == .toggle {
                    Picker(setting.label, selection: value) {
                        Text("Выкл. · 0").tag("0")
                        Text("Вкл. · 1").tag("1")
                        if current != 0 && current != 1 {
                            let text = ControllerSetting.text(current)
                            Text(text).tag(text)
                        }
                    }
                    .labelsHidden()
                } else {
                    TextField(setting.label, text: value)
                        .keyboardType(setting.kind == .integer ? .numberPad : .decimalPad)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 72, maxWidth: 110)
                        .focused($focusedSetting, equals: setting.id)
                }
            } else {
                Text("Недоступно").foregroundStyle(.secondary)
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(setting.label)
                Text(setting.caption).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }

    private func confirmation(_ pending: Review) -> some View {
        NavigationStack {
            Form {
                Section("Текущее и новое значения") {
                    ForEach(pending.edits) { edit in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(edit.setting.label)
                            Text("$\(edit.id) · \(ControllerSetting.text(edit.change.from)) → \(ControllerSetting.text(edit.change.to))\(edit.setting.unit.map { " \($0)" } ?? "")")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if pending.needsRestart {
                    Section {
                        Text("После записи перезапустите питание контроллера.")
                    }
                }
                Button("Подтвердить и записать") { apply(pending) }
                    .disabled(!canWrite || pending.key != loadKey)
            }
            .navigationTitle("Подтвердите изменения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { review = nil }
                }
            }
        }
    }

    private func requestReload() {
        if draft.edited.isEmpty { reload() } else { confirmReload = true }
    }

    private func reload() {
        focusedSetting = nil
        draft = ControllerSettingsDraft()
        draftSource = nil
        reloadCount += 1
    }

    private func read(_ key: LoadKey?) async {
        guard let key, key == loadKey, !Task.isCancelled, !writing else { return }
        loadedKey = nil
        readError = nil
        notice = nil
        do {
            let groups = try await machine.controllerSettings()
            guard key == loadKey, !Task.isCancelled else { return }
            draft.replace(with: groups, keepingEdits: draftSource == key.source)
            draftSource = key.source
            loadedKey = key
        } catch {
            guard key == loadKey, !Task.isCancelled else { return }
            readError = error.localizedDescription
        }
    }

    private func prepareReview() {
        guard canWrite, let key = loadedKey else { return }
        var edits: [Edit] = []
        for setting in draft.edited {
            guard let from = setting.value, let to = setting.parse(draft.values[setting.id] ?? "") else {
                notice = "Проверьте $\(setting.id) (\(setting.label)). Допустимый диапазон — \(ControllerSetting.text(setting.min))–\(ControllerSetting.text(setting.max))."
                failed = true
                focusedSetting = setting.kind == .toggle ? nil : setting.id
                return
            }
            edits.append(Edit(setting: setting, change: ControllerSettingChange(from: from, to: to)))
        }
        guard !edits.isEmpty else { return }
        focusedSetting = nil
        review = Review(key: key, edits: edits)
    }

    private func apply(_ pending: Review) {
        guard canWrite, pending.key == loadKey else { return }
        writing = true
        review = nil
        notice = nil
        let changes = Dictionary(pending.edits.map { ($0.id, $0.change) }, uniquingKeysWith: { first, _ in first })
        Task {
            defer {
                writing = false
                if let key = loadKey, key.source != pending.key.source { reloadCount += 1 }
            }
            do {
                let groups = try await machine.controllerSettings(changes: changes)
                guard source == pending.key.source else { return }
                draft.replace(with: groups)
                notice = pending.needsRestart
                    ? "Параметры сохранены. Перезапустите питание контроллера."
                    : "Параметры сохранены и проверены."
                failed = false
            } catch {
                guard source == pending.key.source else { return }
                notice = error.localizedDescription
                failed = true
                loadedKey = nil
                do {
                    let groups = try await machine.controllerSettings()
                    guard source == pending.key.source else { return }
                    draft.replace(with: groups, keepingEdits: true)
                    loadedKey = pending.key
                } catch {
                    guard source == pending.key.source else { return }
                    readError = "Считайте параметры с платы повторно, чтобы проверить результат записи."
                }
            }
        }
    }
}
