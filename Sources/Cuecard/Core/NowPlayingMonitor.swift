import AppKit
import Combine
import Foundation

/// Watches Spotify and decides what to show.
///
/// The flow is: Spotify broadcasts a change → `TrackChangeDetector` says whether it is
/// news → the track is enriched with artwork and the queue → the active presenter shows
/// it. A slow poll runs alongside as a safety net and to keep playback position fresh,
/// which is what makes repeat-one detectable.
@MainActor
final class NowPlayingMonitor: ObservableObject {
    /// What the menu bar shows. Mirrors the last announced track, not every snapshot.
    @Published private(set) var current: Track?
    @Published private(set) var upNext: Track?
    /// Cover for `current`, for the menu. Kept whichever style is active, because the menu
    /// shows it either way.
    @Published private(set) var currentArtwork: NSImage?
    @Published private(set) var state: PlayerState = .notRunning

    /// Exposed so Settings and the wizard can explain a fallback rather than let the user
    /// wonder why nothing appears.
    let notifications = NotificationAvailability()

    private let preferences: Preferences
    private let webAPI: SpotifyWebAPI
    private let artwork = ArtworkStore()
    private let observer = SpotifyEventObserver()
    private var detector: TrackChangeDetector
    private var bannerPresenter: BannerPresenter?
    private var notchPresenter: NotchPresenter?
    private var announceTask: Task<Void, Never>?
    private var pollTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []

    /// Broadcasts are reliable, so this only has to catch the rare miss and keep the
    /// last-known position current. Frequent enough to notice, rare enough to be free.
    private let pollInterval: TimeInterval = 5

