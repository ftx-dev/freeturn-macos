import SwiftUI
import FreeTurnKit

struct UpdateSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.updater.installing != nil {
            UpdateProgressSheet()
        } else if let update = model.offerUpdate {
            UpdateOfferView(update: update)
        }
    }
}

/// Предложение обновиться: заметки к релизу показываются с базовой разметкой Markdown.
private struct UpdateOfferView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let update: AvailableUpdate

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: AppIcons.image(model.settings.appIcon)).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: L("Доступна версия %@"), update.version)).font(.title3.weight(.semibold))
                    Text(String(format: L("Сейчас установлена %@"), model.updater.currentVersion)).font(.callout).foregroundStyle(.secondary)
                }
            }
            ScrollView {
                MarkdownText(update.notes.isEmpty ? L("Приложение перезапустится. VPN на время обновления отключится.") : update.notes,
                             skipTitle: update.version)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
            .frame(maxHeight: 340)
            HStack {
                if let page = update.pageURL { Link(L("Открыть на GitHub"), destination: page).font(.callout) }
                Spacer()
                Button(L("Позже")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Обновить")) {
                    model.installUpdate(update)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
    }
}

/// Минимальный Markdown для заметок к релизу: заголовки #..###, списки «- » и «* », абзацы,
/// а внутри строк - **жирный**, *курсив*, `код` и ссылки (голые https:// тоже кликабельны).
struct MarkdownText: View {
    let blocks: [Block]

    enum Block: Hashable {
        case heading(level: Int, text: String)
        case bullet(String)
        case paragraph(String)
        case gap
    }

    /// skipTitle: заголовок, повторяющий номер версии («FreeTurnX 0.2.2»), не дублируем.
    init(_ source: String, skipTitle: String? = nil) {
        var out: [Block] = []
        for raw in source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if out.last != .gap, !out.isEmpty { out.append(.gap) }
            } else if let hashes = line.prefix(while: { $0 == "#" }).count as Int?, hashes > 0, hashes <= 6,
                      line.dropFirst(hashes).first == " " {
                let text = String(line.dropFirst(hashes + 1))
                if let skip = skipTitle, out.isEmpty, text.contains(skip) { continue }
                out.append(.heading(level: hashes, text: text))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                out.append(.bullet(String(line.dropFirst(2))))
            } else {
                out.append(.paragraph(line))
            }
        }
        while out.last == .gap { out.removeLast() }
        blocks = out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .heading(level, text):
                    Self.inline(text).font(level <= 3 ? .headline : .subheadline.weight(.semibold))
                        .padding(.top, 4)
                case let .bullet(text):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•").foregroundStyle(.secondary)
                        Self.inline(text)
                    }
                case let .paragraph(text):
                    Self.inline(text)
                case .gap:
                    Spacer().frame(height: 4)
                }
            }
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    static func inline(_ text: String) -> Text {
        // Голые ссылки - в <…>, чтобы разметка сделала их кликабельными.
        let linked = text.replacingOccurrences(of: #"(?<![<(\[])(https?://[^\s<>()]+)"#, with: "<$1>", options: .regularExpression)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: linked, options: options) { return Text(attributed) }
        return Text(text)
    }
}

/// Окно установки обновления: прогресс загрузки с отменой, затем установка и перезапуск.
private struct UpdateProgressSheet: View {
    @Environment(AppModel.self) private var model
    private var updater: Updater { model.updater }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: AppIcons.image(model.settings.appIcon)).resizable().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: L("Обновление до %@"), updater.installing?.version ?? "")).font(.title3.weight(.semibold))
                    Text(status).font(.callout).foregroundStyle(failure == nil ? .secondary : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if failure == nil {
                if updater.phase == .downloading, updater.expected > 0 {
                    ProgressView(value: Double(updater.received), total: Double(updater.expected))
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            HStack {
                Spacer()
                if failure != nil {
                    Button(L("Закрыть")) { updater.dismissFailure() }.keyboardShortcut(.defaultAction)
                } else {
                    Button(L("Отменить")) { updater.cancel() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(updater.phase != .downloading)
                }
            }
        }
        .padding(22)
        .frame(width: 420)
        .interactiveDismissDisabled()
    }

    private var failure: String? {
        if case let .failed(text) = updater.phase { return text }
        return nil
    }

    private var status: String {
        if let failure { return failure }
        switch updater.phase {
        case .downloading:
            guard updater.expected > 0 else { return L("Загрузка…") }
            let mb = { (bytes: Int64) in String(format: "%.1f", Double(bytes) / 1_048_576) }
            return String(format: L("Загрузка: %@ из %@ МБ"), mb(updater.received), mb(updater.expected))
        default:
            return L("Установка… Приложение перезапустится.")
        }
    }
}
