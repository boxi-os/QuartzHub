# Native macOS-App: Prototyp

Gemessen am 2026-11-05 auf `spike/native-macos` (abgezweigt von `feat/1.3` bei `3d11aeff`). Die
Frage: Kann QuartzControl eine native Mac-App werden, mit derselben Funktionalität, und was
kostet und bringt das? Der Prototyp misst die drei Risiken (Logik ohne Electron, Export ohne
Chromium, Bundle) und baut zwei Seiten nach, um den Aufwand der Oberfläche zu schätzen. Er ist
kein Produkt und wird nicht gemergt.

Code: `native/sidecar/` (Node-Helfer), `native/QCNative/` (SwiftPM: App `QCNative`, Probe
`QCExportProbe`), `native/spike/make-document.ts`, `native/scripts/` (Texte, Paket).
Messgeschirr im Scratchpad der Sitzung (`drive.mjs`, `pdfinfo.mjs`, `tocpages.mjs`, `axpos.js`,
`measure.sh`); was davon trägt, steht hier mit dem Ergebnis.

### Bestand

- TypeScript: Main 26.700 Zeilen (89 Dateien), Renderer 45.700 (davon 37.900 Code ohne Leer- und
  Kommentarzeilen, Routen 22.200), shared 5.600
- 26 von 89 Main-Dateien importieren `electron`; benutzt werden `app.getPath` (21×),
  `shell.openExternal` (12×), `net.fetch` (9×), `dialog.showMessageBox` (9×), `safeStorage` (9×),
  `nativeImage.createFromPath` (4×), `BrowserWindow`, `session`, `Menu`, `screen`, `nativeTheme`
- Linux-eigener Code: 5 Dateien. Die Last von Linux ist Testen und Packen, nicht Code.

### 1. Die Dienste ohne Electron

`native/sidecar/build.mjs` bündelt `electron/main` und `shared/` mit esbuild zu einer CJS-Datei;
`electron` zeigt auf `electron-shim.ts`. `entry.ts` macht, was `prepareBeforeWindow()` in
`index.ts` macht, und ruft das unveränderte `registerIpcHandlers()`. Die Kanäle laufen als JSON
je Zeile über stdin/stdout (`rpc.ts`); `webContents.send` wird ein Event, Dialoge und `shell`
fragt der Helfer bei Swift an.

Gemessen mit `drive.mjs` (spawnt den Helfer wie die App, Wegwerf-Profil, Kopie von `gui-test`):

- **171 Kanäle** registriert, 22–27 ms nach dem Laden des Moduls; erste Antwort
  (`settings:environment`) nach 430–1070 ms
- zod-Grenze unverändert: `project:add` mit relativem Pfad wird mit dem Satz aus `mainT()`
  abgelehnt. Erst ohne `refreshMainLanguage()` im Einstieg, dann auf Deutsch: In Electron ruft
  `applyAppMenu()` sie auf, der Helfer muss es selbst tun.
- Dev-Server: `server:start` → `running` nach 13–14 s, `GET /` 200 (170.250 Bytes), 7–8
  `server:log`, 5 `server:statusChanged`, 4 `build:activityChanged`; `server:stop` → `stopped`,
  die PID ist weg (`ps`)
- **Offizielles Node 24.18.1** (dieselbe Fassung wie in Electron 43.4.1), SHA-256 gegen
  `SHASUMS256.txt` geprüft, 121 MB (xz 23 MiB), signiert mit Team-ID von Node.
  `check:runtime` als Kopie mit diesem Binary statt Electron: alle Punkte ✓, `quartz build` 475
  Dateien in 12,6 s

Was der Shim nicht kann oder nur nachbaut:

- `BrowserWindow`/`session`: Export und Vorschau-Markierung (`previewHighlight.ts`) brauchen die
  native Seite (Schritt 3)
- `nativeImage.createFromPath` (Projektbild, 3 synchrone Aufrufe): wirft. Braucht einen Umbau auf
  asynchron oder Bildarbeit in Swift.
