import SwiftUI
import FreeTurnKit

extension ImportDraft: Identifiable {
    public var id: String { link.peer + link.clientId + link.name }
}

/// Панель подтверждения импорта: что добавляется и чего не хватает.
struct ImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let draft: ImportDraft
    @State private var name = ""
    @State private var callLink = ""

    private var accessType: String {
        guard !draft.needsWireGuard else { return L("нет конфига WireGuard") }
        return (try? WGConfig.parse(draft.link.wgConf))?.isAmnezia == true ? "AmneziaWG" : "WireGuard"
    }

    private var canImport: Bool {
        !draft.needsCallLink || !callLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Импорт подключения")).font(.title2.weight(.semibold))
            Form {
                TextField(L("Имя сервера"), text: $name, prompt: Text(draft.suggestedName))
                LabeledContent(L("Адрес"), value: model.masked(draft.link.peer))
                LabeledContent(L("Подключение"), value: draft.link.provider == Provider.direct ? L("Напрямую") : L("Через реле"))
                LabeledContent(L("Тип доступа"), value: accessType)
                if !draft.link.obfProfile.isEmpty, draft.link.obfProfile != ObfProfile.none {
                    LabeledContent(L("Обфускация"), value: draft.link.obfProfile)
                }
                if draft.needsCallLink {
                    TextField(L("Ссылка на звонок"), text: $callLink, prompt: Text("https://vk.ru/call/join/…"))
                    Text(draft.callLink.isEmpty
                        ? L("Создайте звонок, скопируйте ссылку и не завершайте его.")
                        : L("Ссылка пришла вместе с доступом — можно заменить своей."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.columns)

            if draft.needsWireGuard {
                Label(L("В ссылке нет конфига WireGuard. Сервер сохранится, но для подключения конфиг нужно добавить в его настройках."),
                      systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            }
            if draft.duplicateAddress {
                Label(L("Сервер с этим адресом уже есть в списке."), systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }
            if draft.duplicateConf {
                Label(L("Этот конфиг WireGuard уже импортирован."), systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button(L("Отмена"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("Импортировать")) { model.confirmImport(name: name, callLink: callLink) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canImport)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { callLink = draft.callLink }
    }
}
