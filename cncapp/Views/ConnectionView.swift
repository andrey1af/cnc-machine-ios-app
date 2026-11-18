import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var machine: MachineViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var addressFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Состояние") {
                    HStack {
                        ConnectionBadge(connection: machine.connection)
                        Spacer()
                        if machine.connection == .connecting { ProgressView() }
                    }

                    LabeledContent("Сервер", value: serverState)
                    LabeledContent("Контроллер", value: machine.status.connected ? "Подключён" : "Нет связи")
                    if machine.status.connected {
                        LabeledContent("GRBL", value: machine.status.state)
                    }
                }

                Section {
                    TextField("http://repka.local:8080", text: $machine.serverAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($addressFocused)
                        .submitLabel(.go)
                        .onSubmit { applyAddress() }

                    Button("Подключиться") { applyAddress() }
                        .frame(maxWidth: .infinity)
                } header: {
                    Text("Адрес подключения")
                }
            }
            .navigationTitle("Подключение")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private var serverState: String {
        switch machine.connection {
        case .serverOffline: return "Недоступен"
        case .connecting: return "Подключение"
        case .controllerOffline, .connected: return "Доступен"
        }
    }

    private func applyAddress() {
        addressFocused = false
        _ = machine.applyServerAddress()
    }
}
