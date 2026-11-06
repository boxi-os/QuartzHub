# Phase 1: das Gerüst

Gebaut und gemessen am 2026-11-06 auf macOS 27.2, Xcode 27.1 (Swift 6.4), MacBook mit 1470×923 pt
nutzbarer Bildschirmfläche. Was hier steht, war entweder eine Entscheidung oder anders als erwartet.

### Inspektor statt rechter Spalten

Vorgabe des Nutzers: Statt der rechten Spalten von QuartzControl (Detail-Leiste neben Listen,
zweite Spalte der Kartenraster) arbeitet QuartzHub mit einer Inspektor-Spalte rechts. Gewählt aus
drei Varianten: **Auswahl + Seitenkontext** (nicht „nur Auswahl“, nicht „fensterweit mit
Reitern“). Umgesetzt mit SwiftUIs `.inspector(isPresented:)` in `PageScaffold`, Breite 240–440 pt,
ideal 300.

- Sichtbarkeit je Fenster in `@SceneStorage`. Gemessen im UI-Test: ausgeblendet, Seite gewechselt,
  bleibt ausgeblendet.
- **`InspectorCommands` hieß „Informationen Hide“.** In der gepackten App über System Events
  gelesen: Menü Darstellung ▸ „Informationen Hide“, ⌃⌘I. Halb deutsch, halb englisch, und nicht
  unser Wort. Ersetzt durch `InspectorCommand` (eigener `CommandGroup(after: .sidebar)`, Titel
  „Inspektor ein-/ausblenden“ je nach Zustand, gleiches Kürzel ⌃⌘I, Bindung über
  `focusedSceneValue`). Gemessen im UI-Test: Menüpunkt mit beiden Titeln, Kürzel blendet aus und ein.
- **Die Kennung an einem `Form` erreicht den Bedienungshilfe-Baum nicht.** XCUITest fand
  `inspector.pageContext` erst, als die Kennung an der Zeile (`LabeledContent`) saß. Sichtbar war
  der Inspektor die ganze Zeit (Screenshot).

### Texte: ein String Catalog, als JSON gelesen

`scripts/import-strings.mjs` liest `de.ts`, `en.ts` und `electron/main/i18n.ts` mit dem
TypeScript-Parser aus QuartzControls `node_modules` und schreibt `Localizable.xcstrings`:
**2.994 Schlüssel, 118 mit Plural, 374 aus `mainT`**. Die Kommentare über den Schlüsseln wurden zu
`comment` im Katalog.

- `L10n` liest den Katalog selbst als JSON statt über `String(localized:)`: Die Platzhalter
  bleiben benannt (`{{name}}`, wie in QuartzControl), und die Sprache ist eine Einstellung, die ohne
  Neustart wirken soll. Die Datei bleibt ein echter Katalog, den Xcode bearbeiten kann.
- **Plural:** i18next nimmt ohne `_one` den Grundschlüssel als Singular (die Falle aus dem Spike);
  der Import macht daraus die Variante `one`. Dazu kam `_zero` (`buildServer.discovery.partial`):
  i18next nimmt es bei `count === 0` in jeder Sprache, der Katalog kennt `zero` ebenso. Andere
  Endungen brechen den Import ab.
- **SwiftPM verarbeitet den Katalog auch mit `.copy`** und erzeugt Swift-Symbole für Einträge mit
  `extractionState: manual`. Zwei Schlüssel ergaben dasselbe Symbol (`snippets.placeholders.off`
  und `snippets.placeholdersOff`), der Bau brach ab. Ohne `extractionState` erzeugt `xcstringstool`
  keine Symbole; das Bundle enthält den Katalog trotzdem lesbar (Test `bundledCatalogLoads`).
- `qh-check i18n` übersprang anfangs Kommentarzeilen nicht und meldete den Beispielaufruf im
  eigenen Doc-Kommentar als fehlenden Schlüssel. Gegenprobe nach dem Fix: eine Datei mit
  `L10n.t("gibt.es.nicht")` ergibt Exit 1 mit Datei und Zeile.

### Bundle-ID

Geplant war `io.github.boxi_os.quartzhub`. Xcode warnt: In `CFBundleIdentifier` sind nur
Buchstaben, Ziffern, Bindestrich und Punkt erlaubt. QuartzControl kommt auf macOS als
`io.github.boxios.quartzcontrol` an (electron-builder filtert den Unterstrich still, siehe dort
`electron-builder.yml`). QuartzHub ist nur macOS und heißt deshalb gleich
**`io.github.boxios.quartzhub`**.

