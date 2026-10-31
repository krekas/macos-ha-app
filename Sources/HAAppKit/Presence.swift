/// Where HAApp shows itself: a window with a Dock icon, or only the menu bar icon.
public enum Presence: Equatable, Sendable {
    case window
    case menuBarOnly

    /// At launch. Opened at login with the menu bar icon on, HAApp starts quietly
    /// in the menu bar. Opened any other way (Finder, the Dock), it opens its window.
    public static func atLaunch(launchedAtLogin: Bool, showInMenuBar: Bool) -> Presence {
        launchedAtLogin && showInMenuBar ? .menuBarOnly : .window
    }

    /// While running. The Dock icon shows while a window is open, and always
    /// when there is no menu bar icon to come back to.
    public static func current(hasOpenWindow: Bool, showInMenuBar: Bool) -> Presence {
        hasOpenWindow || !showInMenuBar ? .window : .menuBarOnly
    }
}
