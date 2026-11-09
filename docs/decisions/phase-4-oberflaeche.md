# Phase 4: Oberfläche

Die Messungen und Entscheidungen beim Bau der Oberfläche, ein Abschnitt je Teil.

## Entscheidungen zu Beginn (Nutzer, 2026-11-08)

- QuartzControl gibt Funktion, Texte und Ränder vor; das Aussehen ist natives macOS (`Form`
  grouped, Listen, Inspektor statt Karten).
- Die Einstellungen sind ein eigenes Fenster (⌘,).
- Für den Code-Editor darf STTextView über SwiftPM rein, wenn die Lizenz zu GPL-3.0 passt.
- **Ein Fenster „Projekte“ und ein Fenster je Projekt** statt QuartzControls einem Fenster mit
  Startseite. Zwei Projekte können gleichzeitig offen sein, dasselbe nur einmal.

## 4a: Fenster „Projekte“ und Projektfenster

**Aufbau.** `Window` „Projekte“ (`App/Projects/ProjectsWindow.swift`, die erste Szene, also das
Fenster beim Start und das, was das Dock-Symbol zurückholt; Fenster ▸ Projekte, ⇧⌘0) und
`WindowGroup(id: "project", for: String.self)` mit der Projekt-ID (`App/Shell/ProjectWindow.swift`).
SwiftUI hält je Wert ein Fenster: ein zweites Öffnen holt das offene nach vorn. Ablage ▸
„Vorhandenes Projekt öffnen…“ (⌘O) ersetzt „Neues Fenster“: ein Projektfenster ohne Projekt
bedeutet nichts. Die Liste liegt in einem gemeinsamen Modell (`ProjectsModel`); ein Projektfenster,
dessen Projekt entfernt wird, sagt das und bietet die Liste an.

**Kern.** `ProjectOverviews` portiert `projectOverviewService` und Sortierung und Suche aus
`Home.tsx`. Gemessen gegen Home.tsx' eigene Ausdrücke in Node
(`scripts/project-overview-golden.mjs`, 13 Zeilen, 13 Suchen). Dabei gefunden: Ein leerer
`lastOpenedAt` ist in JavaScript falsy und zählt als 0, nicht als NaN; ein unlesbarer ist NaN, und
`NaN || …` fällt auf den Namen durch. Mit NaN sortiert V8 inkonsistent; `JS.sort` bildet das nach,
das unlesbare Projekt steht an derselben Stelle wie in QuartzControl. Eine Abweichung mit Absicht:
Die Suche nimmt „ä“ und „a“ + Trema als gleich (Swifts `contains`), JavaScripts `includes` nicht.
`ProjectList` setzt zusammen, was QuartzControls `projects:*`-Handler zusammen taten (Pfade
umbiegen vor dem Verschieben, Server stoppen und Relay-Geheimnisse löschen beim Entfernen).

**UI-Test.** Der Rauchtest braucht jetzt ein Projekt: ein Wegwerf-Profil mit einem Ordner samt
`quartz.config.yaml`, geöffnet mit `-QHOpenProject <pfad>` (nur Debug). Drei Dinge, die dabei
anders waren als gedacht:

- Der Fenstertitel im Bedienungshilfe-Baum ist Titel und Untertitel zusammen („smoke-projekt –
  Übersicht“); der Test sucht mit `BEGINSWITH`.
- Mit zwei Fenstern findet `app.descendants(…)[kennung].firstMatch` die Kennung im falschen
  Fenster: „inspector.toggle“ gibt es in beiden, der Test klickte den Inspektor der Projektliste
  und wartete im Projektfenster vergeblich. Und „inspector.pageContext“ stand in beiden, die
  Prüfung je Seite hätte also nie scheitern können. Prüfungen im Projektfenster suchen jetzt nur
  dort, und der Kontext der Projektliste heißt „inspector.projectsContext“.
- `app.buttons["Aus der Liste entfernen"]` traf die Kopie des Buttons in der Touch Bar
  („cannot be called with Touch Bar elements“); `app.windows.buttons[…]` trifft den im Dialog.

Gegenproben: Entfernen ohne Wirkung scheitert an „row still listed“, Entfernen ohne Rückfrage an
„no question before removing“.

**Neues Projekt.** `ProjectCreation` (Kern) ist der Ablauf aus `Home.tsx` nach `quartz create`:
in die Liste, Stilblöcke ohne Snapshot verschieben, Beispielvorlage mit `packageWins`, die Sprache
der Website nach der App. Was danach scheitert, wird gemeldet, nicht zurückgenommen. Eine
Abweichung: Ein gescheitertes Verschieben der Stile ist ein eigener Satz; in QuartzControl stand es
zwischen den `art:detail`-Warnungen und kam als „1× ‹ganzer Satz›“ heraus. `ImportWarnings` macht aus
den Warnungen die Sätze von `ImportOutcome.tsx` (gruppiert, Detail-Arten über eine Probe im
Katalog). Der Dialog (`CreateProjectSheet`, ⌘N und Symbolleiste) ist im UI-Test nur bis vor das
Anlegen geprüft: ein echtes Anlegen klont Quartz von GitHub und ist ein Netzlauf.

**Einstellungen.** Ein eigenes Fenster (⌘,) mit drei Tabs: Allgemein (Design, Sprache,
Projektordner, Beim Beenden), Laufzeit (Node, git), Daten & Wartung. Jede Wahl schreibt sofort und
nur ihr Feld (`SettingsStore`, lesen–ändern–schreiben wie QuartzControls ganzes Objekt). Der
GitHub-Token und die Verbindungen kommen mit „Veröffentlichen“. Drei Dinge, gemessen am laufenden
Fenster (2026-11-08):

- **Design** setzt `NSApp.appearance` und greift sofort, in allen Fenstern.
- **Sprache:** Die Fenster bauen ihren Inhalt neu auf (`followsLanguage`, `.id` an einer Revision),
  unsere Menübefehle ebenfalls, wenn ihr `body` die Revision liest; ohne das blieben „Neues
  Projekt…“ und „Inspektor einblenden“ in der alten Sprache. Die Menüs von macOS selbst (Ablage,
  Bearbeiten, Fenster) nehmen die Sprache beim Start. Deshalb schreibt der Wechsel auch
  `AppleLanguages` der App, wie es die Systemeinstellung „Sprache je App“ tut; nach dem Neustart
  hießen sie File, Edit, View. Bei „Systemsprache folgen“ wird der Schlüssel entfernt.
- **Node-Laufzeit:** Die Umgebung wurde bisher einmal beim Start bestimmt. Jetzt wird sie beim
  Umschalten neu bestimmt, und der `BuildService` fragt bei jedem Vorgang die aktuelle
  (`AppServices.current()`): „Gilt für Vorgänge, die danach starten“, wie der Text sagt.

**Neben QuartzControl.** Ein Band oben im Projektfenster, solange QuartzControl läuft
(`NSRunningApplication`, aktualisiert bei Start und Ende von Apps), dazu dessen Dev-Server für genau
dieses Projekt. Nicht am laufenden QuartzControl gesehen: es zu starten, löst dessen Abfrage nach
einer neueren Fassung bei GitHub aus, ein Netzlauf. Was das Band meldet, prüft
`CoexistenceConcernsTests`. Eine Warnung je Schreibvorgang kommt mit den Seiten, die schreiben.

## 4b: Code-Editor und Umsortieren

Zwei Entscheidungen, je mit einer kleinen Messung (2026-11-08, macOS 27.2, Apple Silicon). Das
Messgeschirr liegt in [`phase-4-harness/`](phase-4-harness/README.md). Jede Zahl ist ein Lauf, das
Öffnen schwankte zwischen zwei Läufen um 10 ms. Gebaut wird beides mit der ersten Seite, die es
braucht, nicht vorab.

### Code-Editor: NSTextView mit TextKit 2, kein Fremdpaket

**Was QuartzControl vom Editor will.** CodeMirror steht in `Styles/CustomCss.tsx` und
`PluginOptionsForm/snippets.tsx`. Gebraucht wird:
- SCSS und CSS gefärbt, mit Einrückungslinien (der Block des Cursors dunkler);
- Markdown und HTML mit Zeilenumbruch;
- eine nur lesende Fassung für die Referenzdateien;
- Einfügen an der Cursorstelle, nur wenn der Nutzer einen Cursor gesetzt hat;
- Sprung zu einer Zeile (Diagnose der SCSS-Prüfung);
- Zeilennummern, Suchen, Hell und Dunkel;
- eine Änderung von außen ersetzt das Dokument, ohne einen dritten Stand dazwischen
  (`styles-and-fonts.md`, „Der Editor darf zwischen zwei Ständen nicht durch einen dritten“).

