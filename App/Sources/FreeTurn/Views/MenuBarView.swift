import SwiftUI
import FreeTurnKit

/// Панель в строке меню: управление без основного окна, как у WireGuard, - статус, подключение,
/// выбор сервера и режима, скорость.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    private var state: ConnectionState { model.connection.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if case .connected = state { stats }
            if model.captchaNeedsAttention {
                Button { model.reopenCaptcha() } label: {
                    Label(L("Пройти проверку"), systemImage: "checkmark.shield").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.orange).controlSize(.large)
                .padding(.horizontal, 12).padding(.bottom, 10)
            }
            if case let .failed(failure) = state {
                Text(model.text(for: failure))
                    .font(.caption).foregroundStyle(.red).lineLimit(3)
                    .padding(.horizontal, 14).padding(.bottom, 10)
            }
            Divider()
            servers
            if model.activeServer != nil {
                Divider()
                modeSection
            }
            Divider()
            VStack(spacing: 0) {
                MenuRow(L("Открыть FreeTurnX"), systemImage: "macwindow") { openMain() }
                MenuRow(model.settings.compactWindow ? L("Обычное окно") : L("Компактное окно"),
                        systemImage: model.settings.compactWindow ? "rectangle.split.2x1" : "rectangle.portrait") {
                    model.settings.compactWindow.toggle()
                    model.persist()
                    openMain()
                }
                MenuRow(L("Выйти"), systemImage: "power") {
                    Task {
                        await model.connection.disconnect()
                        NSApp.terminate(nil)
                    }
                }
            }
            .padding(.vertical, 5)
        }
        .frame(width: 300)
    }

    // MARK: шапка

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIcons.image(model.settings.appIcon))
                .resizable().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("FreeTurnX").font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 7, height: 7)
                    Text(statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { state.isActive || Socks5Client.shared.isActive }, set: { _ in model.toggleConnection() }))
                .toggleStyle(.switch).labelsHidden()
                .disabled((model.activeServer == nil && !Socks5Client.shared.isActive) || state == .stopping)
                .accessibilityLabel(state.isActive ? L("Отключить") : L("Подключить"))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private var stats: some View {
        let s = model.connection.stats
        let style = L10n.unitStyle
        return HStack(spacing: 14) {
            Label(Formatters.rate(s.rxRate, style: style), systemImage: "arrow.down")
            Label(Formatters.rate(s.txRate, style: style), systemImage: "arrow.up")
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(Formatters.duration(context.date.timeIntervalSince(model.connection.connectedSince ?? context.date)))
            }
        }
        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 14).padding(.bottom, 10)
    }

    // MARK: серверы

    private var servers: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Серверы")).font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 2)
            if model.servers.list.isEmpty {
                MenuRow(L("Добавить сервер…"), systemImage: "plus") {
                    model.section = .servers
                    openMain()
                }
            }
            ForEach(model.servers.list) { server in
                let active = server.id == model.servers.activeId
                MenuRow(server.name, systemImage: active ? "checkmark" : nil, detail: providerTitle(server.client.provider)) {
                    model.switchServer(to: server.id)
                }
            }
        }
        .padding(.bottom, 6)
    }

    /// Режим подключения выбранного сервера: две равные половины на всю ширину панели.
    @ViewBuilder private var modeSection: some View {
        if let server = model.activeServer {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L("Режим")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if state.isActive {
                        Text(L("меняется после отключения")).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                HStack(spacing: 2) {
                    ForEach([Provider.relay, Provider.direct], id: \.self) { provider in
                        let selected = server.client.provider == provider
                        Button { setProvider(provider, of: server) } label: {
                            Label(provider == Provider.direct ? L("Напрямую") : L("Через релей"),
                                  systemImage: provider == Provider.direct ? "arrow.right" : "point.3.connected.trianglepath.dotted")
                                .font(.callout.weight(selected ? .semibold : .regular))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .foregroundStyle(selected ? Color.white : .primary)
                                .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                .disabled(state.isActive)
                .opacity(state.isActive ? 0.55 : 1)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    private func providerTitle(_ provider: String) -> String {
        provider == Provider.direct ? L("напрямую") : L("через релей")
    }

    private func setProvider(_ provider: String, of server: Server) {
        var edited = server
        edited.client.provider = provider
        model.servers.update(edited)
        model.persist()
    }

    private func openMain() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private var statusText: String {
        switch Socks5Client.shared.state {
        case .starting: return L("Подключение…")
        case let .on(address): return "\(L("Подключено")) · SOCKS5 \(address)"
        default: break
        }
        return switch state {
        case .off: L("Отключено")
        case .starting: L("Запуск…")
        case .connecting: L("Подключение…")
        case .captcha: L("Проверка CAPTCHA")
        case .connected: "\(L("Подключено")) · \(model.activeServer?.name ?? "")"
        case .stopping: L("Отключение…")
        case .failed: L("Ошибка")
        }
    }

    private var statusColor: Color {
        if Socks5Client.shared.isActive { return Socks5Client.shared.state == .starting ? .yellow : .green }
        return switch state {
        case .connected: .green
        case .starting, .connecting, .stopping: .yellow
        case .captcha: .orange
        case .failed: .red
        case .off: .secondary
        }
    }
}

/// Строка панели в стиле системного меню: подсветка при наведении на всю ширину.
private struct MenuRow: View {
    let title: String
    var systemImage: String?
    var detail: String?
    let action: () -> Void
    @State private var hover = false

    init(_ title: String, systemImage: String? = nil, detail: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.detail = detail
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage ?? "circle").opacity(systemImage == nil ? 0 : 1).frame(width: 16)
                Text(title).lineLimit(1)
                Spacer()
                if let detail { Text(detail).font(.caption).foregroundStyle(hover ? .white.opacity(0.85) : .secondary) }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .foregroundStyle(hover ? .white : .primary)
            .background(hover ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .padding(.horizontal, 6)
    }
}

/// Значок в строке меню: знак FreeTurnX (монохромный шаблон - сам подстраивается под тему) и метка состояния.
enum MenuBarIcon {
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor static func image(for state: ConnectionState) -> NSImage {
        let badge: String
        switch state {
        case .connected: badge = "on"
        case .starting, .connecting, .stopping: badge = "busy"
        case .captcha, .failed: badge = "alert"
        case .off: badge = "off"
        }
        if let cached = cache[badge] { return cached }
        let size = NSSize(width: 22, height: 18)
        let mark = L10n.resources.url(forResource: "menubar-mark", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
        let image = NSImage(size: size, flipped: false) { _ in
            // В SVG знак занимает середину холста - рисуем крупнее, чтобы он был ростом с соседние значки.
            mark?.draw(in: NSRect(x: -5, y: -5, width: 28, height: 28), from: .zero, operation: .sourceOver,
                       fraction: badge == "off" ? 0.55 : 1)
            let dot = NSRect(x: 16.5, y: 1, width: 5, height: 5)
            switch badge {
            case "on":
                NSColor.black.setFill()
                NSBezierPath(ovalIn: dot).fill()
            case "busy":
                let ring = NSBezierPath(ovalIn: dot.insetBy(dx: 0.6, dy: 0.6))
                ring.lineWidth = 1.2
                NSColor.black.setStroke()
                ring.stroke()
            case "alert":
                NSColor.black.setFill()
                NSBezierPath(roundedRect: NSRect(x: 18.2, y: 3.2, width: 1.7, height: 5), xRadius: 0.85, yRadius: 0.85).fill()
                NSBezierPath(ovalIn: NSRect(x: 18.2, y: 0.5, width: 1.7, height: 1.7)).fill()
            default: break
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "FreeTurnX"
        cache[badge] = image
        return image
    }
}
