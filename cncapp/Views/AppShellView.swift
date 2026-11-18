import SwiftUI

struct AppShellView: View {
    @EnvironmentObject private var machine: MachineViewModel

    var body: some View {
        TabView {
            ControlView()
                .tabItem { Label("Пульт", systemImage: "move.3d") }

            ProgramView()
                .tabItem { Label("G-code", systemImage: "doc.text") }
        }
        .tint(.blue)
        .alert("Ошибка", isPresented: errorBinding) {
            Button("Закрыть", role: .cancel) { machine.dismissError() }
        } message: {
            Text(machine.lastError ?? "Неизвестная ошибка")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { machine.lastError != nil },
            set: { if !$0 { machine.dismissError() } }
        )
    }
}
