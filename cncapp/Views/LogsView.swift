import SwiftUI

struct LogsCard: View {
    @ObservedObject var logStore: LogStore
    @State private var showDebug = false
    @State private var follow = true

    var body: some View {
        NavigationLink {
            LogsView(showDebug: $showDebug, follow: $follow)
                .environmentObject(logStore)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Журнал")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(logStore.snapshot.standard.last?.msg ?? "События станка")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Открывает список событий станка")
    }
}

struct LogsView: View {
    @EnvironmentObject private var logStore: LogStore
    @Binding var showDebug: Bool
    @Binding var follow: Bool
    @State private var scrollTask: Task<Void, Never>?

    private var visibleLogs: [LogEntry] {
        showDebug ? logStore.snapshot.all : logStore.snapshot.standard
    }

    var body: some View {
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
                    .onChange(of: visibleLogs.last?.id, initial: true) { _, _ in
                        guard follow, scrollTask == nil else { return }
                        scrollTask = Task { @MainActor in
                            do { try await Task.sleep(for: .milliseconds(150)) }
                            catch { return }
                            scrollTask = nil
                            guard follow, let id = visibleLogs.last?.id else { return }
                            proxy.scrollTo(id, anchor: .bottom)
                        }
                    }
                    .onDisappear {
                        scrollTask?.cancel()
                        scrollTask = nil
                    }
                }
            }
        }
        .navigationTitle("Журнал")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
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
            ConnectionToolbarItem()
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
