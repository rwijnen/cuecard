import AppKit
import SwiftUI

@main
enum Cuecard {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // A menu bar app: no Dock icon, never the active app unless a window is open.
        // `LSUIElement` in Info.plist does the same, but setting it here keeps the bare
        // binary behaving the same way when run out of `.build` during development.
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private var auth: SpotifyAuth!
    private var monitor: NowPlayingMonitor!
    private var menuBar: MenuBarController!
    private var updates: UpdateChecker!
    private var settingsWindow: PanelWindow<SettingsView>!
    private var wizardWindow: PanelWindow<SetupWizardView>?
    /// Quitting closes the wizard window too, and that must not count as getting through
    /// setup — otherwise quitting mid-wizard means never seeing it again.
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        auth = SpotifyAuth(preferences: preferences)
        monitor = NowPlayingMonitor(preferences: preferences, auth: auth)
        updates = UpdateChecker(preferences: preferences)

        settingsWindow = PanelWindow(
            title: "Cuecard Settings",
            defaultSize: SettingsView.windowSize
        ) { [preferences, auth, monitor, updates] in
            SettingsView(
                preferences: preferences,
                auth: auth!,
                notifications: monitor!.notifications,
                updates: updates!,
                monitor: monitor!
            )
        }

        menuBar = MenuBarController(
            monitor: monitor,
            preferences: preferences,
            updates: updates
        ) { [weak self] in
            self?.settingsWindow.show()
        }

        monitor.start()
        updates.start()

        if !preferences.completedSetup {
            showWizard()
        }
        Log.app.info("Cuecard is running")
    }

    /// The first callback in the quit sequence — `windowWillClose` arrives *before*
    /// `applicationWillTerminate`, so setting the flag there was too late and quitting
    /// mid-wizard still counted as completing setup.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        isTerminating = true
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        monitor?.stop()
    }

    /// No windows means nothing to restore, and the status item is always there.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showWizard() {
        let window = PanelWindow(
            title: "Welcome to Cuecard",
            closable: true,
            defaultSize: SetupWizardView.windowSize
        ) {
            [preferences, auth, monitor] in
            SetupWizardView(
                preferences: preferences,
                auth: auth!,
                notifications: monitor!.notifications,
                monitor: monitor!
            ) { [weak self] in
                self?.finishSetup()
            }
        }
        // Dismissing the window counts as finishing — re-showing an unwanted wizard on
        // every launch would be worse than skipping the last step — but only when the
        // user closed it, not when the app is on its way out.
        window.onClose = { [weak self] in
            guard let self, !self.isTerminating else { return }
            self.preferences.completedSetup = true
            self.wizardWindow = nil
        }
        wizardWindow = window
        window.show()
    }

    private func finishSetup() {
        preferences.completedSetup = true
        wizardWindow?.close()
        wizardWindow = nil
    }
}
