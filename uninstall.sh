#!/bin/bash
# Remove herdr.app and, optionally, its kitty profile.
set -euo pipefail

PREFIX="$HOME/Applications"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/herdr-kitty"
PURGE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        --purge)  PURGE=1; shift ;;
        -h|--help)
            echo "Usage: ./uninstall.sh [--prefix DIR] [--purge]"
            echo "  --purge  also delete $CONFIG_DIR (your kitty profile and launcher.env)"
            exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

APP="$PREFIX/herdr.app"
if [[ -d "$APP" ]]; then
    rm -rf "$APP"
    echo "removed $APP"
else
    echo "nothing to remove at $APP"
fi

if [[ $PURGE -eq 1 ]]; then
    rm -rf "$CONFIG_DIR"
    echo "removed $CONFIG_DIR"
else
    echo "kept $CONFIG_DIR (use --purge to remove it)"
fi

echo "kitty itself was never modified and is untouched."
