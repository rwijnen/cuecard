#!/usr/bin/env bash
#
# Builds Cuecard.app without Xcode (the Command Line Tools are enough).
#
#   ./build.sh              build build/Cuecard.app
#   ./build.sh --install    also copy it to /Applications and launch it
#   ./build.sh --debug      build the debug configuration
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/Cuecard.app"
CONFIG=release
BUNDLE_ID=com.robinwijnen.Cuecard

DO_INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --install) DO_INSTALL=1 ;;
    --debug) CONFIG=debug ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 64 ;;
  esac
done

echo "==> Compiling ($CONFIG)"
swift build -c "$CONFIG" --product Cuecard
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> Assembling app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Cuecard" "$APP/Contents/MacOS/Cuecard"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Stamp a unique build number into the bundle's copy of the plist, leaving the source at 1.
# Icon and Launch Services caches key on the bundle version, and without a change they will
# keep serving a previous icon however many times the app is reinstalled — touching the
# bundle and restarting the daemons is not always enough.
BUILD_NUMBER="$(date +%Y%m%d%H%M%S)"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist" >/dev/null
echo "    build $BUILD_NUMBER"

echo "==> Building icon"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
if swift "$ROOT/Tools/make-icon.swift" "$ICONSET" >/dev/null 2>&1 \
   && command -v iconutil >/dev/null 2>&1 \
   && iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  echo "    AppIcon.icns"
else
  echo "    skipped (icon generation unavailable — the app still builds)"
fi

# Prefer a real Apple-issued identity. This is not cosmetic: macOS refuses notification
# permission outright to an app whose signature carries no Team Identifier, and only an
# Apple-issued certificate provides one — ad-hoc and self-signed certificates both report
# "TeamIdentifier=not set" and get "Notifications are not allowed for this application".
# A free Apple ID is enough; see README.
# `|| true` matters: with `set -e` and `pipefail`, grep finding nothing would abort the
# script here rather than fall through to the ad-hoc branch below.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -oE '"(Apple Development|Apple Distribution|Developer ID Application)[^"]*"' \
  | head -1 | tr -d '"' || true)"

if [[ -n "$IDENTITY" ]]; then
  echo "==> Signing as $IDENTITY"
  if codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP" >/dev/null 2>&1; then
    TEAM="$(codesign -dv --verbose=2 "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
    echo "    signed (TeamIdentifier=${TEAM:-unknown}) — notifications available"
  else
    echo "    codesign failed; falling back to ad-hoc"
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" >/dev/null 2>&1 || true
  fi
else
  # Ad-hoc still runs fine, and the notch card needs no permission at all. Note the
  # signature changes on every rebuild, so macOS may re-ask for permission to read the
  # stored Spotify token after an update.
  echo "==> Signing (ad-hoc — no Apple signing identity found)"
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" >/dev/null 2>&1 \
    && echo "    signed" \
    || echo "    codesign failed; the app will still run locally"
  cat <<'NOTE'

    NOTE  macOS grants notification permission only to an app whose signature
          carries a Team Identifier, and ad-hoc signing has none. The
          "Notification" style will therefore fall back to notch cards, which
          need no permission and work fine.

          To enable notifications (free, no paid Developer Program needed):
            1. Xcode > Settings > Accounts > + > sign in with any Apple ID
            2. Select the account > Manage Certificates... > + > Apple Development
            3. Re-run this script — it picks the identity up automatically
          Check step 2 worked with:  security find-identity -v -p codesigning
NOTE
fi

echo "==> Built $APP"

if [[ "$DO_INSTALL" == 1 ]]; then
  TARGET_DIR=/Applications
  if [[ ! -w "$TARGET_DIR" ]]; then
    TARGET_DIR="$HOME/Applications"
    mkdir -p "$TARGET_DIR"
    echo "==> /Applications is not writable; installing to $TARGET_DIR"
  fi
  INSTALLED="$TARGET_DIR/Cuecard.app"

  # Notifications and login-item registration key off the bundle identifier, so a copy
  # running from a second location would fight the installed one.
  if pgrep -f "$TARGET_DIR/Cuecard.app/Contents/MacOS/Cuecard" >/dev/null 2>&1; then
    echo "==> Quitting the running copy"
    osascript -e 'tell application "Cuecard" to quit' 2>/dev/null || pkill -x Cuecard || true
    sleep 1
  fi

  echo "==> Installing to $INSTALLED"
  rm -rf "$INSTALLED"
  cp -R "$APP" "$INSTALLED"

  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  [[ -x "$LSREGISTER" ]] && "$LSREGISTER" -f "$INSTALLED" && echo "==> Registered with Launch Services"

  # Icon caches do not notice that the artwork changed. `usernoted` in particular keeps its
  # own copy, so a notification will keep showing the previous icon indefinitely. Bumping
  # the bundle's mtime and restarting the caches is what makes a new icon actually appear.
  echo "==> Refreshing icon caches"
  touch "$INSTALLED"
  killall usernoted 2>/dev/null || true
  killall NotificationCenter 2>/dev/null || true
  killall Dock 2>/dev/null || true

  echo "==> Launching"
  open "$INSTALLED"
  echo
  echo "Cuecard is in the menu bar (♪ icon). It has no Dock icon by design."
fi
