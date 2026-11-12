#!/bin/zsh
# Aufnahmen für das Handbuch (docs/plan.md, Handbuch, 3), am Demo-Projekt von
# scripts/handbook-demo.sh: jede Seite und jeder Reiter des Projektfensters, dazu einige Szenen
# (das leere Fenster „Projekte“, die Übernahme-Frage, „Neues Projekt“, die laufende Vorschau).
#
#   scripts/handbook-shots.sh [--lang de|en] [--theme light|dark] [--only <name,name>] [--out <ordner>]
#
# Ohne Angaben: beide Sprachen, hell, alles, nach <vault>/assets/screenshots/<lang>/<name>-hell.png
# (1440 px breit; dunkel: -dunkel). Danach läuft scripts/handbook-private.swift über die neuen
# Bilder; ein Fund endet mit Exit 1. Bewegt Maus und Tastatur: währenddessen nicht am Mac arbeiten.
#
# Navigiert wird sprachunabhängig: Seiten über ihre Position in der Seitenleiste (die Zeilen geben
# ihre Kennung nicht an die Bedienungshilfen weiter), Reiter über ihre Position im Segment.
set -eu
ROOT=${0:A:h:h}
APP=${QH_APP:-$ROOT/build/DerivedData/Build/Products/Debug/QuartzHub.app}
VAULT=${QH_HANDBOOK_VAULT:-$HOME/Obsidian/QuartzProjekte/QuartzHub-Handbuch}
DEMO=/Users/Shared/QuartzHub-Demo
PROJECT=$DEMO/QuartzProjekte/QuartzHub-Docs
OUT=$VAULT/assets/screenshots
LANGS=(de en); THEMES=(light); ONLY=""
while [ $# -gt 0 ]; do
  case $1 in
    --lang) LANGS=($2); shift 2 ;;
    --theme) THEMES=($2); shift 2 ;;
    --only) ONLY=",$2,"; shift 2 ;;
    --out) OUT=$2; shift 2 ;;
    *) echo "unbekannt: $1" >&2; exit 2 ;;
  esac
done
[ -d "$PROJECT" ] || { echo "Erst scripts/handbook-demo.sh" >&2; exit 1; }

# name | Zeile der Seitenleiste | Reiter (Position, leer = keiner)
# Zeilen: 1 Übersicht, 3 Konfiguration, 4 Plugins, 6 Layout, 7 Stile, 8 Vorlagen, 10 Vorschau & Build,
# 11 Git-Sync, 12 Dokumente, 13 Veröffentlichen, 15 Updates, 16 Snapshots (2, 5, 9, 14: Gruppen).
PAGES=(
  "uebersicht|1|"
  "konfiguration|3|1" "konfiguration-uebersetzungen|3|2"
  "plugins|4|1" "plugins-navigationen|4|2" "plugins-zusaetzliche-inhalte|4|3"
  "plugins-mehrsprachigkeit|4|4" "plugins-formulare|4|5" "plugins-marktplatz|4|6"
  "layout-uebersicht|6|1" "layout-komponenten|6|2" "layout-frames|6|3"
  "stile-basis|7|1" "stile-themes|7|2" "stile-variablen|7|3" "stile-css|7|4"
  "vorlagen|8|"
  "vorschau-und-build|10|" "git-sync|11|" "dokumente|12|" "veroeffentlichen|13|"
  "updates|15|" "snapshots|16|"
)
SCENES=(projekte-leer uebernahme projekte neues-projekt vorschau-und-build-laeuft)

wanted() { [ -z "$ONLY" ] || [[ $ONLY == *",$1,"* ]]; }

winid() {
  # The largest of QuartzHub's windows: the project window when one is open, else Projects.
  swift - <<'SWIFT'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
let own = list.filter { ($0[kCGWindowOwnerName as String] as? String) == "QuartzHub" && ($0[kCGWindowLayer as String] as? Int) == 0 }
let area = { (w: [String: Any]) -> Double in let b = w[kCGWindowBounds as String] as! [String: Double]; return b["Width"]! * b["Height"]! }
if let w = own.max(by: { area($0) < area($1) }) { print(w[kCGWindowNumber as String]!) }
SWIFT
}

