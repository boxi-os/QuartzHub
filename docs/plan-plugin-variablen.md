# Plan: Variablen der Plugins unter Stile ▸ Variablen (2026-11-21)

Anlass: Der Nutzer wollte die Icons der Randleiste von quartz-navigations größer stellen und suchte
`--quartz-nav-rail-icon-size` unter Stile ▸ Variablen. Dort steht sie nicht: Die Seite kennt nur
Variablen, die global an `:root` stehen (`VariableGraph.rootMode`), und quartz-navigations setzt
seine an `.quartz-nav`. Entschieden (Nutzer, 2026-11-21): anzeigen **und** ändern, für die eigenen
Plugins mit Beschreibung aus ihrem Manifest, für fremde Plugins aus dem Build.

## Heute

- **Was fehlt**, gezählt in gui-test (Deklarationen in den Stylesheets der Plugins):
  quartz-navigations 67, obsidian-plugin-excalidraw 66, obsidian-flavored-markdown 13
  (Callout-Icons), quartz-fonts 9 (mit Quartz 5.2 eingebaut, `project_quartz_5_2`), quartz-forms 10,
  canvas-page 1; quartz-layout-box und quartz-multilanguage keine. Im `index.css` des Builds stehen
  73 von 230 Variablen nur an Klassen.
- **Wo ein Wert heute herkommt**, am Beispiel der Icongröße: das Plugin setzt `1.4rem` an
  `.quartz-nav` (in seinem Stylesheet), die Vorlage von gui-test `var(--tpl-icon)` an
  `.quartz-nav--rail` (`custom/plugin-navigations.scss`), wer es ändern will, schreibt heute von Hand
  `.quartz-nav.nav-menue { … }` in `custom.scss`.
- **Wie die Seite schreibt**: Block `css-vars` in `_quartzcontrol.scss`, drei Regeln an `:root`
  (beide Modi, dunkel, nur hell), `docs/formats/projekt.md` §1. Sein Leser nimmt jede
  `--name: wert;` im Block als `:root`-Wert: Regeln mit anderem Selektor können dort **nicht** hinein.

## Ziel

Unter Stile ▸ Variablen ein dritter Abschnitt **„Plugin-Variablen“**, eine Klappgruppe je Plugin
(Anzeigename aus dem Manifest). Jede Zeile wie heute: Muster für Hell und Dunkel, Name, Wert, wer ihn
setzt (Plugin, Vorlage, eigenes CSS, QuartzHub), Zurücksetzen. Im Inspektor Beschreibung (bei den
eigenen Plugins), Selektor, die Kette des Werts und die Felder zum Ändern. Die Suche der Seite findet
sie mit.

Nicht Teil davon: Werte für **eine** Instanz eines Plugins (`.nav-menue`, eine von mehreren
Navigationen). Die Seite ändert eine Variable für alle Instanzen; für eine einzelne bleibt Eigenes CSS,
und der Inspektor sagt das mit einem fertigen Schnipsel zum Kopieren.

## Teil A: Lesen

### A1. Die eigenen Plugins beschreiben ihre Variablen im Manifest

In `package.json` → `quartz` ein Schlüssel `cssVariables`, eine Liste:

```json
"cssVariables": [
  {
    "name": "quartz-nav-rail-icon-size",
    "selector": ".quartz-nav",
    "default": "1.4rem",
    "kind": "length",
    "group": "rail",
    "description": "Icons and monograms in the rail's strip.",
    "description_de": "Icons und Buchstaben in der Leiste des Randmenüs."
  }
]
```

- `kind`: `color`, `length`, `number`, `font`, `time`, `other` (für Muster und Feld im Inspektor);
  `default` darf `var(--…)` sein; `defaultDark`, wo der dunkle Modus einen eigenen Wert hat.
- Quelle der Wahrheit bleibt das Stylesheet des Plugins: ein Test im Plugin vergleicht `cssVariables`
  mit den `--quartz-*`-Deklarationen seines SCSS (keine fehlt, keine zu viel, Vorgaben gleich), wie
  heute `defaultOptions` gegen `src/options.ts`.
