import CoreGraphics
import Foundation

/// Works out where a notch card goes.
///
/// macOS offers no API to draw *in* the notch, so the card is a window of our own pinned
/// flush to the top edge and centred on the notch, which reads as the notch growing
/// downwards. The maths is separated from `NSScreen` so it can be tested with the real
/// numbers a 14-inch MacBook Pro reports.
enum NotchGeometry {
    /// A display has a notch when the system reserves space at the top of it. On
    /// everything else — external monitors, pre-2021 laptops — this is zero.
    static func hasNotch(safeAreaTop: CGFloat) -> Bool { safeAreaTop > 0 }

    /// Horizontal centre of the notch itself.
    ///
    /// The notch is the gap between the two usable menu bar strips, so it is derived
    /// from those rather than assumed to be at the screen's midpoint — which it is not
    /// on a display whose menu bar has been shifted, and cannot be assumed in general.
    static func notchCenterX(
        screenFrame: CGRect,
        auxiliaryTopLeft: CGRect?,
        auxiliaryTopRight: CGRect?
    ) -> CGFloat {
        guard let left = auxiliaryTopLeft, let right = auxiliaryTopRight,
              right.minX > left.maxX
        else { return screenFrame.midX }
        return (left.maxX + right.minX) / 2
    }

    /// Width of the notch, when we can measure it. Used to decide how much of the card's
    /// top strip has to stay empty.
    static func notchWidth(auxiliaryTopLeft: CGRect?, auxiliaryTopRight: CGRect?) -> CGFloat? {
        guard let left = auxiliaryTopLeft, let right = auxiliaryTopRight,
              right.minX > left.maxX
        else { return nil }
        return right.minX - left.maxX
    }

    /// Frame for the card window, in screen coordinates.
    ///
    /// With a notch the top edge sits on the screen's top edge: the strip behind the notch
    /// is part of the window but left blank, so the card appears to hang from it.
    ///
    /// Without one there is nothing to hang from and the menu bar is in the way, so the
    /// window is anchored to `visibleFrame` instead — anchoring to the screen's top edge
    /// drew the card straight over the menu bar of an external display.
    static func cardFrame(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeft: CGRect?,
        auxiliaryTopRight: CGRect?,
        cardSize: CGSize,
        horizontalMargin: CGFloat = 8
    ) -> CGRect {
        let centerX = notchCenterX(
            screenFrame: screenFrame,
            auxiliaryTopLeft: auxiliaryTopLeft,
            auxiliaryTopRight: auxiliaryTopRight
        )

        var originX = centerX - cardSize.width / 2
        // A card wider than the display cannot be inset from both edges; centre it and
        // let it overhang rather than snapping it to one side.
        let lowerBound = screenFrame.minX + horizontalMargin
        let upperBound = screenFrame.maxX - cardSize.width - horizontalMargin
        if upperBound >= lowerBound {
            originX = min(max(originX, lowerBound), upperBound)
        }

        // The card's own top gap is inside `cardSize`, so the window itself goes flush
        // against whichever edge applies.
        let topEdge = hasNotch(safeAreaTop: safeAreaTop) ? screenFrame.maxY : visibleFrame.maxY
        return CGRect(
            x: originX.rounded(),
            y: (topEdge - cardSize.height).rounded(),
            width: cardSize.width,
            height: cardSize.height
        )
    }
}
