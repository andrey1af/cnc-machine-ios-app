import Foundation
import SwiftUI

struct Panel<Content: View>: View {
    let title: String
    let help: String?
    @ViewBuilder let content: Content

    init(_ title: String, help: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.help = help
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.7)
                if let help {
                    Spacer()
                    PanelHelpButton(title: title, message: help)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.45), lineWidth: 0.5)
        }
    }
}

private struct PanelHelpButton: View {
    let title: String
    let message: String
    @State private var isShowing = false

    var body: some View {
        Button { isShowing = true } label: {
            Image(systemName: "questionmark.circle")
                .font(.body)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .accessibilityLabel("Справка: \(title)")
        .alert(title, isPresented: $isShowing) {
            Button("Закрыть", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

struct ConnectionBadge: View {
    let connection: ServerConnection

    var body: some View {
        Label(connection.title, systemImage: connection.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var color: Color {
        switch connection {
        case .connected: return .green
        case .connecting: return .orange
        case .controllerOffline, .serverOffline: return .red
        }
    }
}

struct ConnectionToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        let item = ToolbarItem(placement: .topBarTrailing) {
            ConnectionMenuButton()
        }
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            item.sharedBackgroundVisibility(.hidden)
        } else {
            item
        }
        #else
        item
        #endif
    }
}

private struct ConnectionMenuButton: View {
    @EnvironmentObject private var machine: MachineViewModel
    @State private var showConnection = false

    var body: some View {
        Button { showConnection = true } label: {
            icon.contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Подключение: \(machine.connection.title)")
        .accessibilityHint("Открыть настройки подключения; удерживайте для просмотра статуса")
        .contentShape(.contextMenuPreview, Circle())
        .contextMenu {
            Label(machine.connection.title, systemImage: machine.connection.symbol)
                .disabled(true)
        }
        .sheet(isPresented: $showConnection) { ConnectionView() }
    }

    @ViewBuilder
    private var icon: some View {
        let symbol = Image(systemName: machine.connection.symbol)
            .font(.title3)
            .foregroundStyle(color)
            .frame(width: 44, height: 44)

        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            symbol.glassEffect(.regular.interactive(), in: Circle())
        } else {
            symbol.background(.regularMaterial, in: Circle())
        }
        #else
        symbol.background(.regularMaterial, in: Circle())
        #endif
    }

    private var color: Color {
        switch machine.connection {
        case .connected: return .green
        case .connecting: return .orange
        case .controllerOffline, .serverOffline: return .red
        }
    }
}

struct JogButton: View {
    let title: String
    let systemImage: String?
    var destructive = false
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var isPressed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(background)
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title3.bold())
            } else {
                Text(title)
                    .font(.headline)
            }
        }
        .foregroundStyle(destructive ? .white : .primary)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .scaleEffect(isPressed ? 0.94 : 1)
        .animation(.easeOut(duration: 0.1), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    onPress()
                }
                .onEnded { _ in
                    isPressed = false
                    onRelease()
                }
        )
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }

    private var background: Color {
        if destructive { return isPressed ? .red.opacity(0.75) : .red }
        return isPressed ? Color.accentColor.opacity(0.25) : Color(uiColor: .secondarySystemBackground)
    }
}

