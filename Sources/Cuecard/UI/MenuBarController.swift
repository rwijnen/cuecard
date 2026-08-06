import AppKit
import Combine

/// The status item. Cuecard has no Dock icon and no main window, so this is the whole
/// visible surface when no card is on screen.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let monitor: NowPlayingMonitor
    private let preferences: Preferences
    private let openSettings: () -> Void

    init(monitor: NowPlayingMonitor, preferences: Preferences, openSettings: @escaping () -> Void) {
        self.monitor = monitor
        self.preferences = preferences
        self.openSettings = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "music.note.list",
            accessibilityDescription: "Cuecard"
        )
        statusItem.button?.image?.isTemplate = true

        let menu = NSMenu()
        // Rebuilt on open rather than kept in sync — it is only ever read at that moment.
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        switch monitor.state {
        case .notRunning:
            menu.addItem(disabled("Spotify is not running"))
        case .stopped:
            menu.addItem(disabled("Nothing playing"))
        case .playing, .paused:
            let track = monitor.current
            menu.addItem(disabled(track?.title ?? "Nothing playing"))
            if let track, !track.artist.isEmpty {
                menu.addItem(disabled(track.artist, indented: true))
            }
            if let next = monitor.upNext {
                menu.addItem(.separator())
                menu.addItem(disabled("Up next: \(next.oneLine)"))
            }
        }

        menu.addItem(.separator())

        if monitor.state == .playing || monitor.state == .paused {
            menu.addItem(action("Next Track", #selector(skip), key: "]"))
            menu.addItem(action("Show Card Now", #selector(showCard)))
            menu.addItem(.separator())
        }

        menu.addItem(action("Open Spotify", #selector(openSpotify)))
        menu.addItem(action("Settings…", #selector(showSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(action("Quit Cuecard", #selector(quit), key: "q"))
    }

    // MARK: - Items

    private func disabled(_ title: String, indented: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        if indented { item.indentationLevel = 1 }
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - Actions

    @objc private func skip() { monitor.skip() }

    @objc private func showCard() { monitor.showCurrentTrackNow() }

    @objc private func showSettings() { openSettings() }

    @objc private func openSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: SpotifyEvents.bundleIdentifier
        ) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
