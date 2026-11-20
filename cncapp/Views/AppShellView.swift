import SwiftUI

struct AppShellView: View {
    private enum Tab { case control, program, camera, settings }

    @EnvironmentObject private var machine: MachineViewModel
    @State private var selectedTab: Tab = .control

    var body: some View {
        TabView(selection: $selectedTab) {
            ControlView()
                .tabItem { Label("Пульт", systemImage: "move.3d") }
                .tag(Tab.control)

            ProgramView()
                .tabItem { Label("G-code", systemImage: "doc.text") }
                .tag(Tab.program)

            CameraView(isVisible: selectedTab == .camera)
                .tabItem { Label("Камера", systemImage: "video") }
                .tag(Tab.camera)

            ControllerSettingsView(isVisible: selectedTab == .settings)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
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
