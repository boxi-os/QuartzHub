# Plan: QuartzHub, die native Nachfolgerin von QuartzControl

> Übernommen aus `~/.claude/plans/` am 2026-11-06, ab hier gepflegt. Stand: **Phase 0 bis 2
> abgeschlossen** (Phase 2 am 2026-11-06, `decisions/phase-2-formate.md`); Phase 3 läuft, Punkt 1
> (Grundlagen) fertig am 2026-11-06 (`decisions/phase-3-dienste.md`), Punkt 2 (Projekte) bis auf
> die Teile, die die Config brauchen; Punkt 3 (Konfiguration und Plugins) läuft, die Config ist
> fertig, ebenso die Plugin-Befehle, das Options-Schema und der Marktplatz; Punkt 4 (Build und Server) fertig; Punkt 5 (Stile und Layout) fertig; Punkt 6 (Vorlagen und Übersetzungen) fertig; als Nächstes Punkt 7 (Git, Snapshots, Updates). Abweichungen vom ursprünglichen Plan, mit Messung in
> `decisions/phase-1-geruest.md`:
>
> - Bundle-ID `io.github.boxios.quartzhub` (ohne Unterstrich: in `CFBundleIdentifier` nicht erlaubt)
> - **Inspektor statt rechter Spalten** (Vorgabe des Nutzers, 2026-11-06): jede Seite einspaltig,
>   rechts der native Inspektor mit Auswahl oder Seitenkontext; Regel in `conventions.md`
> - Node 24.22.2 mit dem npm aus demselben Tarball; keine Shims, kein eigenes npm
> - Kerntests per SwiftPM im Paket (`swift test`), im Xcode-Schema mitgezogen
> - Texte: Katalog als JSON gelesen (`L10n`), Platzhalter bleiben `{{name}}`

## Context

QuartzControl (Electron, ~78.000 Zeilen TypeScript) ist zu groß geworden, und Linux lässt sich auf
Dauer nicht sauber testen. Der Prototyp vom 2026-11-05 (`spike/native-macos`,
`docs/decisions/native-macos-spike.md`) hat gezeigt: native geht. Die DMG ist weniger als halb so
groß, der Speicher sinkt um ~40 %, der Start ist ~3× schneller. Der PDF-Export über WebKit verliert
Tagged PDF; darauf verzichtet der Nutzer.

Entscheidungen des Nutzers (2026-11-05):
- QuartzControl **1.3 erscheint noch für alle** (macOS + Linux); danach nur kritische Fixes.
- Neue App **QuartzHub**, eigener Ordner `~/Development/QuartzHub`, nur sie bekommt neue Funktionen.
- **Logik und Oberfläche in Swift.** Node reist nur für Quartz mit, dazu für drei Dinge ohne
  Swift-Ersatz als kurze Kindprozess-Skripte: YAML-Roundtrip mit Kommentaren (`yaml`),
  Plugin-Optionen aus `.d.ts` (TypeScript) und Projektcode (sass, globby, quartz-forms-CLI).
- **Kompatibel + Übernahme:** dieselben Projekte, `.quartz-gui/` im selben Format; beim ersten
  Start Übernahme von Projektliste, Einstellungen, Zugängen/Zielen samt Passwörtern.
- Verteilung über GitHub-Releases, ad hoc signiert, **macOS 15+, nur Apple Silicon**.
- **Erstes Release erst bei Gleichstand** mit QuartzControl 1.3.
- **GPL-3.0-or-later, Repo erst privat.** Tagged PDF ist verzichtbar.

## Name: QuartzHub

Geprüft am 2026-11-05: `quartzhub.app` und `quartzhub.de` sind frei (RDAP/DENIC, gegengeprüft mit
einer Unsinns-Domain), `quartzhub.com` ist vergeben. Auf GitHub gibt es ein Repo „QuartzHub“
(0 Sterne, Studenten-Community). Eine VS-Code-Erweiterung heißt „Quartz Hub“ (Echo Vision), Zweck
unklar. In der Websuche keine Marke QUARTZHUB. Haken: Es gibt viele Marken „QUARTZ“ in Klasse 9/42,
und der Name klingt nach einem offiziellen Angebot von Quartz (jackyzha0). Das galt für
„QuartzControl“ genauso. **Offen beim Nutzer:** DPMAregister und EUIPO eSearch nach „QuartzHub“
in Klasse 9/42 durchsehen. „BrainHub“ verworfen: Kollision mit Brainhub (brainhub.eu,
Softwarefirma) und einer US-Anmeldung BRAINHUB in Klasse 42.

