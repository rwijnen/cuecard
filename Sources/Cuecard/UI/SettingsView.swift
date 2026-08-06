import AppKit
import SwiftUI

struct SettingsView: View {
    /// Opening size for the Settings window. Laid out end to end the four sections come to
    /// about 980 points, which does not fit a laptop display — `Form` scrolls, so the
    /// window opens at a sensible height instead of its full extent.
    static let windowSize = CGSize(width: 460, height: 620)

    @ObservedObject var preferences: Preferences
    @ObservedObject var auth: SpotifyAuth
    @ObservedObject var notifications: NotificationAvailability
    let monitor: NowPlayingMonitor

    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("Where the card appears") {
                StylePicker(selection: $preferences.style)
                    .padding(.vertical, 2)

                NotificationWarning(availability: notifications, preferences: preferences)

                if preferences.style == .notch {
                    Text("The notch card is a window Cuecard draws, not a system "
                         + "notification: it ignores Do Not Disturb and leaves nothing in "
                         + "Notification Centre. macOS provides no other way to put "
                         + "anything in the notch.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Text("Stays on screen for")
                        Slider(value: $preferences.notchDuration, in: 2...15, step: 1)
                        Text("\(Int(preferences.notchDuration))s")
                            .monospacedDigit()
                            .frame(width: 28, alignment: .trailing)
                    }
                    Text("Hovering the card holds it open.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text("Buttons only show on notifications set to Alerts.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Notification Settings") {
                            NSWorkspace.shared.open(URL(
                                string: "x-apple.systempreferences:com.apple.preference.notifications"
                            )!)
                        }
                        .controlSize(.small)
                    }
                }

                Button("Show Card Now") { monitor.showCurrentTrackNow() }
            }

            Section("What it shows") {
                Toggle("Album art", isOn: $preferences.showArtwork)
                Toggle("“Up next” line", isOn: $preferences.showUpNext)
                if preferences.showUpNext && !auth.isConnected {
                    Text("Needs a Spotify connection — see below.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Toggle("Play a sound", isOn: $preferences.playSound)
                Toggle("Announce when a paused track resumes", isOn: $preferences.notifyOnResume)
            }

            Section("Up next (optional)") {
                SpotifyConnectionSection(preferences: preferences, auth: auth)
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    // Read the real state back: registration can fail, and silently
                    // leaving the switch on would misreport it.
                    set: { launchAtLogin = LaunchAtLogin.set($0) }
                ))
                .disabled(!LaunchAtLogin.isAvailable)

                Text("Skipping and album art ask the Spotify app directly, so macOS will "
                     + "request permission to control it once. Detecting track changes "
                     + "needs no permission at all.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            // The user may have changed the notification setting in System Settings since
            // the app launched.
            notifications.refresh()
        }
    }
}
