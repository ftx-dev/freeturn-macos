import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(AppSection.allCases, selection: $model.section) { section in
                Label(section.title, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            VStack(spacing: 0) {
                if let error = model.loadError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.yellow.opacity(0.25))
                }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(model.section.title)
        }
        .frame(minWidth: 920, minHeight: 560)
        .sheet(item: $model.importDraft) { ImportSheet(draft: $0) }
        .alert(L("Ошибка импорта"), isPresented: Binding(get: { model.importError != nil }, set: { if !$0 { model.importError = nil } })) {
            Button(L("Понятно"), role: .cancel) {}
        } message: {
            Text(model.importError ?? "")
        }
        .preferredColorScheme(model.colorScheme)
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .home: HomeView()
        case .servers: ServersView()
        case .routing: RoutingView()
        default: ContentUnavailableView(L("Скоро"), systemImage: model.section.icon)
        }
    }
}
