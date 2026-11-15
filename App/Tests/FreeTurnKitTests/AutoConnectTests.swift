import Foundation
import Testing
@testable import FreeTurnKit

// Автоподключение восстанавливает только сессию, которую пользователь не выключал сам.
@Test(arguments: [
    (true, true, true, true),
    (false, true, true, false),
    (true, false, true, false),
    (true, true, false, false),
])
func autoConnectNeedsAllThree(auto: Bool, wasConnected: Bool, hasServer: Bool, expected: Bool) {
    var settings = AppSettings()
    settings.autoConnect = auto
    settings.wasConnected = wasConnected
    #expect(AutoConnect.shouldConnect(settings: settings, hasActiveServer: hasServer) == expected)
}