**Lizenz.** STTextView steht unter GPLv3 (ohne „or later“), alternativ kommerziell. Seine
Abhängigkeiten sind STTextKitPlus (BSD-3-Clause) und CoreTextSwift (MIT). Das ist mit
GPL-3.0-or-later vereinbar; das gebaute Ganze stünde dann unter GPL-3.0. STTextView scheitert also
nicht an der Lizenz.

**Messung.** Beide Editoren hatten denselben Regex-Färber und dieselbe Schrift, gebaut als
Release. Die Dateien:
- `content.scss` aus gui-test, 1.411 Zeilen;
- alle Dateien unter `custom/` hintereinander, 6.819 Zeilen.

„Tastendruck“ heißt: `insertText` eines Zeichens in die Mitte, dann den Absatz neu färben und
`displayIfNeeded`, gemittelt über 200 Drücke. Der Speicher ist der RSS des Prozesses.

| | NSTextView (TextKit 2) | STTextView 2.4.1 |
|---|---|---|
| Öffnen bis zur ersten Anzeige, 1.411 Zeilen | 19–30 ms | 35–36 ms |
| je Tastendruck ohne Färben | **1,26 ms** | **8,10 ms** |
| je Tastendruck mit Färben, 1.411 / 6.819 Zeilen | 17,9 / 23,5 ms | 25,2 / 32,1 ms |
| Speicher nach dem Öffnen → nach 200 Drücken, ohne Färben | **106 → 121 MB** | **93 → 315 MB** |
| Speicher nach 200 Drücken mit Färben, 6.819 Zeilen | 128 MB | 389 MB |
| Bedienungshilfen (aus einem zweiten Prozess abgefragt) | `AXTextArea`, 11 parametrisierte Attribute | `AXTextArea`, 7 davon |

**Bedienungshilfen.** Beide lesen dieselbe Zeile zu Index 500 (Zeile 8) und denselben Text zu einem
Bereich. STTextView fehlen `AXRangeForIndex`, `AXStyleRangeForIndex`, `AXRTFForRange` und
`AXSharedTextElementForIndex`.

**Was STTextView fertig mitbringt.** Gegenüber NSTextView sind das nur die Zeilennummern.
Einrückungslinien hat keiner von beiden, Suchen haben beide (NSTextView über `usesFindBar`). Für
die Nummern genügt ein `NSRulerView`, der `enumerateTextLayoutFragments` ab dem ersten sichtbaren
Fragment geht (40 Zeilen, `editor-spike/Sources/Spike/Ruler.swift`). Er zeichnet richtig (im
Screenshot steht 1411 an der letzten Zeile von `content.scss`). Messbar kostet er nichts: 1,24 ms je
Tastendruck mit Leiste gegen 1,26 ms ohne, bei 6.819 Zeilen 1,22 ms. Beim Bau beachten: Die leere
Zeile nach dem letzten Zeilenumbruch hat kein Layout-Fragment und bekommt so keine Nummer.

**Das Teure ist das Färben, nicht der Editor.** Die Regex-Färbung des Spikes kostet in beiden
Editoren rund 16 ms je Tastendruck. Ein Tastendruck kostet ohne sie 1,3 ms. Der echte Färber wird
ein kleiner Lexer im Kern, ohne UI testbar. Sein Ziel: wenige Millisekunden je Tastendruck auf den
6.819 Zeilen, gemessen, bevor die erste Seite ihn bekommt.

**Entscheidung.** NSTextView mit TextKit 2 (`NSTextView.scrollableTextView()` liefert TextKit 2),
dazu eigene Zeilennummern, eigenes Färben und eigene Einrückungslinien, als `NSViewRepresentable`.
Kein Paket. STTextView ist bei jedem Tastendruck sechsmal so teuer, und sein Speicher wuchs je
Tastendruck um gut 1 MB. Bei den Bedienungshilfen bietet es weniger, und es würde zwei Pakete
mitbringen, um ein Lineal zu sparen.

### Umsortieren: native Liste, dazu Befehle

**Was QuartzControl tut.** dnd-kit steht in acht Dateien:
- Sortierlisten: installierte Plugins, Formularfelder, Seitenreihenfolge der Dokumente; dazu die
  Ladereihenfolge der Stylesheets, die nur Pfeile hat;
- ein Raster: den Frame-Builder;
- ein Board mit Ablagezonen und Vorrat: das Layout.

Die Regeln dazu stehen in `conventions-full.md` unter „Kein natives HTML5-Drag mehr“ und „Was
keinen festen Platz hat …“:
- Alles muss mit der Tastatur gehen.
- Sortierlisten tragen zusätzlich „nach oben / nach unten“, weil die Tastatur-Aufnahme eine Geste
  ist, die man kennen muss.
- Das Board verschiebt über die Seitenleiste: „Früher“, „Später“, Position, „In den Vorrat legen“.
- Jede Bewegung wird mit einem ganzen Satz angesagt, der sagt, was passiert ist.

**Messung.** Gemessen an einer SwiftUI-Liste mit fünf Zeilen, die von außen über die
Bedienungshilfen gesteuert wurde. Die App druckte die Reihenfolge nach jeder Bewegung.
- **Maus:** `ForEach.onMove` in `List(selection:)`. Alpha, über Delta gezogen, landete dahinter.
  Vorher stand die Liste auf Alpha, Gamma, Delta, Beta, Epsilon, danach auf Gamma, Delta, Alpha,
  Beta, Epsilon.
- **Tastatur:** Ein Menü „Anordnen“ hat „Nach oben“ und „Nach unten“ mit ⌥⌘↑ und ⌥⌘↓, angebunden
  über `focusedSceneValue`. ⌥⌘↓ bewegte die ausgewählte Zeile Beta von Platz 3 auf 4, und die
  Auswahl blieb auf Beta.
- **VoiceOver-Aktionen:** `accessibilityAction(named:)` erscheint als `Name:Nach oben` unter den
  Aktionen. `AXUIElementPerformAction` darauf bewegte Gamma von Platz 3 auf 2. Die Aktionen hängen
  am Inhalt der Zeile (`AXStaticText`), nicht an der `AXRow`.
- **Ansage:** `AccessibilityNotification.Announcement(…).post()` kam je Bewegung einmal als
  `AXAnnouncementRequested` mit dem Satz an, mitgelesen über `AXObserver`.

Nicht gemessen:
- ob VoiceOver die Ansage tatsächlich spricht; die Ansage kam beim System an, gehört wurde sie
  nicht;
- wo die Aktionen landen, wenn eine Zeile mehr als ein Element hat.

**Entscheidung.**
- **Sortierlisten:** `List` mit `onMove` für die Maus. Dazu kommen „Nach oben“ und „Nach unten“
  mit derselben Funktion an drei Stellen:
  - im Menü mit ⌥⌘↑/⌥⌘↓;
  - im Kontextmenü der Zeile;
  - als Bedienungshilfe-Aktion der Zeile.
  
  Nach jeder Bewegung kommt eine Ansage mit den übernommenen `dnd.*`-Sätzen und
  `pluginsInstalled.moveUp`/`moveDown`. Beim Bau zu messen: ob das Kürzel nur greift, solange die
  Liste den Fokus hat (`focusedValue` statt `focusedSceneValue`), und wo die Aktionen bei einer
  Zeile mit mehreren Elementen landen (`accessibilityElement(children: .combine)`).
- **Raster und Board (Layout):** Die Maus zieht mit `draggable` und `dropDestination`. Die Tastatur
  verschiebt über den Inspektor, so wie QuartzControls Seitenleiste seit 1.1. macOS hat keine
  native Geste, mit der die Tastatur etwas in einem Raster zieht. Eine nachgebaute wäre wieder
  dnd-kits Pfeil-Logik mit allen Rändern aus `dndKeyboard.ts`. Gemessen wird das mit der Seite
  Layout.

## 4c: Die Seiten

