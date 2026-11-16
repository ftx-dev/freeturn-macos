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
                Picker(selection: $model.settings.language) {
                    Text(L("Как в системе")).tag("system")
                    Text("Русский").tag("ru")
                    Text("English").tag("en")
                } label: {
                    Text(L("Язык"))
                    if model.settings.language != L10n.language {
                        Text(L("Язык сменится после перезапуска приложения."))
                    }
                }
                Toggle(isOn: $model.settings.privacyMode) {
                    Text(L("Приватный режим"))
                    Text(L("Скрывает адреса, ключи и ссылку на звонок на экране и в логах."))
                }
            }

            Section(L("Подключение")) {
                Toggle(isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) })) {
                    Text(L("Запускать при входе в систему"))
                    if let loginItemError {
                        Text(loginItemError).foregroundStyle(.red)
                    }
                }
                Toggle(isOn: $model.settings.autoConnect) {
                    Text(L("Подключаться при запуске"))
                    Text(L("Восстанавливает подключение, если вы не выключали его сами."))
                }
            }

            Section("CAPTCHA") {
                Picker(L("Открывать капчу"), selection: $model.settings.captchaTarget) {
                    Text(L("В окне приложения")).tag("window")
                    Text(L("В браузере")).tag("browser")
                }
                let manual = model.activeServer?.client.manualCaptcha == true
                Toggle(isOn: $model.settings.advancedCaptcha) {
                    Text(L("Продвинутое решение CAPTCHA"))
                    Text(manual
                        ? L("Недоступно, пока у активного сервера включён ручной ввод капчи.")
                        : L("Проверку в фоне проходит встроенный браузер. Если не получится, откроется ручная капча."))
                }
                .disabled(manual)
            }

            Section(L("Обновления")) {
                LabeledContent(L("Версия"), value: "\(model.updater.currentVersion) · \(UpdateCheck.currentArch)")
                Toggle(isOn: $model.settings.checkUpdates) {
                    Text(L("Проверять при запуске"))
                    Text(L("Новые версии берутся из GitHub Releases, под процессор этого Mac."))
                }
                HStack {
                    updateStatus
                    Spacer()
                    if let update = model.updater.available {
                        Button(String(format: L("Обновить до %@"), update.version)) { model.installUpdate(update) }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button(L("Проверить сейчас")) { Task { await model.updater.check() } }
                            .disabled(model.updater.phase == .checking)
                    }
                }
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

    @ViewBuilder private var updateStatus: some View {
        switch model.updater.phase {
        case .idle: EmptyView()
        case .checking: ProgressView().controlSize(.small)
        case .upToDate: Label(L("Установлена последняя версия"), systemImage: "checkmark.circle").foregroundStyle(.secondary)
        case let .available(update): Text(String(format: L("Доступна версия %@"), update.version))
        case .downloading: Label(L("Загрузка…"), systemImage: "arrow.down.circle").foregroundStyle(.secondary)
        case .installing: Label(L("Установка…"), systemImage: "gearshape").foregroundStyle(.secondary)
        case let .failed(text): Text(text).foregroundStyle(.red)
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
