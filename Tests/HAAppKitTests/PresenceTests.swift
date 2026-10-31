import Testing
@testable import HAAppKit

@Test("At login with the menu bar icon, only the menu bar", arguments: [
    (true, true, Presence.menuBarOnly),
    (true, false, .window),
    (false, true, .window),
    (false, false, .window),
])
func atLaunch(login: Bool, menuBar: Bool, expected: Presence) {
    #expect(Presence.atLaunch(launchedAtLogin: login, showInMenuBar: menuBar) == expected)
}

@Test("The Dock icon goes away only with no window and a menu bar icon", arguments: [
    (true, true, Presence.window),
    (true, false, .window),
    (false, true, .menuBarOnly),
    (false, false, .window),
])
func current(window: Bool, menuBar: Bool, expected: Presence) {
    #expect(Presence.current(hasOpenWindow: window, showInMenuBar: menuBar) == expected)
}