Eine Seite je Abschnitt, in der Reihenfolge des Plans. Vorbild ist jeweils `src/routes/*` in
QuartzControl 1.3.

### Übersicht

Vorbild `ProjectDashboard.tsx`. Neu im Kern sind zwei Dienste:

- **`BuildOutput.info`** beschreibt, was im Ausgabeordner liegt, als Nachbau von `getBuildOutput`.
  Gemessen mit `scripts/build-last-output-golden.mjs` gegen QuartzControls eigenen Code, 15 Fälle:
  - Links, Links ins Leere und ein verlinkter Ausgabeordner;
  - Millisekunden werden abgeschnitten, nicht gerundet;
  - ein Unterordner, der sich nicht lesen lässt.

  Abweichung: Lässt sich ein Unterordner nicht lesen, bekommt die Seite einen Fehler mit dem
  Ordner. QuartzControls Kachel wartete dann für immer auf eine Antwort.
- **`ProjectAttention`** enthält die Regeln des Bands „Handlungsbedarf“ und die Bedingung für
  „Alles ok“, mit je einem Test. Ein Lesevorgang hat drei Zustände: läuft noch, gescheitert,
  fertig. Ein gescheiterter Lesevorgang ergibt nie „Alles ok“.

**Aussehen.** Aus jeder Kachel wird ein Abschnitt eines gruppierten `Form`, untereinander in der
Reihenfolge der Kacheln:

- Die Kopfzeile zeigt das Symbol der Seite, den Namen und rechts den Zustand: Serverzustand, Branch
  oder Zahl der Updates.
- Oben im Abschnitt steht der eine Wert, um den es geht.
- Darunter stehen die Einzelheiten.
- Am Fuß führt ein Verweis auf die zuständige Seite.
- Das Band steht über allen Abschnitten.
- „Build ausführen“, „Snapshot anlegen“ und „Projektordner öffnen“ stehen in der Symbolleiste.
- Der Inspektor zeigt den Seitenkontext mit dem Projektordner.

Gesehen in Hell und Dunkel an einer Kopie von gui-test ohne `node_modules`. Gegen die Platte
geprüft:

| Angabe | Seite | Platte |
|---|---|---|
| Build-Ordner | 475 Dateien, 32 MB, vor 2 Wochen | 475 Dateien, 32.499.736 Byte, 25. Oktober |
| Snapshots | 12, nach einem Klick 13 („Von dir“) | 12 Refs, danach 13 |
| Ziele | 7 | 7 |
| Plugins | 46 von 64 aktiv | – |
| Band | „88 npm-Pakete fehlen“ mit „Installieren“ | – |

„Build ausführen“ meldete ohne Pakete „Build fehlgeschlagen“, und der alte Build blieb liegen.

**Was beim Bau anders war als gedacht.**
- **`RelativeDateTimeFormatter`** liest Wochen nur als `weekOfMonth`. Mit `weekOfYear` kam ein
  leerer Text heraus (gemessen: „“ gegen „vor 3 Wochen“), und die Git-Zeile stand ohne Datum da.
- **Serverzustand und Build-Aktivität** kamen bisher nur als Ereignisse aus `BuildService`.
  `BuildMonitor` liest sie in der Reihenfolge, in der der Dienst sie sendet, über einen Strom mit
  einem Leser auf dem Main Actor. Eine Seite, die vor dem ersten Ereignis öffnet, fragt den Dienst
  einmal. Kommt inzwischen ein Ereignis, gewinnt das Ereignis.
- **XCUITest liest als `label` den Text im Knopf**, auch wenn der Knopf selbst keinen
  Bedienungshilfe-Namen trägt. Die Gegenprobe ohne `accessibilityLabel` blieb grün, also prüft
  eine solche Assertion nichts. Ob ein Element einen Namen hat, sagt erst
  `AXUIElementCopyAttributeValue` (`AXDescription`). So stellte sich auch heraus, dass die Verweise
  `AXLink` mit Namen sind. Namenlos sind nur die Pfeile der Rollbalken und die Ampelknöpfe.
- **Die Update-Prüfung ist der einzige Netzzugriff der Seite** (`git ls-remote`). Rauchtest und
  Ansehen schalten sie im Debug-Bau mit `-QHNoUpdateCheck YES` ab. Der Abschnitt sagt dann „Nicht
  prüfbar“.

**Abweichungen von QuartzControl.**
- „Abbrechen“ bei der Frage zum Ausgabeordner schließt die Frage ohne weitere Meldung. QuartzControl
  zeigte einen Toast „Abgebrochen: …“. Die Frage selbst ist ein `NSAlert`; „Abbrechen“ steht zuerst
  und ist die Standardtaste.
- Was eine Aktion nicht konnte, steht in einem Hinweisfenster. QuartzControl zeigte dafür einen
  Toast.
- Der Rückweg zur Übersicht (`markReturn`) ist nicht übernommen. Die Seitenleiste zeigt den Weg
  zurück.
- Die Tabs, auf die ein Verweis zielt (`config?tab=site`, `styles?tab=customCss`), stehen schon
  in `ProjectAttention.Issue.tab`. Die Seiten lesen sie, sobald sie Tabs haben.

**Nicht gemessen:**
- „Installieren“ (npm aus dem Netz);
- die Update-Prüfung selbst;
- Starten des Servers: ohne `node_modules` startet Quartz nicht, und mit fehlt der Kopie nichts.

### Vorschau & Build

Vorbild `BuildServer.tsx` mit `LogConsole`, `DiscoveredServers` und `BuildActivityLine`. Neu im
Kern ist nur **`ProjectPrefs.outputDirProblem`**: die Regel aus QuartzControls Schema
`projectPrefs` (`ipc/schemas.ts`) für den Ausgabeordner. Erlaubt sind leer, absolut bis 4096
UTF-16-Einheiten oder relativ bis 1024 ohne ein Segment „..“ (getrennt an „/“ und „\“). Gemessen
mit `scripts/output-dir-golden.mjs` gegen das Schema selbst, 37 Fälle. Die Gegenproben scheitern:
Zeichen statt UTF-16 zählen, oder nur an „/“ trennen.

**Aussehen.** Drei Abschnitte eines gruppierten `Form`:
- **Dev-Server.** Er beginnt mit der Adresse: ein Link, wenn der Server läuft, sonst grau mit der
  Adresse, die er haben wird. Daneben steht „Kopieren“. Darunter kommen:
  - die Angaben zum Lauf oder der Hinweis;
  - der Fehler;
  - der Hinweis auf eine fehlende `index.md`;
  - die Aktivität;
  - Starten oder Neustarten und Stoppen;
  - die Server-Einstellungen, eingeklappt, jedes Feld eine Zeile;
  - die Live-Vorschau;
  - die Konsole.
- **Laufende Server auf diesem Rechner** (`ServerScan.discover`).
- **Einmaliger Build** mit:
  - „Jetzt bauen“;
  - dem Inhalt des Ausgabeordners;
  - dem Feld „Ausgabeordner“ mit „Auswählen“ und „Zurücksetzen“;
  - dem Ergebnis;
  - der Konsole.

**Gemessen** in Hell und Dunkel an einer Kopie von gui-test. Die `node_modules` sind per APFS-Klon
mitgekopiert, Server auf 8080/3001:

| Vorgang | Ergebnis |
|---|---|
| Starten | Port 8080 lauscht nach 16 s; Zustand „Läuft“, Vorschau zeigt die Startseite |
| „Mobil“ | Vorschau 390 pt breit, mittig, Anzeige „390 px“ |
| In der Vorschau auf „animation“, dann „Desktop“ | Vorschau bleibt auf „animation“: Breitenwechsel lädt nicht neu |
| „Jetzt bauen“ nach `public/` bei laufendem Server | abgelehnt, der Satz rot in der Build-Konsole |
| Ausgabeordner „../x“ | Fehler unter dem Feld, `project-prefs.json` unverändert |
| Ausgabeordner „dist“, dann bauen | Datei hat `"dist"`, „Erfolgreich in 12,1s“, 475 Dateien in `dist/`, der Server lief weiter |
| „Server beenden“ in der Liste, „Abbrechen“ | Server läuft weiter |
| dasselbe, „Server beenden“ | Port frei, Liste „Es läuft kein Quartz-Server …“, 0 |
| Port 8095 eingetippt, zur Übersicht und zurück | 8095 steht noch, die Adresse sagt `:8095`, die Einstellungen offen |

