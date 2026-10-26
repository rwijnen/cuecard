import AppKit
import Combine
import SwiftUI

/// The status item. Cuecard has no Dock icon and no main window, so this is the whole
/// visible surface when no card is on screen.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let monitor: NowPlayingMonitor
    private let preferences: Preferences
    private let updates: UpdateChecker
    private let openSettings: () -> Void

    init(
        monitor: NowPlayingMonitor,
        preferences: Preferences,
        updates: UpdateChecker,
        openSettings: @escaping () -> Void
    ) {
        self.monitor = monitor
        self.preferences = preferences
        self.updates = updates
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
            if let track = monitor.current {
                menu.addItem(nowPlaying(track))
            } else {
                menu.addItem(disabled("Nothing playing"))
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
        if updates.isAvailable {
            if let version = updates.availableRelease?.version {
                menu.addItem(action("Update to Cuecard \(version)…", #selector(checkForUpdates)))
            } else {
                let item = action("Check for Updates…", #selector(checkForUpdates))
                item.isEnabled = updates.status != .checking && updates.status != .installing
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        menu.addItem(action("Quit Cuecard", #selector(quit), key: "q"))
    }

    // MARK: - Items

    /// Cover, title, artist and album, as a hosted SwiftUI view — an ordinary item cannot
    /// show an image larger than an icon.
    private func nowPlaying(_ track: Track) -> NSMenuItem {
        let item = NSMenuItem()
        let header = NowPlayingMenuHeader(
            track: track,
            artwork: monitor.currentArtwork,
            isPaused: monitor.state == .paused
        ) { [weak self, weak item] in
            // A view item does not close the menu when clicked; it has to be asked.
            item?.menu?.cancelTracking()
            self?.openSpotify()
        }
        let host = NSHostingView(rootView: header)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        item.view = host
        item.toolTip = track.oneLine
        return item
    }

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

    @objc private func checkForUpdates() { updates.checkNow() }

    @objc private func openSpotify() {
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: SpotifyEvents.bundleIdentifier
        ) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
