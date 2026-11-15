import SwiftUI
import FreeTurnKit

extension RuleKind {
    @MainActor var title: String {
        switch self {
        case .app: L("Приложение")
        case .domain: L("Домен")
        case .domainSuffix: L("Домен и поддомены")
        case .domainKeyword: L("Слово в домене")
        case .cidr: L("IP или подсеть")
        }
    }

    var icon: String {
        switch self {
        case .app: "app.dashed"
        case .domain, .domainSuffix, .domainKeyword: "globe"
        case .cidr: "network"
        }
    }

    var placeholder: String {
        switch self {
        case .app: "/Applications/Safari.app"
        case .domain: "example.com"
        case .domainSuffix: "example.com"
        case .domainKeyword: "google"
        case .cidr: "10.0.0.0/8"
        }
    }
}

extension RouteAction {
    @MainActor var title: String {
        switch self {
        case .vpn: L("Через VPN")
        case .direct: L("Напрямую")
        case .block: L("Блокировать")
        }
    }
}

/// Создание и правка одного правила.
struct RuleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: RoutingRule
    let onSave: (RoutingRule) -> Void
    @State private var pickingApp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Правило")).font(.title2.weight(.semibold))
            Form {
                Picker(L("Что"), selection: $rule.kind) {
                    ForEach(RuleKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if rule.kind == .app {
                    LabeledContent(L("Приложение")) {
                        HStack {
                            Text(rule.value.isEmpty ? "—" : rule.value)
                                .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                            Button(L("Выбрать…")) { pickingApp = true }
                            Button(L("Файл…")) { pickExecutable() }
                        }
                    }
                } else {
                    TextField(L("Значение"), text: $rule.value, prompt: Text(rule.kind.placeholder))
                }
                Picker(L("Действие"), selection: $rule.action) {
                    ForEach(RouteAction.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            .formStyle(.columns)
            if !rule.value.isEmpty, !EngineConfig.isValid(rule) {
                Label(L("Такое значение движок не примет."), systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(L("Отмена"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Сохранить")) {
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!EngineConfig.isValid(rule))
            }
        }
        .padding(20)
        .frame(width: 500)
        .sheet(isPresented: $pickingApp) { AppPickerView { rule.value = $0 } }
        // Значение одного типа для другого бессмысленно.
        .onChange(of: rule.kind) { rule.value = "" }
    }

    /// Программы без бандла: утилиты командной строки.
    private func pickExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rule.value = url.path
    }
}
