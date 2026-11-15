import Foundation
import Testing
@testable import FreeTurnKit

@Test func onlyCoreCaptchaPageIsLocal() {
    #expect(CaptchaURL.isLocal("http://127.0.0.1:8765/a"))
    #expect(CaptchaURL.isLocal("http://localhost:8765/"))
    #expect(CaptchaURL.isLocal("http://LOCALHOST:8765/not_robot_captcha?domain=vk.com&x=1"))
    for bad in ["https://localhost:8765/", "http://localhost:8766/", "http://localhost/", "http://evil.com:8765/",
                "http://user@localhost:8765/", "http://localhost.evil.com:8765/", "", "file:///etc/passwd",
                "localhost:8765", "http://127.0.0.1.evil.com:8765/", "javascript:alert(1)"] {
        #expect(!CaptchaURL.isLocal(bad), "\(bad)")
    }
}

private let page = "http://localhost:8765/not_robot_captcha?a=1"
private let page2 = "http://localhost:8765/not_robot_captcha?a=2"
private func manual(_ url: String = page) -> CaptchaRequest { CaptchaRequest(url: url, manual: true) }

@Test func manualInWindowMode() {
    var p = CaptchaPresenter()
    #expect(p.action(for: manual(), target: "window") == .showWindow(page))
    #expect(p.needsAttention)
}

@Test func manualInBrowserMode() {
    var p = CaptchaPresenter()
    #expect(p.action(for: manual(), target: "browser") == .openBrowser(page))
}

// Ядро шлёт состояние не один раз: повтор не должен открывать второе окно или вкладку.
@Test func sameUrlIsNotShownTwice() {
    var p = CaptchaPresenter()
    _ = p.action(for: manual(), target: "window")
    #expect(p.action(for: manual(), target: "window") == .none)
}

@Test func newUrlReplacesOld() {
    var p = CaptchaPresenter()
    _ = p.action(for: manual(), target: "window")
    #expect(p.action(for: manual(page2), target: "window") == .showWindow(page2))
}

@Test func clearedCaptchaDismisses() {
    var p = CaptchaPresenter()
    #expect(p.action(for: nil, target: "window") == .none)
    _ = p.action(for: manual(), target: "window")
    #expect(p.action(for: nil, target: "window") == .dismiss)
    #expect(!p.needsAttention)
    #expect(p.action(for: nil, target: "window") == .none)
    _ = p.action(for: manual(), target: "window")
    #expect(p.action(for: CaptchaRequest(url: "", manual: false), target: "window") == .dismiss)
}

@Test func autoCaptchaLoadsHidden() {
    var p = CaptchaPresenter()
    #expect(p.action(for: CaptchaRequest(url: page, manual: false), target: "window") == .loadHidden(page))
    #expect(!p.needsAttention)
    var b = CaptchaPresenter()
    #expect(b.action(for: CaptchaRequest(url: page, manual: false), target: "browser") == .loadHidden(page))
}

// Внешний адрес не открываем ни в окне, ни в браузере: ядро показывает только свою локальную страницу.
@Test func nonLocalUrlNeverShown() {
    var p = CaptchaPresenter()
    for target in ["window", "browser"] {
        #expect(p.action(for: manual("http://evil.com:8765/x"), target: target) == .none)
        #expect(p.action(for: CaptchaRequest(url: "https://vk.com/captcha", manual: false), target: target) == .none)
    }
    #expect(!p.needsAttention)
    #expect(p.reopenAction(target: "window") == .none)
}

@Test func reopenAfterUserClose() {
    var p = CaptchaPresenter()
    #expect(p.reopenAction(target: "window") == .none)
    _ = p.action(for: manual(), target: "window")
    // Пользователь закрыл окно: состояние презентера не меняется.
    #expect(p.needsAttention)
    #expect(p.action(for: manual(), target: "window") == .none)
    #expect(p.reopenAction(target: "window") == .showWindow(page))
    #expect(p.reopenAction(target: "browser") == .openBrowser(page))
    _ = p.action(for: nil, target: "window")
    #expect(p.reopenAction(target: "window") == .none)
}

@Test func autoAfterManualSwitchesToHidden() {
    var p = CaptchaPresenter()
    _ = p.action(for: manual(), target: "window")
    #expect(p.action(for: CaptchaRequest(url: page2, manual: false), target: "window") == .loadHidden(page2))
    #expect(!p.needsAttention)
}
