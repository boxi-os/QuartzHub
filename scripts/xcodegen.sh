#!/bin/sh
# XcodeGen, projektlokal: geholt nach .tools/xcodegen/<version>, gepinnt mit SHA-256, nie über
# Homebrew (globale Installation, siehe CLAUDE.md „Projektlokalität“). Ohne Argumente erzeugt es
# QuartzHub.xcodeproj aus project.yml; Argumente gehen an xcodegen durch.
#
#   scripts/xcodegen.sh            # = xcodegen generate
#   scripts/xcodegen.sh --version
#
# Anheben: VERSION und SHA256 aus dem Release (gh api repos/yonaskolb/XcodeGen/releases, Feld
# digest von xcodegen.zip) eintragen.
set -eu
VERSION=2.46.0
SHA256=4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/.tools/xcodegen/$VERSION"
BIN="$DIR/xcodegen/bin/xcodegen"

if [ ! -x "$BIN" ]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  echo "[xcodegen] lade $VERSION" >&2
  curl -fsSL -o "$TMP/xcodegen.zip" "https://github.com/yonaskolb/XcodeGen/releases/download/$VERSION/xcodegen.zip"
  ACTUAL="$(shasum -a 256 "$TMP/xcodegen.zip" | cut -d' ' -f1)"
  if [ "$ACTUAL" != "$SHA256" ]; then
    echo "[xcodegen] Prüfsumme stimmt nicht: erwartet $SHA256, gelesen $ACTUAL" >&2
    exit 1
  fi
  rm -rf "$DIR"
  mkdir -p "$DIR"
  unzip -q "$TMP/xcodegen.zip" -d "$DIR"
  [ -x "$BIN" ] || { echo "[xcodegen] $BIN fehlt nach dem Auspacken" >&2; exit 1; }
fi

cd "$ROOT"
if [ "$#" -eq 0 ]; then
  exec "$BIN" generate --quiet
fi
exec "$BIN" "$@"
