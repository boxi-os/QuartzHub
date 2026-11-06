#!/bin/sh
# Holt, was mit QuartzHub reist und nicht im Repo liegt: Node (für Quartz, npm und die Helfer) und
# git. Beide gepinnt, beide mit SHA-256 aus diesem Skript, nicht aus einer Datei neben dem Download:
# Eine Prüfsumme vom selben Server beweist nur, dass die Übertragung heil war.
#
#   scripts/fetch-runtime.sh          # nach Runtime/node und Runtime/git
#
# Node: offizielles darwin-arm64 von nodejs.org. npm reist im Tarball mit (lib/node_modules/npm)
# und ist damit über die Node-Fassung gepinnt; QuartzControl brauchte ein eigenes npm nur, weil
# Electron keines hat. Gemessen im Spike mit 24.18.1 (docs/decisions/native-macos-spike.md).
#
# git: dugite-native wie in QuartzControl (scripts/fetch-git.mjs, dort steht, warum überhaupt ein
# git mitreist und warum genau diese Teile wegfallen). Dieselbe Ausdünnung, hier für darwin-arm64.
#
# Anheben: Version und Prüfsumme gemeinsam ändern (Node: SHASUMS256.txt des Release, git: das
# .sha256-Asset des Release, beide einmal von Hand gegengelesen).
set -eu

NODE_VERSION=24.22.2
NODE_SHA256=1f5ac075be50bed4780ea3be19a007fda95ea4d527d28d76d0b91de47d915115
GIT_VERSION=2.53.0
GIT_BUILD=6981a1f
GIT_SHA256=7786cbf4874561b33a23faebb82bba0e8e9d1a26f1989722877fcc3d0376cebe

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="$ROOT/.tools/downloads"
mkdir -p "$CACHE"

fetch() { # url file sha
  if [ ! -f "$CACHE/$2" ]; then
    echo "[runtime] lade $2" >&2
    curl -fsSL -o "$CACHE/$2.part" "$1"
    mv "$CACHE/$2.part" "$CACHE/$2"
  fi
  actual="$(shasum -a 256 "$CACHE/$2" | cut -d' ' -f1)"
  if [ "$actual" != "$3" ]; then
    rm -f "$CACHE/$2"
    echo "[runtime] Prüfsumme stimmt nicht für $2: erwartet $3, gelesen $actual" >&2
    exit 1
  fi
}

# --- Node ---------------------------------------------------------------------------------------
NODE_DIR="$ROOT/Runtime/node"
if [ "$(cat "$NODE_DIR/.version" 2>/dev/null || true)" != "$NODE_VERSION" ]; then
  name="node-v$NODE_VERSION-darwin-arm64"
  fetch "https://nodejs.org/dist/v$NODE_VERSION/$name.tar.xz" "$name.tar.xz" "$NODE_SHA256"
  rm -rf "$NODE_DIR"
  mkdir -p "$NODE_DIR"
  tar xJf "$CACHE/$name.tar.xz" -C "$NODE_DIR" --strip-components 1
  # Header, Manpages und Corepack (Yarn/pnpm-Weiche) braucht zur Laufzeit niemand.
  rm -rf "$NODE_DIR/include" "$NODE_DIR/share" "$NODE_DIR/lib/node_modules/corepack" "$NODE_DIR/bin/corepack"
  "$NODE_DIR/bin/node" --version >/dev/null
  # Erst nach dem Auspacken: Ein Abbruch mittendrin gilt nicht als fertig.
  echo "$NODE_VERSION" > "$NODE_DIR/.version"
fi
echo "[runtime] node $("$NODE_DIR/bin/node" --version), npm $("$NODE_DIR/bin/node" "$NODE_DIR/lib/node_modules/npm/bin/npm-cli.js" --version), $(du -sh "$NODE_DIR" | cut -f1)"

# --- git ----------------------------------------------------------------------------------------
GIT_DIR="$ROOT/Runtime/git"
if [ "$(cat "$GIT_DIR/.version" 2>/dev/null || true)" != "v$GIT_VERSION" ]; then
  name="dugite-native-v$GIT_VERSION-$GIT_BUILD-macOS-arm64.tar.gz"
  fetch "https://github.com/desktop/dugite-native/releases/download/v$GIT_VERSION/$name" "$name" "$GIT_SHA256"
  rm -rf "$GIT_DIR"
  mkdir -p "$GIT_DIR"
  tar xzf "$CACHE/$name" -C "$GIT_DIR"
  core="$GIT_DIR/libexec/git-core"
  # Git Credential Manager samt .NET (Zugangsdaten gehen über GIT_ASKPASS) und git-lfs.
  find "$core" -maxdepth 1 \( -name '*.dll' -o -name '*.dylib' -o -name '*.so' -o -name '*.pdb' \
    -o -name '*.json' -o -name 'git-credential-manager*' -o -name 'git-lfs' \) -exec rm -rf {} +
  rm -rf "$GIT_DIR/share/locale" "$GIT_DIR/share/gitweb"
  [ -x "$GIT_DIR/bin/git" ] || { echo "[runtime] nach dem Ausdünnen fehlt bin/git" >&2; exit 1; }
  echo "v$GIT_VERSION" > "$GIT_DIR/.version"
fi
echo "[runtime] $("$GIT_DIR/bin/git" --version), $(du -sh "$GIT_DIR" | cut -f1)"