**Was beim Bau anders war als gedacht.**
- **Die Konsole folgte dem Ende nicht.** Ob der Leser unten steht, prüfte sie an der Höhe des
  Dokuments. TextKit 2 legt neue Zeilen aber erst später aus. Die Höhe war also noch die alte,
  und die Konsole blieb auf dem ersten Bildschirm stehen (gesehen an der Server-Konsole). Jetzt
  merkt sie sich das Folgen, wenn der Leser selbst rollt (`boundsDidChange`; wachsender Text
  bewegt keine Grenzen). Sie rollt über den Bereich (`scrollRangeToVisible`), nicht über den
  Rahmen.
- **„localhost:8.080“.** Ein interpolierter String-Literal in `Label("…\(port)")` ist ein
  `LocalizedStringKey`, und die Zahl kam mit Tausenderpunkt heraus. Jetzt steht dort ein
  zusammengesetzter `String`.
- **Ein `Text` meldet seine Worte als Wert, nicht als Label.** Unter XCUITest ist `label` leer, der
  Text steht in `value` (gemessen über `AXValue`). Der Test wartet deshalb auf `value`.
- **Übernommene Texte nannten „QuartzControl“ und „Von dieser App“.** Das betraf die
  Stopp-Fragen, den Warnhinweis und die Herkunft in der Liste. Sie sagen jetzt „QuartzHub“.
- **Die Stopp-Frage teilt sich am Absatz.** Der Text vor dem Absatz ist der Titel, der Rest der
  Text des Hinweisfensters. QuartzControl hatte beides in einem Text.

**Abweichungen von QuartzControl.**
- **Die Konsole ist ein `NSTextView` statt einer Liste.**
  - Text lässt sich über Zeilen hinweg markieren und kopieren.
  - Neue Zeilen werden angehängt, statt bis zu 999 neu zu zeichnen.
  - Der Hintergrund folgt dem System, nicht immer dunkel.
  - Sie folgt dem Ende nur, wenn man unten steht; QuartzControl rollte bei jeder Zeile hinab.
  - Neue Zeilen werden nicht angesagt (`role="log"`); bei einem laufenden Server wäre das
    Dauerrede.
- **Die Vorschau ist ein `WKWebView`.** Eine Navigation bleibt nur innerhalb des Servers. Ein Link
  anderswohin öffnet sich im Browser, ebenso `target="_blank"`. QuartzControls Sandbox ließ beide
  stumm.
- **`sitePreview.highlight` nach dem Laden entfällt.** Es begrenzte `scrollIntoView` der Seite auf
  den iframe. Ein `WKWebView` ist eine eigene Rollansicht, die das Formular nicht mitrollt.
  Beobachtet beim Rollen, nicht mit einem Sprung aus dem Inhaltsverzeichnis gemessen.
- **Ein unverändertes Feld „Ausgabeordner“ schreibt nichts**, auch kein `.quartz-gui/`.
  QuartzControl schrieb bei jedem Verlassen des Feldes.
- **Ein abgelehnter Ordner bekommt einen Satz** (`buildServer.exportDirInvalid`), nicht die
  Meldung von zod.
- **Die Dauer des Builds hat ein Dezimalkomma** („12,1s“). QuartzControls `toFixed` schrieb immer
  einen Punkt.
- **Fertig und abgelehnt werden angesagt.** In QuartzControl war die Ergebniszeile still.
- **Die Server-Einstellungen bleiben im Speicher je Projekt** (`BuildServerMemory`), wie
  `useStickyState`, nicht auf der Platte.

**Nicht gemessen:**
- ein Server mit `remoteDevHost` (Tunnel);
- ein fremder Server aus dem Terminal in der Liste;
- „Ordner öffnen“ und „Auswählen“, weil beide den Finder bzw. das Ablagefenster öffnen;
- VoiceOver.

### Konfiguration: Website, ⌘S und die Frage beim Verlassen

Vorbild `ConfigEditor/index.tsx` mit `ContentFolder`, `ProjectImage` und `SiteSettings`, dazu
`state/saveCommand.ts` und `state/unsavedGuard.tsx`. Neu im Kern:

- **`ProjectImageBox`**, QuartzControls `shared/projectImageBox.ts`: das Projektbild im Kopfbereich
  als eine Layout-Box, an ihrer Klasse wiedererkannt. Gemessen mit
  `scripts/project-image-box-golden.mjs` über 18 Plugin-Listen, verglichen als JSON-Text, also mit
  Schlüsselreihenfolge. Die Gegenproben scheitern: nur doppelte Anführungszeichen erkennen, oder
  `enabled` beim Ersetzen ans Ende stellen.
- **`ContentIndexPage`** („Startseite anlegen“), QuartzControls `createIndexPage`. Welche Notizen
  der Build liest, fragt der neue Helfer `content-files` das globby des Projekts, so wie
  `quartz/util/glob.ts` es aufruft. Fehlt globby, nimmt er QuartzControls Ersatzweg; die Abschrift
  ist per `diff` wortgleich. Die Front Matter schreibt yaml's `stringify` im selben Helfer.
  QuartzControl lud das globby des Projekts in seinen Hauptprozess, hier läuft es in einem kurzen
  Kindprozess. Gemessen mit `scripts/content-index-golden.mjs` über 15 Projekte: globby aus
  gui-test, Ersatzweg, `.gitignore`, verknüpfter Vault, vorhandene `index.md`, Sonderzeichen,
  kaputte Config. Der Test baut sie unter „Gärten-Ü“ nach. Die Gegenproben scheitern: Sortieren
  ohne `numeric` (2 Fälle), oder globby nie finden (die 4 globby-Fälle).

**Aussehen.** Ein gruppiertes `Form`: Content-Ordner, Projektbild, Seiteneinstellungen,
Ausschließen, Statistik, der Verweis auf die Stile. Die Dialoge „Quelle ändern…“ und „Startseite
anlegen…“ sind Sheets. „Speichern“ steht in der Symbolleiste, daneben „Nicht gespeichert“ bzw.
„Gespeichert.“; Fehler beim Speichern stehen oben im Formular.

**Die Frage beim Verlassen** (`App/Shell/UnsavedGuard.swift`). Eine Seite meldet sich mit
`.unsavedChanges(dirty, save:)` beim Wächter ihres Fensters an. Gefragt wird an vier Türen:
Seitenleiste, Link auf einer Seite (`openPage`), Fenster schließen, Beenden. QuartzControl hatte
ein Fenster und fragte an der Seitenleiste und am Weg zur Projektliste. Hier gehen Änderungen beim
Schließen eines Projektfensters verloren, also fragt das Schließen. Die Frage ist ein `NSAlert`
als Sheet am Fenster mit „Abbrechen“, „Speichern“ (wenn die Seite speichern kann) und „Änderungen
verwerfen“ (destruktiv). Ungespeichert zeigt das Fenster zusätzlich den Punkt im Schließen-Knopf
(`isDocumentEdited`).

**Gemessen** in Hell und Dunkel an der gui-test-Kopie und an einem Wegwerf-Projekt:

| Vorgang | Ergebnis |
|---|---|
| Seitentitel geändert | „Nicht gespeichert“ in der Symbolleiste, Punkt im Schließen-Knopf, Ablage ▸ Speichern aktiv |
| Seitenleiste „Plugins“, „Abbrechen“ | bleibt auf Konfiguration, Markierung zurück, Änderung bleibt |
| ⌘S | genau die Zeile `pageTitle` geändert, Snapshot angelegt, Ablage ▸ Speichern wieder grau |
| geändert, ⌘W, „Änderungen verwerfen“ | Fenster zu, Datei unverändert |
| geändert, ⌘Q, „Abbrechen“ | App läuft weiter |
| geändert, ⌘Q, „Speichern“ | Datei geschrieben, App beendet |
| „Startseite anlegen“, Titel „Mein: Garten“, ohne `node_modules` | `title: "Mein: Garten"`, „privat“ (Muster) fehlt, „Teil 2“ vor „Teil 10“, Hinweis auf den Ersatzweg |
| Anbieter „google“, `tagId`, zweites Muster in neuer Zeile, ⌘S | `analytics: {provider: google, tagId: …}`, beide Muster |

