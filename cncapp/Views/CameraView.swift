import SwiftUI
import UIKit

struct CameraView: View {
    let isVisible: Bool

    @EnvironmentObject private var machine: MachineViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var image: UIImage?
    @State private var failure: String?
    @State private var retry = 0
    @State private var showConnection = false

    private struct StreamKey: Equatable {
        let url: URL
        let retry: Int
    }

    private var streamKey: StreamKey? {
        guard isVisible, scenePhase == .active, machine.connection.canReachServer else { return nil }
        return StreamKey(url: machine.activeServerURL, retry: retry)
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Камера")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ConnectionToolbarItem() }
        }
        .sheet(isPresented: $showConnection) { ConnectionView() }
        .task(id: streamKey) { await watch(key: streamKey) }
    }

    @ViewBuilder
    private var content: some View {
        if machine.connection == .authenticationRequired {
            ContentUnavailableView {
                Label("Требуется вход", systemImage: "lock")
            } actions: {
                Button("Ввести пароль") { showConnection = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if machine.connection == .serverOffline {
            ContentUnavailableView {
                Label("Нет связи с Repka", systemImage: "wifi.slash")
            } actions: {
                Button("Переподключиться") { machine.connect() }
                    .buttonStyle(.bordered)
            }
        } else if let failure {
            ContentUnavailableView {
                Label("Камера недоступна", systemImage: "video.slash")
            } description: {
                Text(failure)
            } actions: {
                Button("Повторить") { retry += 1 }
                    .buttonStyle(.bordered)
            }
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding()
                .accessibilityLabel("Видео с USB-камеры станка")
        } else {
            ProgressView(machine.connection == .connecting ? "Подключение к Repka…" : "Получение видео…")
        }
    }

    @MainActor
    private func watch(key: StreamKey?) async {
        guard !Task.isCancelled, key == streamKey else { return }
        image = nil
        failure = nil
        guard let key else { return }

        do {
            let stream = try machine.cameraStream()
            defer { stream.cancel() }
            for try await frame in stream.frames {
                guard !Task.isCancelled, key == streamKey else { return }
                guard let nextImage = UIImage(data: frame) else { throw JPEGFrameBuffer.InvalidFrame() }
                image = nextImage
            }
            guard !Task.isCancelled, key == streamKey else { return }
            failure = image == nil ? "Repka не прислала кадры" : "Видеопоток прерван"
        } catch {
            guard !Task.isCancelled, key == streamKey else { return }
            if case .authenticationRequired? = error as? CNCClientError {
                machine.requireAuthentication()
            } else {
                failure = error.localizedDescription
            }
        }
    }
}
