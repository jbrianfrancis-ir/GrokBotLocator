import Testing
@testable import GrokBotLocator

@Test func appModuleIsLinked() {
    let root = RootView()
    #expect(type(of: root) == RootView.self)
}
