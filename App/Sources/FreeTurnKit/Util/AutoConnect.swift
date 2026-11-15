public enum AutoConnect {
    /// Подключаться при запуске только если прошлую сессию оборвал не пользователь
    /// (выход из приложения, перезагрузка), а не он сам её выключил.
    public static func shouldConnect(settings: AppSettings, hasActiveServer: Bool) -> Bool {
        settings.autoConnect && settings.wasConnected && hasActiveServer
    }
}
