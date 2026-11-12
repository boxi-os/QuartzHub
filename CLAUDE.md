# CLAUDE.md

Anweisungen für Claude Code in diesem Repository.

## Was das ist

**QuartzHub** ist die native macOS-Nachfolgerin von QuartzControl (Electron, Wartung seit 1.3.0,
Repo `~/Development/QuartzControl`): eine App, die [Quartz 5](https://quartz.jzhao.xyz/)-Projekte
verwaltet, Logik und Oberfläche in Swift. Node reist nur für Quartz mit und für drei kurze
Helfer-Skripte (YAML-Roundtrip, Plugin-Optionen aus `.d.ts`, SCSS-Prüfung mit dem Sass des Projekts). macOS 26+, nur Apple Silicon,
GPL-3.0-or-later, Bundle-ID `io.github.boxios.quartzhub`. Erstes Release erst bei Gleichstand mit
QuartzControl 1.3.

Der Plan in Phasen steht in [`docs/plan.md`](docs/plan.md), der Stand unten. **QuartzControl ist
die Spezifikation:** Wer einen Dienst oder eine Seite portiert, liest zuerst die TS-Datei und ihren
Abschnitt in `../QuartzControl/docs/decisions/`. Die Messungen und Ränder dort sind die Testfälle.

## Aufbau

- `App/` — SwiftUI-App (`QuartzHub`). `Projects/` das Fenster „Projekte“; `Shell/` Projektfenster, Sidebar, Menübefehle; `Components/`
  Bausteine (`PageScaffold` mit Inspektor); `Pages/` eine Datei oder ein Ordner je Seite.
- `Packages/QuartzHubCore/` — SwiftPM-Paket mit der ganzen Logik ohne UI, dazu `qh-check`
  (Prüfungen, Nachfolger der `check:*`-Skripte) und `QuartzHubCoreTests` (Swift Testing). Der
  String Catalog liegt hier (`Resources/Localizable.xcstrings`), weil auch der Kern Texte hat.
- `UITests/` — XCUITest-Rauchtest (Nachfolger von `npm run smoke`).
- `Helpers/` — JS-Helfer (`yaml-edit`; `dts-schema`: `.d.ts` und Page-Type-Einstiege mit TypeScripts Parser; `sass-check`: kompiliert mit dem Sass des Projekts; `locale-edit`: Quartz' Sprachdateien mit TypeScripts Parser; `content-files`: welche Notizen Quartz baut, mit dem globby des Projekts), mit esbuild zu `.cjs` gebündelt. `sass` in `Helpers/node_modules` ist nur der Stellvertreter für die Tests (gui-tests Fassung).
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
- `Runtime/node/bin/node scripts/cdn-build.mjs <build> <kopie>`, dann `… scripts/export-pages-golden.mjs <kopie> <chrome.json>`
  und `swift run --package-path Packages/QuartzHubCore qh-check export-pages <kopie> <chrome.json>` — die Seitenskripte
  des Exports in WebKit gegen Chrome, ohne Netz; die Kopie bringt Mermaid und KaTeX' Stylesheet selbst mit (gepinnt nach `.tools/cdn/`)
- `swift run --package-path Packages/QuartzHubCore qh-check export-book <build> <ordner> [--offline] [--pdf]` — ein Build durch den
  Export (Reihenfolge, Seiten, Kapitel, Formeln und Diagramme als PNG); schreibt `content.json`, `pictures/`, `book.epub`, `book.html`,
  mit `--pdf` auch `book.pdf`. Geprüft mit QuartzControls `npm run check:export -- --files <ordner> --book <id>` (Dateien als `<id>.pdf` usw.;
  epubcheck mit `--epubcheck-ssh debian-vm:/home/boxi/epubcheck/epubcheck-5.4.0/epubcheck.jar`)
- `swift run --package-path Packages/QuartzHubCore qh-check export-document <build> <ordner> --config <quartz.config.yaml> [--formats …] [--cancel-after <s>]` —
  der Export wie „Jetzt veröffentlichen“ (Wegwerf-Projekt, Buch über die ganze Website, Ziel „Dokument“, `Deploy.run`), ohne Netz;
  die Dateien heißen `check-export.*` und gehen an dasselbe `check:export -- --files`
- `node scripts/strings.mjs add <schlüssel> --de "…" --en "…" [--comment "…"]` — neuer Text
- `scripts/handbook-demo.sh` — Demo-Projekt für die Handbuch-Aufnahmen unter `/Users/Shared/QuartzHub-Demo`
  (Kopie von QuartzHub-Web, Inhalt aus dem Vault kopiert, Profile für hell und dunkel, neutrale git-Identität)
- `scripts/handbook-shots.sh [--lang de|en] [--theme light|dark] [--only …] [--out …]` — Aufnahmen
  des Projektfensters nach `<vault>/assets/screenshots/`; bewegt Maus und Tastatur
- `swift scripts/handbook-private.swift <vault> [dateien…]` — Handbuch-Texte und, per Texterkennung,
  Aufnahmen auf Persönliches (Konto, `/Users/…`, Mails, `<vault>/private/privat.txt`, Farbprofil mit Bildschirmnamen); Exit 1 bei Fund
- `scripts/fetch-runtime.sh` — Node 24 und git nach `Runtime/` (gepinnt, SHA-256 im Skript)
- `scripts/build-helpers.sh` — JS-Helfer bauen (mit dem Node aus `Runtime/`)
- `scripts/package.sh` — Release-Bau, `.app` mit Runtime und Helfern, ad hoc signiert, DMG nach `build/package/`
- `Runtime/node/bin/node scripts/golden-fixtures.mjs` — Golden Files der Kerntests neu aus `gui-test` und
  `Example` (`.quartz-gui/*.json`, maskiert, nur Dateien in QuartzControls Form)
- `Runtime/node/bin/node scripts/config-golden.mjs` — Golden Files der Config-Tests, erzeugt von
  QuartzControls eigenem `configService.ts` (braucht `../QuartzControl` mit `node_modules`)
- `Runtime/node/bin/node scripts/{paths,duplicate,deps,plugins,marketplace,running-servers,build-output,build-last-output,server-discovery,build-activity,layout-frames,managed-styles,font-file,fonts,style-files,scss-check,variable-graph,site-fonts,snippets,inline-svg,themes,zip,locales,templates,builtin-template,snapshots,content,git,package-deps,core-update,plugin-updates,remote-path,web-url,connections,targets,deploy,git-branch,webhook,github,sftp,rsync,forms-cli,relay-probe,relay,books,export-model,site-facts,document,epub,site-copy,project-overview,output-dir,project-image-box,content-index,option-form,readme-text,navigations,site-preview,layout-boxes,multilanguage,forms-options,form-usages,css-color,variable-resolve,font-delivery,style-settings,layout-board,stage-geometry}-golden.mjs` und `scripts/vm-golden.mjs <schlüssel>` (debian-vm, dazu `QH_VM_TESTS=1 QH_VM_KEY=<schlüssel> QH_FTP_PW=… QH_VM_CERT=<test-ca>` für `DebianVMTests`, `FTPSessionTests` und `FormsRelayVMTests`) — dasselbe für
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
- [`phase-4-oberflaeche.md`](docs/decisions/phase-4-oberflaeche.md) — die Oberfläche: Fenstermodell,
  Seiten, was der UI-Test dabei lernte
- [`phase-5-gleichstand.md`](docs/decisions/phase-5-gleichstand.md) — was beim Schließen der Lücken gemessen und
  entschieden wurde
- [`ui-ueberarbeitung.md`](docs/decisions/ui-ueberarbeitung.md) — die einheitliche Oberfläche (seit 2026-11-12):
  Entscheidungen, macOS 26, Verlauf, Seitentypen, Bewegung
- `~/Development/macos-ui-leitfaden` (eigenes Repo, außerhalb von QuartzHub) — die Regeln der
  Oberfläche verallgemeinert für alle macOS-Apps des Nutzers (Regeln L1–L61, Prüfliste, Methode,
  Bausteine aus `Design.swift`). Quelle der Messungen bleiben hier `docs/conventions.md` und
  `ui-ueberarbeitung.md`; eine neue UI-Erkenntnis aus QuartzHub mit Regel und Messung dem Nutzer für
  den Leitfaden vorschlagen, dort nur auf Wunsch ändern
- [`gleichstand.md`](docs/gleichstand.md) — jede Funktion von QuartzControl 1.3 und ob QuartzHub sie hat
  und an der App gemessen ist (Phase 5)

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
  Schreiber nehmen ihren Snapshot als `SnapshotStore.Take`). Punkt 7 ist fertig: 7b `GitStatus`,
  `GitAuth`, `GitHubRemote`, `Sync`; 7c `PackageJsonDeps`, `CoreUpdate` (Stash-Name und
  Merge-Betreff sind QuartzControls Wortlaut, ein Format beider Apps), `PluginUpdates`. Danach der
  NFD-Durchgang. Punkt 8 (Veröffentlichen) läuft: 8a fertig (`Connections` mit dem Schlüsselbund, `PublishTargets`, `DeployManifests`, `Deploy` mit Ordner, Git-Branch und Webhook, `GitHubAPI`); 8b fertig (SSH über das System-OpenSSH: `SSHLogin`, `HostKeyCheck`, `SFTPChannel`, `SFTPAdapter`, `RsyncAdapter`; lokal gegen ein vom Test gestartetes sshd, dazu debian-vm); 8c fertig (FTP/FTPS über basic-ftp im Helfer `ftp-session`, `FTPAdapter`; `RelayProbe` über URLSession, `FormsCLI`, `FormsRelay`; das Relay über FTPS ist nicht auf der VM gemessen). Punkt 9 (Export) fertig am 2026-11-08: 9a (`Books`, `ExportModel` mit `ICUCollation`, `SiteFacts`, `DocumentHTML`, `BookPack`, `SiteCopy`); 9b fertig (`SiteServer`, `ExportWindow` mit `WKContentRuleList` und Zählen, Seitenskripte in WebKit gegen Chrome mit Mermaid und KaTeX über `cdn-build.mjs`, `ExportCollect`, `BookContentPrep` mit `takeSnapshot`); 9c fertig (`PDFWrite` mit Fußzeile, Lesezeichen und `/Lang` über PDFKit, `ExportBook`, `DocumentAdapter`, `qh-check export-document`); Bilder gegen einen frischen QuartzControl-Export verglichen. Punkt 9 ist fertig.
- **Phase 4 (Oberfläche) läuft.** Entscheidungen des Nutzers vom 2026-11-08 im Plan (natives
  Aussehen, Einstellungsfenster, ein Fenster „Projekte“ und eines je Projekt). 4a fertig: Fenster
  „Projekte“ mit Anlegen und Duplizieren, Projektfenster, Einstellungen, Band neben QuartzControl.
  Der Rauchtest läuft auf einem Wegwerf-Profil mit `-QHOpenProject`. 4b entschieden: Code-Editor
  NSTextView mit TextKit 2 ohne Paket, Umsortieren mit `onMove` und Befehlen (Messgeschirr in
  `docs/decisions/phase-4-harness/`). 4c läuft: Übersicht und Vorschau & Build fertig, Konfiguration (Website und Übersetzungen, dazu ⌘S und die Frage beim Verlassen); Plugins läuft (Installiert mit der Options-Form und Anordnen ▸ Nach oben/unten, Marktplatz, Navigationen mit der Vorschau `EditorPreview`, Zusätzliche Inhalte mit den Snippet-Feldern und dem Code-Editor `CodeEditor`, Mehrsprachigkeit, Formulare mit `FormUsages`, Feld-Editor, Schlüsseln, Texten und Relay über `AppDeploy`). Plugins ist damit fertig. Updates fertig (der Lauf gehört dem Projekt, nicht der Seite). Snapshots fertig (der offene Snapshot im Inspektor, der Unterschied im Sheet). Git-Sync fertig. Stile fertig: Basis, Community-Themes, Variablen, Eigenes CSS (dazu `CssColor`, `VariableResolve`, `VariableEditing`, `FontDelivery`, `StyleSettingsValues` im Kern). Layout fertig: Übersicht, Komponenten (die Bühne), Frames (dazu `LayoutBoard`, `PageTypeOverride`, `LayoutStage`, `StageGeometry`, `FrameEditing` im Kern). Vorlagen fertig (Erstellen und Anwenden, ein Modell je Projekt). Veröffentlichen fertig (Ziele, Diff, Lauf, GitHub Pages; dazu der Reiter „Zugänge“ in den Einstellungen). Dokumente fertig (Bücher, Seitenreihenfolge, Einstellungen im Inspektor); damit sind alle Seiten portiert.
- **Phase 5 (Gleichstand und Release) läuft seit 2026-11-09.** Gleichstand-Liste als Rohfassung
  (`docs/gleichstand.md`: 720 Zeilen, 680 gemessen, 36 anders, 4 fehlen, keine nur gebaut); danach Lücken schließen und messen.
  Rauchtest und Ansehen ohne Netz mit `-QHNoUpdateCheck YES` (nur Debug). Erste Review-Runde
  (`docs/REVIEW-2026-11-11.md`) abgearbeitet: alle neun Befunde und die elf Nebenbei-Punkte,
  Chronik in `docs/reviews.md`. Zweite Runde (`docs/REVIEW-2026-11-11-2.md`, die 60 Commits danach)
  abgearbeitet: 2 Mittel, 6 Niedrig, 18 nebenbei, M1 als Entscheidung (eigene Frames nicht mehr
  mit QuartzControl bauen). Quartz 5.1 unterstützt (2026-11-11): eingebaute Verarbeitung,
  `plugin doctor`, Frames mit Einstiegsmodul, Seitenleisten, Versionen und Release-Notes,
  `quartz info`, Vorlage `docs` (decisions/phase-5-gleichstand.md, Quartz 5.1).
- **UI-Überarbeitung am 2026-11-12 abgeschlossen**, aus dem Branch `ui-ueberarbeitung` in `main` (decisions/ui-ueberarbeitung.md):
  macOS 26, Titel = Ort, Verlauf statt Rückweg-Leiste, Menüs „Gehe zu“ und „Projekt“, Bausteine in
  `App/Components/Design.swift`, alle Seiten und ihre Reiter nach den vier Seitentypen, Hinweise und Fehler als `Callout` oder
  `FieldProblem`, geteilte Bereiche als `SplitPanes`, Klappgruppen als `Fold`, eigene Akzentfarbe Petrol, in Hell und Dunkel
  angesehen und vom Nutzer in Xcode ausprobiert.
- **Pfade sind Zeichenketten mit den Bytes der Platte, nie `URL`s** (NFD-Durchgang): Foundation
  zerlegt „Über“ in `URL(fileURLWithPath:)`, jedem Anhängen und jedem FileManager-Schreiber, Node
  nicht. Rechnen mit `NodePath`, anlegen mit `Posix`, eine URL von außen einmal über
  `Posix.path(url)`. `PathHygieneTests` verbietet die zerlegenden Formen in `Sources` und `App`.
  Tests laufen in Ordnern mit „Gärten-Ü“, maskieren mit `.literal` und vergleichen Namen nach
  UTF-8-Bytes, nicht mit `==`.
- **QuartzControl ist seit 2026-11-11 eingestellt** (1.3.0 die letzte Fassung, keine Fixes mehr;
  Anlass Quartz 5.1, decisions/phase-5-gleichstand.md). Sein Repo bleibt die Spezifikation und die
  Quelle der Übernahme; QuartzHubs Dateien bleiben in 1.3s Format, solange es keine Entscheidung
  dagegen gibt.

## Arbeitsweise

- Ein Dienst oder eine Seite pro Commit, jeweils mit Bau, `qh-check i18n` und den Tests; was
  nebenbei auffällt, wird gesammelt und genannt, nicht miterledigt.
- Code, Kommentare und Commit-Nachrichten Englisch, Nutzertexte und Doku Deutsch; jeder Nutzertext
  in beiden Sprachen im Katalog.
- Vor jedem UI-Urteil die App wirklich starten (Skill `run-app`).
- Review-Listen mit dem Skill `review-befund`.
- Skills und Einstellungen nur projektlokal unter `.claude/`.
