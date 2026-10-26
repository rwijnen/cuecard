import AppKit
import Foundation

/// Everything a card needs to draw itself: the track that just started, what follows it,
/// and the art in whichever form the presenter consumes.
struct Cue {
    var track: Track
    /// `nil` when the Web API is not connected, the queue is empty, or the up-next line
    /// is switched off.
    var next: Track?
    /// Staged file, for `UNNotificationAttachment`.
    var artworkFile: URL?
    /// Decoded image, for the notch card. Also kept for the menu, whatever the style.
    var artworkImage: NSImage?
}

/// The two presentation styles behind one door, so `NowPlayingMonitor` does not care
/// which is active.
@MainActor
protocol Presenter: AnyObject {
    /// Called when the user asks for the next track from the card.
    var onSkip: (() -> Void)? { get set }

    func present(_ cue: Cue)
    func dismiss()
    /// Ask for whatever permission this style needs. Notifications need authorisation;
    /// the notch card needs none.
    func prepare()
}