- `net.request` über Node-`http` mit selbst verfolgten Weiterleitungen. Die Relay-Abfrage
  (`formsService.ts`) ist gegen Chromiums Verhalten gemessen (301/302/303, `Origin: null` nach einer
  Weiterleitung); der Nachbau ist **nicht** dagegen gemessen.
- `safeStorage` im Format von Chromium auf macOS (`v10`, PBKDF2-SHA1 „saltysalt“ 1003, AES-128-CBC),
  Passwort von Swift aus dem Schlüsselbund. Aus der Chromium-Quelle nachgeschrieben, **nicht** gegen
  einen echten Chiffretext von Electron gemessen: Das hieße, den Eintrag „QuartzControl Safe
  Storage“ zu lesen, und das fragt per Dialog. Ein Umzug bestehender Zugangsdaten wäre also eine
  Abfrage beim ersten Start.
- **Beenden mit laufendem Server:** Der Helfer endet mit der App, der Server läuft weiter (so
  gewollt, er hängt an Dateien). Es fehlen die Frage beim Beenden (`settleRunningServers`) und die
  Waisen-Erkennung beim Start (`promptForOrphanedServers`); gemessen: Server PID 31697 lief nach
  dem Beenden weiter und antwortete mit 200.
- Das Bündel lädt beim Start alles, auch TypeScript: Der Helfer belegt im Leerlauf 200 MB (Schritt 4).

### 2. Zwei Seiten in SwiftUI

`QCNative` (macOS 15, Swift 6): Sidebar nach `ProjectLayout.tsx` (`NAV_GROUPS`), „Vorschau &
Build“ vollständig bis auf `DiscoveredServers`, den Link „keine index.md“, den Handbuch-Link und
das Markierungsskript; „Übersicht“ mit 7 von rund 11 Kacheln. Texte aus `de.ts`/`en.ts`, beim Bau
zu JSON geflacht (2.739 Schlüssel), `{{name}}` und `_one`/`_other` wie i18next.

Gemessen an der laufenden App (Fenster-Screenshots, Klicks über Bedienungshilfen):

- Server starten, Status, PID, Log-Zeilen, Live-Vorschau in `WKWebView`, Stoppen: wie in Electron
- Vorschau zuerst weiß: Ein waagerechter `ScrollView` schlägt keine Breite vor, die WebView bekam
  0 px. Volle Breite steht jetzt außerhalb des ScrollViews.
- Übersicht mit echten Daten, auch die Netzabfrage der Updates („Update für Plugins verfügbar“)
- Ein Kanalname war falsch geschrieben (`layoutFrames:` statt `layoutFrame:`), aufgefallen erst
  zur Laufzeit. Swift kennt `ipc-contract.ts` nicht; die Typen sind abgeschrieben. Eine echte
  Portierung braucht erzeugte Kanäle und Typen.
- Die erste Pluralregel war falsch (i18next nimmt ohne `_one` den Grundschlüssel, nicht `_other`).
  `check:i18n` bräuchte eine Swift-Seite.
- Bedienungshilfen: System Events liest die SwiftUI-Buttons **ohne Namen** (`AXTitle` leer, Kinder
  ohne Wert); geklickt wurde nach Position. `npm run smoke` (Playwright gegen Electron) entfällt,
  ein Ersatz wäre XCUITest. Mit VoiceOver nicht gemessen.

Aufwand, gezählt ohne Leer- und Kommentarzeilen:

| | TSX | Swift |
|---|---:|---:|
| Vorschau & Build | 431 | 323 (ohne die vier genannten Teile) |
| Übersicht | 863 | 226 (7 Kacheln) |
| Grundgerüst (Helfer-Anbindung, Modell, Typen, Dialoge, Texte, Bausteine, Sidebar) | – | 639 |

Hochgerechnet mit rund 0,75 Swift-Zeilen je TSX-Zeile: **rund 28.000 Zeilen Swift** für die
Oberfläche. Dazu, was keine native Entsprechung hat:

