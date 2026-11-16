#!/bin/sh
# epubcheck mit einem Java, beides projektlokal: geholt nach .tools/java/<version> und
# .tools/epubcheck/<version>, gepinnt mit SHA-256, nie über Homebrew oder ein systemweites Java
# (CLAUDE.md „Projektlokalität“). Ersetzt epubcheck per ssh auf debian-vm.
#
#   scripts/epubcheck.sh <datei.epub> [optionen]   # = java -jar epubcheck.jar <datei.epub> …
#   scripts/epubcheck.sh --jar                     # Pfad von epubcheck.jar
#   scripts/epubcheck.sh --java-bin                # Ordner mit java, für PATH
#
# Für QuartzControls check:export (ruft `java` über PATH); erst holen, dann einsetzen, sonst
# begänne PATH nach einem gescheiterten Holen mit einem leeren Eintrag (dem aktuellen Ordner):
#   JAVA_BIN="$(scripts/epubcheck.sh --java-bin)" && PATH="$JAVA_BIN:$PATH" npm --prefix ../QuartzControl \
#     run check:export -- --files <ordner> --book <id> --epubcheck-jar "$(scripts/epubcheck.sh --jar)"
#
# Anheben: Java aus der Adoptium-API (api.adoptium.net/v3/assets/latest/21/hotspot?architecture=
# aarch64&image_type=jre&os=mac, Felder release_name und binary.package.checksum), epubcheck aus
# `gh api repos/w3c/epubcheck/releases/latest` (Feld digest der Zip).
set -eu
JAVA_RELEASE=jdk-21.0.13+9
JAVA_FILE=OpenJDK21U-jre_aarch64_mac_hotspot_21.0.13_9.tar.gz
JAVA_SHA256=225bab0a09491ef06835488cd942f5d2befa9a0410a2484f0c8bbcf7506ec09a
EPUBCHECK_VERSION=5.4.0
EPUBCHECK_SHA256=33350c61038e71dfb3d45a76aed04bf5481e6d5500cb780f6e98db8bbd15a28c

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JAVA_DIR="$ROOT/.tools/java/$JAVA_RELEASE"
JAVA_BIN="$JAVA_DIR/$JAVA_RELEASE-jre/Contents/Home/bin"
EPUBCHECK_DIR="$ROOT/.tools/epubcheck/$EPUBCHECK_VERSION"
JAR="$EPUBCHECK_DIR/epubcheck-$EPUBCHECK_VERSION/epubcheck.jar"

# Ohne Argument erst sagen, wie es geht, statt erst zu laden.
[ -n "${1:-}" ] || { echo "Aufruf: scripts/epubcheck.sh <datei.epub> [optionen] | --jar | --java-bin" >&2; exit 2; }

# fetch <name> <url> <sha256> <ziel> <auspacken> <datei im ziel>
# Ausgepackt wird neben dem Ziel und erst vollständig umbenannt: ein abgebrochenes Auspacken lag
# sonst im Ziel und galt beim nächsten Lauf als vorhanden (Review 2026-11-17, N4).
fetch() {
  mkdir -p "$ROOT/.tools"
  TMP="$(mktemp -d "$ROOT/.tools/.fetch.XXXXXX")"
  trap 'rm -rf "$TMP"' EXIT
  echo "[epubcheck] lade $1" >&2
  curl -fsSL -o "$TMP/download" "$2"
  ACTUAL="$(shasum -a 256 "$TMP/download" | cut -d' ' -f1)"
  if [ "$ACTUAL" != "$3" ]; then
    echo "[epubcheck] Prüfsumme von $1 stimmt nicht: erwartet $3, gelesen $ACTUAL" >&2
    exit 1
  fi
  mkdir "$TMP/out"
  $5 "$TMP/download" "$TMP/out"
  [ -e "$TMP/out/$6" ] || { echo "[epubcheck] $6 fehlt nach dem Auspacken von $1" >&2; exit 1; }
  rm -rf "$4"
  mkdir -p "$(dirname "$4")"
  mv "$TMP/out" "$4"
  rm -rf "$TMP"
}
untar() { tar -xzf "$1" -C "$2"; }
unzipTo() { unzip -q "$1" -d "$2"; }

if [ ! -x "$JAVA_BIN/java" ]; then
  fetch "Java $JAVA_RELEASE" \
    "https://github.com/adoptium/temurin21-binaries/releases/download/$(printf %s "$JAVA_RELEASE" | sed 's/+/%2B/')/$JAVA_FILE" \
    "$JAVA_SHA256" "$JAVA_DIR" untar "$JAVA_RELEASE-jre/Contents/Home/bin/java"
fi
if [ ! -f "$JAR" ]; then
  fetch "epubcheck $EPUBCHECK_VERSION" \
    "https://github.com/w3c/epubcheck/releases/download/v$EPUBCHECK_VERSION/epubcheck-$EPUBCHECK_VERSION.zip" \
    "$EPUBCHECK_SHA256" "$EPUBCHECK_DIR" unzipTo "epubcheck-$EPUBCHECK_VERSION/epubcheck.jar"
fi

case "${1:-}" in
  --jar) echo "$JAR" ;;
  --java-bin) echo "$JAVA_BIN" ;;
  *) exec "$JAVA_BIN/java" -jar "$JAR" "$@" ;;
esac
