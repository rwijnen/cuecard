import SwiftUI

/// Real macOS vibrancy — the desktop behind the window, blurred — rather than a flat fill.
///
/// Two settings here are load-bearing and easy to get wrong:
///
/// - `state = .active`. The default, `.followsWindowActiveState`, greys the material out
///   whenever the window is not key — and the notch card lives in a non-activating panel
///   that is *never* key, so it would render permanently flat and washed out.
/// - `blendingMode = .behindWindow`, which samples what is behind the window rather than
///   behind the view. That only works because the panel is `isOpaque = false` with a clear
///   background colour.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    /// The card sits against the notch, where a light material would look wrong whatever
    /// the system appearance is.
    var forcesDarkAppearance = true

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        apply(to: view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        apply(to: view)
    }

    private func apply(to view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        if forcesDarkAppearance {
            view.appearance = NSAppearance(named: .vibrantDark)
        }
    }
}
