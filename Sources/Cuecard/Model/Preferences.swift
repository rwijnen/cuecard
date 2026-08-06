import Foundation
import Combine

/// Where the card appears.
enum PresentationStyle: String, CaseIterable, Identifiable, Sendable {
    /// A real macOS notification, top right, with a Next button. Obeys Do Not Disturb
    /// and lands in Notification Centre for later.
    case notification
    /// A card drawn under the notch. Not a notification — a borderless window we own,
    /// which is the only way to put anything there.
    case notch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notification: "Notification"
        case .notch: "Notch"
        }
    }

    var subtitle: String {
        switch self {
        case .notification: "Standard macOS banner, top right"
        case .notch: "Card under the MacBook Pro notch"
        }
    }
}

/// User settings, persisted in `UserDefaults`. `@Published` so SwiftUI redraws and the
/// monitor can react to a style change without a restart.
final class Preferences: ObservableObject {
    private enum Key {
        static let style = "presentationStyle"
        static let showArtwork = "showArtwork"
        static let showUpNext = "showUpNext"
        static let notchDuration = "notchDuration"
        static let notifyOnResume = "notifyOnResume"
        static let playSound = "playSound"
        static let clientID = "spotifyClientID"
        static let completedSetup = "completedSetup"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.style: PresentationStyle.notification.rawValue,
            Key.showArtwork: true,
            Key.showUpNext: true,
            Key.notchDuration: 5.0,
            Key.notifyOnResume: false,
            Key.playSound: false,
            Key.completedSetup: false,
        ])
        style = PresentationStyle(rawValue: defaults.string(forKey: Key.style) ?? "") ?? .notification
        showArtwork = defaults.bool(forKey: Key.showArtwork)
        showUpNext = defaults.bool(forKey: Key.showUpNext)
        notchDuration = defaults.double(forKey: Key.notchDuration)
        notifyOnResume = defaults.bool(forKey: Key.notifyOnResume)
        playSound = defaults.bool(forKey: Key.playSound)
        clientID = defaults.string(forKey: Key.clientID) ?? ""
        completedSetup = defaults.bool(forKey: Key.completedSetup)
    }

    @Published var style: PresentationStyle {
        didSet { defaults.set(style.rawValue, forKey: Key.style) }
    }

    @Published var showArtwork: Bool {
        didSet { defaults.set(showArtwork, forKey: Key.showArtwork) }
    }

    /// Off is honoured even when credentials exist — some people would rather not know.
    @Published var showUpNext: Bool {
        didSet { defaults.set(showUpNext, forKey: Key.showUpNext) }
    }

    /// How long the notch card stays before it retracts. Hovering it pauses the clock.
    @Published var notchDuration: Double {
        didSet { defaults.set(notchDuration, forKey: Key.notchDuration) }
    }

    /// Whether un-pausing the same track counts as news.
    @Published var notifyOnResume: Bool {
        didSet { defaults.set(notifyOnResume, forKey: Key.notifyOnResume) }
    }

    @Published var playSound: Bool {
        didSet { defaults.set(playSound, forKey: Key.playSound) }
    }

    /// Spotify Web API client ID. Empty means no up-next line: the local Spotify app
    /// cannot be asked what comes next, only the Web API knows the queue.
    @Published var clientID: String {
        didSet { defaults.set(clientID, forKey: Key.clientID) }
    }

    @Published var completedSetup: Bool {
        didSet { defaults.set(completedSetup, forKey: Key.completedSetup) }
    }
}
