import SwiftUI

@main
struct CNCApp: App {
    @StateObject private var machine = MachineViewModel()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environmentObject(machine)
                .task { machine.connect() }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    machine.endJog()
                }
        }
    }
}
