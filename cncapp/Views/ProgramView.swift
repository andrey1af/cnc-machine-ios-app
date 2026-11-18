import SwiftUI
import UniformTypeIdentifiers

struct ProgramView: View {
    @EnvironmentObject private var machine: MachineViewModel
    @State private var isImporterPresented = false
    @State private var startReview: ProgramStartReview?
    @State private var showCancelConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    programCard
                    controlsCard
                    toolpathCard
                }
                .padding()
            }
            .safeAreaInset(edge: .top, spacing: 0) { MachineStatusPanel() }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("G-code")
            .task(id: machine.previewKey) { await machine.loadPreview() }
            .toolbar {
                ConnectionToolbarItem()
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                Task { await machine.uploadProgram(from: url) }
            }
            .sheet(item: $startReview) { review in
                startConfirmation(for: review)
            }
            .confirmationDialog(
                "Отменить выполнение?",
                isPresented: $showCancelConfirmation,
                titleVisibility: .visible
            ) {
                Button("Отменить программу", role: .destructive) {
                    Task { await machine.cancelProgram() }
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Станок плавно остановится, буфер движения будет очищен. Координаты сохранятся.")
            }
        }
    }

    private var programCard: some View {
        Panel("Текущая программа", help: "Поддерживаются файлы G-code до 10 МБ. Оценка времени обновляется раз в минуту, когда по координатам можно определить прогресс.") {
            if machine.status.program.name.isEmpty {
                ContentUnavailableView(
                    "Файл не выбран",
                    systemImage: "doc.badge.plus"
                )
                .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc.text.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(machine.status.program.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text(machine.status.program.statusText)
                            .font(.subheadline)
                            .foregroundStyle(programColor)
                    }
                    Spacer()
                }

                if machine.status.program.running || machine.status.program.state == "completed" {
                    ProgressView(value: machine.status.program.progress)
                        .tint(machine.status.program.state == "failed" ? .red : .blue)
                    Text("\(Int(machine.status.program.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    let program = machine.status.program
                    Text("≈ Пройдено \(program.completed ?? 0) из \(program.lines) команд · прошло \(ProgramStatus.duration(program.elapsedSeconds ?? 0))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let remaining = program.remainingSeconds {
                        Text("≈ Осталось \(ProgramStatus.duration(remaining, roundUp: true))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else if program.running {
                        Text("Осталось: —")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = machine.status.program.error, !error.isEmpty {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Button {
                isImporterPresented = true
            } label: {
                if machine.isUploading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("Загрузить файл", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(!machine.canUploadProgram)
        }
    }

    private var toolpathCard: some View {
        Panel(
            "Траектория 2.5D",
            help: "Зелёный — пройдено. Оранжевый — текущая строка. Красная точка — инструмент. Пунктир — G0.\n\nТекущая строка определяется приблизительно. Начальные режимы: G21 G90 G17. Высота — Z, размеры — мм."
        ) {
            ToolpathView(preview: machine.preview,
                         cacheKey: "\(machine.previewKey)-\(machine.previewRenderVersion)", status: machine.status,
                         online: machine.connection == .connected)
            if let error = machine.previewError {
                Text(error).font(.caption).foregroundStyle(.secondary)
                Button("Повторить") { Task { await machine.loadPreview(force: true) } }
            }
        }
    }

    private var controlsCard: some View {
        Panel("Управление выполнением") {
            Button {
                startReview = ProgramStartReview(
                    program: machine.status.program,
                    workPosition: startPositionText,
                    previewKey: machine.previewKey
                )
            } label: {
                Label("Старт", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStart)

            HStack {
                Button {
                    Task { await machine.pauseProgram() }
                } label: {
                    Label("Пауза", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(machine.status.program.state != "running" || machine.status.isOnHold)

                Button {
                    Task { await machine.resumeProgram() }
                } label: {
                    Label("Продолжить", systemImage: "playpause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(machine.status.program.state != "running" || !machine.status.isOnHold)
            }

            Button(role: .destructive) {
                showCancelConfirmation = true
            } label: {
                Label("Отменить программу", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!machine.status.program.running)
        }
    }

    private func startConfirmation(for review: ProgramStartReview) -> some View {
        NavigationStack {
            Form {
                Section("Выбранная программа") {
                    Text(review.program.name)
                    LabeledContent("Строк", value: review.program.lines.formatted())
                }
                Section("Обязательные действия") {
                    Text("1. Проверьте крепление заготовки.")
                    Text("2. Установите фрезу в начальную точку.")
                    Text("3. Обнулите рабочие координаты XYZ в этой точке.")
                }
                Section("Рабочие координаты (WPos), мм") {
                    Text(review.workPosition ?? "Рабочие координаты недоступны")
                        .monospacedDigit()
                }
                Section {
                    Button("Подтвердить и запустить") {
                        guard canStart, review.previewKey == machine.previewKey else { return }
                        startReview = nil
                        Task { await machine.startProgram() }
                    }
                    .disabled(!canStart || review.previewKey != machine.previewKey)
                }
            }
            .navigationTitle("Запуск G-code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { startReview = nil }
                }
            }
        }
    }

    private var canStart: Bool {
        machine.status.canStartProgram
    }

    private var startPositionText: String? {
        let status = machine.status
        guard status.hasPosition, status.posLabel == "WPos" else { return nil }
        let axes = Axis.allCases.map { "\($0.rawValue) \(status.coordinateText(for: $0))" }
        let position = axes.joined(separator: "\n")
        guard let receivedAt = machine.positionReceivedAt else { return position }
        return "\(position)\nПолучено в \(receivedAt.formatted(date: .omitted, time: .standard))"
    }

    private var programColor: Color {
        switch machine.status.program.state {
        case "completed": return .green
        case "failed", "canceled": return .red
        case "queued", "running": return .orange
        default: return .secondary
        }
    }
}

private struct ProgramStartReview: Identifiable {
    let program: ProgramStatus
    let workPosition: String?
    let previewKey: String

    var id: String { previewKey }
}

private struct ToolpathView: View {
    let preview: ToolpathPreview?
    let cacheKey: String
    let status: MachineStatus
    let online: Bool
    @State private var geometryCache = ToolpathGeometryCache()

    private var live: Bool {
        online && status.program.state == "running" && status.posLabel == "WPos" &&
        preview != nil && preview?.revision == status.program.revision
    }
    private var line: Int { live ? (status.program.currentLine ?? 0) : 0 }

    var body: some View {
        Canvas { context, size in
            draw(context: &context, size: size)
        }
        .frame(height: 260)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("Траектория G-code, текущая строка \(line)")
        if line > 0 {
            Text("≈ Строка \(line): \(status.program.currentText ?? "")")
                .font(.caption.monospaced()).textSelection(.enabled)
        } else if status.program.state == "running" {
            Text("Текущая строка не определена")
                .font(.caption).foregroundStyle(.secondary)
        }
        if let warning = preview?.warning, !warning.isEmpty {
            Text(warning).font(.caption).foregroundStyle(.orange)
        }
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        guard let preview, preview.revision == status.program.revision,
              !preview.segments.isEmpty,
              let geometry = geometryCache.geometry(for: preview, key: cacheKey, size: size) else { return }
        var grid = Path()
        for x in stride(from: 20.0, to: size.width, by: 32) {
            grid.move(to: CGPoint(x: x, y: 10)); grid.addLine(to: CGPoint(x: x, y: size.height - 10))
        }
        for y in stride(from: 20.0, to: size.height, by: 32) {
            grid.move(to: CGPoint(x: 10, y: y)); grid.addLine(to: CGPoint(x: size.width - 10, y: y))
        }
        context.stroke(grid, with: .color(.secondary.opacity(0.12)), lineWidth: 1)
        // Draw the selected segment last so dense toolpaths cannot cover it.
        for selected in [false, true] {
            for segment in geometry.segments where (line > 0 && segment.line == line) == selected {
                let done = status.program.state == "completed" || (line > 0 && segment.line < line)
                let color: Color = selected ? .orange : done ? .green : segment.rapid ? .gray : .blue.opacity(0.55)
                context.stroke(segment.path, with: .color(color), style: StrokeStyle(
                    lineWidth: selected ? 4 : 1.3, dash: segment.rapid ? [4, 4] : []))
            }
        }
        if live {
            let p = geometry.screen(status.pos)
            let marker = Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
            context.fill(marker, with: .color(.red))
            context.stroke(marker, with: .color(.white), lineWidth: 2)
        }
    }
}

private struct ToolpathGeometry {
    struct Segment {
        let line: Int
        let rapid: Bool
        let path: Path
    }

    let segments: [Segment]
    let center: CGPoint
    let scale: CGFloat
    let size: CGSize

    func screen(_ point: [Double]) -> CGPoint {
        let p = Self.project(point)
        return CGPoint(x: (p.x - center.x) * scale + size.width / 2,
                       y: (p.y - center.y) * scale + size.height / 2)
    }

    static func project(_ point: [Double]) -> CGPoint {
        guard point.count == 3 else { return .zero }
        return CGPoint(x: (point[0] - point[1]) * 0.866,
                       y: (point[0] + point[1]) * 0.5 - point[2])
    }
}

private final class ToolpathGeometryCache {
    private var key: String?
    private var size: CGSize = .zero
    private var cached: ToolpathGeometry?

    func geometry(for preview: ToolpathPreview, key: String, size: CGSize) -> ToolpathGeometry? {
        if self.key == key && self.size == size { return cached }
        self.key = key
        self.size = size
        cached = nil

        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for segment in preview.segments {
            for point in segment.points {
                let p = ToolpathGeometry.project(point)
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
        }
        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return nil }
        let scale = min((size.width - 40) / max(maxX - minX, 1),
                        (size.height - 40) / max(maxY - minY, 1))
        let base = ToolpathGeometry(segments: [], center: CGPoint(x: (minX + maxX) / 2,
                                                                  y: (minY + maxY) / 2),
                                    scale: scale, size: size)
        let paths = preview.segments.map { segment in
            var path = Path()
            for (index, point) in segment.points.enumerated() {
                if index == 0 { path.move(to: base.screen(point)) }
                else { path.addLine(to: base.screen(point)) }
            }
            return ToolpathGeometry.Segment(line: segment.line, rapid: segment.rapid, path: path)
        }
        let result = ToolpathGeometry(segments: paths, center: base.center, scale: scale, size: size)
        cached = result
        return result
    }
}