**Was beim Bau anders war als gedacht.**
- **Ablage ▸ Speichern erschien nicht.** SwiftUI lässt die Gruppe `.saveItem` in einer App ohne
  Dokumente weg, ob ersetzt, davor oder dahinter (gemessen, macOS 27). Der Eintrag steht jetzt
  hinter „Öffnen“ mit Trennlinie.
- **Die Seitenleiste blieb auf der abgelehnten Seite markiert.** Die Liste hing an einer Bindung
  auf `pageID`; nach „Abbrechen“ änderte sich `pageID` nicht, also wurde nichts neu gezeichnet. Die
  Markierung hat jetzt einen eigenen Zustand, den „Abbrechen“ zurücksetzt.
- **Das Musterfeld hätte Return verschluckt.** Eine Bindung, die bei jedem Tastendruck leere
  Zeilen wegwirft, nimmt die neue Zeile gleich wieder weg. Das Feld hält seinen Text selbst und
  übergibt die bereinigte Liste.
- **macOS 27 stapelt die Knöpfe des Hinweisfensters senkrecht**, „Abbrechen“ unten, obwohl er als
  erster angelegt ist. Die Reihenfolge legt das System fest.
- **Vier übernommene Texte nannten „QuartzControl“** (Projektbild, Kopfbereich). Sie sagen jetzt
  „QuartzHub“.

**Abweichungen von QuartzControl.**
- **⌘S ist grau, wenn es nichts zu speichern gibt.** QuartzControls Menü konnte das nicht.
- **Fenster schließen und Beenden fragen** (siehe oben).
- **Nach dem Speichern liest die Seite die Datei neu** (Regel „Eine Seite besitzt ihr Dokument“).
  QuartzControl übernahm seinen Entwurf als gespeichert.
- **Ein Anbieter, den QuartzHub nicht kennt, bleibt wählbar**, statt als „Keine Statistik“ zu
  erscheinen.

**Nicht gemessen:**
- „Quelle ändern…“ (kopiert oder verknüpft einen Ordner);
- Bild wählen, ersetzen, entfernen, auch das dunkle (Ablagefenster);
- der Schalter „Im Kopfbereich zeigen“ mit Installation von quartz-layout-box (Netz); die
  Listen-Logik dahinter ist golden gemessen;
- VoiceOver.

### Konfiguration: Übersetzungen

Vorbild `ConfigEditor/Localization.tsx`; im Kern war `LocaleFiles` schon fertig (Helfer
`locale-edit`). Ein Umschalter über dem Inhalt wählt den Reiter, je Fenster gemerkt
(`@SceneStorage("config.tab")`). In der Symbolleiste schob er den Inspektor-Knopf in die
Fenstermitte (gesehen), deshalb steht er über dem Formular.

Der Reiter zeigt den Update-Schutz (`.gitattributes` mit `merge=ours` und Treiber) mit „Jetzt
aktivieren“, darunter Sprache, Suche, „N ungespeichert“ und „Speichern“ in einer Zeile, dann je
Eintrag Schlüssel und Feld. Gespeichert wird je Sprache mit dem Knopf daneben, nicht mit ⌘S, wie
in QuartzControl. Gewählte Sprache, Suche und ungespeicherte Einträge bleiben je Projekt im
Speicher (`LocalizationModel.forProject`, wie `useStickyState`); ein Seitenwechsel fragt deshalb
nicht.

**Gemessen** am Wegwerf-Projekt mit `de-DE.ts` und `en-US.ts` aus gui-test, als git-Repository:

| Vorgang | Ergebnis |
|---|---|
| `propertyDefaults.title` geändert, „Speichern“ | genau diese Zeile in `de-DE.ts` geändert, `.gitattributes` mit `quartz/i18n/locales/*.ts merge=ours`, `merge.ours.driver` = `true`, Abzeichen „Update-Schutz aktiv“ |
| geändert, zur Übersicht und zurück | keine Frage; „1 ungespeichert“ und der Text stehen noch, der Reiter auch |

**Abweichungen von QuartzControl.**
- **Einspaltig.** QuartzControl stellte die Einträge ab breitem Fenster zweispaltig; hier ist es ein
  gruppiertes Formular.
- **Ein Satz statt „ließ sich nicht laden“** (`localization.localeLoadFailed`): „konnte nicht
  geladen werden“, nach der Stilregel.
- **Speichern wird angesagt**, erfolgreich oder nicht.

**Nicht gemessen:** ein Eintrag der Art `template` (mehrzeilig, „JS“) mit Syntaxfehler; ein
Sprachwechsel mit ungespeicherten Einträgen (sie werden verworfen, wie in QuartzControl); VoiceOver.

### Plugins: Installiert und die Options-Form

Vorbild `routes/Plugins/Installed.tsx` und `components/PluginOptionsForm`. Die übrigen fünf Reiter
kommen einzeln; bis dahin zeigen sie den Platzhalter.

**Kern.** `OptionFormText` trägt, was die Form über eine Option sagt: Titel, Beschreibung und
Gruppe je Sprache, Beschriftungen der Auswahl, die Suche, den Satz unter einer Option, deren
Bedingung nicht gilt, die Reihenfolge der Gruppen und den Wert, den eine von Hand getippte Option
wird. Dazu `QuartzConfig.siteLanguages` und `PluginRepository` (das „owner/repo“ einer Quelle).
Gemessen mit `scripts/option-form-golden.mjs` gegen QuartzControls eigenen Code:
- 27 Felder aus zwei Schemas, die beide Normalisierer lesen;
- 19 Werte als eine Zeile;
- 37 getippte Werte, darunter `0x10`, ` true `, `[1, 2` und Ziffern anderer Schriften;
- 9 Configs für die Sprachen und 18 Quellformen.

Sechs Gegenproben schlugen an (Reihenfolge der Gruppen, Trimmen, `@`, an/aus, Kleinschreibung,
Beschriftungen).

**Abweichung.** Ein getipptes `Infinity` bleibt Text. QuartzControls YAML-Schreiber schrieb `.inf`;
der Weg zum Helfer `yaml-edit` ist JSON, und das kennt keine Unendlichkeit. Die Option wäre als
`null` angekommen.

**Form.** Sie besteht aus `Section`s im gegliederten `Form` des Inspektors. Gruppen falten über
`DisclosureGroup`, verschachtelte Objekte stehen als Stapel in ihrer Zeile. Textfelder schreiben
beim Verlassen und bei Return, wie QuartzControl beim `blur`.

Gefunden in der laufenden App: Das Feld verwarf seinen Entwurf sofort nach dem Schreiben und zeigte
einen Augenblick den alten Wert. Beim nächsten Verlassen schrieb das Textfeld diesen alten Wert
zurück. Gemessen: Ein geleertes `condition` stand nach einem Zeilenwechsel wieder als „has-tags“ in
der Datei. Jetzt bleibt der Entwurf stehen, bis die Seite den neuen Wert liefert. Derselbe Ablauf
(eintragen, leeren, Zeile wechseln) lässt die Datei byte-gleich.

**Liste.** Die Reihenfolge folgt Quartz: Komponenten je Position nach `layout.priority`,
Seitentypen und die übrige Verarbeitung je nach `order`, eigene Frames ohne Reihenfolge.
Umsortiert wird auf drei Wegen zu einer Funktion:
- `onMove` mit der Maus;
- Anordnen ▸ Nach oben/Nach unten (⌥⌘↑/⌥⌘↓), über `focusedSceneValue`;
- dieselben zwei im Kontextmenü und als Bedienungshilfe-Aktion.

Jede Bewegung nummeriert die Gruppe in Zehnerschritten neu, wie in QuartzControl. Gemessen an der
gui-test-Kopie:
- ⌥⌘↓ und ⌥⌘↑ stellen die zwei Zeilen wieder her;
- ein dritter Eintrag mit Lücke ging dabei von 70 auf 60.

Bei aktivem Filter ist das Umsortieren aus, und das Menü ist grau. Schreiben geht wie in
QuartzControl durch eine Schlange: Die Änderung steht sofort im Speicher, die Schreibvorgänge
folgen einander, und nur der letzte liest die Datei neu. Jedes Schreiben nimmt einen Snapshot
`configChange`, Entfernen einen `pluginChange`.