App-ID ~~`io.github.boxi_os.quartzhub`~~ **`io.github.boxios.quartzhub`** (so heißt auch QuartzControl auf macOS: `io.github.boxios.quartzcontrol`).

---

## Phase 0 – QuartzControl 1.3 fertig machen und in Wartung schicken (Repo QuartzControl)

1. Offene 1.3-Punkte laut Memory: `check:export`, Screenshots 6.8, Push, Handbuch-Website; dann
   das Release nach `docs/release.md` (alle Plattformen).
2. Danach Linien umstellen: `fix/1.3.x` für kritische Fixes, `feat/1.3` wird nicht fortgeführt.
   `docs/release.md`, `docs/support-matrix.md` und `README` sagen „Wartung: nur kritische Fehler“.
   Den Nachfolger nennen erst, wenn QuartzHub erscheint.
3. `spike/native-macos` als Referenz committen (lokal, nicht mergen). Die Entscheidungsdatei zieht
   als erste Messung in das neue Repo um.
4. `CLAUDE.md`/Memory von QuartzControl: Hinweis auf den Wartungsmodus.

## Phase 1 – Repo und Gerüst (`~/Development/QuartzHub`)

- `git init`, privates GitHub-Repo `boxi-os/QuartzHub`, `LICENSE` GPL-3.0, README zweisprachig.
- **Xcode-Projekt aus `project.yml` (XcodeGen, versioniert)**, weil App-Bundle, Signatur und
  XCUITest ein Xcode-Projekt brauchen. Ziele:
  - `QuartzHubCore`: lokales SwiftPM-Paket, ganze Logik, keine UI
  - `QuartzHub`: SwiftUI-App
  - `QuartzHubCoreTests` (Swift Testing)
  - `QuartzHubUITests` (XCUITest, Ersatz für `npm run smoke`)
  - `qh-check`: Kommandozeile, die die `check:*`-Skripte ersetzt und dieselbe Logik aus dem Kern
    lädt (Regel „lädt statt abschreiben“)
- **Laufzeit-Ressourcen per Skript** (`scripts/fetch-runtime.sh`): offizielles Node 24.x arm64 mit
  SHA-256-Prüfung (wie im Spike), npm gepinnt, git `darwin-arm64` (Muster
  `QuartzControl/scripts/fetch-git.mjs`), Shim-Vorlage aus `resources/runtime/`.
- **JS-Helfer** unter `Helpers/` (esbuild-Bündel aus den npm-Paketen `yaml` und `typescript`):
  `yaml-edit.cjs` (parseDocument/setIn/errors) und `dts-schema.cjs`. Aufgerufen wie
  `formsService`: Kindprozess, JSON über stdin/stdout, Frist.
- **Texte:** einmaliger Import aus `QuartzControl/src/i18n/locales/{de,en}.ts` und
  `electron/main/i18n.ts` in einen String Catalog (`Localizable.xcstrings`). Platzhalter
  `{{name}}` werden zu benannten Formaten, Plurale kommen aus dem Katalog (die Plural-Falle des
  Spikes steht im Konverter als Test). `qh-check i18n` prüft Schlüssel und Parität.
- **Projektregeln:** `CLAUDE.md` und `docs/conventions.md` neu, aus QuartzControl übernommen,
  was plattformunabhängig ist (Arbeitsweise, Messen, Formate, Sprache/Vokabular, Hinweise,
  Bestätigungsdialoge). Electron-Regeln (IPC, Preload, CSP, Sandbox) entfallen, Swift-Gegenstücke
  kommen dazu. `.claude/skills/` projektlokal: `review-befund` übernehmen, `run-app` neu
  (bauen, starten, Screenshot, Bedienungshilfen).
- `scripts/package.sh` (Muster aus dem Spike `native/scripts/package.sh`) → `.app` + DMG.

## Phase 2 – Formate und Übernahme, bevor irgendetwas schreibt

