import AppKit
import SwiftUI

/// A plain window around a SwiftUI view.
///
/// Hand-rolled rather than SwiftUI's `Settings` scene: an accessory app has no menu bar of
/// its own, and opening that scene depends on a private selector that has moved between
/// macOS releases. A window we own opens the same way every time.
@MainActor
final class PanelWindow<Content: View>: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let title: String
    private let closable: Bool
    private let defaultSize: CGSize?
    private let content: () -> Content

    /// Called when the user closes the window, so a wizard can be treated as dismissed.
    var onClose: (() -> Void)?

    /// `defaultSize` is required for any content containing a `ScrollView`: a scroll view
    /// has no intrinsic height, so `fittingSize` collapses and the window opens tiny.
    /// Omit it only when the content can size itself, such as a `Form`.
    init(
        title: String,
        closable: Bool = true,
        defaultSize: CGSize? = nil,
        content: @escaping () -> Content
    ) {
        self.title = title
        self.closable = closable
        self.defaultSize = defaultSize
        self.content = content
    }

    func show() {
        if window == nil {
            // No `.fullSizeContentView`: with an opaque title bar it puts the top of the
            // content underneath it, which hid the first heading of every wizard step.
            // Resizable on purpose — content height depends on things settled at runtime
            // (whether notifications are available, how long an error message is), so a
            // fixed window would eventually clip something.
            var mask: NSWindow.StyleMask = [.titled, .resizable]
            if closable { mask.insert(.closable) }
            let window = NSWindow(
                contentRect: .zero,
                styleMask: mask,
                backing: .buffered,
                defer: false
            )
            window.title = title
            window.titlebarAppearsTransparent = false
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: content())
            // Sized from the SwiftUI content's own intrinsic size, but never taller than
            // the screen can show — a window that opens with its buttons below the Dock
            // is unusable, and on a laptop display that is easy to hit.
            let intrinsic = defaultSize ?? window.contentView?.fittingSize ?? .zero
            let available = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame.size
            window.setContentSize(CGSize(
                width: min(intrinsic.width, available.width - 40),
                // Leave room for the title bar, which sits outside the content size.
                height: min(intrinsic.height, available.height - 60)
            ))
            window.center()
            self.window = window
        }
        // An accessory app is never active, so ordering the window front is not enough to
        // make it usable — it has to be able to take focus.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
