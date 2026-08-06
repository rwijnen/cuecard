import SwiftUI

/// Shown when the notification style has been chosen but macOS will not deliver
/// notifications. Says what is happening, why, and offers the one-click way out — an
/// unexplained fallback would be worse than none.
struct NotificationWarning: View {
    @ObservedObject var availability: NotificationAvailability
    @ObservedObject var preferences: Preferences

    var body: some View {
        if preferences.style == .notification, let explanation = availability.explanation {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Notifications are unavailable — showing notch cards instead.")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Switch to notch cards") { preferences.style = .notch }
                    .controlSize(.small)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
            )
        }
    }
}
