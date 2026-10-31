import SwiftUI

/// Fixed widths and heights. Everything else sizes to its content.
enum Layout {
    /// The menu bar window.
    static let menuWidth: CGFloat = 320
    /// The menu scrolls past this height.
    static let menuMaxHeight: CGFloat = 560
    /// The empty menu's height, so its message has room.
    static let menuEmptyHeight: CGFloat = 200
    /// The column for an item's symbol, so names line up.
    static let symbolColumn: CGFloat = 20
    /// The main window's smallest size.
    static let mainMinWidth: CGFloat = 360
    static let mainMinHeight: CGFloat = 320
    /// The main window's first size.
    static let mainDefaultWidth: CGFloat = 420
    static let mainDefaultHeight: CGFloat = 520
    /// The Settings page beside the sidebar.
    static let settingsWidth: CGFloat = 520
    /// Text fields in Settings rows, so long values (an access token) don't stretch the row.
    static let settingsFieldWidth: CGFloat = 280
    /// The Settings sidebar.
    static let settingsSidebarWidth: CGFloat = 200
    /// The Settings window's height; a longer page scrolls.
    static let settingsHeight: CGFloat = 560
}
