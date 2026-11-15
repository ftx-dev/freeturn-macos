import WebKit
import FreeTurnKit

/// WebView для страницы капчи ядра: чистая сессия и никаких переходов наружу.
@MainActor
final class CaptchaWeb: NSObject, WKNavigationDelegate, WKUIDelegate {
    let view: WKWebView

    init(url: String) {
        let config = WKWebViewConfiguration()
        // Куки не переживают проверку: каждая капча начинается с чистого листа, как на Android.
        config.websiteDataStore = .nonPersistent()
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        view = WKWebView(frame: NSRect(x: 0, y: 0, width: 460, height: 600), configuration: config)
        super.init()
        view.navigationDelegate = self
        view.uiDelegate = self
        if CaptchaURL.isLocal(url), let target = URL(string: url) {
            view.load(URLRequest(url: target))
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Ядро переписывает страницы провайдера так, что всё идёт через его локальный порт.
        // Любой другой адрес - попытка увести WebView наружу.
        guard let url = navigationAction.request.url else { return .cancel }
        if url.scheme == "about" { return .allow }
        return CaptchaURL.isLocal(url.absoluteString) ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Всплывающие окна открываем в том же WebView, если адрес локальный.
        if let url = navigationAction.request.url, CaptchaURL.isLocal(url.absoluteString) {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func stop() {
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
    }
}
