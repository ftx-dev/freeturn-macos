import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var visited: Set<AppSection> = []
    /// Окно при запуске уже закрывали (режим «только в строке меню») - второй раз не закрываем.
    @MainActor private static var launchHandled = false

    var body: some View {
        @Bindable var model = model
        Group {
            if model.settings.compactWindow {
                CompactView().frame(width: 400, height: 600)
            } else {
                split.frame(minWidth: 920, minHeight: 560)
            }
        }
        // Размер окна под режим задаём самому окну. Не windowResizability(.contentSize): с ним окно
        // подгонялось под содержимое, и достраиваемые в фоне разделы раздвигали его - вкладки дёргались.
        .background(NoOpenAnimation())
        .onChange(of: model.settings.compactWindow, initial: true) { _, compact in
            DispatchQueue.main.async { WindowMode.apply(compact: compact) }
        }
        .onAppear {
            // Только в строке меню: при запуске окна нет, как у WireGuard. Открыть - из панели.
            if !Self.launchHandled {
                Self.launchHandled = true
                if model.settings.menuBarOnly { dismissWindow(id: "main") }
            }
        }
        .sheet(item: $model.importDraft) { ImportSheet(draft: $0) }
        .sheet(item: $model.sharing) { ShareSheet(server: $0) }
        .alert(L("Следите за обновлениями"), isPresented: $model.offerTelegram) {
            Button(L("Подписаться")) { NSWorkspace.shared.open(AppModel.telegramURL) }
            Button(L("Не сейчас"), role: .cancel) {}
        } message: {
            Text(L("Подпишитесь на Telegram-канал, чтобы первыми узнавать о новых версиях."))
        }
        .sheet(item: $model.offerUpdate) { UpdateSheet(update: $0) }
        .alert(L("Ошибка импорта"), isPresented: Binding(get: { model.importError != nil }, set: { if !$0 { model.importError = nil } })) {
            Button(L("Понятно"), role: .cancel) {}
        } message: {
            Text(model.importError ?? "")
        }
        .preferredColorScheme(model.colorScheme)
    }

    private var split: some View {
        @Bindable var model = model
        return NavigationSplitView {
            List(AppSection.allCases, selection: $model.section) { section in
                Label(section.title, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            // Зазор между заголовком окна и подсветкой выбранной вкладки. Не contentMargins: тот
            // применяется не с первого кадра, и вкладки заметно прыгали после запуска.
            .padding(.top, 8)
        } detail: {
            VStack(spacing: 0) {
                if let error = model.loadError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.yellow.opacity(0.25))
                }
                // Открытый однажды раздел остаётся жить: формы «Серверов» и «Маршрутов» собираются
                // 200-350 мс, и пересобирать их на каждом переключении - это и была задержка.
                ZStack {
                    ForEach(AppSection.allCases.filter(visited.contains)) { section in
                        let current = section == model.section
                        page(section)
                            .opacity(current ? 1 : 0)
                            .allowsHitTesting(current)
                            .accessibilityHidden(!current)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: model.section, initial: true) { _, section in
                    visited.insert(section)
                }
                // Остальные разделы собираются по одному сразу после показа окна - тогда и первый
                // переход в любой из них мгновенный.
                .task {
                    for section in AppSection.allCases {
                        try? await Task.sleep(for: .milliseconds(60))
                        visited.insert(section)
                    }
                }
            }
            .navigationTitle(model.section.title)
        }
    }

    @ViewBuilder private func page(_ section: AppSection) -> some View {
        switch section {
        case .home: HomeView()
        case .servers: ServersView()
        case .routing: RoutingView()
        case .logs: LogsView()
        case .settings: SettingsView()
        case .about: AboutView()
        }
    }
}

/// Экспериментальный компактный режим: окно 400×600 с главным экраном и быстрыми переходами.
/// Разделы целиком открываются в обычном окне - кнопки внизу разворачивают его на нужном разделе.
struct CompactView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HomeView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: 0) {
                ForEach([AppSection.servers, .routing, .logs, .settings]) { section in
                    Button { expand(to: section) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: section.icon).font(.system(size: 15))
                            Text(section.title).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
        .navigationTitle("FreeTurnX")
        .toolbar {
            ToolbarItem {
                Button { expand(to: .home) } label: {
                    Label(L("Развернуть"), systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help(L("Обычное окно"))
            }
        }
    }

    private func expand(to section: AppSection) {
        model.section = section
        model.settings.compactWindow = false
        model.persist()
    }
}

/// Размеры главного окна в обычном и компактном режимах.
enum WindowMode {
    static let compact = NSSize(width: 400, height: 600)
    static let regularMin = NSSize(width: 920, height: 560)
    static let regularDefault = NSSize(width: 1000, height: 680)

    @MainActor static func apply(compact isCompact: Bool) {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) else { return }
        if isCompact {
            window.contentMinSize = compact
            window.contentMaxSize = compact
            if window.contentLayoutRect.size != compact { resize(window, to: compact) }
        } else {
            window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            window.contentMinSize = regularMin
            let size = window.contentLayoutRect.size
            if size.width < regularMin.width || size.height < regularMin.height { resize(window, to: regularDefault) }
        }
        window.standardWindowButton(.zoomButton)?.isEnabled = !isCompact
    }

    /// Меняет размер, оставляя на месте левый верхний угол окна - как при ручном растягивании.
    @MainActor private static func resize(_ window: NSWindow, to content: NSSize) {
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: window.isVisible)
    }
}

/// Окно появляется уже в итоговом виде. Первые ~0,2 с после создания macOS раскладывает подложку
/// боковой панели шире (пока достраивает заголовок и тулбар), и вкладки «дёргались» на место.
/// Поэтому окно 0,3 с остаётся прозрачным и показывается без системной анимации открытия.
struct NoOpenAnimation: NSViewRepresentable {
    /// Окна, которые уже прятали: служебный вид SwiftUI может пересоздать.
    @MainActor private static var handled = Set<ObjectIdentifier>()

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, NoOpenAnimation.handled.insert(ObjectIdentifier(window)).inserted else { return }
            window.animationBehavior = .none
            window.alphaValue = 0
            // Окно держится сильной ссылкой: показ не зависит от жизни этого вида.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { window.alphaValue = 1 }
        }
    }

    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
