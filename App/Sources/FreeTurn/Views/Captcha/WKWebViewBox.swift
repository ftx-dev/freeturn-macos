import SwiftUI
import WebKit

/// Готовый WKWebView внутри SwiftUI.
struct WKWebViewBox: NSViewRepresentable {
    let view: WKWebView

    func makeNSView(context: Context) -> WKWebView { view }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
