import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var machine: MachineViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var addressFocused: Bool
    @State private var password = ""
    @State private var isApplying = false
    @State private var connectionError: String?

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
                    TextField(MachineViewModel.defaultServerAddress, text: $machine.serverAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($addressFocused)
                        .submitLabel(.go)
                        .onSubmit { applyAddress() }

                    if usesHTTPS {
                        SecureField("Пароль веб-пульта", text: $password)
                            .submitLabel(.go)
                            .onSubmit { applyAddress() }
                    }

                    if let connectionError {
                        Text(connectionError).font(.footnote).foregroundStyle(.red)
                    }

                    Button("Подключиться") { applyAddress() }
                        .frame(maxWidth: .infinity)
                } header: {
                    Text("Адрес подключения")
                }
                .disabled(isApplying)
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
        case .authenticationRequired: return "Требуется вход"
        case .controllerOffline, .connected: return "Доступен"
        }
    }

    private var usesHTTPS: Bool {
        machine.serverAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("https://")
    }

    private func applyAddress() {
        guard !isApplying else { return }
        addressFocused = false
        connectionError = nil
        isApplying = true
        let candidate = usesHTTPS ? password : ""
        Task {
            defer { isApplying = false }
            do {
                try await machine.applyServerAddress(password: candidate)
                password = ""
            } catch {
                connectionError = error.localizedDescription
            }
        }
    }
}
