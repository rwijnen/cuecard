import AppKit
import SwiftUI

/// Draws the card under the notch.
///
/// This is deliberately **not** a notification. macOS exposes no way to put content in
/// the notch, so the only honest implementation is a borderless window of our own, pinned
/// to the top of the display and centred on the notch. Consequences worth knowing: it
/// does not obey Do Not Disturb, it leaves nothing behind in Notification Centre, and it
/// needs no notification permission.
@MainActor
final class NotchPresenter: Presenter {
    var onSkip: (() -> Void)?

    private let preferences: Preferences
    private let model = NotchCardModel()
    private var panel: NSPanel?
    private var retractTask: Task<Void, Never>?
    private var isHovered = false

    /// Matches the spring in `NotchCardView`, so the window is not ordered out from
    /// under the animation.
    private let animationDuration: TimeInterval = 0.45

    init(preferences: Preferences) {
        self.preferences = preferences
        model.onSkip = { [weak self] in
            self?.onSkip?()
            // The next track will bring its own card; retract this one immediately so
            // the two do not cross over.
            self?.retract(after: 0.1)
        }
        model.onHover = { [weak self] hovering in
            self?.isHovered = hovering
            // Reading the whole card, including a long up-next line, can take longer
            // than the timeout. Hold it open while the pointer is on it.
            if hovering { self?.retractTask?.cancel() } else { self?.scheduleRetract() }
        }
        model.onActivateSpotify = {
            NSRunningApplication
                .runningApplications(withBundleIdentifier: SpotifyEvents.bundleIdentifier)
                .first?
                .activate()
        }
    }

    /// Nothing to ask for — this style needs no authorisation.
    func prepare() {}

    func present(_ cue: Cue) {
        let screen = Self.preferredScreen()
        let panel = ensurePanel()

        model.metrics = Self.metrics(
            for: screen,
            cardWidth: model.metrics.cardWidth,
            hasUpNext: cue.next != nil
        )
        model.cue = cue

        let frame = NotchGeometry.cardFrame(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea,
            cardSize: CGSize(width: model.metrics.cardWidth, height: model.metrics.totalHeight)
        )
        panel.setFrame(frame, display: false)
        (panel.contentView as? PassthroughContainer)?.transparentTopHeight =
            model.metrics.transparentTopHeight
        panel.orderFrontRegardless()

        // One tick later, so the window is on screen before the card slides out of it.
        if !model.revealed {
            DispatchQueue.main.async { [weak self] in self?.model.revealed = true }
        }
        scheduleRetract()
    }

    func dismiss() { retract(after: 0) }

    // MARK: - Window

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(
            contentRect: .zero,
            // `.nonactivatingPanel` is what lets the Next button be clicked without
            // pulling focus away from whatever the user is actually doing.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // SwiftUI draws the card's shadow; a window shadow would trace the full
        // rectangle, including the transparent notch strip.
        panel.hasShadow = false
        panel.isMovable = false
        panel.animationBehavior = .none
        // Above the menu bar, present on every Space, and never in the window cycle.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        let container = PassthroughContainer()
        let host = NSHostingView(rootView: NotchCardView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        panel.contentView = container

        self.panel = panel
        return panel
    }

    private func scheduleRetract() {
        retractTask?.cancel()
        retract(after: max(1.5, preferences.notchDuration))
    }

    private func retract(after delay: TimeInterval) {
        retractTask?.cancel()
        retractTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
            }
            guard let self, !self.isHovered else { return }
            self.model.revealed = false
            try? await Task.sleep(for: .seconds(self.animationDuration))
            guard !Task.isCancelled, !self.isHovered else { return }
            self.panel?.orderOut(nil)
        }
    }

    // MARK: - Screen

    /// The notch is on the built-in display, so that is where the card belongs. Falls
    /// back to the active display, where the card renders as a plain floating banner.
    static func preferredScreen() -> NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    static func metrics(for screen: NSScreen, cardWidth: CGFloat, hasUpNext: Bool) -> NotchCardMetrics {
        var metrics = NotchCardMetrics()
        metrics.cardWidth = min(cardWidth, screen.frame.width - 32)
        metrics.bodyHeight = hasUpNext
            ? NotchCardMetrics.bodyHeightWithUpNext
            : NotchCardMetrics.bodyHeightWithoutUpNext
        metrics.notchStripHeight = screen.safeAreaInsets.top
        metrics.notchWidth = NotchGeometry.notchWidth(
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea,
            auxiliaryTopRight: screen.auxiliaryTopRightArea
        )
        return metrics
    }
}

/// Lets clicks in the transparent strip above the card through to the menu bar.
///
/// The card's window has to reach the notch to sit flush against it, which means its top
/// overlaps the menu bar on either side. AppKit hit-tests the whole window rectangle
/// regardless of what is drawn there, so without this the card would silently eat clicks on
/// nearby menus and status items.
private final class PassthroughContainer: NSView {
    var transparentTopHeight: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if transparentTopHeight > 0, local.y > bounds.maxY - transparentTopHeight { return nil }
        return super.hitTest(point)
    }
}
