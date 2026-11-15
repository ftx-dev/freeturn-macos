import AppKit
import SwiftUI
import WebKit

/// Отдельное окно ручной капчи: поверх остальных окон, открывается и закрывается само.
@MainActor
final class CaptchaWindowController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var web: CaptchaWeb?
    private var onUserClose: (() -> Void)?
    /// Окно закрываем мы сами (капча решена), а не пользователь.
    private var closingProgrammatically = false

    func show(url: String, onUserClose: @escaping () -> Void) {
        close()
        let web = CaptchaWeb(url: url)
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
                            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = L("Проверка на робота")
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: CaptchaWindowContent(webView: web.view))
        panel.center()
        self.panel = panel
        self.web = web
        self.onUserClose = onUserClose
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        guard let panel else { return }
        closingProgrammatically = true
        panel.close()
        closingProgrammatically = false
        release()
    }

    func windowWillClose(_ notification: Notification) {
        guard !closingProgrammatically else { return }
        let callback = onUserClose
        release()
        callback?()
    }

    private func release() {
        web?.stop()
        web = nil
        panel?.delegate = nil
        panel = nil
        onUserClose = nil
    }
}

private struct CaptchaWindowContent: View {
    let webView: WKWebView

    var body: some View {
        VStack(spacing: 0) {
            Text(L("Пройдите проверку для продолжения. Окно закроется само."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            Divider()
            WKWebViewBox(view: webView)
        }
        .frame(minWidth: 400, minHeight: 520)
    }
}