- quartz-navigations (67, Beschreibungen aus der README-Tabelle), quartz-forms (10). layout-box und
  multilanguage haben keine; sie bekommen nichts.
- **Beim Umsetzen prüfen:** ob `quartz plugin doctor` oder der Loader einen unbekannten
  Manifest-Schlüssel meldet (der Loader liest `PluginManifest`, `quartz/plugins/loader/types.ts`; die
  Prüfung unbekannter Schlüssel in `plugin-validation.js` gilt den Einträgen der Config). Meldet er
  etwas, kommt die Liste in eine eigene Datei des Pakets (`quartz-variables.json`).

### A2. Kern: `PluginVariables`

Neuer Dienst im Kern neben `VariableGraph`, gleiche Regeln für das Lesen von CSS (`eachRule`,
`declarations`, Zähler mit Strings und Kommentaren):

1. **Aus den Manifesten** der installierten Plugins (über die Quelle, die das Options-Schema schon
   findet, `PluginSource`): je Plugin die Liste aus A1. Braucht keinen Build.
2. **Aus dem Build**: jede Deklaration einer Variable in einer Regel, deren Selektor nicht global ist,
   mit Selektor, ob in `@layer`, ob in `@media`, und Modus (`[saved-theme="dark"] …`). Zugeordnet
   wird sie dem Plugin, in dessen Paketdateien `--<name>:` steht (für npm-Plugins steckt das CSS als
   String im `dist/`-JS); findet sich keines, steht sie unter „Ohne Plugin“ und nur, wenn kein
   Stylesheet des Projekts sie setzt. Variablen aus A1 werden mit dem Build abgeglichen, nicht doppelt
   gezeigt.
3. **Aus den Stylesheets des Projekts** (`custom/`, `imported/`, `custom.scss`): wer dieselbe
   Variable an welchem Selektor setzt; daraus „gesetzt von der Vorlage“ / „von deinem CSS“ und ob das
   stärker ist als der Wert der Seite (Spezifität, sonst Reihenfolge).

Antwort: je Plugin eine Liste `{ name, selector, light, dark, kind, description, setBy }`, dazu wie
heute `sources` (Manifest, Build). Ohne Build stehen nur die Manifest-Variablen da, mit dem Hinweis wie
heute (`styles.variables.noBuild`).

Tests: Golden File aus dem Build von gui-test (maskiert wie die anderen, `scripts/…-golden.mjs`
entfällt, weil QuartzControl das nie konnte: erwartete Werte von Hand, je Fall mit Grund); Ränder:
Variable in `@media`, nur dunkel, `var()`-Kette über eine `:root`-Variable (`--tpl-icon`), zwei
Plugins mit gleichem Präfix, Plugin ohne Manifest, kein Build.

### A3. Auflösen

`VariableResolve.Context` bekommt die Plugin-Variablen dazu; eine Kette wie
`--quartz-nav-rail-icon-size → var(--tpl-icon) → 1.1rem` löst sich über die vorhandenen `:root`-Werte
auf, das Muster einer Farbe ebenso. Kein zweiter Auflöser.

## Teil B: Ändern

### B1. Format: ein neuer verwalteter Block `plugin-vars`

In `_quartzcontrol.scss`, nach `css-vars`:

```scss
/* --- QuartzControl:managed:plugin-vars:start --- */
.quartz-nav {
  --quartz-nav-rail-icon-size: 1.5rem;
}

:root[saved-theme="dark"] .quartz-nav {
  --quartz-nav-color-icon: #8a8a8a;
}
/* --- QuartzControl:managed:plugin-vars:end --- */
```

- Eine Regel je Selektor und Modus, der Selektor wie im Manifest bzw. im Build des Plugins. „Nur
  hell“ wie bei `css-vars` mit `:root:not([saved-theme="dark"]) <selektor>`.
