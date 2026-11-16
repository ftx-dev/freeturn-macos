import SwiftUI
import FreeTurnKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginItemError: String?
    @State private var confirmingReset = false
    @State private var exporting = false
    @State private var restoreFile: URL?
    @State private var password = ""
    @State private var passwordAgain = ""

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
                LabeledContent(L("Иконка")) {
                    HStack(spacing: 10) {
                        ForEach(AppIcons.variants, id: \.id) { variant in
                            Button {
                                model.settings.appIcon = variant.id
                                AppIcons.apply(variant.id)
                            } label: {
                                VStack(spacing: 4) {
                                    Image(nsImage: AppIcons.image(variant.id)).resizable().frame(width: 44, height: 44)
                                    Text(variant.title).font(.caption)
                                }
                                .padding(6)
                                .background(model.settings.appIcon == variant.id ? Color.accentColor.opacity(0.18) : .clear,
                                            in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(model.settings.appIcon == variant.id ? Color.accentColor : .clear, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(variant.title)
                        }
                    }
                }
                Toggle(isOn: $model.settings.privacyMode) {
                    Text(L("Приватный режим"))
                    Text(L("Скрывает адреса, ключи и ссылку на звонок на экране и в логах."))
                }
            }

            Section(L("Окно")) {
                Toggle(isOn: $model.settings.menuBarOnly) {
                    Text(L("Только в строке меню"))
                    Text(L("Без значка в Dock: подключение, серверы и скорость — в панели по значку в строке меню, как у WireGuard."))
                }
                .onChange(of: model.settings.menuBarOnly) { _, on in AppModel.applyDockPolicy(menuBarOnly: on) }
                Toggle(isOn: $model.settings.compactWindow) {
                    Text(L("Компактное окно"))
                    Text(L("Окно 400×600: все разделы в одну колонку, вкладки внизу."))
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

            Section {
                LabeledContent {
                    Button(L("Экспортировать…")) { password = ""; passwordAgain = ""; exporting = true }
                } label: {
                    Text(L("Экспорт настроек"))
                    Text(L("Серверы, маршруты и настройки в файл под паролем. Файл открывается и в Android-клиенте."))
                }
                LabeledContent {
                    Button(L("Восстановить…")) {
                        if let url = model.chooseBackupFile() { password = ""; restoreFile = url }
                    }
                } label: {
                    Text(L("Восстановление"))
                    Text(L("Текущие серверы и настройки будут заменены."))
                }
            } header: {
                Text(L("Резервная копия"))
            } footer: {
                if let message = model.backupMessage {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                }
            }

            Section(L("Сброс")) {
                Button(L("Сбросить все настройки"), role: .destructive) { confirmingReset = true }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
        }
        .formStyle(.grouped)
        .onChange(of: model.settings) { model.persist() }
        // Раздел живёт скрытым: статус службы освежаем при каждом показе, а не только при создании.
        .task(id: model.section) { if model.section == .settings { await model.refreshDaemonStatus() } }
        .sheet(isPresented: $exporting) {
            PasswordSheet(title: L("Экспорт настроек"), confirm: true, password: $password, passwordAgain: $passwordAgain,
                          hint: L("Понадобится при восстановлении на другом устройстве. Восстановить пароль нельзя.")) {
                exporting = false
                model.exportBackup(password: password)
            }
        }
        .sheet(item: $restoreFile) { url in
            PasswordSheet(title: L("Восстановление"), confirm: false, password: $password, passwordAgain: $passwordAgain,
                          hint: L("Текущие серверы и настройки будут заменены.")) {
                Task {
                    if await model.restoreBackup(from: url, password: password) { restoreFile = nil }
                }
            }
        }
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

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Пароль резервной копии: при экспорте - дважды, при восстановлении - один раз.
private struct PasswordSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let title: String
    let confirm: Bool
    @Binding var password: String
    @Binding var passwordAgain: String
    let hint: String
    let action: () -> Void

    private var problem: String? {
        if password.isEmpty { return L("Введите пароль") }
        if confirm, password != passwordAgain { return L("Пароли не совпадают") }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.weight(.semibold))
            SecureField(L("Пароль"), text: $password)
            if confirm { SecureField(L("Повторите пароль"), text: $passwordAgain) }
            Text(hint).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !confirm, let message = model.backupMessage, message == L("Неверный пароль") || message == L("Неверный формат файла") {
                Text(message).font(.callout).foregroundStyle(.red)
            }
            HStack {
                if let problem, !password.isEmpty { Text(problem).font(.callout).foregroundStyle(.orange) }
                Spacer()
                Button(L("Отмена"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(confirm ? L("Экспортировать") : L("Восстановить"), action: action)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { model.backupMessage = nil }
    }
}