struct MachineStatusPanel: View {
    @EnvironmentObject private var machine: MachineViewModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Axis.allCases, id: \.self) { axis in
                    AxisPosition(
                        axis: axis,
                        value: machine.status.coordinateText(for: axis),
                        isLimited: machine.status.connected && machine.status.pins.contains(axis.rawValue)
                    )
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    details
                    Spacer(minLength: 0)
                    emergencyButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    details
                    emergencyButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(statusText)
                .fontWeight(.semibold)
                .foregroundStyle(statusColor)
            if let receivedAt = machine.positionReceivedAt {
                let time = receivedAt.formatted(date: .omitted, time: .standard)
                Text(machine.status.hasPosition ? "Получено в \(time)" : "Последние данные в \(time)")
                    .foregroundStyle(.secondary)
            } else {
                Text("Координаты недоступны")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .monospacedDigit()
    }

    private var statusText: String {
        guard machine.connection == .connected else { return machine.connection.title }
        guard machine.status.hasPosition else { return machine.status.state }
        return "\(machine.status.posLabel) · мм · \(machine.status.state)"
    }

    private var statusColor: Color {
        switch machine.connection {
        case .serverOffline, .controllerOffline: return .red
        case .connecting: return .orange
        case .connected:
            if machine.status.isAlarm { return .red }
            return machine.status.isIdle ? .green : .orange
        }
    }

    private var emergencyButton: some View {
        Button(role: .destructive) {
            Task { await machine.emergencyStop() }
        } label: {
            Label("Аварийный стоп", systemImage: "stop.circle.fill")
                .font(.caption.weight(.semibold))
                .frame(minHeight: 34)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(!machine.status.connected)
    }
}

private struct AxisPosition: View {
    let axis: Axis
    let value: String
    let isLimited: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(axis.rawValue)
                .font(.caption.bold())
                .foregroundStyle(isLimited ? .red : .secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced, weight: .semibold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueText: String
    let presets: [Double]
    let unit: String
    let fractionDigits: Int
    let inputValue: (Double) -> Double
    let sliderValue: (Double) -> Double
    let onEditingChanged: (Bool) -> Void
    let onCommit: (Double) -> Void

    @State private var draft = ""
    @State private var showPresets = false
    @FocusState private var fieldFocused: Bool

    init(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueText: String,
        presets: [Double],
        unit: String,
        fractionDigits: Int = 0,
        inputValue: @escaping (Double) -> Double = { $0 },
        sliderValue: @escaping (Double) -> Double = { $0 },
        onEditingChanged: @escaping (Bool) -> Void,
        onCommit: @escaping (Double) -> Void
    ) {
        self.title = title
        _value = value
        self.range = range
        self.valueText = valueText
        self.presets = presets
        self.unit = unit
        self.fractionDigits = fractionDigits
        self.inputValue = inputValue
        self.sliderValue = sliderValue
        self.onEditingChanged = onEditingChanged
        self.onCommit = onCommit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Button {
                    showPresets = true
                } label: {
                    HStack(spacing: 5) {
                        Text(valueText).font(.callout.monospacedDigit())
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityLabel("\(title), \(valueText)")
                .accessibilityHint("Выбрать предустановленное значение")
                .contextMenu { presetOptions }
                .confirmationDialog(title, isPresented: $showPresets, titleVisibility: .visible) {
                    presetOptions
                }
            }
            HStack(spacing: 10) {
                Slider(value: $value, in: range) { editing in
                    onEditingChanged(editing)
                    if !editing { onCommit(clamped(value)) }
                }

                TextField("Значение", text: $draft)
                    .font(.callout.monospacedDigit())
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 92)
                    .focused($fieldFocused)
                    .onSubmit(applyDraft)

                if fieldFocused {
                    Button {
                        fieldFocused = false
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Применить значение")
                }
            }
        }
        .onAppear { syncDraft() }
        .onChange(of: value) { _, _ in
            if !fieldFocused { syncDraft() }
        }
        .onChange(of: fieldFocused) { wasFocused, isFocused in
            if isFocused {
                onEditingChanged(true)
            } else if wasFocused {
                applyDraft()
            }
        }
    }

    private var presetOptions: some View {
        ForEach(presets, id: \.self) { preset in
            Button("\(preset.formatted()) \(unit)") {
                let position = clamped(sliderValue(preset))
                value = position
                syncDraft()
                fieldFocused = false
                onCommit(position)
            }
        }
    }

    private func applyDraft() {
        let normalized = draft.replacingOccurrences(of: ",", with: ".")
        onEditingChanged(false)
        guard draft != formattedValue else { return }
        guard let parsed = Double(normalized), parsed.isFinite else {
            syncDraft()
            return
        }

        let newValue = clamped(sliderValue(parsed))
        value = newValue
        syncDraft()
        onCommit(newValue)
    }

    private func clamped(_ number: Double) -> Double {
        min(max(number, range.lowerBound), range.upperBound)
    }

    private func syncDraft() {
        draft = formattedValue
    }

    private var formattedValue: String {
        let displayedValue = inputValue(value)
        if fractionDigits == 0 {
            return String(Int(displayedValue.rounded()))
        } else {
            var formatted = String(format: "%.*f", fractionDigits, displayedValue)
            if formatted.contains(".") {
                while formatted.last == "0" { formatted.removeLast() }
                if formatted.last == "." { formatted.removeLast() }
            }
            return formatted
        }
    }
}
