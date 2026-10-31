import SwiftUI

/// Custom fills and lines. They adapt to light, dark, and Increase Contrast.
/// Use system materials and `.background` first; these are for what they lack.
enum Surfaces {
    /// A thin outline around a swatch or a small drawn shape.
    static let hairline = Color.primary.opacity(0.15)
    /// A light accent wash behind accent text, like a tag.
    static var accentWash: Color { Palette.accent.opacity(0.15) }
    /// Shadow under a drawn knob or chip.
    static let knobShadow = Color.black.opacity(0.2)
    /// Unavailable or stale states (S-008), and errors.
    static let warning = Color.orange
}