- **`docs/formats.md`:** jede Datei, die QuartzControl liest oder schreibt, mit Form, Schreiber und
  Lesern.
  - Im Profil (`userData`): `projects.json`, `settings.json`, `connections.json`,
    `publish-targets.json`, `deploy-secrets.json`, `relay-secrets.json`, `theme-presets.json`,
    `window-state.json`, `dialog-state.json`, `templates/`, `theme-docs/`
  - In den Projekten (`.quartz-gui/`): `logs/`, `authored-frames/`, `content-backups/`,
    `deploy-manifest-<id>*.json`, `core-update.json`, `project-prefs.json`,
    `layout-breakpoints.json`, Snapshot-Store, `running-servers.json` u. a.
  - Im Stylesheet: die Marker in `custom.scss` und `_quartzcontrol.scss`
- **Codable-Modelle mit Golden-File-Tests** gegen echte Dateien aus Kopien von `gui-test` und
  `Example` (nie das echte Profil, nie `hinterland-history`). Schreiben über Temp-Datei, `fsync`
  und `rename` (Muster `jsonStore.ts`).
- **Übernahme beim ersten Start:**
  - Projektliste und Einstellungen kopieren
  - Zugangsdaten mit dem Chromium-Format entschlüsseln. Dafür gibt es eine Abfrage für
    „QuartzControl Safe Storage“, die Formel steht im Spike `electron-shim.ts` und wird hier zum
    ersten Mal gegen einen echten Chiffretext gemessen.
  - Je Geheimnis ein eigener Schlüsselbund-Eintrag von QuartzHub; das Original bleibt unberührt.
- **Nebeneinander-Betrieb:** QuartzControl kennt keine prozessübergreifenden Sperren. Laufen beide
  Apps (`NSRunningApplication`) oder gibt es fremde Server in `running-servers.json`, warnt
  QuartzHub, bevor es in ein Projekt schreibt. Fremde Server zählen nie als eigene Waisen.

**Stand nach Phase 2:** Golden Files und Sichten gibt es für die JSON-Dateien aus Profil und
`.quartz-gui/`. Die übrigen Formate (Stylesheet-Marker, Snapshot-Store, `.qtpl`, Locales,
`quartz-books/`) bekommen ihre Leser, Schreiber und Tests mit dem Dienst, der sie braucht, in
Phase 3; `formats.md` nennt sie. Die Warnung vor dem Schreiben bei laufendem QuartzControl kommt mit
dem ersten Schreiber (`Coexistence` ist da, die Abfrage `NSRunningApplication` in der App fehlt noch).

## Phase 3 – Kern-Dienste in Swift (`QuartzHubCore`)

Für jeden Dienst gilt: die TS-Datei und ihren Abschnitt in `docs/decisions/` als Spezifikation
lesen. Die Messungen und Ränder dort sind die Testfälle. Portieren, Tests schreiben, wo möglich
gegen QuartzControls Ergebnis auf derselben Projektkopie messen. Ein Dienst pro Commit. Reihenfolge
nach Abhängigkeit:

1. **Grundlagen**
   - Prozessstarter (Ersatz für `runCommand.ts`): `Process` mit Argumenttrennung `--`, Shell nur
     für npm/npx, Fristen; Prozessgruppen statt `tree-kill`
   - Node-Laufzeit und Shims (`nodeRuntime.ts`; `BackgroundOnly` ist im Spike gemessen) und
     git-Laufzeit (`gitRuntime.ts`)
   - PATH (`environmentService.ts`), Logs in Dateien mit Tail (`logBuffer.ts`)
   - Sperren als Actors je `realpath` (`styleLock.ts`, `projectLock.ts`), i18n für den Kern
   - **Stand 2026-11-06: fertig.** `ProcessRunner` (posix_spawn, Prozessgruppe), `HostPath`,
     `ToolEnvironment`/`GitRuntime`/`EnvironmentReport` (keine Shims), `LogBuffer`, `ProjectLock`;
     i18n für den Kern gab es seit Phase 1 (`L10n`). Das Tailen der Logs kommt mit `buildService`.
2. **Projekte:** `projectStore`, `projectOverviewService`, `projectPrefsService`, `projectPaths`
   (repoint), `duplicateService`, `createService`, `contentService`/`contentSymlink`,
   `projectIconService` (ImageIO statt `nativeImage`)
   - **Stand 2026-11-06:** fertig sind `ProjectStore`, `QuartzGuiDirectory.create` (mit der
     `.gitignore`-Zeile), `ProjectPrefsStore`, `ContentFolder` (Status, Zählen, Symlink parken),
     `ProjectIcon` (ImageIO), `ProjectCreator`. **Nach hinten gezogen, weil sie `readConfig`/
     `writeConfig` brauchen:** `projectPaths` und `duplicateService` (direkt nach `configService`
     in Punkt 3), die Übersicht (`pageTitle`/`baseUrl` aus der Config, dazu Serverstatus und
     Relay-Geheimnisse: mit Punkt 4 und 8), aus `contentService` Quelle wechseln (Snapshot, Punkt 7),
     Startseite anlegen und Formular-Verwendungen (Config, globby des Projekts als Kindprozess).
     Der echte Lauf von `ProjectCreator` gegen GitHub ist noch nicht gemessen
     (`QH_NETWORK_TESTS=1`).
