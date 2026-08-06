import AppKit
import SwiftUI

/// The Web API sign-in, shared by Settings and the wizard.
///
/// Worth stating plainly in the UI, because it surprises people: the up-next line is the
/// *only* thing this buys. The desktop app's scripting interface has no concept of a
/// queue, so nothing local can answer "what plays next".
struct SpotifyConnectionSection: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var auth: SpotifyAuth
    /// The wizard wants the rationale spelled out; Settings does not need it twice.
    var showExplanation = true

    @State private var error: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showExplanation {
                Text("Spotify only tells the Mac what is playing now — never what is queued. "
                     + "Connecting a Spotify app of your own adds the “Up next” line. "
                     + "Everything else works without it.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if auth.isConnected {
                connected
            } else {
                setup
            }

            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var connected: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text("Connected — the up-next line is available.").font(.system(size: 12))
            Spacer()
            Button("Disconnect") {
                auth.disconnect()
                error = nil
            }
        }
    }

    @ViewBuilder
    private var setup: some View {
        VStack(alignment: .leading, spacing: 9) {
            steps

            HStack(spacing: 6) {
                TextField("Client ID", text: $preferences.clientID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                Button(auth.isConnecting ? "Waiting…" : "Connect") { connect() }
                    .disabled(auth.isConnecting || preferences.clientID
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 5) {
            step(1) {
                HStack(spacing: 4) {
                    Text("Create an app at")
                    Link("developer.spotify.com/dashboard",
                         destination: URL(string: "https://developer.spotify.com/dashboard")!)
                }
            }
            step(2) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Add this exact Redirect URI:")
                    HStack(spacing: 5) {
                        Text(LoopbackReceiver.redirectURI)
                            .font(.system(size: 10.5, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 4))
                        Button(copied ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(LoopbackReceiver.redirectURI, forType: .string)
                            copied = true
                        }
                        .controlSize(.small)
                    }
                }
            }
            step(3) { Text("Paste the app's Client ID below and press Connect.") }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private func step<Content: View>(_ number: Int, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(number).").monospacedDigit()
            content()
        }
    }

    private func connect() {
        error = nil
        Task {
            do {
                try await auth.connect()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
