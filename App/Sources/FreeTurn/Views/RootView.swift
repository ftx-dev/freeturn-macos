import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var visited: Set<AppSection> = []
    @State private var frozenSize = CGSize(width: 730, height: 620)
    /// Текущий размер области - без перерисовки на каждом кадре (не @State-значение, а коробка).
    @State private var liveSize = SizeBox()
    /// Окно при запуске уже закрывали (режим «только в строке меню») - второй раз не закрываем.
    @MainActor private static var launchHandled = false

    var body: some View {
        @Bindable var model = model
        Group {
            if model.settings.compactWindow {
                // Высота - вся доступная под тулбаром: размер окна задаёт WindowMode, а не жёсткая рамка
                // (рамка 600 pt не учитывала тулбар и обрезала вкладки снизу и содержимое сверху).
                CompactView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                split.frame(minWidth: 920, minHeight: 560)
            }
        }
        // Размер окна под режим задаём самому окну. Не windowResizability(.contentSize): с ним окно
        // подгонялось под содержимое, и достраиваемые в фоне разделы раздвигали его - вкладки дёргались.
        .background(NoOpenAnimation())
        .onChange(of: model.settings.compactWindow, initial: true) { _, compact in
            AppModel.compactWindowSetting = compact
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
                // Скрытые разделы получают замороженный размер (см. ниже): при сворачивании боковой панели
                // каждый кадр пересчитывается только видимый раздел - иначе анимация шла рывками.
                ZStack(alignment: .topLeading) {
                    ForEach(AppSection.allCases.filter(visited.contains)) { section in
                        let current = section == model.section
                        page(section)
                            // Скрытый раздел раскладывается в замороженном размере, а наружу отдаёт ноль:
                            // на размер области влияет только видимый, скрытые не пересчитываются на каждом кадре.
                            .frame(width: current ? nil : max(frozenSize.width, 1), height: current ? nil : max(frozenSize.height, 1),
                                   alignment: .topLeading)
                            .frame(width: current ? nil : 0, height: current ? nil : 0, alignment: .topLeading)
                            .frame(maxWidth: current ? .infinity : nil, maxHeight: current ? .infinity : nil)
                            .opacity(current ? 1 : 0)
                            .allowsHitTesting(current)
                            .accessibilityHidden(!current)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                // Кнопка сжатия - на соседнем после разделов элементе: SwiftUI ставит кнопки в порядке
                // разметки, так «+» серверов и маршрутов оказывается слева от неё, а она - справа с краю.
                Color.clear.frame(height: 0)
                    .toolbar {
                        ToolbarItem {
                            Button {
                                model.settings.compactWindow = true
                                model.persist()
                            } label: {
                                Label(L("Компактное окно"), systemImage: "arrow.down.right.and.arrow.up.left")
                            }
                            .help(L("Компактное окно"))
                        }
                    }
                // Размер для скрытых разделов обновляется только при переключении вкладки: в анимации
                // боковой панели скрытые не пересчитываются вовсе - ни на каждом кадре, ни разом в конце.
                .onGeometryChange(for: CGSize.self) { $0.size } action: { liveSize.size = $0 }
                .onChange(of: model.section) { frozenSize = liveSize.size }
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

/// Узкая раскладка (компактное окно 400×600): разделы с двумя колонками показывают список,
/// а детали - отдельным экраном с кнопкой «Назад».
private struct CompactLayoutKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var compactLayout: Bool {
        get { self[CompactLayoutKey.self] }
        set { self[CompactLayoutKey.self] = newValue }
    }
}

/// Экспериментальный компактный режим: окно 400×600, все разделы в одну колонку, вкладки внизу.
struct CompactView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.section {
                case .home: HomeView()
                case .servers: ServersView()
                case .routing: RoutingView()
                case .logs: LogsView()
                case .settings: SettingsView()
                case .about: AboutView()
                }
            }
            .environment(\.compactLayout, true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: 0) {
                ForEach(AppSection.allCases) { section in
                    let current = section == model.section
                    Button { model.section = section } label: {
                        VStack(spacing: 3) {
                            Image(systemName: section.icon).font(.system(size: 15, weight: current ? .semibold : .regular))
                            Text(section.title).font(.system(size: 9.5)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(current ? Color.accentColor : .secondary)
                    .accessibilityAddTraits(current ? .isSelected : [])
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 4)
            // Кнопка - на панели вкладок, а не на всём окне: SwiftUI ставит кнопки в порядке вложенности,
            // так «+» раздела (серверы, маршруты) оказывается слева от неё, а она - справа с краю.
            .toolbar {
                ToolbarItem {
                    Button {
                        model.settings.compactWindow = false
                        model.persist()
                    } label: {
                        Label(L("Развернуть"), systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .help(L("Обычное окно"))
                }
            }
        }
        .navigationTitle(model.section == .home ? "FreeTurnX" : model.section.title)
    }
}

/// Шапка экрана деталей в узкой раскладке: «‹ Назад» и заголовок.
struct CompactBackBar: View {
    let title: String
    let back: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: back) {
                Label(L("Назад"), systemImage: "chevron.left").labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            Spacer()
            Text(title).font(.headline).lineLimit(1)
            Spacer()
            Color.clear.frame(width: 60, height: 1) // уравновешивает кнопку, чтобы заголовок стоял по центру
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// Размеры главного окна в обычном и компактном режимах. Размеры - области содержимого под тулбаром.
enum WindowMode {
    static let compact = NSSize(width: 400, height: 600)
    static let regularMin = NSSize(width: 920, height: 560)
    static let regularDefault = NSSize(width: 1000, height: 680)

    @MainActor static func apply(compact isCompact: Bool) {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) else { return }
        // Тулбар лежит поверх содержимого окна: размер окна = нужная область + высота тулбара.
        let toolbar = max(0, (window.contentView?.frame.height ?? 0) - window.contentLayoutRect.height)
        func full(_ size: NSSize) -> NSSize { NSSize(width: size.width, height: size.height + toolbar) }
        if isCompact {
            window.contentMinSize = full(compact)
            window.contentMaxSize = full(compact)
            if window.contentLayoutRect.size != compact { resize(window, to: full(compact)) }
        } else {
            window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            window.contentMinSize = full(regularMin)
            let size = window.contentLayoutRect.size
            if size.width < regularMin.width || size.height < regularMin.height { resize(window, to: full(regularDefault)) }
        }
        window.standardWindowButton(.zoomButton)?.isEnabled = !isCompact
    }

    /// Меняет размер, оставляя на месте левый верхний угол окна - как при ручном растягивании.
    @MainActor private static func resize(_ window: NSWindow, to content: NSSize) {
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        // Без анимации: animate: true блокирует приложение на время анимации - «Развернуть» подвисало.
        window.setFrame(frame, display: true, animate: false)
    }
}

/// Окно появляется уже в итоговом виде. В момент показа SwiftUI ставит окну тулбар (область
/// содержимого меняется с 620 на 600 pt), и стеклянная подложка боковой панели доезжает на место
/// за несколько кадров - вкладки «дёргались». Окно прячется ровно в момент, когда становится
/// активным (до первой отрисовки), и показывается через несколько кадров, без анимации открытия.
struct NoOpenAnimation: NSViewRepresentable {
    @MainActor private static var handled = Set<ObjectIdentifier>()

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.animationBehavior = .none
        }
    }

    /// Спрятать окно до первой отрисовки. Страховка: через секунду оно показывается в любом случае.
    @MainActor static func hide(_ window: NSWindow) {
        guard handled.insert(ObjectIdentifier(window)).inserted else { return }
        window.animationBehavior = .none
        window.alphaValue = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { window.alphaValue = 1 }
    }

    /// Окно стало активным: подложка доезжает на место за несколько кадров - показать после них.
    @MainActor static func revealSoon(_ window: NSWindow) {
        guard window.alphaValue < 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { window.alphaValue = 1 }
    }

    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Изменяемая коробка для значения, которое не должно вызывать перерисовку.
final class SizeBox { var size = CGSize(width: 730, height: 620) }