ax() { osascript -e "tell application \"System Events\" to tell process \"QuartzHub\"
 set frontmost to true
 $1
end tell" >/dev/null; }
key() { ax "keystroke \"$1\" using command down"; }
escape() { ax "key code 53"; }

# The project window: any but the Projects window, whose title is "Projekte" or "Projects".
project_window='(first window whose name is not "Projekte" and name is not "Projects")'

page() {
  ax "set selected of row $1 of outline 1 of scroll area 1 of group 1 of splitter group 1 of group 1 of $project_window to true"
}

tab() {
  # The tabs' segmented control is the window's only radio group, a few groups deep.
  ax "set w to $project_window
 set els to entire contents of w
 repeat with e in els
  try
   if role of e is \"AXRadioGroup\" then
    click radio button $1 of e
    exit repeat
   end if
  end try
 end repeat"
}

# launch <lang> <profile> <windows to wait for> [more arguments]
launch() {
  local lang=$1 profile=$2 windows=$3; shift 3
  pkill -x QuartzHub 2>/dev/null || true
  sleep 2
  open -n "$APP" --args -QHLanguage "$lang" -ApplePersistenceIgnoreState YES -QHProfileDir "$profile" \
    -QHNoUpdateCheck YES -QHMemorySecrets YES -QHWindowSize 1440x900 "$@"
  # Adding the project runs node once (its frames' paths); its window comes after that.
  for i in {1..40}; do
    sleep 1
    osascript -e 'tell application "System Events" to tell process "QuartzHub" to count windows' 2>/dev/null | grep -q "^[$windows-9]" && break
  done
  sleep 3
}

with_project() { launch $1 "$DEMO/profile-$2" 2 -QHMigrationSource "" -QHOpenProject "$PROJECT"; ax "perform action \"AXRaise\" of $project_window"; }

# An empty profile in the given theme, made again for every use: the question at the first start
# would otherwise not come back.
empty_profile() {
  local p="$DEMO/profile-empty-$1"
  rm -rf "$p"; mkdir -p "$p"
  printf '{\n  "theme": "%s"\n}\n' "$1" > "$p/settings.json"
  echo "$p"
}

new=()
shoot() {
  local file="$OUT/$lang/$1-$suffix.png"
  screencapture -o -x -l "$(winid)" "$file"
  sips --resampleWidth 1440 "$file" >/dev/null
  new+=("$file")
  echo "$file"
}

for lang in $LANGS; do
  for theme in $THEMES; do
    suffix=$([ $theme = light ] && echo hell || echo dunkel)
    mkdir -p "$OUT/$lang"

    todo=0; for line in $PAGES; do wanted ${line%%|*} && todo=1; done
    if [ $todo = 1 ]; then
      with_project $lang $theme
      for line in $PAGES; do
        name=${line%%|*}; rest=${line#*|}; row=${rest%%|*}; t=${rest#*|}
        wanted $name || continue
        page $row; sleep 2
        [ -n "$t" ] && { tab $t; sleep 2; }
        shoot $name
      done
    fi

    if wanted projekte-leer; then
      launch $lang "$(empty_profile $theme)" 1 -QHMigrationSource ""
      shoot projekte-leer
    fi
    if wanted uebernahme; then
      launch $lang "$(empty_profile $theme)" 1 -QHMigrationSource "$DEMO/quartzcontrol-profile"
      sleep 2; shoot uebernahme; escape
    fi
    if wanted projekte || wanted neues-projekt; then
      launch $lang "$DEMO/profile-$theme" 1 -QHMigrationSource ""
      if wanted projekte; then shoot projekte; fi
      if wanted neues-projekt; then key n; sleep 3; shoot neues-projekt; escape; fi
    fi
    if wanted vorschau-und-build-laeuft; then
      with_project $lang $theme
      page 10; sleep 2; key r
      # Quartz builds before it serves; the preview shows the site after that.
      sleep 25
      shoot vorschau-und-build-laeuft
      key .; sleep 3
    fi
  done
done
pkill -x QuartzHub 2>/dev/null || true
[ ${#new} -eq 0 ] && exit 0
swift "$ROOT/scripts/handbook-private.swift" "$VAULT" $new
