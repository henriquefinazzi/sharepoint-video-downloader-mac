#!/bin/zsh
# Builds SharePoint Video Downloader from source and installs it to ~/Applications.
#
# Signing:
#   - If you have an "Apple Development" certificate (free with any Apple ID added in
#     Xcode → Settings → Accounts), it's used, and Safari loads the extension normally.
#   - Otherwise the app is signed ad hoc, and you must enable
#     Safari → Settings → Developer → "Allow unsigned extensions" (resets when Safari quits).
#
# Optional environment variables:
#   SPVD_TEAM            Apple team ID to sign with (default: from your certificate)
#   SPVD_BUNDLE_PREFIX   bundle ID prefix (default: com.<your user name>)
#   SPVD_UNSIGNED=1      force ad-hoc signing
#   SPVD_INSTALL_DIR     where to install (default: ~/Applications)
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_NAME="SharePoint Video Downloader.app"
INSTALL_DIR="${SPVD_INSTALL_DIR:-$HOME/Applications}"
DEST="$INSTALL_DIR/$APP_NAME"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

say() { print -P "%F{cyan}==>%f $*"; }
die() { print -P "%F{red}Error:%f $*" >&2; exit 1; }

# --- Prerequisites ------------------------------------------------------------
xcodebuild -version >/dev/null 2>&1 \
  || die "Xcode is required (the full app from the App Store, not only the Command Line Tools).
       After installing it, run: sudo xcode-select -s /Applications/Xcode.app"

# --- Signing --------------------------------------------------------------------
team="${SPVD_TEAM:-}"
if [[ -z "$team" && "${SPVD_UNSIGNED:-0}" != 1 ]]; then
  cert_name="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
  if [[ -n "$cert_name" ]]; then
    team="$(security find-certificate -c "$cert_name" -p 2>/dev/null \
      | openssl x509 -noout -subject 2>/dev/null | sed -n 's/.*OU *= *\([A-Z0-9]*\).*/\1/p')"
  fi
fi

user_slug="$(id -un | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')"
prefix="${SPVD_BUNDLE_PREFIX:-com.${user_slug:-local}}"

signing_args=()
if [[ -n "$team" && "${SPVD_UNSIGNED:-0}" != 1 ]]; then
  say "Signing with Apple team $team (bundle prefix: $prefix)"
  signing_args=(-allowProvisioningUpdates)
else
  team=""
  say "No Apple Development certificate found: signing ad hoc (bundle prefix: $prefix)"
  signing_args=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- PROVISIONING_PROFILE_SPECIFIER=)
fi

cat > "$PROJECT_DIR/Config/Local.xcconfig" <<EOF
// Written by scripts/install.sh — not committed.
SPVD_BUNDLE_PREFIX = $prefix
DEVELOPMENT_TEAM = $team
EOF

# --- Build (outside OneDrive/iCloud folders: sync attributes break code signing) ---
BUILD_DIR="$(mktemp -d -t spvd-build)"
cleanup() {
  local built="$BUILD_DIR/Build/Products/Release/$APP_NAME"
  if [[ -d "$built" ]]; then
    # Keep Safari from also listing the temporary build copy.
    pluginkit -r "$built/Contents/PlugIns/SPVideoDownloaderExtension.appex" 2>/dev/null || true
    "$LSREGISTER" -u "$built" 2>/dev/null || true
  fi
  rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

say "Building…"
xcodebuild -project "$PROJECT_DIR/SPVideoDownloader.xcodeproj" -scheme SPVideoDownloader \
  -configuration Release -derivedDataPath "$BUILD_DIR" -quiet "${signing_args[@]}" build \
  2> >(grep -vE "CoreSimulator|DVTErrorPresenter|Simulator device|IDERunDestination|appintentsmetadata" >&2)

# --- Install ----------------------------------------------------------------------
say "Installing to $DEST"
osascript -e "quit app \"${APP_NAME%.app}\"" 2>/dev/null || true
sleep 1
mkdir -p "$INSTALL_DIR"
rm -rf "$DEST"
ditto "$BUILD_DIR/Build/Products/Release/$APP_NAME" "$DEST"
"$LSREGISTER" -f "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/SPVideoDownloaderExtension.appex" 2>/dev/null || true

say "Done. Next:"
echo "   1. Open \"${APP_NAME%.app}\" once (from $INSTALL_DIR)."
[[ -z "$team" ]] && echo "   2. Safari → Settings → Developer → enable \"Allow unsigned extensions\"."
echo "   •  Safari → Settings → Extensions → enable \"SharePoint Video Downloader\"."
