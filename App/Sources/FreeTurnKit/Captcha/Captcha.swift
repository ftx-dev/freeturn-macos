import Foundation

public enum CaptchaURL {
    /// Только локальная страница капчи ядра (порт 8765 на loopback) допускается к показу.
    public static func isLocal(_ url: String) -> Bool {
        guard let c = URLComponents(string: url), c.scheme?.lowercased() == "http",
              c.user == nil, c.password == nil, c.port == 8765,
              let host = c.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost"
    }
}

public enum CaptchaAction: Equatable, Sendable {
    /// Ручная капча в окне приложения.
    case showWindow(String)
    /// Ручная капча в браузере по умолчанию.
    case openBrowser(String)
    /// Автоматическая капча: страницу грузит невидимый браузер.
    case loadHidden(String)
    case dismiss
    case none
}

/// Решает, что делать с каждым событием капчи от ядра. Без интерфейса - чтобы это можно было проверить.
public struct CaptchaPresenter: Sendable {
    private var shownURL: String?
    private var manualURL: String?

    public init() {}

    /// Ручная капча ждёт пользователя (в том числе после того, как он закрыл окно).
    public var needsAttention: Bool { manualURL != nil }

    public mutating func action(for captcha: CaptchaRequest?, target: String) -> CaptchaAction {
        guard let captcha, !captcha.url.isEmpty else {
            guard shownURL != nil else { return .none }
            shownURL = nil
            manualURL = nil
            return .dismiss
        }
        guard CaptchaURL.isLocal(captcha.url), captcha.url != shownURL else { return .none }
        shownURL = captcha.url
        manualURL = captcha.manual ? captcha.url : nil
        guard captcha.manual else { return .loadHidden(captcha.url) }
        return present(captcha.url, target: target)
    }

    /// Окно закрыли руками: тот же адрес сам больше не всплывёт (он уже показан), но открыть его снова можно.
    public func reopenAction(target: String) -> CaptchaAction {
        manualURL.map { present($0, target: target) } ?? .none
    }

    private func present(_ url: String, target: String) -> CaptchaAction {
        target == "browser" ? .openBrowser(url) : .showWindow(url)
    }
}
