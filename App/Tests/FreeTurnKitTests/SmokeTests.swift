import Testing
@testable import FreeTurnKit

@Test func coreVersionPinned() {
    #expect(AppInfo.coreVersion == "v4.1.5")
}
