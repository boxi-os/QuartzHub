# Vor einem Release

> **Noch nie durchlaufen.** Das erste Release ist 1.0.0 (Entscheidung 2026-11-13: Gleichstand mit
> QuartzControl 1.3 erreicht, 682 Funktionen gemessen, 38 bewusst anders, keine fehlt). Wer die Liste
> durchläuft, schreibt hier oben, wann, auf welchem Commit und was ihm dabei auffiel. Ein neuer
> Handgriff kommt mit dem Anlass dazu, der ihn erzwungen hat.

Was außer `scripts/package.sh` getan werden muss, damit ein Release vollständig ist. Vorbild ist
QuartzControls `docs/release.md` (dort mit Messungen und Begründungen je Punkt), ohne das, was nur
Electron, Linux und die VMs betraf. QuartzHub ist ein Paket für eine Plattform: eine DMG für macOS 26+
auf Apple Silicon, ad hoc signiert, nicht notarisiert.

Die Reihenfolge ist die, in der die Punkte voneinander abhängen.

## 1. Die Fassungsnummer

- `project.yml`: `MARKETING_VERSION` (die Fassung, semver) und `CURRENT_PROJECT_VERSION` (Build-Nummer,
  je Release um eins höher). Danach `scripts/xcodegen.sh`.
- `README.md` und `README.de.md`: der Absatz „Stand“.

**Keine Vorabfassung als Release.** Die Update-Prüfung fragt GitHubs `releases/latest`
(`AppUpdateCheck`), und das lässt Entwürfe und Vorabfassungen aus. Ein `1.0.1-rc.1` als Prerelease
erreicht also keinen Nutzer über den Hinweis; die Nummer wird mit `SemVer.isNewer` verglichen, ein
führendes „v“ im Tag fällt weg.

## 2. Alles liegt auf `main` und ist gepusht

    git status -sb                       # nichts offen, nichts voraus
    git branch -a                        # nur main (und origin/gh-pages, der Website-Branch)

Ein Fix auf einem Branch, der nie gemergt wurde, ist keiner. Nach 1.0.0 gilt wie in QuartzControl:
Fixes für die veröffentlichte Fassung auf `fix/<major>.<minor>.x`, gemergt in die Linie danach, nie
umgekehrt.

## 3. Die Prüfungen sind grün

    swift test --package-path Packages/QuartzHubCore
    xcodebuild -project QuartzHub.xcodeproj -scheme QuartzHub -derivedDataPath build/DerivedData test
    swift run --package-path Packages/QuartzHubCore qh-check i18n
    swift run --package-path Packages/QuartzHubCore qh-check handbook

Der Rauchtest bewegt Maus und Tastatur (rund 4 min, 2026-11-14). `docs/gleichstand.md` hat keine Zeile
„fehlt“ oder „gebaut“ (die Wörter stehen nur im Kopf der Übersichtstabelle).

## 4. Die eigenen Plugins sind veröffentlicht, und die App liest gegen sie

Die Editoren der vier eigenen Plugins sind gegen eine Fassung gelesen (`readAgainst`, `sameCode` in
`LayoutBoxes.swift`, `MultilanguageOptions.swift`, `NavigationVariants.swift`, `FormsOptions.swift`);
eine andere Fassung bekommt in jeder Zeile den Hinweis, die Angaben könnten abweichen. Je Repo:

    git -C ~/Development/<plugin> fetch && git -C ~/Development/<plugin> status -sb   # nichts voraus
    git -C ~/Development/<plugin> describe --tags                                     # die gelesene Fassung

Ein Commit nach dem Tag, der nur Tests, README oder `AGENTS.md` ändert, braucht keine Fassung, solange
er gepusht ist. Eine neue Fassung mit geändertem `src` heißt: den Editor gegen sie lesen und
`readAgainst` heben, sonst `sameCode` ergänzen.

**Stand 2026-11-14:** layout-box `v0.4.2` (+2: README, Test), multilanguage `v0.3.0`, navigations
`v0.4.3` (+1), forms `v0.6.0` (+1: README); App liest 0.4.2, 0.3.0, 0.4.2 (0.4.3 gleicher Code), 0.6.0.

## 5. Die Liste der Google-Schriften ist nicht zu alt

