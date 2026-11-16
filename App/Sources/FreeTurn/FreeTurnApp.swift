import SwiftUI
import FreeTurnKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Главное окно прячется в тот же момент, когда становится активным (до первой отрисовки),
        // и показывается, когда подложка боковой панели перестроится под тулбар - см. NoOpenAnimation.
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: nil) { note in
            guard let window = note.object as? NSWindow, window.identifier?.rawValue == "main" else { return }
            MainActor.assumeIsolated { NoOpenAnimation.revealSoon(window) }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Окно SwiftUI уже создано, но ещё не нарисовано - прячем, пока не станет активным.
        for window in NSApp.windows where window.identifier?.rawValue == "main" {
            MainActor.assumeIsolated { NoOpenAnimation.hide(window) }
        }
    }

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

        MenuBarExtra {
            MenuBarView()
                .environment(model)
        } label: {
            Image(nsImage: MenuBarIcon.image(for: model.connection.state))
        }
        .menuBarExtraStyle(.window)
    }
}
