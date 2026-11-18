import SwiftUI

struct ControlView: View {
    @EnvironmentObject private var machine: MachineViewModel
    @State private var showZeroConfirmation = false
    @State private var stepPosition = 500.0
    @State private var feedXY = 100.0
    @State private var feedZ = 300.0
    @State private var lockedControls: Set<ControlField> = []
    @State private var pendingControls: Set<ControlField> = []
    @State private var coordinateChangesLocked = false

    private let grid = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    private let speedPresets: [Double] = [10, 25, 50, 100, 200]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    jogPanel
                    settingsPanel
                    machinePanel
                    LogsCard(logStore: machine.logStore)
                }
                .padding()
            }
            .safeAreaInset(edge: .top, spacing: 0) { MachineStatusPanel() }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("CNC Пульт")
            .toolbar {
                ConnectionToolbarItem()
            }
            .confirmationDialog(
                "Обнулить рабочие координаты X, Y и Z в текущей точке?",
                isPresented: $showZeroConfirmation,
                titleVisibility: .visible
            ) {
                Button("Обнулить координаты") { Task { await machine.zero() } }
                Button("Отмена", role: .cancel) {}
            }
            .onAppear(perform: syncControls)
            .onChange(of: machine.status) { _, _ in syncControls() }
            .onChange(of: canEditSettings) { _, available in
                if !available {
                    lockedControls.removeAll()
                    syncControls()
                }
            }
            .onDisappear { machine.endJog() }
        }
    }

    private var jogPanel: some View {
        Panel("Перемещение", help: "Короткое касание перемещает ось на один шаг. Удерживайте кнопку для непрерывного движения. Блокировка отключает ручное перемещение.") {
            Button {
                coordinateChangesLocked.toggle()
                if coordinateChangesLocked { machine.endJog() }
            } label: {
                Label(
                    coordinateChangesLocked ? "Разблокировать перемещение" : "Заблокировать перемещение",
                    systemImage: coordinateChangesLocked ? "lock.fill" : "lock.open"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(coordinateChangesLocked ? .orange : .accentColor)

            HStack(alignment: .center, spacing: 14) {
                LazyVGrid(columns: grid, spacing: 8) {
                    Color.clear.frame(height: 64)
                    jogButton("Y+", icon: "arrow.up", axis: .y, direction: 1)
                    Color.clear.frame(height: 64)

                    jogButton("X−", icon: "arrow.left", axis: .x, direction: -1)
                    JogButton(title: "STOP", systemImage: nil, destructive: true) {
                        Task { await machine.stopJog() }
                    } onRelease: {}
                    .frame(height: 64)
                    .opacity(canStopJog ? 1 : 0.45)
                    .allowsHitTesting(canStopJog)
                    jogButton("X+", icon: "arrow.right", axis: .x, direction: 1)

                    Color.clear.frame(height: 64)
                    jogButton("Y−", icon: "arrow.down", axis: .y, direction: -1)
                    Color.clear.frame(height: 64)
                }

                VStack(spacing: 8) {
                    jogButton("Z+", icon: "arrow.up.to.line", axis: .z, direction: 1)
                    Spacer(minLength: 8)
                    jogButton("Z−", icon: "arrow.down.to.line", axis: .z, direction: -1)
                }
                .frame(width: 66, height: 208)
            }
        }
    }

    private var settingsPanel: some View {
        Panel("Шаг и скорость") {
            ValueSlider(
                title: "Шаг",
                value: $stepPosition,
                range: 0...1_000,
                valueText: "\(formattedStep) мм",
                presets: [0.1, 1, 5, 10, 50],
                unit: "мм",
                fractionDigits: 3,
                inputValue: stepFrom(position:),
                sliderValue: positionFrom(step:),
                onEditingChanged: { editing in
                    setEditing(.step, editing: editing)
                },
                onCommit: { position in
                    commit(.step) { await machine.updateStep(stepFrom(position: position)) }
                }
            )
            .disabled(pendingControls.contains(.step))

            ValueSlider(
                title: "Скорость X/Y",
                value: $feedXY,
                range: 1...300,
                valueText: "\(Int(feedXY)) мм/мин",
                presets: speedPresets,
                unit: "мм/мин",
                onEditingChanged: { editing in
                    setEditing(.feedXY, editing: editing)
                },
                onCommit: { value in
                    commit(.feedXY) { await machine.updateFeedXY(value) }
                }
            )
            .disabled(pendingControls.contains(.feedXY))

            ValueSlider(
                title: "Скорость Z",
                value: $feedZ,
                range: 1...300,
                valueText: "\(Int(feedZ)) мм/мин",
                presets: speedPresets,
                unit: "мм/мин",
                onEditingChanged: { editing in
                    setEditing(.feedZ, editing: editing)
                },
                onCommit: { value in
                    commit(.feedZ) { await machine.updateFeedZ(value) }
                }
            )
            .disabled(pendingControls.contains(.feedZ))
        }
        .disabled(!canEditSettings)
    }

    private var machinePanel: some View {
        Panel("Станок") {
            VStack(spacing: 10) {
                Button { Task { await machine.unlock() } } label: {
                    Label("Снять блокировку", systemImage: "lock.open")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                HStack {
                    Button { Task { await machine.home() } } label: {
                        Label("Хоминг", systemImage: "house")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button { showZeroConfirmation = true } label: {
                        Label("Ноль XYZ", systemImage: "scope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .disabled(!machine.status.connected || machine.status.program.running)
        }
    }

    private func jogButton(_ title: String, icon: String, axis: Axis, direction: Int) -> some View {
        JogButton(title: title, systemImage: icon) {
            machine.beginJog(axis: axis, direction: direction)
        } onRelease: {
            machine.endJog()
        }
        .frame(height: 64)
        .opacity(canJog ? 1 : 0.45)
        .allowsHitTesting(canJog)
    }

    private var canJog: Bool {
        machine.status.connected && !machine.status.program.running && !coordinateChangesLocked
    }

    private var canStopJog: Bool {
        machine.status.connected && !machine.status.program.running
    }

    private var canEditSettings: Bool {
        machine.connection == .connected || machine.connection == .controllerOffline
    }

    private var formattedStep: String {
        let value = stepFrom(position: stepPosition)
        return value < 0.1 ? String(format: "%.3f", value) : String(format: "%.2f", value)
    }

    private func stepFrom(position: Double) -> Double {
        let value = 0.1 * pow(500, position / 1_000)
        return Double(String(format: "%.4g", value)) ?? value
    }

    private func positionFrom(step: Double) -> Double {
        let clamped = min(max(step, 0.1), 50)
        return log(clamped / 0.1) / log(500) * 1_000
    }

    private func syncControls() {
        if !lockedControls.contains(.step), !pendingControls.contains(.step) {
            stepPosition = positionFrom(step: machine.status.step)
        }
        if !lockedControls.contains(.feedXY), !pendingControls.contains(.feedXY) {
            feedXY = min(max(machine.status.feedXY, 1), 300)
        }
        if !lockedControls.contains(.feedZ), !pendingControls.contains(.feedZ) {
            feedZ = min(max(machine.status.feedZ, 1), 300)
        }
    }

    private func setEditing(_ field: ControlField, editing: Bool) {
        if editing && canEditSettings {
            lockedControls.insert(field)
        } else {
            lockedControls.remove(field)
        }
    }

    private func commit(_ field: ControlField, operation: @escaping @MainActor () async -> Bool) {
        guard canEditSettings else {
            syncControls()
            return
        }
        guard pendingControls.insert(field).inserted else { return }
        Task {
            let applied = if canEditSettings { await operation() } else { false }
            pendingControls.remove(field)
            if !applied { syncControls() }
        }
    }
}

private enum ControlField: Hashable {
    case step
    case feedXY
    case feedZ
}
