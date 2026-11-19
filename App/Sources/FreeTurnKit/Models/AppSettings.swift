public struct AppSettings: Codable, Equatable, Sendable {
    public var theme = "system"
    public var language = "system"
    public var privacyMode = false
    public var advancedCaptcha = true
    public var autoConnect = false
    public var launchAtLogin = false
    public var debugScreen = false
    public var tunStack = "mixed"
    /// Где показывать ручную капчу: "window" - отдельное окно приложения, "browser" - браузер по умолчанию.
    public var captchaTarget = "window"
    /// Проверять новые версии в GitHub Releases при запуске.
    public var checkUpdates = true
    /// Иконка приложения: standard (Classic) - синяя, black - чёрная OLED, x - чёрная с буквой X (по умолчанию).
    public var appIcon = "x"
    /// Экспериментальное компактное окно 400×600: одна колонка с главным экраном.
    public var compactWindow = false
    public var increasedStreamLimits = false
    /// Только в строке меню: без значка в Dock, управление - из панели в строке меню (как у WireGuard).
    public var menuBarOnly = false
    /// Разовое предложение подписаться на Telegram-канал уже показано.
    public var telegramPromptShown = false
    /// Прошлую сессию пользователь не выключал сам - основание для автоподключения.
    public var wasConnected = false

    public init() {}

    public var maxStreams: Int { increasedStreamLimits ? 96 : 24 }
    public var maxStreamsPerCred: Int { increasedStreamLimits ? 48 : 24 }

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
        checkUpdates = c.value(.checkUpdates, d.checkUpdates)
        let icon = c.value(.appIcon, d.appIcon)
        appIcon = ["standard", "black", "x"].contains(icon) ? icon : d.appIcon
        compactWindow = c.value(.compactWindow, d.compactWindow)
        increasedStreamLimits = c.value(.increasedStreamLimits, d.increasedStreamLimits)
        menuBarOnly = c.value(.menuBarOnly, d.menuBarOnly)
        telegramPromptShown = c.value(.telegramPromptShown, d.telegramPromptShown)
        wasConnected = c.value(.wasConnected, d.wasConnected)
    }
}