3. **Konfiguration und Plugins:** `configService` über `yaml-edit.cjs`; `pluginService`
   (Quartz-CLI); `pluginSchemaService` über `dts-schema.cjs` plus Portierung von
   `shared/pluginOptionSchema.ts`; `marketplaceService`, `projectDependencies`
   - **Stand 2026-11-06:** fertig sind `ConfigFile` (über `yaml-edit`, gegen QuartzControls
     `configService.ts` in 17 Fällen byte-gleich), aus Punkt 2 nachgeholt `ProjectPaths` und
     `ProjectDuplicator` (ebenso gegen QuartzControls Code gemessen). Der Snapshot vor dem
     Speichern der Config kommt mit Punkt 7. Danach `ProjectDependencies` und `PluginCommands`
     (`pluginService`), ebenso gemessen. Dann das Options-Schema: `PluginSource`
     (`quartzPluginName`), `OptionSchema` (`pluginOptionSchema.ts`), `PluginSchemaReader`
     (`pluginSchemaService`, ein Helfer-Aufruf je Seite) und `qh-check option-schema`, das an acht
     Projekten dieselbe Tabelle schreibt wie QuartzControls `check:option-schema`. Zuletzt der
     Marktplatz (`Marketplace`), ebenso gemessen. **Punkt 3 ist damit fertig**, bis auf den Snapshot
     vor dem Speichern (Punkt 7) und den Token aus den Zugängen (Punkt 8).
4. **Build und Server:** `buildService`, `buildOutputGuard`, `serverDiscovery`,
   `runningServersStore`, Waisen-Erkennung beim Start und Frage beim Beenden (im Spike gefehlt)
   - **Stand 2026-11-06: fertig.** `ProcessRunner` (Ausgabe während des Laufs, `launch` für den
     Server), `RunningServersStore`, `BuildOutputGuard` (auch über den echten Pfad), `ServerScan`,
     `BuildService` (Build und Dev-Server), `OrphanedServers`, `stopAllServers`; in der App die
     Frage nach verwaisten Servern und die beim Beenden, im UI-Test mit echtem Quartz gemessen.
     Die Vorbereitung vor Build und Start ist eine Liste von Schritten; Frames, Stile und
     Google-Schriften trägt Punkt 5 dort ein (Nutzer, 2026-11-06). Offen: ATS für die HTTP-Probe
     im App-Bundle, gemessen mit der ersten Seite, die den Scan zeigt.
5. **Stile und Layout:**
   - `styleService` (sass aus dem Projekt als Kindprozess) und `fontService`/`fontFile`
     (Obergrenzen beim Entpacken)
   - `variableGraphService` (handgeschriebener CSS-Leser, Kaskaden-Schichten),
     `shared/gridFrameCss.ts`, `shared/cssVariables.ts`, `layoutFrameService`, `snippetService`
   - SVG-Bereiniger (`inlineSvg.ts`; Gegenprobe im HTML-Parser von WebKit)
   - Theme-Marktplatz, Presets, Style Settings
   - **Stand 2026-11-06: fertig**, in drei Teilen in einem Zug (Nutzer, 2026-11-06). 5a, was der
     Build braucht: Frames (`LayoutFrames`, `GridFrameCss`, `GroupLayouts`), verwaltete Blöcke und
     Ladereihenfolge (`StyleSheets`), Schriften (`FontFile`, `FontService`); die Vorbereitung vor
     Build und Start hat jetzt vier Schritte. 5b, die Stile-Seite: Stylesheet-Dateien und
     „Zusammenlegen“, SCSS-Prüfung mit dem Sass des Projekts über den Helfer `sass-check`,
     Variablen-Graph, Schriften der Website. 5c: Snippets, SVG-Bereiniger auf libxml2 mit
     `qh-check inline-svg` in WebKit (Variante A), Theme-Presets, Style-Settings-Schema,
     Theme-Marktplatz. Jeder Dienst gegen QuartzControls eigenen Code gemessen
     (`scripts/*-golden.mjs`, der Bereiniger in Chrome). Offen: Umstellen und Zusammenlegen lehnen
     ohne Snapshot ab bis Punkt 7; der GitHub-Token für den Theme-Marktplatz kommt mit Punkt 8;
     echte Netzläufe (Google Fonts, Theme-Marktplatz, Anlegen) fragt der Nutzer einzeln frei.
