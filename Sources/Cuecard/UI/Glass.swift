import SwiftUI

/// Liquid Glass where the system has it (macOS 26 and later), the earlier look elsewhere.
///
/// Every use is guarded twice. `#available` covers the macOS the app runs on, which can be
/// as old as 14. `compiler(>=6.2)` covers the SDK it is built with: the glass API does not
/// exist before the macOS 26 SDK, and both CI and anyone building with older Command Line
/// Tools would otherwise fail to compile rather than fall back.
extension View {
    /// A glass surface in `shape`, or `fallback` drawn behind the view before macOS 26.
    ///
    /// `tint` is a hint, not a fill: glass shifts the colour of what shows through it,
    /// so a tint reads as a wash over the desktop rather than as a painted background.
    @ViewBuilder
    func glassSurface<S: Shape, Fallback: View>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        @ViewBuilder fallback: () -> Fallback
    ) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background { fallback() }
        }
        #else
        background { fallback() }
        #endif
    }

    /// The glass button styles, falling back to the standard bordered ones.
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
        #else
        if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        #endif
    }
}
