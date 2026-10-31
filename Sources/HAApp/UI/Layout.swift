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
    /// Every Settings tab.
    static let settingsWidth: CGFloat = 520
}