**Kleinstes Fenster.** Sechs Reiter mit fester Breite drückten das Fenster bei 900 pt breiter als
den Bildschirm. Der UI-Test fand die Seitenleiste nicht mehr („Unable to find hit point“). Reicht
der Platz nicht, werden die Reiter jetzt ein Menü (`ViewThatFits`).

**Offen bis zur Seite Layout.** „Im Layout-Editor“ und „Auf der Bühne zeigen“ öffnen die Seite
Layout, wählen dort aber noch nichts aus. Die Widgets der Layout-Box (Snippet-Datei, Bild einfügen,
Platzhalter) und die Gründe „wirkt nicht“ für Navigationen, Layout-Box und Formulare kommen mit
ihren Reitern. Bis dahin ist `file` ein Textfeld.

Die Prüfung, ob ein Plugin ein Update hat (`git ls-remote` je Eintrag), läuft wie auf der Übersicht
nicht mit `-QHNoUpdateCheck YES`.

### Plugins: Marktplatz

Vorbild `routes/Plugins/Marketplace.tsx` und `components/ReadmeText.tsx`. Der Katalog kommt aus
`Marketplace` (Phase 3) und gilt fünfzehn Minuten für alle Fenster (`AppServices.marketplace`).
Gefragt wird erst, wenn der Reiter erscheint, nicht mit der Seite. Der Token hebt nur das
Anfragelimit und kommt vor jeder Anfrage aus den Verbindungen.

**README ohne HTML.** `ReadmeText` liest die Markdown-Formen einer Plugin-README (Überschriften,
Absätze, Listen, Codeblöcke, Tabellen, Code, Fett, Links) in Blöcke, die die App nativ zeigt; HTML
verliert seine Klammern, ein Bild sagt seinen Alt-Text. Gemessen mit
`scripts/readme-text-golden.mjs`: QuartzControls Komponente liefert React-Elemente, das Skript
liest sie in eine neutrale Form zurück. Verglichen werden
- die sechs READMEs der Plugins von gui-test,
- 20 Ränder (Leerzeichen anderer Schriften, U+2028, CRLF, offene Kommentare und Tags, Links aller
  Arten, die Grenze von 4000 Zeichen je Absatz),
- 400 Zufallstexte mit festem Startwert.

Alle 426 stimmen. JavaScripts `\s`, `.` und `$` stehen ausgeschrieben im Muster, denn ICU versteht
sie anders (gemessen mit NSRegularExpression gegen Node): `\s` trifft U+0085, aber nicht U+FEFF;
`.` trifft weder U+000B noch U+0085; `$` trifft auch vor einem letzten Zeilenende. Zwei Gegenproben schlugen an: `.` mit U+2028 bei 8 von 426, `trim` ohne U+00A0 bei 42.

**Preis.** Eine README von 256 KB aus lauter offenen Links unter der Absatzgrenze braucht in Swift
1,4 s (Debug-Bau), in Node 70 ms; ICU sucht langsamer zurück als V8. Echte READMEs sind schnell,
alle 426 zusammen 0,11 s. Deshalb liest der Inspektor die README außerhalb des Main-Threads und
zeigt bis dahin „Lade die Beschreibung…“. Ein einzelner Absatz von 120 KB dieser Art ist dank der
Grenze in 9 ms Text; ohne sie 22 s (`overlongParagraphIsPlainText`).

**Liste.** Die Suche und die Teilung in Plugins (Markierung `quartz-plugin`, nicht archiviert) und
„Weitere Repositories“ stehen im Kern (`MarketplaceResult.split`), nach Sternen und sonst in der
Reihenfolge des Katalogs. Der Satz, was die weiteren Repositories sind, steht als Zeile in der Liste,
nicht im Abschnittskopf, der ihn auf eine Zeile kürzte.

**Installieren** geht über `PluginsModel.add` (`quartz plugin add` mit Snapshot `pluginChange`) und
wartet zuerst auf die Schreib-Schlange von Installiert: Der CLI schreibt die Config, und ein
später gespeicherter Stand hätte den neuen Eintrag wieder entfernt.

Angesehen gegen GitHub (nur lesend) an der gui-test-Kopie, Hell und Dunkel: 47 Plugins im Katalog,
44 davon im Projekt, eine README mit Codeblöcken und Links, „Weitere Repositories“ auf- und
zugeklappt, Katalog neu geladen. Nicht ausgelöst: Installieren und Hinzufügen, das wären npm- und
git-Läufe ins Netz. Der UI-Test öffnet den Reiter nicht, weil er ohne Netz läuft.

Geändert: Der leere Inspektor sagte „Wähle links ein Plugin“. Der Hinweis „nicht erreichbar“
verwies auf einen GitHub-Token „in den Einstellungen“, wo QuartzHub ihn nicht hat, und hatte vier
Sätze.

### Die Vorschau neben den Plugin-Editoren

Vorbild `components/SitePreview.tsx`, `utils/sitePreview.ts`, `data/componentSelectors.ts` und
`electron/main/services/previewHighlight.ts`. Navigationen, Zusätzliche Inhalte, Mehrsprachigkeit
und Formulare zeigen sie unter ihrer Liste (`EditorPreview`).

**Kern.** Gemessen mit `scripts/site-preview-golden.mjs` gegen QuartzControls Code:
- welcher Selektor einen Eintrag findet (`ComponentSelectors`), 14 Einträge mit Kopien und Klassen;
- ob ein Bericht des Markierungsskripts gilt, 21 Fälle;
- der Zoom-Ausschnitt, 40 Fälle;
- die nächste Seite mit dem Eintrag und welcher Satz unter der Vorschau steht.

Seitenpfade werden nach Bytes verglichen, nicht mit `==` („Über“ in NFC und NFD sind zwei Seiten,
wie in Node). Das Markierungsskript selbst ist QuartzControls `previewScript`, wie dessen Bundle es
übersetzt. Das Golden-Skript schreibt es als `PreviewScript.swift`, und ein zweiter Lauf lässt die
Datei byte-gleich. Drei Gegenproben schlugen an: Vergleich mit `==`, Zoom-Grenze 2,0, Kopien nicht
ausgenommen.

**Skalieren.** Die Website wird in echter Gerätebreite gerendert (Desktop mindestens 1280 px) und
auf die Spalte verkleinert, wie QuartzControls iframe mit CSS-Transform. Nativ hängt die WKWebView
in einer Ansicht, deren `bounds` der Ausschnitt der Website sind. AppKit zeichnet sie dann skaliert
und rechnet Klicks zurück, und die Web-Ansicht behält ihre Größe, also bleibt auch der Viewport der
Website gleich. In der laufenden App: 1280 px gezeigt mit 73 %, scharf; der Zoom auf eine
Navigation zeigt sie mit 100 %.

Das Skript meldet sich mit `parent.postMessage`. In der Web-Ansicht ist die Website das oberste
Fenster, `parent` ist also die Seite selbst; ein Nutzerskript reicht die Meldung als Text an
QuartzHub weiter, und `PreviewMarks.report` prüft jedes Feld. Gesehen: Markierung und Abdunkeln,
„Markiert: „Akkordeon #1““. Nach einer gespeicherten Änderung lädt Quartz' eigener Live-Reload die
Seite neu, und die Markierung steht wieder.

### Plugins: Navigationen

Vorbild `routes/Plugins/Navigations.tsx`, `navigationVariants.ts`, `instanceClass.ts`,
`navigationRoot` in `optionFormExtras.ts` und der Teil von `LayoutEditor/utils.ts`, den die Editoren
mit der Bühne teilen (`LayoutEntries`). Gemessen mit `scripts/navigations-golden.mjs`, mit dem
Schema von quartz-navigations aus gui-test:
- 3290 Gründe „wirkt nicht“ (zehn Varianten, sieben Werte für `mobile`, alle Optionen);
- 52 Form-Einstellungen mit Leitabschnitt, Sätzen und dem, was nur gesetzt erscheint;
- 22 Namen als Klasse, 12 Einträge und 11 Duplikate mit Neunummerierung.

Drei Gegenproben schlugen an (Slug ohne NFKD, `columns` mit Wirkung, Kopie behält `id`).