    init(preferences: Preferences, auth: SpotifyAuth) {
        self.preferences = preferences
        self.webAPI = SpotifyWebAPI(auth: auth)
        self.detector = TrackChangeDetector(notifyOnResume: preferences.notifyOnResume)

        preferences.$notifyOnResume
            .sink { [weak self] value in self?.detector.notifyOnResume = value }
            .store(in: &cancellables)

        // Switching style should visibly do something, so let the next track through
        // even if it is the one already playing, and clear the old style off screen.
        preferences.$style
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.bannerPresenter?.dismiss()
                self.notchPresenter?.dismiss()
                self.detector.reset()
                self.activePresenter().prepare()
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func start() {
        activePresenter().prepare()

        // Whatever is already playing is not news — you just launched the app.
        Task { @MainActor in
            let snapshot = await SpotifyScripting.snapshotAsync()
            state = snapshot.state
            current = snapshot.track
            detector.prime(snapshot)
            await refreshUpNext()
            if preferences.showArtwork, let track = snapshot.track {
                let image = await artwork.image(for: track.artworkURL)
                // A track change may have been announced while this was downloading.
                if current?.identity == track.identity { currentArtwork = image }
            }
        }

        observer.start { [weak self] snapshot in
            self?.handle(snapshot)
        }

        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.poll() }
        }
        // .common, or the poll stalls whenever a menu is open or a window is dragged.
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        observer.stop()
        pollTimer?.invalidate()
        pollTimer = nil
        announceTask?.cancel()
    }

    // MARK: - Commands

    func skip() {
        SpotifyScripting.nextTrackAsync()
    }

    /// Shows the current track again, on demand. Used by the setup wizard and the menu so
    /// the chosen style can be seen without waiting for a track to end.
    func showCurrentTrackNow() {
        Task { @MainActor in
            let snapshot = await SpotifyScripting.snapshotAsync()
            state = snapshot.state
            guard let track = snapshot.track else {
                present(Cue(track: Self.sampleTrack, next: Self.sampleNext))
                return
            }
            detector.reset()
            await announce(track)
        }
    }

    // MARK: - Pipeline

    private func handle(_ snapshot: PlaybackSnapshot) {
        state = snapshot.state
        if snapshot.state != .playing, snapshot.track == nil {
            current = nil
            currentArtwork = nil
        }

        guard let track = detector.evaluate(snapshot) else { return }
        Log.spotify.info("announcing \(track.oneLine, privacy: .public)")
        announceTask?.cancel()
        announceTask = Task { @MainActor [weak self] in await self?.announce(track) }
    }

    private func poll() async {
        guard SpotifyEvents.spotifyIsRunning else {
            state = .notRunning
            return
        }
        handle(await SpotifyScripting.snapshotAsync())
    }

    private func announce(_ track: Track) async {
        var track = track
        var next: Track?

        if preferences.showUpNext, webAPI.isAvailable {
            do {
                let queue = try await webAPI.queue()
                // Only trust the queue if the API agrees with the local app about what is
                // playing. Otherwise playback is on another device (or the API has not
                // caught up) and its queue describes a different session.
                if let playing = queue.current, playing.matches(track) {
                    next = queue.upcoming.first
                    if track.artworkURL == nil { track.artworkURL = playing.artworkURL }
                    if track.album == nil { track.album = playing.album }
                } else {
                    Log.spotify.debug("queue is for a different track; skipping up-next")
                }
            } catch {
                Log.spotify.error("queue lookup failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        if preferences.showArtwork, track.artworkURL == nil {
            track.artworkURL = await SpotifyScripting.artworkURLAsync()
        }
        guard !Task.isCancelled else { return }

        current = track
        upNext = next
        currentArtwork = nil

        var cue = Cue(track: track, next: next)
        if preferences.showArtwork {
            // The decoded image is always wanted — the notch card draws it and the menu
            // shows it whichever style is active. A notification also needs a file it can
            // take ownership of, which is only worth staging when one will be posted, so
            // this has to know which presenter will actually be used, fallback included.
            // Both come from the same disk cache, so the cover is downloaded once.
            cue.artworkImage = await artwork.image(for: track.artworkURL)
            if effectiveStyle == .notification {
                cue.artworkFile = await artwork.attachmentCopy(for: track.artworkURL)
            }
        }
        guard !Task.isCancelled else { return }
        currentArtwork = cue.artworkImage
        present(cue)
    }

    private func present(_ cue: Cue) {
        let presenter = activePresenter()
        presenter.onSkip = { [weak self] in self?.skip() }
        presenter.present(cue)
    }

    /// Keeps the menu's up-next line current between tracks.
    private func refreshUpNext() async {
        guard preferences.showUpNext, webAPI.isAvailable, let current else {
            upNext = nil
            return
        }
        guard let queue = try? await webAPI.queue(), let playing = queue.current,
              playing.matches(current)
        else { return }
        upNext = queue.upcoming.first
    }

    /// The style that will actually be used. Falls back to the notch card when macOS has
    /// refused notification permission, because the alternative is an app that looks like
    /// it is working and shows nothing at all.
    private var effectiveStyle: PresentationStyle {
        if preferences.style == .notification, notifications.isUnavailable { return .notch }
        return preferences.style
    }

    private func activePresenter() -> Presenter {
        switch effectiveStyle {
        case .notification:
            if bannerPresenter == nil {
                bannerPresenter = BannerPresenter(preferences: preferences, availability: notifications)
            }
            return bannerPresenter!
        case .notch:
            if notchPresenter == nil { notchPresenter = NotchPresenter(preferences: preferences) }
            return notchPresenter!
        }
    }

    // MARK: - Sample content

    /// Stand-in for the preview when Spotify is not playing, so choosing a style in the
    /// wizard still shows something.
    static let sampleTrack = Track(
        id: "sample",
        title: "Teardrop",
        artist: "Massive Attack",
        album: "Mezzanine"
    )
    static let sampleNext = Track(id: "sample-next", title: "Inertia Creeps", artist: "Massive Attack")
}

extension Track {
    /// Loose identity match across the two sources. The Web API returns a URI, the
    /// broadcast usually does too, but local files and podcasts arrive without one — so
    /// fall back to comparing what a human would compare.
    func matches(_ other: Track) -> Bool {
        if !id.isEmpty, !other.id.isEmpty { return id == other.id }
        return title.caseInsensitiveCompare(other.title) == .orderedSame
            && artist.caseInsensitiveCompare(other.artist) == .orderedSame
    }
}
