import CoreGraphics
import Foundation
import Testing

@testable import Cuecard

/// Numbers below are what a 14-inch MacBook Pro (M3 Pro) reports at its default scaled
/// resolution: a 1512×982 frame, a 32-point safe area, and menu bar strips of 656 points
/// each side of a 200-point notch. `realHardware` uses the exact values measured on one,
/// which are not symmetric.
@Suite("Notch geometry")
struct NotchGeometryTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let safeAreaTop: CGFloat = 32
    private let auxLeft = CGRect(x: 0, y: 950, width: 656, height: 32)
    private let auxRight = CGRect(x: 856, y: 950, width: 656, height: 32)
    private let cardSize = CGSize(width: 428, height: 136)

    /// Verbatim from a 14-inch M3 Pro whose primary display is a 3008×1692 external
    /// monitor: the built-in panel sits *below* it in the global coordinate space, so its
    /// frame origin is negative and its `maxY` is zero. Placement code that assumes a
    /// screen starts at the origin gets this wrong.
    @Test("real hardware: an external primary puts the built-in display at a negative origin")
    func realHardware() {
        let builtIn = CGRect(x: 806, y: -982, width: 1512, height: 982)
        let left = CGRect(x: 806, y: -32, width: 663, height: 32)
        let right = CGRect(x: 1654, y: -32, width: 664, height: 32)

        #expect(NotchGeometry.notchWidth(auxiliaryTopLeft: left, auxiliaryTopRight: right) == 185)
        #expect(NotchGeometry.notchCenterX(
            screenFrame: builtIn, auxiliaryTopLeft: left, auxiliaryTopRight: right
        ) == 1561.5)

        // 428 wide by 124 tall is the card at its shipped metrics: 92 body + 32 notch.
        let frame = NotchGeometry.cardFrame(
            screenFrame: builtIn,
            visibleFrame: builtIn,
            safeAreaTop: 32,
            auxiliaryTopLeft: left,
            auxiliaryTopRight: right,
            cardSize: CGSize(width: 428, height: 124)
        )
        // Matches what the window server reported for the live panel.
        #expect(frame == CGRect(x: 1348, y: -124, width: 428, height: 124))
        #expect(frame.maxY == builtIn.maxY)
    }

    @Test("a notch is detected from the safe area")
    func detection() {
        #expect(NotchGeometry.hasNotch(safeAreaTop: 32))
        #expect(!NotchGeometry.hasNotch(safeAreaTop: 0))
    }

    @Test("the notch centre comes from the gap between the menu bar strips")
    func centreFromAuxiliaryAreas() {
        let centre = NotchGeometry.notchCenterX(
            screenFrame: screen,
            auxiliaryTopLeft: auxLeft,
            auxiliaryTopRight: auxRight
        )
        #expect(centre == 756)
    }

    /// A display whose menu bar strips are not symmetric still has to be handled — the
    /// notch is where the gap is, not necessarily at the midpoint.
    @Test("an off-centre notch is found where the gap actually is")
    func asymmetricNotch() {
        let centre = NotchGeometry.notchCenterX(
            screenFrame: screen,
            auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 500, height: 32),
            auxiliaryTopRight: CGRect(x: 700, y: 950, width: 812, height: 32)
        )
        #expect(centre == 600)
    }

    @Test("without auxiliary areas the card falls back to the screen centre")
    func centreFallback() {
        #expect(NotchGeometry.notchCenterX(
            screenFrame: screen, auxiliaryTopLeft: nil, auxiliaryTopRight: nil
        ) == 756)
    }

    @Test("notch width is the gap between the strips")
    func width() {
        #expect(NotchGeometry.notchWidth(auxiliaryTopLeft: auxLeft, auxiliaryTopRight: auxRight) == 200)
        #expect(NotchGeometry.notchWidth(auxiliaryTopLeft: nil, auxiliaryTopRight: nil) == nil)
    }

    /// Overlapping or reversed rects would produce a negative width, which would draw a
    /// nonsense tab. Better to report no notch.
    @Test("nonsense auxiliary areas report no notch width")
    func degenerateAreas() {
        #expect(NotchGeometry.notchWidth(
            auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 900, height: 32),
            auxiliaryTopRight: CGRect(x: 800, y: 950, width: 700, height: 32)
        ) == nil)
    }

    @Test("the card is centred on the notch and flush with the top edge")
    func cardPlacement() {
        let frame = NotchGeometry.cardFrame(
            screenFrame: screen,
            visibleFrame: screen,
            safeAreaTop: safeAreaTop,
            auxiliaryTopLeft: auxLeft,
            auxiliaryTopRight: auxRight,
            cardSize: cardSize
        )
        #expect(frame.midX == 756)
        // Flush: no inset, so the card's top strip sits behind the notch.
        #expect(frame.maxY == screen.maxY)
        #expect(frame.size == cardSize)
    }

    /// Anchoring to the screen's top edge here drew the card straight over the menu bar of
    /// an external display, so without a notch the visible frame is what counts.
    @Test("without a notch the card is anchored below the menu bar, not at the bezel")
    func noNotchInset() {
        let frame = NotchGeometry.cardFrame(
            screenFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
            visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440 - 37),
            safeAreaTop: 0,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil,
            cardSize: cardSize
        )
        // Annotated: a compound integer literal here would be typed `Int` inside the
        // macro expansion and compared against a CGFloat, which does not do what it looks
        // like it does.
        let expectedMaxY: CGFloat = 1403
        #expect(frame.maxY == expectedMaxY)
        #expect(frame.midX == CGFloat(1280))
        // Nothing may sit in the menu bar's 37 points.
        #expect(frame.maxY <= 1440 - 37)
    }

    /// A second display sits at a non-zero origin in the global coordinate space; the card
    /// has to land on that display, not the main one.
    @Test("the card lands on a display with a non-zero origin")
    func secondaryDisplay() {
        let external = CGRect(x: -2560, y: 200, width: 2560, height: 1440)
        let frame = NotchGeometry.cardFrame(
            screenFrame: external,
            visibleFrame: CGRect(x: -2560, y: 200, width: 2560, height: 1440 - 37),
            safeAreaTop: 0,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil,
            cardSize: cardSize
        )
        #expect(external.contains(CGPoint(x: frame.midX, y: frame.midY)))
        // Below that display's own menu bar, in global coordinates.
        #expect(frame.maxY == CGFloat(1603))
    }

    @Test("a card near the edge is pulled back on screen")
    func clamping() {
        // A pathological notch position hard against the left edge.
        let frame = NotchGeometry.cardFrame(
            screenFrame: screen,
            visibleFrame: screen,
            safeAreaTop: safeAreaTop,
            auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 10, height: 32),
            auxiliaryTopRight: CGRect(x: 60, y: 950, width: 1452, height: 32),
            cardSize: cardSize
        )
        #expect(frame.minX >= screen.minX)
        #expect(frame.maxX <= screen.maxX)
    }

    /// Both edges cannot be honoured at once here, so centring is the least surprising
    /// outcome — snapping to one side would look broken.
    @Test("a card wider than the display is centred rather than snapped")
    func oversizedCard() {
        let narrow = CGRect(x: 0, y: 0, width: 300, height: 600)
        let frame = NotchGeometry.cardFrame(
            screenFrame: narrow,
            visibleFrame: narrow,
            safeAreaTop: 0,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil,
            cardSize: CGSize(width: 428, height: 136)
        )
        #expect(frame.midX == narrow.midX)
    }

    @Test("frames land on whole points")
    func integralOrigin() {
        let frame = NotchGeometry.cardFrame(
            screenFrame: CGRect(x: 0, y: 0, width: 1511, height: 981),
            visibleFrame: CGRect(x: 0, y: 0, width: 1511, height: 981),
            safeAreaTop: 32,
            auxiliaryTopLeft: CGRect(x: 0, y: 949, width: 655, height: 32),
            auxiliaryTopRight: CGRect(x: 856, y: 949, width: 655, height: 32),
            cardSize: cardSize
        )
        #expect(frame.origin.x == frame.origin.x.rounded())
        #expect(frame.origin.y == frame.origin.y.rounded())
    }
}
