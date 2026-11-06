#!/bin/sh
# Baut QuartzHub.app (Release, arm64) mit allem, was mitreist, und eine DMG daraus.
#
#   scripts/package.sh [ausgabeordner]      # Vorgabe: build/package
#
# Ein Bau, dem etwas fehlt, bricht ab, statt zu warnen (docs/conventions.md): Fehlen Runtime/node,
# Runtime/git oder die Helfer, endet das Skript mit dem Schritt, der sie holt.
# Signiert wird ad hoc wie bei QuartzControl: innen nach außen, ohne Team und ohne Notarisierung.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/package}"
cd "$ROOT"

[ -x Runtime/node/bin/node ] || { echo "Runtime/node fehlt: scripts/fetch-runtime.sh" >&2; exit 1; }
[ -x Runtime/git/bin/git ] || { echo "Runtime/git fehlt: scripts/fetch-runtime.sh" >&2; exit 1; }
scripts/build-helpers.sh 2>/dev/null
for h in yaml-edit dts-schema sass-check; do
  [ -f "Helpers/dist/$h.cjs" ] || { echo "Helpers/dist/$h.cjs fehlt nach dem Bau" >&2; exit 1; }
done

scripts/xcodegen.sh
xcodebuild -project QuartzHub.xcodeproj -scheme QuartzHub -configuration Release \
  -derivedDataPath build/DerivedData -quiet build
BUILT="build/DerivedData/Build/Products/Release/QuartzHub.app"

rm -rf "$OUT"
mkdir -p "$OUT"
APP="$OUT/QuartzHub.app"
cp -R "$BUILT" "$APP"
RES="$APP/Contents/Resources"
# -R keeps npm's and npx's relative symlinks in node/bin.
cp -R Runtime/node "$RES/node"
cp -R Runtime/git "$RES/git"
rm -f "$RES/node/.version" "$RES/git/.version" "$RES/node/CHANGELOG.md" "$RES/node/README.md"
mkdir -p "$RES/helpers" "$RES/licenses"
cp Helpers/dist/*.cjs "$RES/helpers/"
cp Resources/licenses/* "$RES/licenses/"
mv "$RES/node/LICENSE" "$RES/licenses/node-LICENSE.txt"
cp LICENSE "$RES/licenses/QuartzHub-LICENSE.txt"

# Inner Mach-O files first, then the bundle. `file` decides, not the executable bit: git-core has
# shell scripts with +x that codesign would refuse.
find "$RES/node" "$RES/git" -type f -perm +111 | while read -r f; do
  if file -b "$f" | grep -q '^Mach-O'; then codesign --force --sign - "$f" 2>&1 | grep -v 'replacing existing signature' >&2 || true; fi
done
codesign --force --sign - "$APP" 2>&1 | grep -v 'replacing existing signature' >&2 || true
codesign --verify --deep --strict "$APP"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$OUT/QuartzHub-$VERSION-arm64.dmg"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "QuartzHub" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"
rm -rf "$STAGE"
echo "App: $(du -sh "$APP" | cut -f1)  DMG: $(du -h "$DMG" | cut -f1)  ($DMG)"
