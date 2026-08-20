#!/bin/bash
# sheepdock — build and install herdr.app, a macOS launcher that opens herdr in
# its own kitty window with its own Dock icon.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="$HOME/Applications"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/herdr-kitty"
ICON_SOURCE="https://herdr.dev/assets/logo.png"
FORCE=0
MASK_ARG=()

usage() {
    cat <<'USAGE'
Usage: ./install.sh [options]

  --prefix DIR    where to install herdr.app (default: ~/Applications)
  --icon SRC      logo URL or image path (default: herdr.dev's logo)
  --no-mask       keep the logo square instead of applying the macOS squircle
  --force         overwrite an existing kitty profile in the config directory
  -h, --help      show this help

Requires kitty (brew install --cask kitty) and herdr on your PATH.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        --icon)   ICON_SOURCE="$2"; shift 2 ;;
        --no-mask) MASK_ARG=(--no-mask); shift ;;
        --force)  FORCE=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

step() { printf '\n\033[1m==>\033[0m %s\n' "$1"; }
ok()   { printf '    \033[32m✓\033[0m %s\n' "$1"; }
warn() { printf '    \033[33m!\033[0m %s\n' "$1"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || die "sheepdock is macOS only."

# --- locate kitty ------------------------------------------------------------
step "Locating kitty"
KITTY_APP="${KITTY_APP:-}"
if [[ -z "$KITTY_APP" ]]; then
    for candidate in /Applications/kitty.app "$HOME/Applications/kitty.app"; do
        [[ -x "$candidate/Contents/MacOS/kitty" ]] && { KITTY_APP="$candidate"; break; }
    done
fi
if [[ -z "$KITTY_APP" ]]; then
    # A Homebrew wrapper on PATH points back into the app bundle.
    wrapper="$(command -v kitty 2>/dev/null || true)"
    if [[ -n "$wrapper" ]]; then
        resolved="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$wrapper")"
        case "$resolved" in
            */kitty.app/Contents/MacOS/kitty) KITTY_APP="${resolved%/Contents/MacOS/kitty}" ;;
        esac
    fi
fi
[[ -n "$KITTY_APP" && -x "$KITTY_APP/Contents/MacOS/kitty" ]] \
    || die "kitty.app not found. Install it with:  brew install --cask kitty
       (or point this script at it with KITTY_APP=/path/to/kitty.app)"
ok "$KITTY_APP"

# --- herdr is needed at runtime, not build time ------------------------------
if command -v herdr >/dev/null 2>&1; then
    ok "herdr at $(command -v herdr)"
else
    warn "herdr is not on your PATH — install it before launching, or add its"
    warn "directory to $CONFIG_DIR/launcher.env"
fi

# --- icon --------------------------------------------------------------------
step "Building the icon"
ICNS="$REPO/build/herdr.icns"
python3 "$REPO/tools/make-icon.py" --source "$ICON_SOURCE" --out "$ICNS" ${MASK_ARG[@]+"${MASK_ARG[@]}"}

# --- assemble the bundle -----------------------------------------------------
APP="$PREFIX/herdr.app"
step "Assembling $APP"
mkdir -p "$PREFIX"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

install -m 0644 "$REPO/src/Info.plist" "$APP/Contents/Info.plist"
install -m 0755 "$REPO/src/herdr-launch" "$APP/Contents/MacOS/herdr-launch"
install -m 0644 "$ICNS" "$APP/Contents/Resources/herdr.icns"

# Only the small kitty launcher is a real copy; everything heavy is symlinked
# into kitty.app, so the bundle stays ~1 MB instead of ~157 MB and picks up
# kitty's resources after an upgrade automatically.
cp -f "$KITTY_APP/Contents/MacOS/kitty" "$APP/Contents/MacOS/kitty"
ln -s "$KITTY_APP/Contents/MacOS/kitten" "$APP/Contents/MacOS/kitten"
ln -s "$KITTY_APP/Contents/Frameworks"   "$APP/Contents/Frameworks"
for resource in Python kitty Assets.car cacert.pem doc man terminfo kitty.icns; do
    [[ -e "$KITTY_APP/Contents/Resources/$resource" ]] \
        && ln -s "$KITTY_APP/Contents/Resources/$resource" "$APP/Contents/Resources/$resource"
done

printf '%s' "$KITTY_APP" > "$APP/Contents/Resources/.kitty-path"
/usr/bin/shasum -a 256 "$KITTY_APP/Contents/MacOS/kitty" | cut -d' ' -f1 | tr -d '\n' \
    > "$APP/Contents/Resources/.kitty-source-sha"
ok "bundle assembled ($(du -sh "$APP" | cut -f1))"

# Ad-hoc signature, flat on purpose: --deep chokes on the symlinks that point
# out of the bundle. A locally built app is not quarantined, so this is enough.
codesign --force --sign - "$APP" >/dev/null 2>&1 && ok "ad-hoc signed" || warn "codesign failed (harmless)"

# --- kitty profile -----------------------------------------------------------
step "Installing the kitty profile"
mkdir -p "$CONFIG_DIR"
if [[ -e "$CONFIG_DIR/kitty.conf" && $FORCE -eq 0 ]]; then
    warn "$CONFIG_DIR/kitty.conf exists — keeping it (use --force to replace)"
else
    install -m 0644 "$REPO/src/kitty.conf" "$CONFIG_DIR/kitty.conf"
    ok "$CONFIG_DIR/kitty.conf"
fi
[[ -e "$CONFIG_DIR/launcher.env" ]] \
    || { install -m 0644 "$REPO/src/launcher.env.example" "$CONFIG_DIR/launcher.env"; \
         ok "$CONFIG_DIR/launcher.env (from example)"; }

# --- register ----------------------------------------------------------------
touch "$APP"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[[ -x "$LSREG" ]] && "$LSREG" -f "$APP" >/dev/null 2>&1 || true

step "Done"
echo "    Launch it from Finder, Spotlight or Launchpad, or run:"
echo "        open -a \"$APP\""
echo "    Drag it to the Dock to keep it there."
