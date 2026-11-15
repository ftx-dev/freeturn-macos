import SwiftUI
import FreeTurnKit
import UniformTypeIdentifiers

struct LogsView: View {
    @Environment(AppModel.self) private var model
    @State private var minLevel: LogLevel = .debug
    @State private var source: LogSource?
    @State private var query = ""

    private static let order: [LogLevel] = [.debug, .info, .warn, .error]
    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var lines: [LogLine] {
        let floor = Self.order.firstIndex(of: minLevel) ?? 0
        return model.logs.lines.filter { line in
            (Self.order.firstIndex(of: line.level) ?? 0) >= floor
                && (source == nil || line.source == source)
                && (query.isEmpty || line.text.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        let lines = lines
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker(L("Уровень"), selection: $minLevel) {
                    Text(L("Все")).tag(LogLevel.debug)
                    Text(L("Инфо и выше")).tag(LogLevel.info)
                    Text(L("Предупреждения и ошибки")).tag(LogLevel.warn)
                    Text(L("Только ошибки")).tag(LogLevel.error)
                }
                .labelsHidden().fixedSize()
                Picker(L("Источник"), selection: $source) {
                    Text(L("Все источники")).tag(LogSource?.none)
                    Text(L("Ядро")).tag(LogSource?.some(.core))
                    Text(L("Движок")).tag(LogSource?.some(.engine))
                    Text(L("Приложение")).tag(LogSource?.some(.app))
                }
                .labelsHidden().fixedSize()
                TextField(L("Поиск"), text: $query).textFieldStyle(.roundedBorder)
                Button(L("Копировать"), systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lines.map(render).joined(separator: "\n"), forType: .string)
                }
                .disabled(lines.isEmpty)
                Button(L("Сохранить…"), systemImage: "square.and.arrow.down") { save() }
                Button(L("Очистить"), systemImage: "trash") { model.logs.clear() }
                    .disabled(model.logs.lines.isEmpty)
            }
            .labelStyle(.iconOnly)
            .padding(10)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(lines) { line in
                            Text(render(line))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(color(line.level))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(line.id)
                        }
                    }
                    .padding(10)
                }
                // Новые строки - внизу: держим их на виду.
                .onChange(of: lines.last?.id) { _, last in
                    if let last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
            .overlay {
                if lines.isEmpty { ContentUnavailableView(L("Нет логов"), systemImage: "text.alignleft") }
            }
        }
    }

    private func render(_ line: LogLine) -> String {
        "\(Self.time.string(from: line.date)) [\(line.source.rawValue)] \(line.text)"
    }

    private func color(_ level: LogLevel) -> Color {
        switch level {
        case .debug: .secondary
        case .info: .primary
        case .warn: .orange
        case .error: .red
        }
    }

    /// Файл сессии целиком (он длиннее экрана и переживает переподключения).
    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "freeturn-log.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? model.logFile.export(to: url)
    }
}
