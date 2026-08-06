import Foundation
import UserNotifications

/// A real macOS notification: top right, in Notification Centre afterwards, obeying Do
/// Not Disturb and the user's alert-style choice.
///
/// The layout maps onto the notification's three text slots, which is what gives the
/// requested shape for free:
///
///     ┌──────────────────────────────┬─────┐
///     │ Song title            (title)│ art │
///     │ Artist · Album     (subtitle)│     │
///     │ Up next: Song — Artist (body)│     │
///     └──────────────────────────────┴─────┘
@MainActor
final class BannerPresenter: NSObject, Presenter {
    /// Categories are what give a notification its buttons; the identifier has to match
    /// on the request or the Next button will not appear.
    private static let categoryIdentifier = "cuecard.nowplaying"
    private static let skipActionIdentifier = "cuecard.skip"

    var onSkip: (() -> Void)?

    private let center = UNUserNotificationCenter.current()
    private let preferences: Preferences
    private let availability: NotificationAvailability
    private var lastIdentifier: String?

    init(preferences: Preferences, availability: NotificationAvailability) {
        self.preferences = preferences
        self.availability = availability
        super.init()
        center.delegate = self
    }

    func prepare() {
        let skip = UNNotificationAction(
            identifier: Self.skipActionIdentifier,
            title: "Next",
            options: []
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryIdentifier,
                actions: [skip],
                intentIdentifiers: [],
                options: []
            )
        ])
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                Log.present.error("notification authorisation failed: \(error.localizedDescription, privacy: .public)")
            }
            let availability = self.availability
            Task { @MainActor in
                availability.record(granted: granted, error: error)
                // Permission granted is not the same as visible: follow up with the real
                // settings, which is where an alert style of None shows up.
                availability.refresh()
            }
        }
    }

    func present(_ cue: Cue) {
        let content = UNMutableNotificationContent()
        content.title = cue.track.title
        content.subtitle = Self.subtitle(for: cue.track)
        // The last line is the up-next hint. Left empty when there is nothing to say,
        // which collapses the row rather than showing a stub.
        content.body = cue.next.map { "Up next: \($0.oneLine)" } ?? ""
        content.categoryIdentifier = Self.categoryIdentifier
        content.sound = preferences.playSound ? .default : nil
        content.interruptionLevel = .active

        if let file = cue.artworkFile {
            do {
                content.attachments = [try UNNotificationAttachment(identifier: "art", url: file)]
            } catch {
                // Not worth dropping the notification over — show it without the cover.
                Log.present.error("could not attach artwork: \(error.localizedDescription, privacy: .public)")
                try? FileManager.default.removeItem(at: file)
            }
        }

        // Replacing the previous notification instead of stacking them: on a short
        // playlist you would otherwise end up with a column of stale tracks.
        let identifier = "cuecard.\(UUID().uuidString)"
        if let lastIdentifier {
            center.removeDeliveredNotifications(withIdentifiers: [lastIdentifier])
        }
        lastIdentifier = identifier

        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
            if let error {
                Log.present.error("could not post notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func dismiss() {
        guard let lastIdentifier else { return }
        center.removeDeliveredNotifications(withIdentifiers: [lastIdentifier])
        self.lastIdentifier = nil
    }

    static func subtitle(for track: Track) -> String {
        [track.artist, track.album]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }
}

/// `@preconcurrency`: the delegate protocol is not annotated for actor isolation, but
/// UserNotifications does call both methods on the main queue.
extension BannerPresenter: @preconcurrency UNUserNotificationCenterDelegate {
    /// Without this the system suppresses banners while the app is frontmost. Cuecard has
    /// no windows of its own most of the time, but the Settings window counts.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(preferences.playSound ? [.banner, .sound] : [.banner])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == Self.skipActionIdentifier {
            Task { @MainActor in self.onSkip?() }
        }
        completionHandler()
    }
}
