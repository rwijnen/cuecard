import Foundation
import UserNotifications

/// Tracks whether macOS will actually show us notifications.
///
/// This is not paranoia. macOS refuses notification authorisation outright to an app with
/// no code-signing identity — `requestAuthorization` fails immediately with "Notifications
/// are not allowed for this application", and the deprecated `NSUserNotification` API is
/// worse: it accepts the notification, records it as delivered, and draws nothing. A build
/// signed ad-hoc, which is what you get without an Apple Developer certificate, therefore
/// cannot use the notification style at all.
///
/// So rather than going quiet, the app notices and falls back to the notch card, and the
/// UI says why.
@MainActor
final class NotificationAvailability: ObservableObject {
    enum Status: Equatable {
        case unknown
        case authorized
        /// Carries a sentence fit to show the user.
        case unavailable(String)
    }

    @Published private(set) var status: Status

    init() {
        // Decided up front when there is no bundle, because merely *asking*
        // `UNUserNotificationCenter.current()` would raise an uncatchable exception. This
        // is what makes `swift run Cuecard` usable during development.
        status = AppBundle.isApp
            ? .unknown
            : .unavailable("Cuecard is running as a bare binary rather than an installed "
                           + "app, so macOS will not deliver notifications to it.")
    }

    var isUnavailable: Bool {
        if case .unavailable = status { return true }
        return false
    }

    var explanation: String? {
        if case .unavailable(let reason) = status { return reason }
        return nil
    }

    func record(granted: Bool, error: Error?) {
        if let error {
            // The signing case is the common one and the message the system gives is
            // opaque, so name the likely cause instead of parroting it.
            let reason = error.localizedDescription.contains("not allowed")
                ? "macOS will not grant notification permission to an app without a code-signing "
                    + "identity, which is what an ad-hoc build is. Notch cards work regardless."
                : error.localizedDescription
            status = .unavailable(reason)
        } else if granted {
            status = .authorized
        } else {
            status = .unavailable(
                "Notifications are turned off for Cuecard in System Settings › Notifications."
            )
        }
        Log.present.info("notification availability: \(String(describing: self.status), privacy: .public)")
    }

    /// Re-reads the system's own view of things, for when the user changes it in System
    /// Settings while the app is running.
    ///
    /// Permission alone is not enough to be seen: an app can be authorised and still have
    /// its alert style set to None, in which case notifications go straight to Notification
    /// Centre and no banner is ever drawn. That looks exactly like a broken app, so it is
    /// treated as unavailable and explained.
    func refresh() {
        guard AppBundle.isApp else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let authorized = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            let bannersOff = settings.alertStyle == .none || settings.alertSetting == .disabled

            Log.present.info("""
            notification settings: authStatus=\(settings.authorizationStatus.rawValue) \
            alertStyle=\(settings.alertStyle.rawValue) \
            alertSetting=\(settings.alertSetting.rawValue) \
            notificationCentre=\(settings.notificationCenterSetting.rawValue)
            """)

            Task { @MainActor [weak self] in
                guard let self else { return }
                switch settings.authorizationStatus {
                case _ where authorized && bannersOff:
                    self.status = .unavailable(
                        "Cuecard may notify, but its alert style is set to None, so nothing is "
                            + "drawn on screen. In System Settings › Notifications › Cuecard, "
                            + "choose Banners or Alerts."
                    )
                case .authorized, .provisional:
                    self.status = .authorized
                case .denied:
                    self.status = .unavailable(
                        "Notifications are turned off for Cuecard in System Settings › Notifications."
                    )
                default:
                    // Still undetermined — leave whatever `record` concluded in place.
                    break
                }
            }
        }
    }
}