- **Das ist eine Erweiterung des Dateiformats von 1.3** (wie `fullWidth` in `frame.json`) und damit
  eine Entscheidung (s. u.). Gelesen in QuartzControls `writeManagedBlocks`
  (`electron/main/services/styleService.ts`): 1.3 nimmt beim Schreiben nur seine vier Blöcke heraus
  und hängt sie wieder an, alles andere bleibt als Text stehen; der neue Block überlebt also, landet
  dann vor `css-vars` (unschädlich, andere Selektoren). Nicht in `css-vars`: dessen Leser nähme jede
  Deklaration als `:root`-Wert.
- Schreiber in `StyleSheets` neben `variableOverrides`, mit Snapshot (`SnapshotStore.Take`) wie die
  anderen; `docs/formats/projekt.md` §1 bekommt den Block.

### B2. Wer gewinnt

Der Block steht nach den Stylesheets der Vorlage, ist ungelayert und hat den Selektor des Plugins:
Er gewinnt gegen das Plugin (dessen Regeln in `@layer` stehen; beim Umsetzen je Plugin nachsehen)
und gegen eine Regel der Vorlage mit gleicher Spezifität (gui-test: `.quartz-nav--rail` gegen
`.quartz-nav`, beide 0,1,0, die spätere gewinnt). **Messen**, nicht annehmen: in gui-test
`--quartz-nav-rail-icon-size` über die Seite setzen, bauen, im Browser die berechnete Größe lesen.

Setzt eine Regel des Projekts dieselbe Variable stärker (höhere Spezifität, etwa `.quartz-nav.nav-menue`
in `custom.scss`), zeigt die Seite das wie heute die Kollisionen von `css-vars`
(`styles.variables.collisionNote`): Hinweis an der Zeile und im Inspektor, mit Sprung nach Eigenes CSS.

### B3. Oberfläche

- `VariablesTab`: Abschnitt „Plugin-Variablen“ nach „Alle Theme- und Build-Variablen“, eine `Fold`
  je Plugin; Zeilen und Inspektor wie bei den anderen (`VariableRowView`, `VariableInspector`),
  erweitert um Beschreibung, Selektor, „gesetzt von“. Zustand der Gruppen in `VariablesPlace`.
- Speichern wie heute über die Seite (ein Entwurf, ⌘S, Frage beim Verlassen); `StylesModel` hält
  die Plugin-Überschreibungen neben `overrides`.
- Der Inspektor des Seitenkontexts zählt sie mit („Von dir geändert“).
- Alle neuen Texte über `scripts/strings.mjs`, de und en.

## Teil C: Plugins und Handbuch

- quartz-navigations 0.7.0 (`cssVariables`, Test gegen das SCSS, README nennt den Schlüssel),
  quartz-forms entsprechend; QuartzHub nimmt die Fassungen in `sameCode` bzw. liest dagegen.
- Handbuch: Kapitel Stile ▸ Variablen um die Plugin-Variablen erweitern, de und en, Aufnahme neu;
  `qh-check handbook`.

## Teil D: Die Variablen des Basis-Templates (TPL)

Nachfrage des Nutzers (2026-11-21): die 85 `--tpl-*` des Basis-Templates sortiert und erklärt.
Heute stehen sie als eine flache Gruppe „TPL“ unter „Alle Theme- und Build-Variablen“, ohne Erklärung;
ihre Werte schreibt das Template in den Block `css-vars`, Kommentare dazu gibt es kaum (zwei in
`custom/foundation.scss`).

- **Wo die Erklärungen stehen:** als Katalog in Kommentaren am Anfang von `custom/foundation.scss`
  des Basis-Templates, eine Zeile je Variable mit Gruppe, Art und Text (de, en). Die Datei reist im
  Paket unter `files/styles/custom/` mit; weder `.qtpl` noch `.quartz-gui/` brauchen ein neues
  Format, und jedes andere Template kann denselben Katalog mitbringen. Dieselben Felder wie
  `cssVariables` der Plugins (A1), ein Leser für beides im Kern.
