import SwiftUI
import FreeTurnKit
import UniformTypeIdentifiers

/// Параметры сервера. Правки сохраняются сразу.
struct ServerDetailView: View {
    @Environment(AppModel.self) private var model
    let serverId: String

    private var server: Binding<Server> {
        Binding(
            get: { model.servers.list.first { $0.id == serverId } ?? Server(name: "") },
            set: { model.servers.update($0); model.persist() })
    }

    /// Параметры сервера под живым подключением менять нельзя: ядро и движок уже запущены с ними.
    private var locked: Bool {
        model.connection.state.isActive && model.connection.activeServerId == serverId
    }

    var body: some View {
        let s = server
        let relay = s.wrappedValue.client.provider == Provider.relay
        Form {
            if locked {
                Label(L("Остановите подключение, чтобы изменить этот сервер."), systemImage: "lock")
                    .foregroundStyle(.secondary)
            }
            if !s.wrappedValue.client.wireGuardActive {
                Label(L("Добавьте конфиг WireGuard, чтобы подключиться"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            Section {
                TextField(L("Имя сервера"), text: s.name)
                secretField(L("Адрес сервера"), s.client.serverAddress, prompt: "1.2.3.4:56000")
                Picker(L("Способ"), selection: s.client.provider) {
                    Text(L("Через релей")).tag(Provider.relay)
                    Text(L("Напрямую")).tag(Provider.direct)
                }
                if relay {
                    secretField(L("Ссылка на звонок"), s.client.callLink, prompt: "https://vk.ru/call/join/…")
                }
            } header: {
                Text(L("Подключение"))
            } footer: {
                if relay { footnote(L("Создайте звонок, скопируйте ссылку и не завершайте его.")) }
            }

            if relay {
                Section {
                    Stepper(String(format: L("Потоки: %d"), s.wrappedValue.client.threads),
                            value: s.client.threads, in: 1...model.settings.maxStreams)
                    Stepper(String(format: L("Потоков на аккаунт: %d"), s.wrappedValue.client.streamsPerCred),
                            value: s.client.streamsPerCred, in: 1...model.settings.maxStreamsPerCred)
                } header: {
                    Text(L("Производительность"))
                } footer: {
                    footnote(L("Рекомендуется 8–12 потоков: больше — выше риск блокировки со стороны сервиса звонков."))
                }
            }

            Section {
                Picker(L("Профиль"), selection: s.opts.obfProfile) {
                    ForEach(ObfProfile.values, id: \.self) { Text($0 == ObfProfile.none ? L("Выкл") : $0).tag($0) }
                }
                if s.wrappedValue.opts.obfEnabled {
                    HStack {
                        secretField(L("Ключ (64 hex)"), s.opts.obfKey)
                            .font(.system(.body, design: .monospaced))
                        Button(L("Сгенерировать")) { s.wrappedValue.opts.obfKey = ObfProfile.generateKey() }
                    }
                    Stepper(s.wrappedValue.opts.obfTimingMs == 0
                                ? L("Пейсинг: выкл")
                                : String(format: L("Пейсинг: %d мс"), s.wrappedValue.opts.obfTimingMs),
                            value: s.opts.obfTimingMs, in: 0...ObfProfile.timingMax, step: 5)
                }
            } header: {
                Text(L("Обфускация"))
            } footer: {
                if s.wrappedValue.opts.obfEnabled, !ObfProfile.isValidKey(s.wrappedValue.opts.obfKey) {
                    footnote(L("Неверный формат — нужны 64 hex-символа. Ключ должен совпадать с ключом сервера."), color: .red)
                }
            }

            Section {
                Picker(L("Резолвер ядра"), selection: s.client.dnsMode) {
                    Text(L("Авто")).tag("auto")
                    Text("UDP/53").tag("plain")
                    Text("DoH").tag("doh")
                }
                TextField(L("DNS-серверы вручную"), text: s.client.customDns, prompt: Text("1.1.1.1, 8.8.8.8"))
                Toggle(L("DNS текущей сети"), isOn: s.client.useCarrierDns)
                    .disabled(!DnsList.normalize(s.wrappedValue.client.customDns).isEmpty)
            } header: {
                Text("DNS")
            } footer: {
                if DnsList.hasInvalidTokens(s.wrappedValue.client.customDns) {
                    footnote(L("Некорректные адреса будут пропущены."), color: .orange)
                }
            }

            if relay {
                Section(L("Дополнительно")) {
                    Picker(L("Транспорт до реле"), selection: s.client.useUdp) {
                        Text("TCP").tag(false)
                        Text("UDP").tag(true)
                    }
                    Toggle(L("Ручной ввод капчи"), isOn: s.client.manualCaptcha)
                    Toggle(L("Альтернативный TURN-узел"), isOn: s.client.magicSwitch)
                    if s.wrappedValue.client.magicSwitch {
                        secretField(L("Адрес TURN-узла"), s.client.magicTurn)
                    }
                }
            }

            Section(L("Туннель")) {
                if model.settings.privacyMode {
                    Label(L("Конфиг скрыт в приватном режиме."), systemImage: "eye.slash")
                        .foregroundStyle(.secondary)
                } else {
                    TextEditor(text: Binding(
                        get: { s.wrappedValue.client.wireGuardConfig },
                        set: { text in
                            s.wrappedValue.client.wireGuardConfig = text
                            s.wrappedValue.client.tunnelTransport =
                                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? TunnelTransport.none : TunnelTransport.wireguard
                        }))
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 150)
                        .privacySensitive()
                }
                HStack {
                    tunnelStatus(s.wrappedValue.client.wireGuardConfig)
                    Spacer()
                    Button(L("Загрузить из файла…")) { loadConfig(into: s) }
                }
            }

            Section(L("Маршруты")) {
                Picker(L("Профиль маршрутов"), selection: s.client.routingProfileId) {
                    Text(L("По умолчанию")).tag(String?.none)
                    ForEach(model.routing.profiles) { Text(model.displayName($0)).tag(String?.some($0.id)) }
                }
            }

            Section(L("Отладка")) {
                Toggle(L("Подробное логирование"), isOn: s.client.debugMode)
            }
        }
        .formStyle(.grouped)
        .disabled(locked)
    }

    /// Приватный режим: адреса, ключи и ссылка видны точками, но их можно ввести и заменить.
    @ViewBuilder private func secretField(_ title: String, _ text: Binding<String>, prompt: String? = nil) -> some View {
        if model.settings.privacyMode {
            SecureField(title, text: text, prompt: prompt.map { Text($0) })
        } else {
            TextField(title, text: text, prompt: prompt.map { Text($0) })
        }
    }

    private func footnote(_ text: String, color: Color = .secondary) -> some View {
        Text(text).font(.callout).foregroundStyle(color).frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func tunnelStatus(_ text: String) -> some View {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(L("Конфиг не задан")).font(.caption).foregroundStyle(.secondary)
        } else {
            switch Result(catching: { try WGConfig.parse(text) }) {
            case let .success(config):
                Label(config.isAmnezia ? "AmneziaWG" : "WireGuard", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.green)
            case let .failure(error):
                Label(wgErrorText(error), systemImage: "xmark.circle").font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func wgErrorText(_ error: Error) -> String {
        switch error as? WGConfigError {
        case .missingInterface: L("В конфиге нет секции [Interface]")
        case .missingPrivateKey: L("В конфиге нет PrivateKey")
        case .missingAddress: L("В конфиге нет Address")
        case .missingPeer: L("В конфиге нет секции [Peer]")
        case .missingPublicKey: L("У пира нет PublicKey")
        case nil: L("Не удалось разобрать конфиг WireGuard")
        }
    }

    private func loadConfig(into server: Binding<Server>) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "conf") ?? .plainText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        server.wrappedValue.client.wireGuardConfig = text
        server.wrappedValue.client.tunnelTransport = TunnelTransport.wireguard
    }
}
