public struct AppSettings: Codable, Equatable, Sendable {
    public var theme = "system"
    public var language = "system"
    public var privacyMode = false
    public var advancedCaptcha = false
    public var autoConnect = false
    public var launchAtLogin = false
    public var debugScreen = false
    public var tunStack = "mixed"
    /// Где показывать ручную капчу: "window" - отдельное окно приложения, "browser" - браузер по умолчанию.
    public var captchaTarget = "window"
    /// Прошлую сессию пользователь не выключал сам - основание для автоподключения.
    public var wasConnected = false

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        theme = c.value(.theme, d.theme)
        language = c.value(.language, d.language)
        privacyMode = c.value(.privacyMode, d.privacyMode)
        advancedCaptcha = c.value(.advancedCaptcha, d.advancedCaptcha)
        autoConnect = c.value(.autoConnect, d.autoConnect)
        launchAtLogin = c.value(.launchAtLogin, d.launchAtLogin)
        debugScreen = c.value(.debugScreen, d.debugScreen)
        let stack = c.value(.tunStack, d.tunStack)
        tunStack = ["system", "gvisor", "mixed"].contains(stack) ? stack : d.tunStack
        captchaTarget = c.value(.captchaTarget, d.captchaTarget) == "browser" ? "browser" : "window"
        wasConnected = c.value(.wasConnected, d.wasConnected)
    }
}
