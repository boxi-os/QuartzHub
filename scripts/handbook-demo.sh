#!/bin/zsh
# Richtet das Demo-Projekt für die Aufnahmen des Handbuchs ein (docs/plan.md, Handbuch, 3).
#
#   scripts/handbook-demo.sh            # legt an oder bringt auf den Stand von Projekt und Vault
#
# Die Aufnahmen zeigen Pfade, Projektnamen und Ziele. Damit nichts Persönliches ins Handbuch kommt,
# liegt das Demo unter /Users/Shared/QuartzHub-Demo: eine Kopie des Handbuch-Projekts, der Inhalt
# eine Kopie des Vaults (kein Link, sonst stünde dessen Pfad im Bild), ohne Snapshots, Logs und
# Ziele, mit je einem Profil für hell und dunkel ohne Zugänge, dazu quartz-forms mit zwei Formularen
# (braucht dafür Netz). Quellen: QH_HANDBOOK_PROJECT und QH_HANDBOOK_VAULT, sonst die Orte aus
# docs/plan.md.
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
# quartz-forms for Plugins ▸ Formulare: two forms that send nothing (transport "demo", so no relay,
# no address and no secret), embedded on one page per language. From GitHub, not from a local
# clone: the plugin list shows the source, and a clone's path is personal. Needs the net.
(cd "$P" && PATH="${0:A:h:h}/Runtime/node/bin:$PATH" npx quartz plugin add github:boxi-os/quartz-forms >/dev/null)
python3 - "$P/quartz.config.yaml" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
old = "      forms: {}\n      transport:\n        kind: relay\n"
new = """      forms:
        kontakt:
          template: contact
          title:
            de: Kontakt
            en: Contact
        feedback:
          template: feedback
          title:
            de: War diese Seite hilfreich?
            en: Was this page helpful?
          pageContext: true
      transport:
        kind: demo
"""
if text.count(old) != 1:
    sys.exit("quartz-forms: its default options are not where expected")
open(path, "w", encoding="utf-8").write(text.replace(old, new))
PY
cat > "$P/content/kontakt.md" <<'MD'
---
title: Kontakt
description: Fragen und Rückmeldungen zum Handbuch.
translationKey: kontakt
form: kontakt
---

Fragen zum Handbuch oder zu QuartzHub? Dieses Formular ist eine Vorführung und sendet nichts.

```quartz-form
feedback
```
MD
cat > "$P/content/en/contact.md" <<'MD'
---
title: Contact
description: Questions and feedback on the handbook.
translationKey: kontakt
form: kontakt
---

Questions about the handbook or QuartzHub? This form is a demonstration and sends nothing.

```quartz-form
feedback
```
MD
# Commits from Git-Sync or a snapshot would carry the global identity into a picture.
git -C "$P" config user.name "QuartzHub Demo"
git -C "$P" config user.email "demo@example.invalid"
# A book and two publishing targets, so Dokumente and Veröffentlichen show something: a folder and a
# document target, both under the demo folder (nothing leaves the Mac).
mkdir -p "$P/quartz-books" "$DEMO/Ausgabe"
cat > "$P/quartz-books/handbuch.json" <<JSON
{
  "title": "QuartzHub-Handbuch",
  "subtitle": "Quartz-Websites auf dem Mac",
  "author": "QuartzHub",
  "language": "de",
  "root": "",
  "order": null,
  "excluded": [],
  "coverImage": "",
  "toc": true,
  "tagIndex": false,
  "backlinks": false,
  "outsideLinks": "site",
  "pdf": { "pageSize": "A4", "landscape": false },
  "version": 1
}
JSON
cat > "$P/.quartz-gui/publish-targets.json" <<JSON
[
  {
    "id": "6f1d6c1e-0000-4000-8000-0000000000a1",
    "name": "Testordner",
    "destination": { "type": "folder", "path": "$DEMO/Ausgabe/website", "deleteRemoved": true },
    "excludes": []
  },
  {
    "id": "6f1d6c1e-0000-4000-8000-0000000000a2",
    "name": "Handbuch als PDF und ePub",
    "destination": { "type": "document", "path": "$DEMO/Ausgabe/buch", "bookId": "handbuch", "formats": ["pdf", "epub"] },
    "excludes": []
  }
]
JSON

# The copy's state as one commit, so Git-Sync shows a project that is up to date.
git -C "$P" add -A
git -C "$P" diff --cached --quiet || git -C "$P" commit -qm "Handbuch-Demo"

# Two more rows for the Projects window: a second site (only its config, enough for the list) and
# one whose folder is gone, for the warning.
R=$DEMO/QuartzProjekte/Rezepte
mkdir -p "$R"
printf 'configuration:\n  pageTitle: Rezepte\n  baseUrl: rezepte.example.org\n' > "$R/quartz.config.yaml"
rm -rf "$DEMO/QuartzProjekte/Alte-Website"

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
  },
  {
    "id": "6f1d6c1e-0000-4000-8000-000000000002",
    "name": "Rezepte",
    "path": "$R",
    "addedAt": "2026-10-02T09:00:00.000Z",
    "lastOpenedAt": "2026-11-01T18:30:00.000Z"
  },
  {
    "id": "6f1d6c1e-0000-4000-8000-000000000003",
    "name": "Alte-Website",
    "path": "$DEMO/QuartzProjekte/Alte-Website",
    "addedAt": "2025-03-14T10:00:00.000Z",
    "lastOpenedAt": "2025-06-20T16:00:00.000Z"
  }
]
JSON
  # The folder dialogs start in the demo, so a sheet shows its path and not an empty field.
  printf '{\n  "theme": "%s",\n  "defaultProjectDirectory": "%s"\n}\n' "$theme" "$DEMO/QuartzProjekte" > "$prof/settings.json"
  printf '[]\n' > "$prof/running-servers.json"
done
# A profile of QuartzControl for the question at the first start: one project and settings, no
# connections and no secrets (so nothing asks for the keychain).
qc="$DEMO/quartzcontrol-profile"
mkdir -p "$qc"
# Only the first project: the question counts what it found.
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); json.dump(d[:1], open(sys.argv[2], "w"), indent=2)' \
  "$DEMO/profile-light/projects.json" "$qc/projects.json"
printf '{\n  "theme": "system",\n  "language": "system"\n}\n' > "$qc/settings.json"
echo "Demo: $P"
