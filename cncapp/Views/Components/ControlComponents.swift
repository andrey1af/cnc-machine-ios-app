import Foundation
import SwiftUI

struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.7)
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

struct ConnectionMenuButton: View {
    @EnvironmentObject private var machine: MachineViewModel
    @State private var showConnection = false

    var body: some View {
        Button { showConnection = true } label: {
            Image(systemName: machine.connection.symbol)
                .font(.title3)
                .foregroundStyle(color)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Подключение: \(machine.connection.title)")
        .accessibilityHint("Открыть настройки подключения; удерживайте для просмотра статуса")
        .contextMenu {
            Label(machine.connection.title, systemImage: machine.connection.symbol)
                .disabled(true)
        }
        .sheet(isPresented: $showConnection) { ConnectionView() }
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

struct AxisPosition: View {
    let axis: Axis
    let value: Double
    let isLimited: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(axis.rawValue)
                .font(.caption.bold())
                .foregroundStyle(isLimited ? .red : .secondary)
            Text(String(format: "%+.3f", value))
                .font(.system(.title3, design: .monospaced, weight: .semibold))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueText: String
    let fractionDigits: Int
    let inputValue: (Double) -> Double
    let sliderValue: (Double) -> Double
    let onEditingChanged: (Bool) -> Void
    let onCommit: (Double) -> Void

    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    init(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueText: String,
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
                Text(valueText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
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

    private func applyDraft() {
        let normalized = draft.replacingOccurrences(of: ",", with: ".")
        guard let parsed = Double(normalized), parsed.isFinite else {
            syncDraft()
            onEditingChanged(false)
            return
        }

        let newValue = clamped(sliderValue(parsed))
        value = newValue
        syncDraft()
        onEditingChanged(false)
        onCommit(newValue)
    }

    private func clamped(_ number: Double) -> Double {
        min(max(number, range.lowerBound), range.upperBound)
    }

    private func syncDraft() {
        let displayedValue = inputValue(value)
        if fractionDigits == 0 {
            draft = String(Int(displayedValue.rounded()))
        } else {
            var formatted = String(format: "%.*f", fractionDigits, displayedValue)
            if formatted.contains(".") {
                while formatted.last == "0" { formatted.removeLast() }
                if formatted.last == "." { formatted.removeLast() }
            }
            draft = formatted
        }
    }
}
