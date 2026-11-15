import SwiftUI
import FreeTurnKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?
    @State private var confirmingReset = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section(L("Интерфейс")) {
                Picker(L("Тема"), selection: $model.settings.theme) {
                    Text(L("Системная")).tag("system")
                    Text(L("Светлая")).tag("light")
                    Text(L("Тёмная")).tag("dark")
                }
                Picker(L("Язык"), selection: $model.settings.language) {
                    Text(L("Как в системе")).tag("system")
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                }
                if model.settings.language != L10n.language {
                    Text(L("Язык сменится после перезапуска приложения.")).font(.caption).foregroundStyle(.secondary)
                }
                Toggle(L("Приватный режим"), isOn: $model.settings.privacyMode)
                Text(L("Скрывает адреса, ключи и ссылку на звонок на экране и в логах."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("Подключение")) {
                Toggle(L("Запускать при входе в систему"), isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                if let loginItemError {
                    Text(loginItemError).font(.caption).foregroundStyle(.red)
                }
                Toggle(L("Подключаться при запуске"), isOn: $model.settings.autoConnect)
                Text(L("Восстанавливает подключение, если вы не выключали его сами."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("CAPTCHA") {
                Picker(L("Открывать капчу"), selection: $model.settings.captchaTarget) {
                    Text(L("В окне приложения")).tag("window")
                    Text(L("В браузере")).tag("browser")
                }
                let manual = model.activeServer?.client.manualCaptcha == true
                Toggle(L("Продвинутое решение CAPTCHA"), isOn: $model.settings.advancedCaptcha)
                    .disabled(manual)
                Text(manual
                    ? L("Недоступно, пока у активного сервера включён ручной ввод капчи.")
                    : L("Проверку в фоне проходит встроенный браузер. Если не получится, откроется ручная капча."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L("Фоновая служба")) {
                LabeledContent(L("Состояние"), value: model.daemonStatusText)
                HStack {
                    Button(L("Переустановить")) { model.reinstallDaemon() }
                    Button(L("Удалить службу"), role: .destructive) { model.uninstallDaemon() }
                    if model.installingDaemon { ProgressView().controlSize(.small) }
                }
                .disabled(model.installingDaemon || model.connection.state.isActive)
                if let error = model.daemonInstallError {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }

            Section(L("Отладка")) {
                Toggle(L("Показывать отладочную информацию"), isOn: $model.settings.debugScreen)
                if model.settings.debugScreen {
                    LabeledContent(L("Приложение"), value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
                    LabeledContent(L("Ядро"), value: model.connection.coreVersion.isEmpty ? AppInfo.coreVersion : model.connection.coreVersion)
                    LabeledContent(L("Движок"), value: "Amnezia Box \(AppInfo.engineVersion)")
                    LabeledContent(L("Каталог данных"), value: model.store.directory.path)
                    if !model.connection.launchArgs.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("Команда запуска ядра")).font(.caption).foregroundStyle(.secondary)
                            Text(model.redactedLaunchArgs)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            Section(L("Сброс")) {
                Button(L("Сбросить все настройки"), role: .destructive) { confirmingReset = true }
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.settings) { model.persist() }
        .task { await model.refreshDaemonStatus() }
        .confirmationDialog(L("Сбросить все настройки?"), isPresented: $confirmingReset) {
            Button(L("Сбросить"), role: .destructive) { model.resetAll() }
        } message: {
            Text(L("Подключение остановится, серверы, профили маршрутов и логи будут удалены."))
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            try LoginItem.set(on)
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
        launchAtLogin = LoginItem.isEnabled
    }
}
