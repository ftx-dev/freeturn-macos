import AppKit

/// Автоматическая («продвинутая») капча: страницу проверки грузит настоящий браузерный движок
/// в невидимом окне, как фоновый WebView на Android. Живёт только на время проверки.
@MainActor
final class AutoCaptchaHost {
    private var web: CaptchaWeb?
    private var window: NSWindow?

    func show(url: String) {
        clear()
        let web = CaptchaWeb(url: url)
        // WebView без окна WebKit считает скрытым и притормаживает скрипты, поэтому окно есть,
        // но за пределами экрана и без права стать активным.
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 460, height: 640),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.contentView = web.view
        window.orderBack(nil)
        self.web = web
        self.window = window
    }

    func clear() {
        web?.stop()
        web = nil
        window?.close()
        window = nil
    }
}