6. **Vorlagen und Übersetzungen:** `templatePackage/*` (`.qtpl`). Zip selbst geschrieben wie
   `zipArchive.ts`, Deflate über Apples Compression-Framework, Grenzen und `containedPath`.
   Dazu `localizationService`.
   - **Stand 2026-11-06: fertig**, in drei Teilen in einem Zug (Nutzer, 2026-11-06). 6a `ZipArchive`
     (Deflate über Compression, CRC-32 selbst; gegen QuartzControls `readZip`/`createZip` und drei
     fremde Leser). 6b `LocaleFiles` mit dem Helfer `locale-edit` (TypeScript 5.9.3 wie dort); ein
     Code, der kein Sprachcode ist, liest und schreibt hier nichts (QuartzControls Import ließ ihn
     durch). 6c `TemplatePackage` (alle zwölf Bausteine, Export, Dry-Run, Import, das Format vor 1)
     und `BuiltinTemplate` (`qc-basic.qtpl` aus 1.3.0 in `Resources/templates/`, dieselbe Adresse).
     Jeder Dienst gegen QuartzControls eigenen Code gemessen (`scripts/*-golden.mjs`). Offen: Der
     Import lehnt bis Punkt 7 ab (Snapshot vorher, wie dort); echte Netzläufe (Abruf der Vorlage,
     Import mit echtem `npm install`) fragt der Nutzer einzeln frei.
7. **Git, Snapshots, Updates:** `snapshotService` (eigenes Git-Repo), `gitStatusService`,
   `syncService`, `backupService`, `updateService` (Core-Update). **Vorher die Langfassung in
   `conventions-full.md` lesen.**
   - **Stand 2026-11-06:** in drei Teilen in einem Zug (Nutzer, 2026-11-06); `appUpdateService`
     kommt mit Phase 5. 7a fertig: `SnapshotStore` (ein Index je Vorgang, mit QuartzControl
     geteilt und in beide Richtungen gemessen, Aufräumen nach zehn Minuten), `ContentBackups` und
     `ContentFolder.changeSource`, die sechs wartenden Schreiber angeschlossen. Nebenbefund:
     Foundation legt Namen zerlegt (NFD) an; die neuen Schreiber gehen über `Posix`, die übrigen
     stellt ein eigener Durchgang nach Punkt 7 um (Nutzer, 2026-11-06). 7b fertig: `GitStatus`,
     `GitAuth` mit `GitHubRemote`, `Sync` (das echte `quartz sync` gegen ein lokales Bare-Repo
     gemessen; der Push zu GitHub mit Token steht als Netzlauf aus). Als Nächstes 7c.
8. **Veröffentlichen:**
   - `connectionsService` (Schlüsselbund), `publishTargetsService`, `githubService`
   - Adapter:
     - SFTP über SwiftNIO SSH (Citadel); Modus 0644, Keepalive ~60 s, Host-Keys
     - FTP/FTPS als eigener Client auf Network.framework (es gibt keine gepflegte Swift-Bibliothek)
     - rsync über `/usr/bin/rsync`. **Unter macOS 15 ist das openrsync**: Flags und Modi neu
       messen (`shared/rsyncSupport.ts`)
     - Git-Branch, Ordner, Webhook
   - Relay-Abfrage über `URLSession` mit Redirect-Delegate, gegen die in
     `publishing-and-credentials.md` gemessenen Chromium-Fälle (301/302/303, `Origin: null`). Dazu
     `formsService` (quartz-forms-CLI). Gemessen auf `debian-vm` wie bisher.