- **Gruppen** (aus den Namen, Vorschlag): Abstände (`space`, `indent`, `target`), Spalten (`col`),
  Kopf- und Fußzeile (`header`, `footer`), Text (`text`, `leading`, `tracking`, `underline`),
  Flächen und Linien (`surface`, `rule`, `radius`, `shadow`, `backdrop`), Callouts (13), Icons,
  Randmenü und Schublade (`rail`, `drawer`), Bewegung und Fokus (`motion`, `fade`, `focus`), Farben
  (`accent`, `positive`).
- **Anzeige:** Hat ein Projekt einen Katalog, stehen seine Variablen als eigener Abschnitt
  „Template-Variablen“ mit diesen Gruppen, wie die Hauptvariablen; ohne Katalog bleibt alles wie heute.
- **Texte:** 85 Erklärungen, entworfen aus der Verwendung im SCSS des Templates, vom Nutzer
  durchgesehen. Das Basis-Template kommt aus dem öffentlichen Repo (`BuiltinTemplate`): neue
  Projekte bekommen den Katalog ohne Release; bestehende (gui-test) mit dem nächsten Anwenden des
  Templates oder von Hand.

## Reihenfolge

1. Manifest in quartz-navigations (A1) samt Test, Release; danach quartz-forms.
2. Kern lesen (A2, A3) mit Golden File und Tests.
3. Anzeigen (B3 ohne Felder): der Abschnitt, Zeilen, Inspektor nur lesend. App ansehen, hell und dunkel.
4. Format und Schreiber (B1) mit Tests, `formats/projekt.md`.
5. Ändern in der Oberfläche (B3 Felder, B2 Hinweise), in gui-test gemessen (B2).
6. Handbuch.

Je Schritt ein Commit mit Bau, `qh-check i18n`, Kerntests, Rauchtest und der App angesehen.
Aufwand grob: Lesen und Anzeigen (1–3) und Ändern (4–5) sind etwa gleich groß; das Handbuch kommt
dazu.

## Zu entscheiden

1. **Neuer Block `plugin-vars`** in `_quartzcontrol.scss` (B1), also eine Erweiterung des
   1.3-Formats. Vorschlag: ja, mit dem Marker-Präfix `QuartzControl` wie die anderen Blöcke.
2. **Ort im Manifest:** `quartz.cssVariables` (Vorschlag), oder eine eigene Datei, falls Quartz den
   Schlüssel bemängelt (A1, beim Umsetzen geprüft).
3. **Beschreibungen zweisprachig** im Manifest (`description`, `description_de`)? Vorschlag: ja; die
   Optionen der Plugins sind heute nur englisch, die Variablen wären die ersten mit Deutsch.
4. **Fremde Plugins** (Excalidraw 66, Callout-Icons 13): mit anzeigen und ändern wie die eigenen,
   nur ohne Beschreibung. Vorschlag: ja, eingeklappt.

## Entscheidungen des Nutzers (2026-11-21)

Alles wie vorgeschlagen: neuer Block `plugin-vars` mit dem Präfix `QuartzControl`;
`quartz.cssVariables` im Manifest (eigene Datei nur, falls Quartz den Schlüssel bemängelt);
Beschreibungen zweisprachig (`description`, `description_de`); fremde Plugins anzeigen und ändern wie
die eigenen, ohne Beschreibung, eingeklappt; Teil D mit den vorgeschlagenen Gruppen.

## Umgesetzt

- **Schritt 1 (2026-11-21):** quartz-navigations 0.7.0 (64 Variablen) und quartz-forms 0.7.0 (10) mit
  `quartz.cssVariables`; Vorgaben aus dem SCSS übernommen, nicht abgetippt; je ein Test hält die Liste
  gegen das SCSS (mit falscher Vorgabe rot). Quartz nimmt den Schlüssel an: `plugin doctor --verbose`
  gibt mit und ohne ihn dasselbe aus, gui-test baut. Das Format ist ein Objekt `{ groups, variables }`,
  damit Reihenfolge und Gruppenbeschriftung (de/en) mitreisen. QuartzHub: beide in `sameCode`.