### Laufzeit und Paket

- Node **24.22.2** (LTS, 2026-10-27) statt 24.18.1 aus dem Spike: QuartzHub ist an keine
  Electron-Fassung gebunden. npm **11.19.1** kommt aus demselben Tarball; ein eigenes npm wie in
  QuartzControl braucht es nicht, ebenso keine Shims (`node`/`npm`/`npx` liegen in `node/bin`).
  Ohne `include/`, `share/` und Corepack: 147 MB (Binary 131 MB).
- git **2.53.0** aus dugite-native, ausgedünnt wie in QuartzControl: 26 MB. `git init` in leerer
  Umgebung läuft, warnt aber „templates not found in //share/git-core/templates“: Der
  Prozessstarter muss in Phase 3 die Umgebung setzen, wie `gitRuntime.ts` es tut.
- Helfer mit esbuild: `yaml-edit.cjs` 234 KB, `dts-schema.cjs` 8,6 MB (TypeScript).
  - yaml-edit gegen `gui-test/quartz.config.yaml` (64 Plugins, 15 Kommentare): denselben Wert
    setzen ergibt die Datei **byte-gleich**; einen anderen Wert setzen ändert genau eine Zeile; alle
    Kommentare bleiben. Ein Syntaxfehler kommt mit Zeile und Spalte.
  - dts-schema gegen `quartz-layout-box` und `quartz-forms` aus `gui-test/.quartz/plugins`:
    Optionen der obersten Ebene gelesen (`file, dir, html, className, …` bzw. `forms, transport,
    keys, spam, …`); ein fehlender Ordner ergibt `schema: null`, eine kaputte Anfrage `ok: false`.
    Die Abschrift ist per `diff` wortgleich mit QuartzControl. **Nicht** gemessen: die Ausgabe
    gegen QuartzControls Ergebnis für dieselben Plugins; das macht `qh-check option-schema` in
    Phase 3 mit dem Normalisierer.
- `scripts/package.sh`: App **170 MB**, DMG **63 MB** (Spike: 175 / 67,4). Aus dem Bundle in leerer
  Umgebung: `node v24.22.2`, `npm 11.19.1`, `git 2.53.0`, Helfer antwortet. Signatur ad hoc,
  `codesign --verify --deep --strict` ohne Fehler.

### UI-Rauchtest

`UITests/SmokeTests.swift`, Nachfolger von `npm run smoke`: jede der 12 Seiten in zwei
Fenstergrößen, Inspektor da; Inspektor über Button, Menü und ⌃⌘I. Lauf rund 90 s.

Wie die Fenstergröße zustande kam, war die längste Strecke:

1. Erster Lauf grün, aber ohne Prüfung der Größe. Mit Prüfung: Das Fenster war nie 560 hoch. Die
   Mindesthöhe gilt für den Inhalt, die Symbolleiste kommt dazu: **Minimum 900×612**.
2. Ziehen an der Ecke unten rechts, an der Ecke oben links, an der Symbolleiste und an den Kanten:
   **Keins davon bewegte das Fenster** unter XCUITest. Das Verkleinern hatte nur „funktioniert“,
   weil das Fenster schon in Minimalgröße öffnete.
3. `XCUIScreen.main.screenshot().image.size` liefert Pixel, nicht Punkte.
4. `.defaultSize` wirkte nicht, weil ein gespeicherter Rahmen (`NSWindow Frame …` in den Defaults
   der App, `285 152 900 612`) Vorrang hat.

Lösung: Startargument `-QHWindowSize BxH` setzt `defaultSize` und entfernt vorher die gespeicherten
Rahmen; der Test startet die App je Größe neu (900×560 und 1400×860; 1500×950 passt nicht auf
1470 pt). Gemessen: 900 und 1400 breit. So hat es auch QuartzControls Smoke gemacht (Größe per API).

### Offen für später

- Ein App-Icon fehlt (bewusst: nicht das von QuartzControl, damit beide nebeneinander unterscheidbar
  sind).
- `qh-check i18n` könnte warnen, wenn ein benutzter Schlüssel noch „QuartzControl“ sagt.
- Der Rauchtest prüft das Kürzel ⌃⌘I nur auf Deutsch.
