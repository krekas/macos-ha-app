import AppKit
import SwiftUI

/// Every animation in the app. Reduce Motion turns movement into a quick fade
/// (or nothing), so views never check it themselves.
enum Motion {
    private static var reduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Hover fills coming and going.
    static var hover: Animation { .easeOut(duration: 0.12) }
    /// Presses and small flips, like a light turning on.
    static var quick: Animation? { reduced ? nil : .snappy(duration: 0.18) }
    /// General UI changes: a row's state, a section opening.
    static var ui: Animation { reduced ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25) }
    /// Selection moving through a live list.
    static var select: Animation? { reduced ? nil : .snappy(duration: 0.15) }
    /// Panels and popovers appearing.
    static var appear: Animation { reduced ? .easeOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.85) }
    /// Panels and popovers going away. Faster than they came.
    static var dismiss: Animation { .easeIn(duration: 0.12) }
    /// Sensor numbers changing. Pair with `.contentTransition(.numericText())`;
    /// units never animate.
    static var numberRoll: Animation? { reduced ? nil : .snappy(duration: 0.3) }
    /// Rows added, removed, or reordered.
    static var listChange: Animation? { reduced ? nil : .snappy(duration: 0.25) }
    /// A slow loop, like a "connecting" pulse. nil under Reduce Motion: stop the loop.
    static var pulse: Animation? { reduced ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true) }
}
