import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var visited: Set<AppSection> = []

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
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
        .frame(minWidth: 920, minHeight: 560)
        .sheet(item: $model.importDraft) { ImportSheet(draft: $0) }
        .sheet(item: $model.sharing) { ShareSheet(server: $0) }
        .alert(L("Следите за обновлениями"), isPresented: $model.offerTelegram) {
            Button(L("Подписаться")) { NSWorkspace.shared.open(AppModel.telegramURL) }
            Button(L("Не сейчас"), role: .cancel) {}
        } message: {
            Text(L("Подпишитесь на Telegram-канал, чтобы первыми узнавать о новых версиях."))
        }
        .alert(String(format: L("Доступна версия %@"), model.offerUpdate?.version ?? ""),
               isPresented: Binding(get: { model.offerUpdate != nil }, set: { if !$0 { model.offerUpdate = nil } }),
               presenting: model.offerUpdate) { update in
            Button(L("Обновить")) { model.installUpdate(update) }
            Button(L("Позже"), role: .cancel) {}
        } message: { update in
            Text(update.notes.isEmpty ? L("Приложение перезапустится. VPN на время обновления отключится.") : update.notes)
        }
        .alert(L("Ошибка импорта"), isPresented: Binding(get: { model.importError != nil }, set: { if !$0 { model.importError = nil } })) {
            Button(L("Понятно"), role: .cancel) {}
        } message: {
            Text(model.importError ?? "")
        }
        .preferredColorScheme(model.colorScheme)
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

