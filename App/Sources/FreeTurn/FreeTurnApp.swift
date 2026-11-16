import SwiftUI
import FreeTurnKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Окно можно закрыть: приложение остаётся в строке меню и держит подключение.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct FreeTurnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("FreeTurnX", id: "main") {
            RootView()
                .environment(model)
                // Ссылка freeturn://, открытая кликом в браузере или мессенджере.
                .onOpenURL { model.offerImport($0.absoluteString) }
        }
        .defaultSize(width: 1000, height: 680)
        // Размер окна задаёт содержимое: обычный режим растягивается, компактный - ровно 400×600.
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            Image(nsImage: MenuBarIcon.image(for: model.connection.state))
        }
        .menuBarExtraStyle(.window)
    }
}