- **Schritt 2 (2026-11-21):** `PluginVariables` im Kern. Gemessen an einer Kopie von gui-test: 64 + 10 aus
  den Katalogen, 19 von Quartz selbst (Callouts), je 1 von canvas-page und Excalidraw, nichts ohne
  Zuordnung, 0,29 s. Zwei Dinge, die erst die echte Kopie zeigte: Die Suche nach `--name:` im Text jedes
  Pakets brauchte 11,4 s (jetzt einmal je Paket als Bytes gelesen), und die Callout-Variablen landeten
  bei quartz-themes, dessen Paket die Namen auch enthält (jetzt wird Quartz' eigenes `quartz/` zuerst
  gefragt, ohne `.quartz-cache`, das eine Kopie von allem hält). Namen mit `_` (Hilfsvariablen wie
  `--_size`) bleiben weg. Aufrufer übergeben nur eingeschaltete Plugins. A3 braucht keinen eigenen
  Code: `VariableResolve.resolveValueLiteral` löst `var(--tpl-icon)` schon über die `:root`-Werte auf.
- **Schritt 3 (2026-11-21):** Abschnitt „Plugin-Variablen“ unter Stile ▸ Variablen (`PluginVariablesSection`),
  eine Klappgruppe je Plugin, die beschriebenen zuerst, dann die aus dem Build, Quartz und „Ohne Plugin“
  zuletzt; bei den beschriebenen die Gruppen des Katalogs in seiner Reihenfolge und die Beschreibung in
  der Sprache der App unter jeder Zeile; „im Projekt gesetzt“, wo eine ungelayerte Regel sie auch setzt.
  Inspektor nur lesend: Beschreibung, Plugin, Vorgabe (aufgelöst über die `:root`-Werte), Selektor, die
  Regeln des Projekts, weitere Selektoren, ein Schnipsel zum Kopieren. Die Suche der Seite filtert mit.
  Angesehen an der Kopie von gui-test (95 Variablen, dunkel; hell nicht angesehen). Die Zeile zeigt die
  Vorgabe des Plugins, nicht den Wert, der gilt: Welche Regel gewinnt, kommt mit Schritt 5 (B2).
- **Schritt 4 (2026-11-21):** Block `plugin-vars` (`PluginVariableOverrides`, Lesen, Schreiben,
  `StyleSheets.savePluginVariableOverrides`). Er hängt als fünfter an `ManagedBlocks.movedMarkers` und erbt damit
  Lesen aus beiden Dateien, Umzug und Reihenfolge (zuletzt, nach `css-vars`); in einem Projekt in Form 1.0 steht er in
  `custom.scss`. Ein Vorlagen-Export nimmt ihn nicht als eigenen Text mit (`TemplatePackage.managedMarkers`; ihn in
  Vorlagen mitzunehmen wäre ein eigener Schritt). Nicht geschrieben wird, was keine einzelne Deklaration bliebe
  (Selektor oder Wert mit Klammer, Semikolon, Kommentar, Zeilenumbruch; Selektorlisten). Gegenproben: ohne den
  Eintrag in `movedMarkers` bzw. `managedMarkers` scheitern die Tests. `formats/projekt.md` §1 beschreibt den Block.
