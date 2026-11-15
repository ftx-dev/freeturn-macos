import SwiftUI
import FreeTurnKit

struct HomeView: View {
    @Environment(AppModel.self) private var model

    private var state: ConnectionState { model.connection.state }

    private var kind: ConnectButton.Kind {
        switch state {
        case .off: .off
        case .starting, .connecting, .stopping: .busy
        case .captcha: .attention
        case .connected: .on
        case .failed: .error
        }
    }

    private var title: String {
        switch state {
        case .off: L("Нажмите для подключения")
        case .starting: L("Запуск…")
        case .connecting: L("Подключение…")
        case .captcha: L("Проверка CAPTCHA")
        case .connected: L("Подключено")
        case .stopping: L("Отключение…")
        case .failed: L("Ошибка")
        }
    }

    var body: some View {
        if model.servers.list.isEmpty {
            ContentUnavailableView {
                Label(L("Нет серверов"), systemImage: "server.rack")
            } description: {
                Text(L("Добавьте сервер, чтобы подключиться"))
            } actions: {
                Button(L("Добавить сервер")) { model.section = .servers }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ScrollView {
                VStack(spacing: 18) {
                    ConnectButton(kind: kind) { model.toggleConnection() }
                        .disabled(state == .stopping)
                        .padding(.top, 20)
                    Text(title).font(.title2.weight(.semibold))
                    serverLine
                    failureView
                    if case .connected = state { StatsGrid() }
                    if let profile = model.activeProfile {
                        Label("\(L("Маршруты:")) \(model.displayName(profile))", systemImage: "arrow.triangle.branch")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(24)
            }
        }
    }

    @ViewBuilder private var serverLine: some View {
        if let server = model.activeServer {
            Menu {
                ForEach(model.servers.list) { item in
                    Button {
                        model.setActive(item.id)
                    } label: {
                        if item.id == server.id { Label(item.name, systemImage: "checkmark") } else { Text(item.name) }
                    }
                }
            } label: {
                // Одна строка текста: у меню без рамки составная подпись схлопывается до первого элемента.
                Text(serverSummary(server))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(state.isActive)
            .foregroundStyle(.secondary)
        }
    }

    private func serverSummary(_ server: Server) -> String {
        var parts = [server.name, server.client.provider == Provider.direct ? L("Напрямую") : L("Через реле")]
        if server.client.provider != Provider.direct, let streams = streamsText { parts.append(streams) }
        return parts.joined(separator: " · ")
    }

    private var streamsText: String? {
        switch state {
        case let .connected(streams, total), let .connecting(streams, total):
            total > 0 ? "\(streams)/\(total) \(L("потоков"))" : nil
        default: nil
        }
    }

    @ViewBuilder private var failureView: some View {
        if case let .failed(failure) = state {
            switch failure {
            case .daemonNotInstalled: DaemonInstallView(outdated: false)
            case .daemonVersionMismatch: DaemonInstallView(outdated: true)
            default:
                Text(model.text(for: failure))
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: 520)
            }
        }
    }
}

private struct StatsGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let stats = model.connection.stats
        let style = L10n.unitStyle
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatTile(title: L("Загрузка"), value: Formatters.rate(stats.rxRate, style: style), icon: "arrow.down")
                StatTile(title: L("Отдача"), value: Formatters.rate(stats.txRate, style: style), icon: "arrow.up")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    StatTile(title: L("Время сессии"),
                             value: Formatters.duration(context.date.timeIntervalSince(model.connection.connectedSince ?? context.date)),
                             icon: "clock")
                }
            }
            GridRow {
                StatTile(title: L("Принято"), value: Formatters.bytes(stats.rx, style: style), icon: "tray.and.arrow.down")
                StatTile(title: L("Отправлено"), value: Formatters.bytes(stats.tx, style: style), icon: "tray.and.arrow.up")
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
        .frame(maxWidth: 540)
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }
}