- 2 Dateien mit CodeMirror (CSS/SCSS/HTML/Markdown): eine WebView-Insel mit CodeMirror oder ein
  nativer Editor mit eigener Hervorhebung
- 8 Dateien mit `@dnd-kit`: Die Tastatur-Drags nach den Regeln in `conventions.md` wären in
  SwiftUI neu zu bauen; SwiftUI hat keinen `KeyboardSensor`.
- 12 `shared/`-Module, die der Renderer importiert (`quartzPluginName`, `gridFrameCss`,
  `cssVariables` …): in Swift abschreiben widerspricht „Ein Prüfskript, das Logik der App braucht,
  lädt sie“; die Alternative ist eine Frage an den Helfer je Aufruf.

In Zeit ist das nicht geschätzt; das Maß ist die Zeilenzahl.

### 3. Der Export ohne Chromium

Dasselbe Dokument für beide Engines: `make-document.ts` ruft die echte `documentHtml()` mit 13
Seiten aus `public/` der `gui-test`-Kopie (Artikel aus den Dateien, Links zwischen den Seiten als
Anker), lokal ausgeliefert. Referenz ist Chrome über Playwright mit den Optionen, die `writePdf.ts`
an `printToPDF` gibt (`preferCSSPageSize`, `printBackground`, Outline, getaggt); `export.md` hat
Chrome und Electron für das Handbuch gleich gemessen. WebKit: `QCExportProbe`, `mediaType =
"print"`, helle Darstellung, `NSPrintOperation` in eine Datei. Gelesen mit pdf-lib und `pdftotext`.

| | Chrome | WebKit |
|---|---|---|
| Seiten | 74 | 77 |
| Format | 595×842 | 595×842 |
| Fußzeile „gui-test · 3 / 74“ | ja | **nein** |
| Lesezeichen je Ebene | 13 / 84 / 82 | **keine** |
| benannte Ziele (`/Dests`) | 249 | **0** |
| interne Links / Web-Links | 285 / 145 | 284 / 143 |
| getaggt (`/MarkInfo`, `/StructTreeRoot`) | ja | **nein** |
| Druckzeit nach dem Laden | – | 0,4 s |

- `createPDF` paginiert nicht: 5 Streifen à 658×14400 pt
- `NSPrintOperation.run()` kehrt mit einer WKWebView nicht zurück (60 s ohne Ausgabe);
  `runModal(for:)` druckt. Der Rückruf kommt auf einem eigenen Thread (Swift 6 bricht ab, bis er
  auf den Main-Thread geht), und die Operation hält ihren Delegate nicht.
- Hintergründe nur mit `preferences.shouldPrintBackgrounds = true`
- Ränder aus `@page` hält WebKit ein. Die Randfelder (`@bottom-left`, `@bottom-right`) und
  `counter(pages)` gibt es dort nicht.
- **Seitenzahlen fürs Inhaltsverzeichnis gehen trotzdem:** Die Links tragen in WebKit ein Ziel mit
  Seite. Ziele des Inhaltsverzeichnisses, Chrome 3 4 10 18 26 …, WebKit 3 4 11 19 27 … (anders
  umbrochen). Der zweite Durchgang liest dann die Links statt `/Dests`.
- Zeilen umbrechen in WebKit früher, deshalb 77 statt 74 Seiten. Ursache nicht ermittelt.
- Bild eines Elements (`capturePage` für ePub/HTML) mit `takeSnapshot`: Ein Fenster weit außerhalb
  jedes Bildschirms liefert nichts (die Aufnahme kehrt nicht zurück, Abbruch nach 90 s). Auf einem
  Bildschirm mit `alphaValue = 0` und `ignoresMouseEvents` liefert sie ein Bild mit Inhalt (ein
  `pre`, 1316×224). `scrollIntoView` wirkt unter dem Druck-Stylesheet nicht; die Ansicht muss bis
  zum Element wachsen.
