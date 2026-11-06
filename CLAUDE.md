# CLAUDE.md

Anweisungen für Claude Code in diesem Repository.

## Was das ist

**QuartzHub** ist die native macOS-Nachfolgerin von QuartzControl (Electron, Wartung seit 1.3.0,
Repo `~/Development/QuartzControl`): eine App, die [Quartz 5](https://quartz.jzhao.xyz/)-Projekte
verwaltet, Logik und Oberfläche in Swift. Node reist nur für Quartz mit und für zwei kurze
Helfer-Skripte (YAML-Roundtrip, Plugin-Optionen aus `.d.ts`). macOS 15+, nur Apple Silicon,
GPL-3.0-or-later, Bundle-ID `io.github.boxios.quartzhub`. Erstes Release erst bei Gleichstand mit
QuartzControl 1.3.

Der Plan in Phasen steht in [`docs/plan.md`](docs/plan.md), der Stand unten. **QuartzControl ist
die Spezifikation:** Wer einen Dienst oder eine Seite portiert, liest zuerst die TS-Datei und ihren
Abschnitt in `../QuartzControl/docs/decisions/`. Die Messungen und Ränder dort sind die Testfälle.

## Aufbau

- `App/` — SwiftUI-App (`QuartzHub`). `Shell/` Fenster, Sidebar, Menübefehle; `Components/`
  Bausteine (`PageScaffold` mit Inspektor); `Pages/` eine Datei oder ein Ordner je Seite.
- `Packages/QuartzHubCore/` — SwiftPM-Paket mit der ganzen Logik ohne UI, dazu `qh-check`
  (Prüfungen, Nachfolger der `check:*`-Skripte) und `QuartzHubCoreTests` (Swift Testing). Der
  String Catalog liegt hier (`Resources/Localizable.xcstrings`), weil auch der Kern Texte hat.
- `UITests/` — XCUITest-Rauchtest (Nachfolger von `npm run smoke`).
- `Helpers/` — JS-Helfer (`yaml-edit`, `dts-schema`), mit esbuild zu `.cjs` gebündelt.
- `Runtime/` — geholtes Node und git (nicht versioniert). `Resources/licenses/` — Lizenztexte.
- `project.yml` — Quelle des Xcode-Projekts (XcodeGen). `QuartzHub.xcodeproj` und
  `App/Info.plist` sind erzeugt und nicht versioniert.

## Befehle

Je Befehl eine Zeile; was ein Skript genau tut, steht in seinem Kopf.

- `scripts/xcodegen.sh` — Xcode-Projekt aus `project.yml` erzeugen (XcodeGen projektlokal unter
  `.tools/`, gepinnt mit SHA-256). **Nach jeder Änderung an `project.yml` und nach neuen Dateien.**
- `xcodebuild -project QuartzHub.xcodeproj -scheme QuartzHub -derivedDataPath build/DerivedData build` — Debug-Bau
- `xcodebuild … -scheme QuartzHub -derivedDataPath build/DerivedData test` — UI-Rauchtest (jede
  Seite in zwei Fenstergrößen, Inspektor, Menü, ⌃⌘I) und die Kerntests. Braucht die Erlaubnis
  für Bedienungshilfen; bewegt Maus und Tastatur, rund 1,5 min
- `swift test --package-path Packages/QuartzHubCore` — nur die Kerntests, ohne Xcode-Projekt
- `swift run --package-path Packages/QuartzHubCore qh-check i18n` — Schlüssel der Aufrufe gegen
  den Katalog, Parität de/en, Platzhalter. Exit 0 gut, 1 Befunde, 2 Aufruf falsch, 3 nicht alles geprüft
- `node scripts/strings.mjs add <schlüssel> --de "…" --en "…" [--comment "…"]` — neuer Text
- `scripts/fetch-runtime.sh` — Node 24 und git nach `Runtime/` (gepinnt, SHA-256 im Skript)
- `scripts/build-helpers.sh` — JS-Helfer bauen (mit dem Node aus `Runtime/`)
- `scripts/package.sh` — Release-Bau, `.app` mit Runtime und Helfern, ad hoc signiert, DMG nach `build/package/`
- `Runtime/node/bin/node scripts/golden-fixtures.mjs` — Golden Files der Kerntests neu aus `gui-test` und
  `Example` (`.quartz-gui/*.json`, maskiert, nur Dateien in QuartzControls Form)
- `node scripts/import-strings.mjs <QuartzControl> [--check]` — der einmalige Textimport
  (2026-11-06). Seitdem ist der Katalog die Quelle; `--check` weicht ab, sobald ein neuer Text dazukam

## Konventionen

@docs/conventions.md

**Greift die Einbindung in deiner Fassung von Claude Code nicht, lies die Datei zuerst**, vor der
ersten Änderung. Die Langfassungen der aus QuartzControl übernommenen Regeln (mit Messung und
Review) stehen dort in `../QuartzControl/docs/decisions/conventions-full.md` unter derselben
Überschrift; neue Regeln dieses Projekts mit ihrer Messung in `docs/decisions/`.

## Wo die Messungen stehen

- [`formats.md`](docs/formats.md) — jede Datei, die QuartzControl liest oder schreibt, und was
  QuartzHub damit tut
- [`native-macos-spike.md`](docs/decisions/native-macos-spike.md) — der Prototyp vom 2026-11-05
  (DMG, Start, Speicher, WebKit-Export), Messgeschirr in `native-macos-spike-harness/`
- [`phase-1-geruest.md`](docs/decisions/phase-1-geruest.md) — Gerüst: Inspektor, Texte,
  Laufzeit, Paket, UI-Test, mit allem, was beim ersten Bau anders war als gedacht
- [`phase-2-formate.md`](docs/decisions/phase-2-formate.md) — JSON wie Node, Sichten statt
  Codable, Golden Files, Übernahme samt Messung gegen Electron und am echten Profil
- [`phase-3-dienste.md`](docs/decisions/phase-3-dienste.md) — die Kern-Dienste, ein Abschnitt je
  Dienst (Prozessstarter, …)

## Stand

- **Phase 1 (Gerüst) abgeschlossen am 2026-11-06.** App mit Sidebar (Gruppen wie QuartzControl),
  jede Seite ein Platzhalter mit Inspektor; Katalog mit 2.994 übernommenen Texten; `qh-check
  i18n`; Runtime, Helfer, Paket (App 170 MB, DMG 63 MB).
- **Phase 2 (Formate, Übernahme) abgeschlossen am 2026-11-06.** `docs/formats.md` mit drei Teilen
  unter `docs/formats/`; JSON wie Node (`JSONStore`, `JSJSON`, gegen Node gemessen); Sichten auf die
  JSON-Dateien mit 13 Golden Files; Übernahme beim ersten Start (Dialog, Geheimnisse in den
  Schlüsselbund), gemessen am echten Profil und gegen Electron.
- **Phase 3 (Kern-Dienste) läuft.** Punkt 1, Grundlagen, fertig am 2026-11-06: Prozessstarter,
  PATH, Node-/git-Laufzeit und Umgebung der Kindprozesse, Log-Puffer, Sperren je Projekt
  (`docs/decisions/phase-3-dienste.md`). Als Nächstes Punkt 2, Projekte.
- QuartzControl bekommt nur noch kritische Fixes auf `fix/1.3.x`; die passieren im
  QuartzControl-Repo, nicht hier.

## Arbeitsweise

- Ein Dienst oder eine Seite pro Commit, jeweils mit Bau, `qh-check i18n` und den Tests; was
  nebenbei auffällt, wird gesammelt und genannt, nicht miterledigt.
- Code, Kommentare und Commit-Nachrichten Englisch, Nutzertexte und Doku Deutsch; jeder Nutzertext
  in beiden Sprachen im Katalog.
- Vor jedem UI-Urteil die App wirklich starten (Skill `run-app`).
- Review-Listen mit dem Skill `review-befund`.
- Skills und Einstellungen nur projektlokal unter `.claude/`.