**Abweichung.** Ein Eintrag an einer Position, die die Bühne nicht kennt, ließ QuartzControls
`duplicateAfter` werfen; `LayoutEntries` antwortet `nil`. QuartzControls `getLayout` zählt auch eine
Liste als Layout-Block (`typeof` sagt `object`); das ist übernommen.

**Oberfläche.** Liste und Vorschau stehen untereinander in einem `VSplitView`, die gewählte
Navigation im Inspektor: an/aus, die Variante als Kacheln, dann die Optionen dieser Variante. Was
bei ihr nicht wirkt, steht ausgegraut mit den Varianten, bei denen es wirkt. „Neue Navigation“
öffnet dieselben Kacheln in einem Popover. Alles schreibt über die Schlange von Installiert.

Gemessen an der gui-test-Kopie, Hell und Dunkel:
- Variante Baum und zurück zu Akkordeon: eine Zeile, danach byte-gleich;
- Duplizieren nummeriert die linke Seitenleiste neu (vier Prioritäten) und hängt die Kopie mit
  `className: nav-menue nav-menue-2` an;
- Entfernen über den Dialog nimmt nur die Kopie, die Neunummerierung bleibt (wie in QuartzControl);
- eine neue Leiste steht im Kopfbereich mit Priorität 80 und `nav-bar`, und nach dem Neubau
  markiert die Vorschau sie;
- „Alle Optionen in der Plugin-Liste“ öffnet Installiert mit der Navigation im Inspektor.

Gefunden in der laufenden App: „Auf der Bühne zeigen“ und „Alle Optionen …“ standen nebeneinander
und wurden im Inspektor abgeschnitten; jetzt stehen sie untereinander.

### Der Code-Editor, zum ersten Mal gebraucht

`App/Components/CodeEditor.swift` baut die Entscheidung aus 4b. Es ist NSTextView mit TextKit 2 und
den Zeilennummern aus dem Messgeschirr (eine Nummer je Absatz, ein umbrochener Absatz behält eine).
Dazu kommen die Suchleiste des Systems, Hell und Dunkel über dynamische Systemfarben und das
Einfügen an der Cursorstelle, nur wenn der Nutzer einen Cursor gesetzt hat (sonst ans Ende, auf
eine eigene Zeile, wie in QuartzControl). Gefärbt wird je Zeile durch `CodeColors` im Kern (HTML und
Markdown; CSS und SCSS kommen mit Stile). Regeln laufen nie über einen Zeilenumbruch. Ein
HTML-Kommentar oder ein Codeblock über mehrere Zeilen wird deshalb nur an seinen Marken gefärbt,
wo CodeMirror das ganze Dokument parste.

**Messung.** Eine Zeile in der Mitte von 5.000 Zeilen färben, 2.000-mal: zusammen 0,5 s für HTML
und Markdown. Die Gegenprobe (jede Regel über das ganze Dokument) lief nach zehn Minuten noch und
wurde abgebrochen. Die Schranke im Test liegt bei 5 ms je Zeile, weit über der Messung.

**Zwei Fehler, gefunden beim Klicken.** Beide sind behoben, und ihr Grund steht im Code:
- Die Einfügung kam nicht an, solange der Editor sie als Binding bekam. Eine Ansicht, deren `body`
  ein Binding nur weiterreicht, rechnet SwiftUI nicht neu, also lief `updateNSView` nie. Jetzt geht
  die Einfügung als Wert hinein.
- Danach lief die Einfügung, verschwand aber wieder. Sie geschah mitten in `updateNSView`; SwiftUI
  verwirft das Zurückschreiben ins Binding dort, und das nächste Update setzte den alten Text.
  Jetzt fügt der Editor einen Takt später ein.

Gemessen an der Datei auf der Platte: `{{title}}` steht nach „Snippet speichern“ an der
Cursorstelle.

### Plugins: Zusätzliche Inhalte

Vorbild `routes/Plugins/ExtraContent.tsx`, `ExtraContentFiles.tsx`, `layoutBoxes.ts`,
`boxSilenced` und `layoutBoxRoot` in `optionFormExtras.ts` und die Snippet-Felder aus
`PluginOptionsForm/snippets.tsx`. Gemessen mit `scripts/layout-boxes-golden.mjs`, mit dem Schema
von quartz-layout-box aus gui-test:
- 34 Optionssätze, je mit sechs installierten Fassungen für die Frage, wo das Plugin abbricht;
- sechs Umbenennungen eines Schnipsels über 17 Einträge;
- 372 Form-Einstellungen;
- dazu Bildverweise, Ordnernamen und Geschwisterwerte.

Nachgebaut ist auch JavaScripts Spread von Listen und Texten (`{ ...[1] }` ergibt `{"0": 1}`).
`mentionsImage` vergleicht UTF-16-Einheiten wie `includes`: „ü“ und „u + ̈“ sind zwei Namen. Vier
Gegenproben schlugen an:
- `byLang` wird beim Umbenennen nicht nachgezogen;
- `null` bricht nie;
- der Ordnername ohne `trim`;
- Swifts `contains` statt `includes`.

**Oberfläche.** In der Mitte stehen drei Teile untereinander in einem `VSplitView`: die Boxen, die
Dateien hinter ihnen (Schnipsel je Ordner, Bilder, das Projektbild nur lesend) und die Vorschau. Die
gewählte Box steht im Inspektor: an/aus, „Text in der Konfiguration | Datei“ als Kacheln, dann die
Optionen. Was nicht wirkt, steht grau mit dem Grund. Die Options-Form kennt jetzt den Projektpfad.
Ein Feld mit `x-quartz-widget: snippetFile` ist dann eine Dateiauswahl mit „Neu“, „Importieren…“
und „Bearbeiten“. Ein HTML- oder Markdown-Text bekommt „Bild einfügen…“ (ein SVG auf Wunsch als
Code über `InlineSvg`), und wo das Plugin `placeholders` hat, die Liste der Platzhalter. Installiert
benutzt dafür jetzt dieselben Extras ohne Kacheln wie QuartzControl (`OptionRoot.withoutTiles`).
Fragen mit drei Antworten (Ersetzen, Vorhandene verwenden, Abbrechen) sind `Confirm.choose`.

Gemessen an der gui-test-Kopie, Hell und Dunkel:
- Datei → Text → Datei an „Über dieses Handbuch“: Aus einer Markdown-Datei wird der Beispieltext,
  `file` steht grau mit „wirkt nicht“. Zurück mit „Text entfernen“ ist die Config byte-gleich.
- `sidebar-note.en.md` → `sidebar-note.english.md`: Die Datei heißt neu, die Box nennt für `en`
  den neuen Namen. Zurückbenannt ist die Config byte-gleich.
- Neue Box: links, Priorität 50, `layout-box-neue-box`. Duplizieren gibt der Kopie
  `layout-box-neue-box layout-box-neue-box-2` und nummeriert links neu. Zwei gleich benannte
  Boxen heißen „Neue Box #8“ und „#9“. Entfernen über den Dialog nimmt nur die Kopie.
- Snippet bearbeiten: Tippen zeigt „Ungespeichert“. `{{title}}` aus der Liste landet am Cursor,
  „Snippet speichern“ schreibt die Datei. Danach ist die Datei zurückgespielt.

Gefunden in der laufenden App und behoben:
- „Neu“, „Importieren…“ und „Bearbeiten“ neben der Dateiauswahl waren im Inspektor auf je einen
  Buchstaben gekürzt. Dasselbe galt für „Bild einfügen…“ neben „Schließen“ und „Snippet
  speichern“. Beide Reihen stehen jetzt in eigenen Zeilen.
- Die Kachel „Text in der Konfiguration“ trennte das Wort.
- Der Status „… ist gespeichert.“ drückte den Dateinamen auf „side…te.md“.
- Die Platzhalter waren als graue Knöpfe zu breit; jetzt sind sie randlos in der Akzentfarbe.

Nicht gemessen: Importieren und „Bild einfügen…“ mit dem Dateidialog, In den Papierkorb, Ordner
hinter einer Verknüpfung.

### Plugins: Mehrsprachigkeit

Vorbild `routes/Plugins/Multilanguage.tsx` und `multilanguageOptions.ts`. Gemessen mit
`scripts/multilanguage-golden.mjs`, mit dem Schema von quartz-multilanguage aus gui-test:
- 13 Optionssätze, je mit 188 Schritten zusammen: umbenennen, entfernen, veröffentlichen,
  tauschen, ändern, hinzufügen, unverändert zurückschreiben;