- Nicht gemessen: Mermaid und KaTeX im Export, ePub aus WebKit-Aufnahmen, das Sperren fremder
  Anfragen (`WKContentRuleList` statt der Sitzungsregeln in `exportWindow.ts`).

Fußzeile und Lesezeichen ließen sich nach dem Druck mit pdf-lib oder PDFKit setzen. **Tagged PDF
nicht:** Das PDF aus 1.3 ist getaggt, eines aus WebKit wäre es nicht.

### 4. Bundle, Start, Speicher

Nativ gepackt mit `native/scripts/package.sh` (dieselben fünf `extraResources` wie
`electron-builder.yml`, ad hoc signiert, DMG UDZO); Electron ist die veröffentlichte
`QuartzControl-1.2.0-arm64.dmg` (ebenfalls UDZO). Start bis zum ersten Fenster: Zeitstempel vor dem
Start, `CGWindowList` alle 50 ms. Speicher: RSS aller Prozesse der App nach 10 s Leerlauf, leeres
Profil, je zwei Läufe.

| | Electron 1.2.0 | Nativ |
|---|---:|---:|
| DMG | 150,2 MB | **67,4 MB** |
| installiert | 391 MB | **175 MB** |
| davon Laufzeit | Electron Framework 273 MB | Node 115 MB |
| davon App-Code | `app.asar` 52 MB | Helfer 14 MB + App 1,6 MB |
| Lizenzen | 19 MB (Chromium-Liste) | < 1 MB |
| Start bis Fenster | 0,73 s (erster Start 3,71 s) | **0,27 s** |
| Speicher im Leerlauf | ~525 MB (Main 240, Renderer 138, GPU 85–90, Utility 50) | **~305 MB** (App 105, Helfer 200) |

- Der Bau aus der gepackten App läuft (475 Dateien) über die Shims auf das mitgelieferte Node.
- npm setzt `process.title`; das registriert sich bei LaunchServices als
  „npm exec quartz build“, aber als **`BackgroundOnly`** (Bundle-Pfad ist das Node-Binary). Electron
  hatte hier `Foreground`, also ein Dock-Symbol (`nodeRuntime.ts`). Am Dock selbst nicht angesehen.

### Was nativ nicht gleichwertig geht

1. **Tagged PDF** (Barrierefreiheit des PDF-Exports)
2. Fußzeile und Lesezeichen des PDFs nur über Nacharbeit am fertigen PDF
3. Die Relay-Abfrage gegen Chromiums Weiterleitungsverhalten: neu zu messen
4. Tastatur-Drags und Editoren: neu zu bauen, die Regeln dazu neu zu messen
5. Der automatische UI-Test (`smoke`): neu, mit einem anderen Werkzeug

### Empfehlung

Die Messungen tragen eine native App: Die Dienste laufen unverändert unter einem Node, das Quartz
ohnehin braucht, und damit bleiben die Messungen in `decisions/` gültig. Die DMG ist weniger als
halb so groß, der Speicher sinkt um rund 40 %, der Start ist fast dreimal so schnell. Die Kosten
liegen in der Oberfläche (rund 28.000 Zeilen Swift, dazu Editoren, Drags und Tests) und im
PDF-Export (kein Tagged PDF).

- **Linux einstellen** hängt nicht davon ab und entlastet sofort.
- Wenn nativ: in Stufen, nicht in einem Wurf. Erste Stufe wäre eine native Hülle mit dem Helfer,
  die die vorhandene Oberfläche in einer WKWebView zeigt (Preload als `WKScriptMessageHandler`).
  Das bringt das kleinere Bundle und den Abschied von Linux sofort (Speicher nicht gemessen);
  Seiten wandern danach einzeln nach SwiftUI. **Diese Hülle ist nicht gemessen** und wäre der
  nächste Prototyp.
- Vor jeder Entscheidung: ob Tagged PDF verzichtbar ist.
