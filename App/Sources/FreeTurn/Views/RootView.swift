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
        .frame(minWidth: 760, minHeight: 520)
        .preferredColorScheme(model.colorScheme)
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .home: HomeView()
        default: ContentUnavailableView(L("Скоро"), systemImage: model.section.icon)
        }
    }
}
