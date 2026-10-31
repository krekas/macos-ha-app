import SwiftUI

/// Corner radii. Inner corners are concentric: inner = outer - inset.
enum Radius {
    /// Chips, key caps, small badges.
    static let xs: CGFloat = 6
    /// Controls and small fills inside a card.
    static let sm: CGFloat = 8
    /// Row hover and selection fills.
    static let row: CGFloat = 10
    /// Cards and previews.
    static let md: CGFloat = 12
    /// Widgets.
    static let lg: CGFloat = 18
    /// Floating glass.
    static let xl: CGFloat = 26

    /// A continuous rounded rectangle, the shape every custom fill uses.
    static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}
