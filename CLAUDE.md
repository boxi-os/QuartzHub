# CLAUDE.md

Anweisungen für Claude Code in diesem Repository.

## Was das ist

**QuartzHub** ist die native macOS-Nachfolgerin von QuartzControl (Electron, Wartung seit 1.3.0,
Repo `~/Development/QuartzControl`): eine App, die [Quartz 5](https://quartz.jzhao.xyz/)-Projekte
verwaltet, Logik und Oberfläche in Swift. Node reist nur für Quartz mit und für drei kurze
Helfer-Skripte (YAML-Roundtrip, Plugin-Optionen aus `.d.ts`, SCSS-Prüfung mit dem Sass des Projekts). macOS 15+, nur Apple Silicon,
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
- `Helpers/` — JS-Helfer (`yaml-edit`; `dts-schema`: `.d.ts` und Page-Type-Einstiege mit TypeScripts Parser; `sass-check`: kompiliert mit dem Sass des Projekts; `locale-edit`: Quartz' Sprachdateien mit TypeScripts Parser), mit esbuild zu `.cjs` gebündelt. `sass` in `Helpers/node_modules` ist nur der Stellvertreter für die Tests (gui-tests Fassung).
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
- `swift run --package-path Packages/QuartzHubCore qh-check option-schema <projekt> [--plugin <name>] [--dump]` —
  wie viele Optionen je Plugin QuartzHub darstellen kann; dieselbe Tabelle wie QuartzControls
  `check:option-schema` (nur lesend; Exit 3, wenn etwas nicht lesbar war)
- `swift run --package-path Packages/QuartzHubCore qh-check inline-svg [projekt]` — der SVG-Bereiniger gegen
  WebKit, mit einem Projekt mit quartz-layout-box auch durch dessen Markdown-Kette (Exit 3 ohne)
- `node scripts/strings.mjs add <schlüssel> --de "…" --en "…" [--comment "…"]` — neuer Text
- `scripts/fetch-runtime.sh` — Node 24 und git nach `Runtime/` (gepinnt, SHA-256 im Skript)
- `scripts/build-helpers.sh` — JS-Helfer bauen (mit dem Node aus `Runtime/`)
- `scripts/package.sh` — Release-Bau, `.app` mit Runtime und Helfern, ad hoc signiert, DMG nach `build/package/`
- `Runtime/node/bin/node scripts/golden-fixtures.mjs` — Golden Files der Kerntests neu aus `gui-test` und
  `Example` (`.quartz-gui/*.json`, maskiert, nur Dateien in QuartzControls Form)
- `Runtime/node/bin/node scripts/config-golden.mjs` — Golden Files der Config-Tests, erzeugt von
  QuartzControls eigenem `configService.ts` (braucht `../QuartzControl` mit `node_modules`)
- `Runtime/node/bin/node scripts/{paths,duplicate,deps,plugins,marketplace,running-servers,build-output,server-discovery,build-activity,layout-frames,managed-styles,font-file,fonts,style-files,scss-check,variable-graph,site-fonts,snippets,inline-svg,themes,zip,locales,templates,builtin-template,snapshots,content,git}-golden.mjs` — dasselbe für
  `ProjectPaths`, `ProjectDuplicator`, `ProjectDependencies`, `PluginCommands`, `Marketplace`, die Build- und Server-Dienste, `LayoutFrames`, `StyleSheets`, `StyleFiles`, `ScssCheck`, `VariableGraph`, `SiteFonts`, `Snippets`, `InlineSvg` (dessen Skript in Chrome, über QuartzControls playwright-core), `FontFile` und `FontService`
  (`layout-frames` und `managed-styles` lesen Frames und Stylesheets von gui-test und Example, nur lesend)
- `Runtime/node/bin/node scripts/option-schema-golden.mjs [QuartzControl] [gui-test]` — Plugin-Namen,
  Normalisierer und Leser des Options-Schemas aus QuartzControls Code; liest gui-tests Plugins (nur lesend)
  und kopiert ihre package.json und `.d.ts` nach `Fixtures/option-schema/real`
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
  (`docs/decisions/phase-3-dienste.md`). Punkt 2, Projekte, ohne die Teile, die die Config
  brauchen (Projektliste, `.quartz-gui/` anlegen, Projekt-Einstellungen, Content-Ordner lesen,
  Projektbild, Anlegen); was fehlt, steht im Plan. Punkt 3 läuft: Config lesen und schreiben
  (`ConfigFile` über `yaml-edit`), dazu aus Punkt 2 `ProjectPaths` und Duplizieren, alle drei gegen
  QuartzControls eigenen Code gemessen (`scripts/*-golden.mjs`), dazu `ProjectDependencies` und
  `PluginCommands`, dann das Options-Schema (`PluginSource`, `OptionSchema`, `PluginSchemaReader`,
  `qh-check option-schema`). Zuletzt der Marktplatz (`Marketplace`). Punkt 3 ist fertig. Punkt 4 (Build und Server) ist
  fertig: `BuildService` (Build und Dev-Server), `BuildOutputGuard`, `ServerScan`,
  `RunningServersStore`, `OrphanedServers`, dazu in der App die Fragen beim Start und beim
  Beenden (`App/Shell/ServerLifecycle.swift`); was vor dem Build noch fehlt (Frames, Stile,
  Schriften), kommt mit Punkt 5. Echte Quartz-Läufe: `QH_QUARTZ_TESTS=1`; UI-Test der Fragen:
  `TEST_RUNNER_QH_SERVER_PROJECT=<Kopie von gui-test>`. Punkt 5 (Stile und Layout) ist fertig:
  Frames, verwaltete Blöcke, Schriften, Stylesheet-Dateien, SCSS-Prüfung (Helfer `sass-check`),
  Variablen-Graph, Snippets, SVG-Bereiniger (`qh-check inline-svg`), Themes; bis Punkt 8 fehlt der
  GitHub-Token. Punkt 6 (Vorlagen und Übersetzungen) ist fertig: `ZipArchive`, `LocaleFiles`
  (Helfer `locale-edit`), `TemplatePackage` (zwölf Bausteine), `BuiltinTemplate`
  (`Resources/templates/qc-basic.qtpl`). Punkt 7 läuft: 7a fertig (`SnapshotStore` mit einem Index
  je Vorgang, mit QuartzControl geteilt; `ContentBackups`, `ContentFolder.changeSource`; die
  Schreiber nehmen ihren Snapshot als `SnapshotStore.Take`). **Neue Schreiber legen Namen über
  `Posix` an, nicht über Foundation:** Foundation zerlegt „Über“ auf dem Weg zur Platte (NFD), Node
  nicht; Dateilisten in Tests nach UTF-8-Bytes vergleichen, nicht mit `==`. Die übrigen Dienste
  stellt ein eigener Durchgang nach Punkt 7 um. 7b fertig (`GitStatus`, `GitAuth`, `GitHubRemote`,
  `Sync`). Als Nächstes 7c.
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
