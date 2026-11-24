import SwiftUI
import FreeTurnKit
import UniformTypeIdentifiers

struct LogsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.compactLayout) private var compact
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

    private static var levelTitles: [(LogLevel, String)] {
        [(.debug, L("Все")), (.info, L("Инфо и выше")), (.warn, L("Предупреждения и ошибки")), (.error, L("Только ошибки"))]
    }

    private static var sourceTitles: [(LogSource?, String)] {
        [(nil, L("Все источники")), (.core, L("Ядро")), (.engine, L("Движок")), (.app, L("Приложение"))]
    }

    private var levelPicker: some View {
        Picker(L("Уровень"), selection: $minLevel) {
            Text(L("Все")).tag(LogLevel.debug)
            Text(L("Инфо и выше")).tag(LogLevel.info)
            Text(L("Предупреждения и ошибки")).tag(LogLevel.warn)
            Text(L("Только ошибки")).tag(LogLevel.error)
        }
        .labelsHidden()
    }

    private var sourcePicker: some View {
        Picker(L("Источник"), selection: $source) {
            Text(L("Все источники")).tag(LogSource?.none)
            Text(L("Ядро")).tag(LogSource?.some(.core))
            Text(L("Движок")).tag(LogSource?.some(.engine))
            Text(L("Приложение")).tag(LogSource?.some(.app))
        }
        .labelsHidden()
    }

    private var searchField: some View {
        TextField(L("Поиск"), text: $query).textFieldStyle(.roundedBorder)
    }

    @ViewBuilder private func actions(_ lines: [LogLine]) -> some View {
        Button(L("Копировать"), systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(lines.map(render).joined(separator: "\n"), forType: .string)
        }
        .disabled(lines.isEmpty)
        Button(L("Сохранить…"), systemImage: "square.and.arrow.down") { save() }
        Button(L("Очистить"), systemImage: "trash") { model.logs.clear() }
            .disabled(model.logs.lines.isEmpty)
    }

    var body: some View {
        let lines = lines
        VStack(spacing: 0) {
            // В узком окне фильтры - отдельной строкой над поиском и кнопками.
            Group {
                if compact {
                    VStack(spacing: 8) {
                        // У выпадающих списков macOS свой внутренний отступ - компенсируем, чтобы края
                        // совпали с полем поиска слева и кнопкой «Очистить» справа.
                        // Свои кнопки-меню вместо системных списков: у тех свой внутренний отступ,
                        // и края не совпадали с полем поиска и кнопкой «Очистить».
                        HStack(spacing: 8) {
                            FilterMenu(title: Self.levelTitles.first { $0.0 == minLevel }?.1 ?? "") {
                                ForEach(Self.levelTitles, id: \.0) { level, title in Button(title) { minLevel = level } }
                            }
                            FilterMenu(title: Self.sourceTitles.first { $0.0 == source }?.1 ?? "") {
                                ForEach(Self.sourceTitles, id: \.1) { value, title in Button(title) { source = value } }
                            }
                        }
                        HStack(spacing: 8) { searchField; actions(lines) }
                    }
                } else {
                    HStack(spacing: 10) { levelPicker.fixedSize(); sourcePicker.fixedSize(); searchField; actions(lines) }
                }
            }
            .labelStyle(.iconOnly)
            .padding(10)
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(lines) { line in
                            logText(line)
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
        prefix(line) + line.text
    }

    private func prefix(_ line: LogLine) -> String {
        "\(Self.time.string(from: line.date)) [\(line.source.rawValue)] "
    }

    private func logText(_ line: LogLine) -> Text {
        guard let segments = line.segments else { return Text(render(line)) }
        var message = AttributedString(prefix(line))
        for segment in segments {
            var part = AttributedString(segment.text)
            if let foreground = segment.foreground { part.foregroundColor = color(foreground) }
            if let background = segment.background { part.backgroundColor = color(background) }
            message.append(part)
        }
        return Text(message)
    }

    private func color(_ rgb: LogLine.RGB) -> Color {
        Color(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
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

/// Кнопка-меню фильтра в узкой раскладке: форма как у поля поиска, края - вровень с ним.
private struct FilterMenu<Items: View>: View {
    let title: String
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu {
            items()
        } label: {
            HStack(spacing: 4) {
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .frame(maxWidth: .infinity)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}