- die Gruppen der Einstellungen in beiden Sprachen;
- 24 Code-Prüfungen.

QuartzControl merkt sich in einer WeakMap, aus welchem geschriebenen Eintrag eine Sprache gelesen
ist, damit ein `DE`, das niemand angefasst hat, `DE` bleibt. In Swift ist das ein Feld `readFrom`
am Eintrag, das beim Ändern wegfällt. Die Golden-Datei beschreibt die Schritte deshalb als Schritte
auf den Einträgen, und der Test geht sie auf seinen eigenen nach.

`normalizeCode` nimmt `NSString.lowercased`, nicht Swifts `lowercased()`: Nur das schreibt ein
Schluss-Sigma als „ς“ wie JavaScripts `toLowerCase` (gemessen mit „ΣΟΦΟΣ“). Vier Gegenproben
schlugen an:
- `readFrom` vergessen;
- Swifts Kleinschreibung;
- ein zweiter Eintrag vor seiner Sprache bleibt beim Tauschen stehen;
- die Gruppe ohne Namen nicht zuletzt.

Für den letzten Fall hat das echte Schema keine Felder, deshalb steht ein kleines eigenes Schema
in der Golden-Datei. Eine fünfte Gegenprobe, Sortieren ohne den Platz als Gleichstand, schlug
nicht an: Swifts Sortierung ist in der Praxis stabil, zugesagt ist es nicht, und der Gleichstand
bleibt im Code.

**Oberfläche.** Oben steht der Eintrag mit „Eingeschaltet“ und „Alle Optionen“. Darunter kommt
eine Liste mit zwei Abschnitten: die Sprachen (ziehen, Anordnen ▸ Nach oben/unten mit ⌥⌘↑/⌥⌘↓,
Kontextmenü, Bedienungshilfe-Aktion) und die Gruppen der Einstellungen mit einer Zeile, was sie
gerade sagen. Unten steht die Vorschau. Im Inspektor steht eine Sprache, eine Gruppe (eine Gruppe
aus einem einzigen Objekt zeigt dessen Inhalt mit `switcher.`-Schlüsseln) oder der Überblick.

Gemessen an der gui-test-Kopie, Hell und Dunkel; nach jedem Hin und Zurück war die Config
byte-gleich:
- `en` → `en-GB` schreibt `en-gb` in einer Zeile und behält die Auswahl;
- `de` als Code von English sagt „Diese Sprache gibt es schon.“ und schreibt nichts;
- „Früher“ tauscht die Einträge, ⌥⌘↑ tauscht zurück (das Menü bot für die zweite Sprache nur
  „Nach oben“ an);
- `FR` hinzufügen schreibt `- fr`, Entfernen über den Dialog nimmt es wieder;
- English nicht veröffentlichen schreibt `publishLanguages: [de]`. Deutsch entfernen fragt dann
  „… entfernen und English veröffentlichen?“ mit „Entfernen und veröffentlichen“ (abgebrochen),
  wieder einschalten gibt `[]`;
- `switcher.showCurrent` aus und an.

Gefunden in der laufenden App: Die Code-Spalte brach „EN-GB“ in zwei Zeilen; sie ist jetzt
einzeilig und so breit wie nötig.

### Plugins: Formulare

Vorbild `routes/Plugins/Forms.tsx` mit `FormFieldsEditor.tsx`, `FormText.tsx`, `FormsTexts.tsx`,
`FormsKeys.tsx` und `FormsRelay.tsx`; die Regeln in `formsOptions.ts` (`FormsOptions`, gemessen
mit `scripts/forms-options-golden.mjs`).

**Wo ein Formular eingebettet ist** (`FormUsages`), gemessen mit `scripts/form-usages-golden.mjs`
gegen QuartzControls `shared/formUsages.ts` und `contentService.formUsages`:
- 31 Pfade durch `quartzSlug` und `slugPath`;
- 50 Seiten durch `pageFormUse` (Frontmatter, Codeblöcke, Platzhalter, Inline-Code, CR, U+2028,
  U+0085, NFC und NFD);
- 12 kleine Projekte durch den ganzen Scan, mit und ohne globby, mit verlinktem Vault, einer
  unlesbaren Datei und den Filtern remove-draft und explicit-publish.

Die Frontmatter liest der Helfer `content-files` (`op: parse`) mit dem yaml-Paket, das
QuartzControl nahm, alle Seiten in einem Aufruf. Ein Datum (ein Dokument mit `%YAML 1.1`) wird
dabei `null`: JSON hätte es zum String gemacht, und der Scan hätte ihn als Titel gelesen. Die
Regeln sind von Hand nachgebaut, wo ICU anders liest als V8: `.` hält bei U+0085 an, `(?i)` nimmt
das Kelvin-Zeichen für ein k, Swifts `==` hält „ü“ und „ü“ für gleich. Sieben Gegenproben
schlugen an: Swifts `==`, `(?i)`, das Zählen der unlesbaren Dateien, Swifts Kleinschreibung,
ohne Sortieren, die Filter ohne ihren Schalter und der Helfer ohne die Datumsregel.

Abweichung: QuartzControl zeigte bei einem Scan, der scheitert, die Sätze von „Startseite
anlegen“ („… deshalb ist keine Startseite angelegt“). Der Scan hat eigene Sätze.

**Oberfläche, Teil 1: Liste und Formular.** Oben stehen der Eintrag mit „Eingeschaltet“ und
„Alle Optionen“, das Urteil von quartz-forms (`FormsCLI.check`, 600 ms nach dem letzten Schreiben,
nachdem die Warteschlange leer ist) und die Warnung, wenn eine Seite ein Formular nennt, das es
nicht gibt. Die Liste hat zwei Abschnitte, die Formulare und die Einstellungen für alle. Darunter
steht die Vorschau; sie markiert `form.quartz-form[data-form="<id>"]` und geht über „Zeigen“
(`PreviewGoTo`, neu in `EditorPreview`) auf eine Seite, die das Formular einbindet. Im Inspektor
stehen das Formular in Teilen zum Aufklappen (welche offen sind, gilt für alle Formulare je
Fenster) oder ein Bereich. Jedes Schreiben geht gegen den neuesten Stand des Formulars; ein Wert,
den die Vorlage schon gibt, wird nicht geschrieben. Der Feld-Editor, die eigenen Bereiche
Schlüssel, Texte und Layout-Position und das Relay folgen; bis dahin zeigt „Felder“ den
allgemeinen Listen-Editor, und die Zeile „Relay“ fehlt.

Gemessen an der gui-test-Kopie, Hell und Dunkel; nach jedem Hin und Zurück war die Config
byte-gleich:
- Titel setzen und leeren;
- `kontakt` → `kontakt-neu`: Die Rückfrage nennt `kontakt.md`. „Abbrechen“ schreibt nichts,
  „Kennung ändern“ schreibt eine Zeile, und die Warnung über die unbekannte Kennung erscheint.
  Zurück fragt nicht, weil keine Seite `kontakt-neu` nennt;
- Neues Formular mit „Feedback“: quartz-forms meldet „recipient: das Relay braucht den Namen des
  Empfängers“ an Zeile und Teil. Duplizieren und Entfernen (die Rückfrage sagt „Keine Seite bindet
  es ein.“);
- „Anonym“ ein (dann steht „wirkt nicht“ bei „Seite mitschicken“) und aus;
  `showFingerprint: false` landet unter `encryption`;
- „Kopieren“ beim Codeblock legt die drei Zeilen in die Zwischenablage.

Gefunden in der laufenden App:
- Die Kennung im Hinzufügen-Popover folgte der Vorlage nicht: Das Feld schreibt beim Fokussieren
  seinen Wert zurück, und das zählte als getippt. Jetzt zählt nur ein geänderter Text.
- Der Hinweis darunter war bei „Ziffern…“ abgeschnitten: Das Popover hängt am Kopf eines
  Listenabschnitts und erbt dessen eine Zeile. `.lineLimit(nil)` am Popover behebt das.
- Ein abgebrochenes Umbenennen ließ die neue Kennung im Feld stehen.
- Das rote Problem-Abzeichen war auf einer ausgewählten Zeile kaum lesbar; jetzt ist es gefüllt.
