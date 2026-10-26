import SwiftUI

/// The Updates section of Settings: the automatic-check switch, what the last check found,
/// and a button to check (or install) now.
struct UpdateSection: View {
    @ObservedObject var updates: UpdateChecker
    @ObservedObject var preferences: Preferences

    var body: some View {
        Toggle("Check for updates automatically", isOn: $preferences.checkForUpdates)
            .disabled(!updates.isAvailable)

        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(versionLine)
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(updates.availableRelease == nil ? .secondary : Color.accentColor)
            }
            Spacer()
            if updates.status == .checking || updates.status == .installing {
                ProgressView().controlSize(.small)
            }
            Button(updates.availableRelease == nil ? "Check Now" : "Update…") { updates.checkNow() }
                .glassButtonStyle(prominent: updates.availableRelease != nil)
                .disabled(!updates.isAvailable || updates.status == .checking || updates.status == .installing)
        }

        if !updates.isAvailable {
            Text("Updates need the installed app — run ./build.sh --install.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var versionLine: String {
        updates.currentVersion.map { "Cuecard \($0)" } ?? "Cuecard (development build)"
    }

    private var statusLine: String {
        switch updates.status {
        case .checking: return "Checking…"
        case .installing: return "Installing…"
        case .available(let release): return "Version \(release.version?.description ?? release.tagName) is available."
        case .failed(let message): return "Last check failed: \(message)"
        case .upToDate, .idle:
            guard let last = updates.lastChecked else { return "Not checked yet." }
            let relative = last.formatted(.relative(presentation: .named))
            return updates.status == .upToDate ? "Up to date — checked \(relative)." : "Last checked \(relative)."
        }
    }
}
