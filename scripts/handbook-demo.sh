#!/bin/zsh
# Richtet das Demo-Projekt für die Aufnahmen des Handbuchs ein (docs/plan.md, Handbuch, 3).
#
#   scripts/handbook-demo.sh            # legt an oder bringt auf den Stand von Projekt und Vault
#
# Die Aufnahmen zeigen Pfade, Projektnamen und Ziele. Damit nichts Persönliches ins Handbuch kommt,
# liegt das Demo unter /Users/Shared/QuartzHub-Demo: eine Kopie des Handbuch-Projekts, der Inhalt
# eine Kopie des Vaults (kein Link, sonst stünde dessen Pfad im Bild), ohne Snapshots, Logs und
# Ziele, mit je einem Profil für hell und dunkel ohne Zugänge. Quellen: QH_HANDBOOK_PROJECT und
# QH_HANDBOOK_VAULT, sonst die Orte aus docs/plan.md.
set -eu
SRC=${QH_HANDBOOK_PROJECT:-$HOME/Documents/QuartzProjekte/QuartzHub-Web}
VAULT=${QH_HANDBOOK_VAULT:-$HOME/Obsidian/QuartzProjekte/QuartzHub-Handbuch}
DEMO=/Users/Shared/QuartzHub-Demo
P=$DEMO/QuartzProjekte/QuartzHub-Docs

[ -f "$SRC/quartz.config.yaml" ] || { echo "Kein Quartz-Projekt: $SRC" >&2; exit 1; }
[ -d "$VAULT" ] || { echo "Kein Vault: $VAULT" >&2; exit 1; }
mkdir -p "$P"

# The project without its content link, build output, snapshots, logs and targets.
rsync -a --delete --exclude /content --exclude /public --exclude /.quartz-gui/snapshots.git \
  --exclude /.quartz-gui/logs --exclude /.quartz-gui/publish-targets.json "$SRC/" "$P/"
[ -L "$P/content" ] && rm "$P/content"
rsync -a --delete --exclude .git --exclude private --exclude .obsidian --exclude .DS_Store "$VAULT/" "$P/content/"
# The own frames are named by the project's path (ProjectPaths), in the config and in Quartz's
# lock file; the copy names its own.
sed -i '' "s#$SRC/#$P/#g" "$P/quartz.config.yaml" "$P/quartz.lock.json"
# Commits from Git-Sync or a snapshot would carry the global identity into a picture.
git -C "$P" config user.name "QuartzHub Demo"
git -C "$P" config user.email "demo@example.invalid"

for theme in light dark; do
  prof="$DEMO/profile-$theme"
  mkdir -p "$prof"
  cat > "$prof/projects.json" <<JSON
[
  {
    "id": "6f1d6c1e-0000-4000-8000-000000000001",
    "name": "QuartzHub-Docs",
    "path": "$P",
    "addedAt": "2026-11-12T12:00:00.000Z",
    "lastOpenedAt": "2026-11-12T12:00:00.000Z"
  }
]
JSON
  printf '{\n  "theme": "%s"\n}\n' "$theme" > "$prof/settings.json"
  printf '[]\n' > "$prof/running-servers.json"
done
echo "Demo: $P"