`GoogleFontList.fetched` (heute `2026-11-05`) erscheint im Satz „Diesen Namen führt Google nicht
(Liste vom …)“; der Nutzer liest das Datum, wenn er entscheidet, ob er sich vertippt hat. Die Liste
entsteht aus QuartzControls `src/data/googleFonts.ts` (`npm run fetch:google-fonts` dort, dann
`Runtime/node/bin/node scripts/font-delivery-golden.mjs` hier). Älter als ein paar Monate: erneuern.

## 6. Das Paket entsteht und startet

    scripts/package.sh                   # build/package/QuartzHub.app und QuartzHub-<fassung>-arm64.dmg

Dann an der DMG selbst, nicht an `build/`:

- gemountet, `Info.plist` trägt die Fassung aus Punkt 1, `codesign -v` gültig;
- `Resources/licenses/` vollständig (`git-LICENSE.txt` nennt QuartzHub);
- aus dem gemounteten Abbild gestartet, mit Wegwerf-Profil
  (`--args -QHProfileDir <scratch> -QHMigrationSource ""`): das Fenster „Projekte“ sagt
  „Werkzeuge bereit“, Node und npm „in QuartzHub“; git kommt vom System, wenn es eines gibt
  (`GitRuntime.resolve`), sonst das mitgelieferte. Das mitgelieferte deshalb direkt prüfen:
  `GIT_EXEC_PATH=<app>/Contents/Resources/git/libexec/git-core <app>/Contents/Resources/git/bin/git ls-remote https://github.com/boxi-os/QuartzHub HEAD`;
- **erster Start wie beim Nutzer:** Eine heruntergeladene DMG trägt die Quarantäne; Gatekeeper
  verweigert den ersten Start, „Dennoch öffnen“ unter Systemeinstellungen ▸ Datenschutz & Sicherheit
  lässt ihn zu. So steht es im Handbuch (1.2 „Installieren und erster Start“) und in den Notizen
  (Punkt 8). Ohne Herunterladen: eine Kopie der DMG mit
  `xattr -w com.apple.quarantine "0083;$(printf %x $(date +%s));Safari;" <kopie>`, gemountet sagt
  `spctl -a -vv -t exec <mnt>/QuartzHub.app` „rejected“. Den Weg über „Dennoch öffnen“ geht einmal je
  Release ein Mensch, mit der DMG aus dem Release-Entwurf (Punkt 8).

## 7. Der Tag

Annotierter Tag auf dem Commit, der die Fassungsnummer trägt, und pushen:

    git tag -a v<fassung> -m "QuartzHub <fassung>"
    git push origin v<fassung>

## 8. Die Release-Seite

    gh release create v<fassung> build/package/QuartzHub-<fassung>-arm64.dmg --title "QuartzHub <fassung>" --notes-file <notizen> --draft

Erst als Entwurf: die DMG von der Seite herunterladen, Prüfsumme vergleichen, ersten Start (Punkt 6)
mit ihr nachgehen. Dann `gh release edit v<fassung> --draft=false`. Nie `--prerelease` (Punkt 1);
solange der Entwurf steht, sieht ihn `releases/latest` nicht. Die Notizen haben, in Englisch:

- **was neu ist** (für 1.0.0: die Nachfolgerin von QuartzControl, nativ, liest dieselben Projekte);
- **Voraussetzungen:** macOS 26 oder neuer, Apple Silicon;
- **erster Start:** nicht notarisiert, „Dennoch öffnen“ (Punkt 6) oder `xattr -dr com.apple.quarantine`;
- **neben QuartzControl:** QuartzHub übernimmt beim ersten Start Projektliste, Einstellungen und
  Zugänge aus QuartzControl, ohne dessen Dateien zu ändern; beide lesen dieselben Projekte im Format
  von 1.3;
- **Prüfsummen** als eigener Abschnitt „Checksums (SHA-256)“: `shasum -a 256 <dmg>`, nach dem
  Hochladen gegen die Datei auf der Seite gehalten.

Danach antwortet `https://api.github.com/repos/boxi-os/QuartzHub/releases/latest` mit dem Tag (vorher
404, und QuartzHub zeigt dann nichts). Ein Bau mit kleinerer Fassung zeigt im Fenster „Projekte“ den
Hinweis; ansehen lässt er sich ohne zweites Release mit `-QHAppUpdateLatest <fassung>` (nur Debug).