9. **Export:** WebKit-Pipeline nach dem Spike
   - `NSPrintOperation.runModal`, `shouldPrintBackgrounds`
   - unsichtbares Fenster mit Alpha 0 auf einem Bildschirm; die Ansicht wächst bis zum Element,
     weil `scrollIntoView` unter dem Druck-Stylesheet nichts tut
   - Fußzeile und Lesezeichen per PDFKit nach dem Druck; Inhaltsverzeichnis-Seitenzahlen aus den
     Zielen der Link-Annotationen
   - ePub (epubcheck), Offline-HTML; Sperrregeln über `WKContentRuleList`
   - Mermaid- und KaTeX-Fertigerkennung neu messen

## Phase 4 – Oberfläche in SwiftUI (`QuartzHub`)

- **Grundgerüst:**
  - Fenster, Sidebar-Gruppen (`ProjectLayout.tsx`), Startseite, Einstellungen, Menü mit
    Speichern-Befehl
  - Sticky-State (`@SceneStorage`), Schutz vor ungespeicherten Änderungen,
    Bestätigungsdialoge (`NSAlert`, sichere Antwort zuerst)
  - Ansagen (`AccessibilityNotification`)
- **Bausteine** nach `src/components/ui.tsx`: Card/CardHeading, Field, Segmented,
  DetailLayout/SelectableRow, LogConsole, InfoNote, HandbookLink. Jeder Button bekommt einen
  expliziten Bedienungshilfe-Namen (im Spike lieferte System Events SwiftUI-Buttons ohne Namen).
- **Seiten** in dieser Reihenfolge: Übersicht, Vorschau & Build, Konfiguration, Plugins, Updates,
  Snapshots, Git-Sync, Stile, Layout, Vorlagen, Veröffentlichen, Dokumente. Vorbild ist jeweils
  `src/routes/*`; Texte aus dem String Catalog.
- **Zwei Entscheidungen zu Beginn von Phase 4**, mit kleiner Messung:
  - Code-Editor (heute CodeMirror in 2 Dateien): STTextView mit eigener Hervorhebung oder
    TextKit 2
  - Drag & Drop mit Tastatur (heute dnd-kit in 8 Dateien) nach den Regeln in `conventions.md`
- XCUITest-Rauchtest für jede Seite in zwei Fenstergrößen. Er ersetzt `smoke.mjs` und dient
  zugleich als Screenshot-Werkzeug fürs Handbuch.

## Phase 5 – Gleichstand und erstes Release

- **Gleichstand-Liste** aus den Routen, Kanälen (`shared/ipc-contract.ts`, 171 Kanäle) und
  Handbuch-Kapiteln von QuartzControl 1.3. Abgehakt wird nur, was an der gebauten App gemessen ist.
- **Review-Runden** mit dem übernommenen Skill `review-befund`.
- **Handbuch:** Kopie des QuartzControl-Handbuchs anpassen und online stellen (Muster
  `HANDBOOK_URL`).
- `docs/release.md` für QuartzHub, DMG, GitHub-Release; das Repo öffentlich machen, wenn der
  Nutzer es will. In QuartzControls README auf den Nachfolger hinweisen.

## Verifikation (je Phase)

- Phase 0: Release-Prüfliste aus `docs/release.md`; `git cherry` über die Linien.
- Phase 1: `xcodegen` und `xcodebuild` grün, App startet, `scripts/package.sh` erzeugt eine DMG,
  `qh-check i18n` grün.
- Phase 2: Golden-File-Tests lesen und schreiben jede Datei aus `formats.md` bytegleich zurück,
  wo QuartzControl das tut. Die Übernahme ist an einer Profilkopie gemessen; QuartzControl liest
  danach dieselben Projekte ohne Fehler.
- Phase 3: Swift-Tests je Dienst. Die `check:*`-Gegenstücke in `qh-check` (runtime, plugin-names,
  option-schema, core-update, inline-svg, stylesheet-consolidation, tokens) laufen gegen dieselben
  Projektkopien wie in QuartzControl. Veröffentlichen ist auf `debian-vm` gemessen, der Export
  gegen Chrome bzw. die PDF-Werte von 1.3.
- Phase 4: XCUITest-Rauchtest, Durchklicken der gebauten App mit `run-app`, Hell und Dunkel.
- Phase 5: Gleichstand-Liste vollständig, Review-Runde ohne Befund über „Niedrig“.

## Erster Arbeitsschritt nach Freigabe

Phase 0, Punkt 1 (QuartzControl 1.3 fertigstellen). Danach Phase 1 im neuen Ordner. Das
Anlegen des privaten GitHub-Repos ist extern sichtbar und wird vorher noch einmal bestätigt.
