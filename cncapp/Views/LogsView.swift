import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var logStore: LogStore
    @State private var showDebug = false
    @State private var follow = true
    @State private var scrollTask: Task<Void, Never>?

    private var visibleLogs: [LogEntry] {
        showDebug ? logStore.snapshot.all : logStore.snapshot.standard
    }

    var body: some View {
        NavigationStack {
            Group {
                if visibleLogs.isEmpty {
                    ContentUnavailableView(
                        "Журнал пуст",
                        systemImage: "list.bullet.rectangle",
                        description: Text("События станка появятся после подключения")
                    )
                } else {
                    ScrollViewReader { proxy in
                        List(visibleLogs) { entry in
                            LogRow(entry: entry)
                                .id(entry.id)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)
                        .onChange(of: visibleLogs.last?.id) { _, _ in
                            guard follow, scrollTask == nil else { return }
                            scrollTask = Task { @MainActor in
                                do { try await Task.sleep(for: .milliseconds(150)) }
                                catch { scrollTask = nil; return }
                                scrollTask = nil
                                guard follow, let id = visibleLogs.last?.id else { return }
                                proxy.scrollTo(id, anchor: .bottom)
                            }
                        }
                        .onDisappear { scrollTask?.cancel(); scrollTask = nil }
                    }
                }
            }
            .navigationTitle("Журнал")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ConnectionMenuButton()
                    Menu {
                        Toggle("Показывать DEBUG", isOn: $showDebug)
                        Toggle("Автопрокрутка", isOn: $follow)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    Button(role: .destructive) { logStore.clear() } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(logStore.snapshot.all.isEmpty)
                }
            }
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(entry.timestamp)
                    .foregroundStyle(.secondary)
                Text(entry.level)
                    .fontWeight(.bold)
                    .foregroundStyle(levelColor)
                Spacer()
            }
            Text(entry.msg)
                .foregroundStyle(entry.level == "ERROR" ? .red : .primary)
            if let attrs = entry.attrs, !attrs.isEmpty {
                Text(attrs)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .padding(.vertical, 2)
    }

    private var levelColor: Color {
        switch entry.level {
        case "INFO": return .green
        case "WARN": return .orange
        case "ERROR": return .red
        default: return .secondary
        }
    }
}