## 9. Das Handbuch ist online, wenn die Release-Seite steht

Das Projekt `~/Documents/QuartzProjekte/QuartzHub-Web` baut aus dem Vault
`~/Obsidian/QuartzProjekte/QuartzHub-Handbuch` (Entscheidung 2026-11-13: GitHub Pages im Repo
`boxi-os/QuartzHub` selbst, Branch `gh-pages`, nie `main`; Adresse `https://boxi-os.github.io/QuartzHub/`
= `Handbook.base`). Veröffentlicht wird über QuartzHub („Veröffentlichen“, Ziel „GitHub Pages“), erst
nach Punkt 8, denn der Download-Kasten (`quartz/static/snippets/download*.html`) zeigt auf die
Release-Seite. Danach jede Seite, auf die die App verweist, mit 200:

    grep -oE '(de|en): "[^"]*"' Packages/QuartzHubCore/Sources/QuartzHubCore/L10n/Handbook.swift \
      | sed -E 's/^(de|en): "//; s/"$//' | sort -u | while read -r p; do
        printf '%s %s\n' "$(curl -s -o /dev/null -w '%{http_code}' "https://boxi-os.github.io/QuartzHub/$p")" "/$p"
      done | grep -v '^200'

Still heißt gut (52 Adressen: 25 Seiten je Sprache und die zwei Startseiten, Stand 2026-11-14). Die Seite der Website und die Start-Seiten `/` und `/en/` dazu im Browser ansehen.
PDF und ePub des Handbuchs kommen erst, wenn QuartzControl vom Netz ist und aus den Handbüchern
entfernt (Entscheidung 2026-11-13); bis dahin hat die Website keine Download-Links auf sie.

## 10. Die Grundvorlage liegt im Vorlagen-Repo

QuartzHub holt `qc-basic.qtpl` aus `boxi-os/quartzcontrol-templates` (`BuiltinTemplate.url`, ein Tag
Cache), QuartzControl 1.3 auch. Am Release-Tag, nach Punkt 8:

- `Resources/templates/qc-basic.qtpl` dorthin kopieren (Wegwerf-Klon mit `gh repo clone`); das
  Paket trägt ein neueres `createdAt` als das alte, sonst gewinnt ein Cache;
- die README des Repos nennt QuartzHub;
- der Fußzeilen-Link der Vorlage zeigt auf QuartzHub (`parts/plugins.json`), nicht auf QuartzControl
  (seit 2026-11-14 so in `Resources/templates/qc-basic.qtpl`, ebenso der Kommentar in
  `parts/styles.json` und die Druck-Regel in `a11y.scss`; `createdBy.app` und die Marker `QuartzControl:syntax:` sind Format und bleiben);
- **die Example-Vorlage** `qc-example.qtpl` baut auf der Grundvorlage auf und wird mit ihr neu erzeugt
  (Entscheidung 2026-11-13, docs/plan.md): mit QuartzHub, „Vorlagen ▸ Erstellen“ am Example-Projekt.
  Vorher die Bausteine gegen `qc-basic` halten (Frames, Theme, Farben, Layout, Variablen, Schriften,
  Stylesheets gleich; 2026-11-14 wich nur `a11y.scss` ab, die Druck-Regel des Example kam darauf
  in `qc-basic`) und die gebaute Example-Seite auf `<br>` an jedem Zeilenende prüfen: Die Seiten sind
  bei Spalte 100 umbrochen, und Quartz 5.1 macht daraus ohne `strictLineBreaks: true` bei
  Obsidian-Markdown sichtbare Umbrüche (3.081 auf 228 Seiten). Zuletzt erzeugt 2026-11-14 für 1.0.0.

`latest.json` im selben Repo ist QuartzControls Update-Kanal, nicht QuartzHubs; ob es zum Abschalten
von QuartzControl auf QuartzHub zeigt, ist eine eigene Entscheidung.

## 11. QuartzControl nennt seine Nachfolgerin

QuartzControls `README.md` und `README.de.md` verweisen auf QuartzHub und dessen Release-Seite
(Commit in `../QuartzControl` auf `main`).
