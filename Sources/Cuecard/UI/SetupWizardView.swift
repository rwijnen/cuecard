import SwiftUI

/// First-run setup: three short steps, and the last one is genuinely optional.
///
/// The Spotify connection is deliberately the final step and skippable — it is the one
/// part that needs a developer account, and holding the whole app hostage to it would be
/// a poor trade for a single line of text.
struct SetupWizardView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var auth: SpotifyAuth
    @ObservedObject var notifications: NotificationAvailability
    let monitor: NowPlayingMonitor
    let onFinish: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, style, upNext
    }

    @State private var step: Step = .welcome

    var body: some View {
        VStack(spacing: 0) {
            // Scrollable, because a step can grow after it is laid out — the notification
            // warning appears only once macOS answers the authorisation request, and
            // without this it pushed the heading off the top and the buttons off the
            // bottom of a fixed-size window.
            ScrollView {
                content
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)

            Divider()
            // Outside the ScrollView, so Continue and Back are always reachable.
            controls
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        // Fills the window rather than dictating its size — the window's own default is
        // `SetupWizardView.windowSize` below. A fixed frame here would be clipped the
        // moment the window is resized, which is the bug this replaced.
        .frame(minWidth: 420, maxWidth: .infinity, minHeight: 340, maxHeight: .infinity)
    }

    /// Opening size for the wizard window. Sized for the tallest step — the style step,
    /// with the picker, the explanation, the notification warning and a preview button.
    static let windowSize = CGSize(width: 500, height: 560)

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: welcome
        case .style: style
        case .upNext: upNext
        }
    }

    // MARK: - Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tint)
            Text("Cuecard").font(.system(size: 22, weight: .semibold))
            Text("A card whenever a new song starts: cover, title, artist, a button to skip "
                 + "it, and what is coming next.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 7) {
                bullet("Lives in the menu bar — no Dock icon, no window.")
                bullet("Reads track changes from Spotify's own broadcast, so detection is "
                       + "instant and needs no permission.")
                bullet("Never writes to your library and never plays anything on its own.")
            }
            .padding(.top, 4)
        }
    }

    private var style: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Where should the card appear?").font(.system(size: 17, weight: .semibold))
            StylePicker(selection: $preferences.style)
            Text(preferences.style == .notch
                 ? "A card Cuecard draws under the notch. It ignores Do Not Disturb and "
                   + "leaves nothing in Notification Centre — macOS offers no API to put a "
                   + "real notification there."
                 : "A standard macOS notification, top right. Obeys Do Not Disturb and "
                   + "stays in Notification Centre. Set Cuecard to “Alerts” in System "
                   + "Settings if you want the Next button always visible.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            NotificationWarning(availability: notifications, preferences: preferences)

            Button("Preview it") { monitor.showCurrentTrackNow() }
                .padding(.top, 2)
            Text("Uses whatever Spotify is playing, or a sample if it is idle.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The “Up next” line").font(.system(size: 17, weight: .semibold))
            SpotifyConnectionSection(preferences: preferences, auth: auth)
            Spacer()
            Text("You can do this later in Settings — nothing else depends on it.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "circle.fill").font(.system(size: 4)).foregroundStyle(.tertiary)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack {
            ForEach(Step.allCases, id: \.rawValue) { dot in
                Circle()
                    .fill(dot == step ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: 6, height: 6)
            }

            Spacer()

            if step != .welcome {
                Button("Back") {
                    step = Step(rawValue: step.rawValue - 1) ?? .welcome
                }
            }

            switch step {
            case .welcome, .style:
                Button("Continue") {
                    step = Step(rawValue: step.rawValue + 1) ?? .upNext
                }
                .keyboardShortcut(.defaultAction)
            case .upNext:
                // Skipping is a first-class exit here, not a fine-print escape hatch.
                if !auth.isConnected {
                    Button("Skip for now") { onFinish() }
                }
                Button("Done") { onFinish() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