- **Schritt 5 (2026-11-22):** Ändern im Inspektor (Hell und dunkel, auf Wunsch Dunkel eigens, Farbwähler bei
  Farben, Zurücksetzen), gespeichert mit der Seite (⌘S, Frage beim Verlassen) über `StylesModel.pluginOverrides`;
  ein Wert, der keine Deklaration bliebe, wird unter dem Feld gemeldet und hält das Speichern an
  (`styles.variableNotWritable`, wie bei `css-vars`). **B2 gemessen** an der Kopie von gui-test, Block über den
  Schreiber, gebaut, in Chrome: `--quartz-nav-rail-icon-size` 1.5rem in hell und dunkel, Icons 24 px (die Vorlage
  hätte 1.1rem); `--quartz-forms-error` mit eigenem Dunkel-Wert `#a00`/`#faa` statt der Werte des Plugins. Im
  Build steht die Regel der Seite hinter der der Vorlage (`.quartz-nav--rail`, gleiche Spezifität). Wer stärker ist,
  sagt `PluginVariableCascade`: höhere Spezifität, oder gleiche und aus `custom.scss` (das den Block mit seiner
  ersten Zeile lädt, seine Regeln kommen danach); ein `Callout` im Inspektor nennt die Regel, für Dunkel eigens
  (eine Regel der Vorlage für dunkel schlägt einen Wert für beide Modi). In der App durchgespielt: Hinweis bei
  `.quartz-nav.nav-menue` in custom.scss, Tippen, ⌘S, Datei, Zurücksetzen, unsicherer Wert. **Grenze:** Die Regeln
  des Projekts kommen aus dem letzten Build. Die eigene Regel der Seite erkennt QuartzHub daran, dass Selektor und
  Wert zum gespeicherten Block passen; ein älterer eigener Wert steht bis zum nächsten Build als Regel des Projekts
  da. Eine in SCSS verschachtelte Regel von custom.scss wird nicht als „später“ erkannt.
- **Teil D (2026-11-22):** `TemplateVariables` liest Kataloge aus Kommentaren `/* quartz-variables … */` in den
  geladenen Stylesheets (Ladereihenfolge, die erste Datei gibt Gruppe und Text; dasselbe JSON wie
  `quartz.cssVariables`, ohne Selektor heißt `:root`). Abschnitt „Template-Variablen“ zwischen Haupt- und allen
  Variablen, mit den Gruppen des Katalogs und der Erklärung unter jeder Zeile; Zeilen und Inspektor die gewohnten
  (der Wert bleibt in `css-vars`), dazu die Erklärung oben im Inspektor; die Katalog-Variablen fehlen dafür unter
  „Alle Theme- und Build-Variablen“. Weil die Vorlage ihre Werte in denselben Block schreibt wie der Nutzer, zeigt der
  Abschnitt „Vorlage“ statt „eigene Variable“, keinen Papierkorb und kein „geändert“ (Entfernen bleibt im Inspektor,
  mit Rückfrage). Katalog des Basis-Templates: 80 Variablen (75 aus `cssVariables`, 5 aus den Stylesheets) in den
  zehn Gruppen des Plans, Texte aus der Verwendung im SCSS der Vorlage; geschrieben von `scripts/template-variables.mjs`
  aus `scripts/template-variables/qc-basic.json`, `createdAt` 2026-11-22. Gemessen an der Kopie von gui-test (Katalog
  dort ergänzt): baut, der Kommentar steht in keiner ausgelieferten CSS-Datei (Quartz minifiziert ihn weg).
  **Offen:** die Texte vom Nutzer durchsehen; beim nächsten Release das Paket ins Vorlagen-Repo (`docs/release.md`
  Punkt 10) und die Example-Vorlage darauf neu erzeugen; bestehende Projekte bekommen den Katalog mit dem nächsten
  Anwenden der Vorlage oder von Hand.
- **Handbuch (2026-11-22):** 5.7 in beiden Sprachen um „Variablen der Vorlage“ und „Variablen der Plugins“ erweitert
  (Vault-Commit), `qh-check handbook` und `handbook-private.swift` ohne Befund. Das Demo-Projekt bekommt
  navigations in neuester Fassung und den Katalog der Vorlage (`handbook-demo.sh`); `handbook-shots.sh` kennt die
  Aufnahmen `stile-variablen-vorlage` und `stile-variablen-plugins` (Klicks über die Beschriftungen, die Zeile der
  Plugin-Variable über die Suche, weil die Liste Zeilen außerhalb des Bildes nicht anlegt). **Offen:** die vier
  Aufnahmen machen (der Nutzer wollte später; das Skript steuert Maus und Tastatur), dann Handbuch online.

