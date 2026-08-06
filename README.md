<img src="Docs/icon.png" width="104" align="right" alt="">

# Cuecard

**A card whenever a new song starts.** Cover, title, artist, a button to skip it — and a
one-liner telling you what plays next. Menu bar only: no Dock icon, no window.

[![CI](https://github.com/rwijnen/cuecard/actions/workflows/ci.yml/badge.svg)](https://github.com/rwijnen/cuecard/actions/workflows/ci.yml)
[![Licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](#development)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift&logoColor=white)](#development)
[![No dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)](Package.swift)

```bash
git clone https://github.com/rwijnen/cuecard.git
cd cuecard && ./build.sh --install
```

Ten seconds, no Xcode needed — the Command Line Tools are enough. macOS 14+, Apple silicon
or Intel.

---

![The notch card: album art, title, artist, skip button, and the up-next line](Docs/notch-card.png)

*Shown with Reduce Transparency on. Normally the card's background is live macOS vibrancy —
the desktop behind it, blurred — which cannot be captured offscreen.*

## Two places the card can appear

![Choosing between notification and notch](Docs/style-picker.png)

| | |
|---|---|
| **Notification** | A real macOS notification, top right. Obeys Do Not Disturb, stays in Notification Centre, carries the album art as an attachment and the skip as a notification action. **Requires a code-signing identity — see below.** |
| **Notch** | A card pinned under the MacBook Pro notch. Needs no permission, works in any build. Ignores Do Not Disturb and leaves nothing behind. |

### The notch card is not a notification

macOS exposes no API to put content in the notch. Anything that appears there is a
borderless window the app draws and positions itself, and Cuecard is no exception. It
measures the notch from `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea` rather
than assuming a size — a 14-inch M3 Pro reports 185 points, not the 200 usually assumed —
and centres the card on it. Clicks in the transparent strip above the card pass through, so
it never eats a click meant for the menu bar.

The background is real vibrancy (`NSVisualEffectView`, `.behindWindow`), with a gentle scrim
over it so white text stays legible against a bright wallpaper, and it switches to an opaque
fill under Reduce Transparency. One non-obvious requirement: the effect view's `state` must
be `.active`, because the card lives in a non-activating panel that is never key and the
default `.followsWindowActiveState` would render it permanently flat.

On a display without a notch — an external monitor — the card is anchored to `visibleFrame`
so it hangs below that display's menu bar rather than on top of it.

### Notifications need an Apple-issued certificate

macOS refuses notification authorisation to any app whose signature carries no **Team
Identifier**, and only an Apple-issued certificate provides one. Measured, not assumed:

| Signature | `TeamIdentifier` | `requestAuthorization` |
|---|---|---|
| Ad-hoc (`codesign -s -`) | not set | fails: *"Notifications are not allowed for this application"* |
| Self-signed certificate | not set | fails, identically |
| Apple Development / Developer ID | set | works |

One dead end worth naming so nobody else spends an afternoon on it: a **self-signed
code-signing certificate does not help.** Even created with the `codeSigning` EKU and
trusted for `codeSign`, `TeamIdentifier` stays unset, because macOS derives it from
certificate fields only Apple can issue.

**Getting a certificate is free.** It needs Xcode installed, but not a paid Developer
Program membership:

1. Xcode → Settings → Accounts → **+** → sign in with any Apple ID.
2. Select the account → **Manage Certificates…** → **+** → **Apple Development**.
3. Check it landed: `security find-identity -v -p codesigning` should list
   `Apple Development: you@example.com (XXXXXXXXXX)`.
4. Re-run `./build.sh --install`. It picks the identity up on its own and prints the Team
   Identifier it signed with — no code or config changes.

**If step 3 reports `0 valid identities found`** while the certificate clearly exists,
the chain is broken rather than the certificate. Check it:

```bash
security find-identity -p codesigning   # note: no -v, so invalid ones are listed too
```

`CSSMERR_TP_NOT_TRUSTED` there means the **Apple WWDR intermediate** that issued your
certificate is missing. Apple retired the original one in February 2023, and a machine that
has only that expired copy cannot build a chain for a modern `OU=G3` certificate. Xcode
ships the replacements, so no download is needed:

```bash
security add-certificates -k ~/Library/Keychains/login.keychain-db \
  /Applications/Xcode.app/Contents/SharedFrameworks/DVTFoundation.framework/Versions/A/Resources/AppleWWDRCA-2030.cer
```

Match the file to your certificate's issuer — `AppleWWDRCA-2030.cer` is `OU=G3`,
`AppleWWDRCAG6.cer` is `OU=G6`. Check yours with:

```bash
security find-certificate -c "Apple Development" -p | openssl x509 -noout -issuer
```

A paid membership ($99/yr) gets you a **Developer ID Application** certificate instead,
which `build.sh` also prefers automatically and which is what you would need to distribute
the app to anyone else.

Until then Cuecard does not go quiet: it notices the refusal, **falls back to the notch
card**, and says so in Settings with a one-click switch.

## The "Up next" line

This is the one feature that needs the network, and it is optional. Spotify's desktop app
tells the Mac what is playing *now* and nothing about what is queued — its scripting
interface has no concept of a queue. `GET /v1/me/player/queue` in the Web API is the only
source, so an "up next" line means signing in.

Setup is three steps, all in Settings (or the first-run wizard, where the whole step can be
skipped):

1. Create an app at [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard).
2. Add `http://127.0.0.1:8888/callback` as a Redirect URI, exactly. Spotify requires the
   literal loopback address; it stopped accepting `localhost` in 2025.
3. Paste the Client ID and press Connect.

Sign-in is Authorization Code with **PKCE**, so no client secret is stored anywhere — a
desktop app cannot keep one. The only scope requested is `user-read-playback-state`;
skipping goes through the local app, which needs no scope and no Premium subscription. The
refresh token goes in the Keychain, with a `0600` file in Application Support as a fallback
if the Keychain refuses.

Without a connection everything else works — the card simply has no last line.

![The card with no artwork and no queue connected](Docs/notch-card-no-art.png)

## How it detects a track change

Not by polling. Spotify broadcasts a distributed notification,
`com.spotify.client.PlaybackStateChanged`, on every playback change, and it carries the
whole track in its `userInfo`. That is the primary trigger: instant, free, and requiring
**no Automation permission at all**.

Apple Events are used for exactly two things the broadcast cannot do — fetch the artwork
URL, and skip — so the permission prompt only appears when you press something. A slow
5-second poll runs alongside as a safety net and to keep the playback position fresh, which
is what makes repeat-one detectable.

Between Spotify and your notification centre sits a filter, because Spotify also broadcasts
on pause, resume and seek, and the poller re-reports the same track every few seconds:

| Situation | Result |
|---|---|
| A different track starts | Announced |
| The same track re-reported | Silent |
| Paused, then resumed | Silent (opt in under Settings) |
| Repeat-one wraps around | Announced |
| Whatever was playing when the app launched | Silent — you know what is on |
| Position jitter near the start | Silent |

## Permissions

| | |
|---|---|
| Track detection | None |
| Album art, skipping | Automation, for Spotify — prompted once, on first use |
| Notification style | Notifications, plus a code-signing identity |
| Notch style | None |

Cuecard never plays anything on its own, never writes to your library, and talks to no
network host but `accounts.spotify.com`, `api.spotify.com` and Spotify's image CDN.

## Development

```bash
swift test          # 71 tests, no network, no Spotify needed
swift build
./build.sh          # build/Cuecard.app
./build.sh --debug
```

The parts worth knowing about are separated so they can be tested as pure functions:
`TrackChangeDetector` (the announce/stay-quiet rules), `NotchGeometry` (where the card
goes, including the real measurements from a 14-inch M3 Pro whose primary display is an
external monitor, so the built-in panel has a negative frame origin), `SpotifyEvents`
(broadcast payload parsing), `SpotifyScripting.parseSnapshot` and `SpotifyWebAPI.decodeQueue`.

`swift run Cuecard` works for iterating on the notch card, and falls back to it
automatically: several system frameworks — `SMAppService`, `UNUserNotificationCenter` —
raise an Objective-C exception that Swift cannot catch when called from a process that is
not a real `.app`, so `AppBundle.isApp` is checked before any of them. Anything touching
notifications or the login item needs `./build.sh --install`.

Two things that bit during development and are now pinned by tests:

- **`st` is a reserved word in AppleScript** — the ordinal suffix from "1st". `set st to …`
  is a syntax error, so the scripts spell their variables out.
- **AppleScript formats reals with the user's decimal separator.** On this machine
  `player position` comes back as `248,675`, and parsing it as `Double` without
  normalising the comma silently broke repeat-one detection.

Logging goes through one subsystem:

```bash
log stream --predicate 'subsystem == "com.robinwijnen.Cuecard"'
```
