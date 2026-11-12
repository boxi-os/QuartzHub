# UI-Überarbeitung

Seit 2026-11-12. Das Konzept mit Mock-Fenster, Regeln und Aufnahmen des Stands davor ist eine private
Konzeptseite (Artifact „QuartzHub UI-Konzept“). Hier stehen die Entscheidungen und was beim Bau des
Prototyps (Branch `ui-ueberarbeitung`) gemessen wurde.

## Entscheidungen des Nutzers

- **Unterreiter bleiben im Inhalt**, als eine Komponente für alle vier Seiten (`PageTabs`), nicht in
  Seitenleiste oder Symbolleiste.
- **Mindest-macOS 26.** Liquid Glass gibt es dann überall, die neuen Toolbar-APIs (`ToolbarSpacer`,
  `.glassProminent`, `safeAreaBar`) brauchen kein `#available`.
- **Formulare im breiten Fenster: Variante C** („Erklärung daneben“). Ab etwa 900 pt Inhaltsbreite
  stehen Überschrift und Erklärung eines Abschnitts links, die Einstellungen rechts daneben; darunter
  eine Spalte. Verworfen: A (mittig, viel leere Fläche) und B (zwei Spalten, die Leserichtung springt).
  B bleibt möglich für Seiten mit zwei gleichwertigen Abschnitten.
- **Bewegung statt Sprüngen:** Wechsel an Breitengrenzen, Auf- und Zuklappen, Ein- und Ausblenden
  werden animiert; Seiten- und Reiterwechsel nicht.

## macOS 26 als Ziel

Gemessen am 2026-11-12 mit Xcode 27.1: Das Anheben brachte sechs neue Veraltet-Warnungen, alle
behoben. `Text + Text` ist seit macOS 26 veraltet (jetzt Interpolation von `Text` in `Text`), und
`posix_spawn_file_actions_addchdir_np` heißt jetzt ohne `_np`. Im Paket steht `.macOS("26.0")`, weil
`.v26` erst ab swift-tools-version 6.2 bekannt ist und das Paket auf 6.0 bleibt.

## Titel, Verlauf, Symbolleiste, Menüs

Gemessen am 2026-11-12 an der App (Debug-Bau, Kopie von gui-test, Wegwerf-Profil, macOS 27.2).

- **Titel = Ort.** `navigationTitle` ist die Seite, `navigationSubtitle` der Reiter (leer auf Seiten
  ohne Reiter). Der Bedienungshilfe-Baum liest beides zusammen („Plugins – Installiert“), deshalb
  findet der Rauchtest das Projektfenster jetzt über die Seitenleiste (`sidebar`), nicht mehr über
  den Titel.
- **Menü „Fenster“.** Mit dem Ort als Titel stünde dort bei zwei Projekten auf derselben Seite
  zweimal „Konfiguration (Website)“. `NSApp.changeWindowsItem` mit „gui-test – Plugins › Formulare“
  hielt erst nicht: AppKit schreibt den Eintrag neu, sobald SwiftUI Titel oder Untertitel setzt.
  Gelöst mit KVO auf `title` und `subtitle` (`WindowMenuTitle`); gemessen über System Events:
  „gui-test – Plugins › Formulare“, nach Zurück „gui-test – Übersicht“.
- **Verlauf** (`NavigationHistory`, ersetzt `ReturnLink`): Seite und Reiter je Schritt, höchstens
  50, nicht über einen Neustart. Ein Schritt entsteht, wenn die Seite oder ihr Reiter wechselt; der
  erste Reiter, den eine Seite nach dem Erscheinen meldet, vervollständigt nur den Ort. Ein Schritt
  auf eine andere Seite geht durch `UnsavedGuard`, wie die Seitenleiste. Gemessen: Plugins ▸
  Navigationen, Formulare, dann dreimal Zurück: Navigationen, Installiert, Übersicht.
  Falle: Nimmt eine Seite beim Erscheinen einen geschickten Reiter, liefert das Lesen von
  `@SceneStorage` im selben Abschluss womöglich noch den alten. Gemeldet wird deshalb erst über
  `onChange(of: tab)`.
- **Kürzel.** `.keyboardShortcut("[")` wird auf der deutschen Tastatur automatisch zu ⌘Ö (Vorwärts
  ⌘Ä), wie in Safari und Finder; per System Events gemessen (`AXMenuItemCmdChar` „Ö“), beide Tasten
  wirken. Projekt ▸ Server starten ⌘R, stoppen ⌘., Build ausführen ⌘B; keine Kollision mit
  vorhandenen Kürzeln. Gemessen von der Übersicht aus: ⌘R startet den Server der gui-test-Kopie
  („Server stoppen“ wird aktiv), ⌘. stoppt ihn, danach lauscht nichts mehr auf 8080. Server und
  Build nehmen die Optionen und den Ausgabeordner, die Vorschau & Build für das Projekt hält.
- **Reihenfolge rechts.** Hing der Inspektor-Schalter außen am Seiteninhalt (`.toolbar` nach der
  Seite), stand er vor „Speichern“: Symbolleisten-Einträge äußerer Modifier kommen zuerst. Am Inhalt
  des Inspektors (`.inspector { … .toolbar { } }`) steht er ganz rechts und bleibt auch bei
  ausgeblendetem Inspektor sichtbar (beide Zustände aufgenommen).
- **Rauchtest.** Neu: Übersicht ▸ Link auf Plugins, Titel nennt die Seite und nicht das Projekt,
  Zurück, Vorwärts. Gegenprobe: mit stillgelegtem Zurück scheitert er („Zurück did not lead to the
  overview“).

## Bausteine

`App/Components/Design.swift`: `Spacing` (4, 8, 12, 16, 20, 24; Seitenrand 20), `FormWidth`, `Motion`
(`.smooth(duration: 0.3)` für Anordnungen, `.snappy(duration: 0.2)` für Ein- und Ausblenden, mit
„Bewegung reduzieren“ keine Bewegung), `Callout`, `PageTabs` (eine eigene Zeile über dem Inhalt,
siehe „Reiter-Inhalte“), `SaveButton`, `SettingsForm` und `SettingsSection` (Variante C), `Card` und
`CardGrid`, `WorkspaceHeader`.

### Formulare: Variante C mit nativen Zeilen

Ein `Form` kann die Überschrift eines Abschnitts nicht neben seine Zeilen setzen. Gemessen am
2026-11-12 mit einem Testprogramm (Scratchpad, SwiftUI auf macOS 27.2) und dann in der App:

- **Ein gruppiertes `Form` je Abschnitt** mit `.scrollDisabled(true)` und
  `.fixedSize(horizontal: false, vertical: true)` in der Scrollansicht der Seite wird so hoch wie
  seine Zeilen und behält die Optik der Plattform (Beschriftung links, Feld, Schalter und Auswahl
  rechts). Daneben oder darüber steht die Überschrift, umgeschaltet mit `AnyLayout`
  (`HStackLayout`/`VStackLayout`).
- **Scrollen:** Das Mausrad über einem Kasten scrollt die Seite (CGEvent-Scrollen über
  „Projektbild“ bei 1200 pt, die Seite lief weiter); die gesperrten Formulare halten nichts fest.
- **Ränder:** Ein gruppiertes `Form` lässt etwa 20 pt über und unter seinem Kasten.
  `contentMargins(.vertical, …)` ändert daran nichts, weder für `.scrollContent` noch für alle
  Stellen. Ausgeglichen mit −12 pt über dem Kasten, wenn die Überschrift darüber steht. Dann
  verdeckte der Hintergrund des Formulars die Überschrift; `.scrollContentBackground(.hidden)` und
  `zIndex` lösen das.
- **Grenze:** ab 900 pt Breite der Seite stehen Überschrift und Erklärung daneben (Spalte 220 pt),
  bis 1120 pt; darunter eine Spalte bis 880 pt. Bei 1200 × 780 mit Inspektor untereinander, bei
  1680 × 1000 daneben. Zwischen den Abschnitten steht dann eine Linie (`Group(subviews:)`).
- **Bewegung:** Bei 1300 pt Fensterbreite und ⌃⌘I wechselt die Konfiguration von untereinander auf
  daneben. Eine Aufnahme direkt nach dem Tastendruck zeigt den Inspektor halb draußen und die Kästen
  auf dem Weg nach rechts, eine Sekunde später den Endstand.

## Konfiguration

Die erste Seite auf den neuen Bausteinen: `SettingsForm` mit den zehn Abschnitten von Website, die
Reiter als `PageTabs`, Fehler als `Callout`. Zwei Beschreibungen (Content-Ordner, Eingebaute
Verarbeitung) stehen jetzt als Erklärung beim Abschnitt statt als erste Zeile. Speichern ist nur
mit Ungespeichertem aktiv; „Nicht gespeichert“ und „Gespeichert.“ daneben entfallen, das sagt der
Punkt im Schließen-Knopf. Der Rauchtest prüft das jetzt am Knopf (aus, an, nach ⌘S wieder aus);
Gegenprobe: mit immer aktivem Speichern scheitert er („Speichern is on with nothing to save“).

## Snapshots

Die Musterseite für den Typ Liste, gemessen am 2026-11-12 an der gui-test-Kopie (18 Snapshots).

- **Tabelle über die volle Breite** (`Table`) mit Zeitpunkt, Name, Anlass; ab 720 pt Breite der Seite
  dazu der Commit. Spalten, die mit der Breite kommen, nimmt `Table` nicht nachträglich auf: Ohne
  `.id(wide)` fehlte der Commit auch bei 1680 pt, mit erscheint er. Löschen über das Kontextmenü und
  die Entf-Taste (`onDeleteCommand`), leer und beim Laden ein `ContentUnavailableView` bzw. `ProgressView`.
- **Kein Kopf mehr über der Liste.** „Snapshot anlegen“ ist ➕ in der Symbolleiste und öffnet ein
  Popover mit Name und Erklärung (Return legt an). Gemessen: „UI-Test Popover“ angelegt, die
  Meldung „Snapshot angelegt.“ steht als `Callout` über der Tabelle, die Zeile oben mit „Von dir“.
  Die Einstellung „Content-Ordner mitsichern“ und der Satz zu Git-Sync stehen im Inspektor, wenn
  nichts gewählt ist.
- **Auswahl:** Ein Klick auf „quartz-betterbases“ öffnet den Snapshot im Inspektor mit „4 Dateien
  unterscheiden sich“ wie vorher.

## Vorschau & Build

Die Musterseite für den Typ Arbeitsfläche, gemessen am 2026-11-12 an der gui-test-Kopie.

- **Die Website füllt die Mitte** (`ScaledSite`, aus `EditorPreview` gelöst: `MarkedSite` mit dem
  `CutView`, der die Bounds skaliert). Desktop rendert mit `max(Tablet-Grenze + 1, 1280)` px und
  wird eingepasst. Vorher bekam die Vorschau die Breite der Formularzeile (rund 570 pt) und zeigte
  deshalb auch bei 1680 pt das Handy-Layout der Website. Jetzt: 900 × 560 Desktop-Layout eingepasst,
  1200 × 780 „1280 px · 54 %“, 1680 × 1000 „1280 px · 91 %“. Mobil 390 px mittig mit 100 %.
- **„100 %“** zeigt echte Pixel und scrollt seitlich. Zuerst war das eine zweite Webansicht; der
  Wechsel lud die Website neu und sprang von „Kontakt“ zurück auf die Startseite. Jetzt ist es eine
  Webansicht in einer Scrollansicht, die beim Einpassen gesperrt ist; „Kontakt“ bleibt beim Wechsel
  auf Mobil und auf 100 %.
- **Die Leiste über der Website** (Breite, Maßstab, Einpassen/100 %, Neu laden, Browser) war bei
  900 pt mit Inspektor breiter als die Mitte und schob die Seitenleiste aus dem Fenster. Jetzt drei
  Stufen über `ViewThatFits`: alles, dann Menüs statt Segmenten, dann ohne Maßstab.
- **Symbolleiste:** Build als Symbol (Hammer), Neu starten, dann Starten bzw. Stoppen als die eine
  hervorgehobene Aktion (`.glassProminent`). Der Knopf in der leeren Vorschau ist nicht hervorgehoben.
- **Ausgabe** unten wie in Xcode: ein `DisclosureGroup` mit beiden Konsolen nebeneinander, 160 pt hoch.
  Der Zustand wird gemerkt (`server.outputOpen`).
- **Inspektor:** Adresse mit Kopieren, Angaben zum Lauf, Server-Einstellungen, die laufenden Server
  auf dem Mac, der einmalige Build mit Ausgabeordner. Zwei Zeilen brachen dort hässlich um
  („lo-cal-host :808 0“, „Ausga-beordner (optional)“) und stehen jetzt untereinander.

## Die übrigen Seiten

Nach dem OK des Nutzers zum Prototyp (2026-11-12), eine Seite je Commit, jede mit Bau,
`qh-check i18n`, Rauchtest über alle Seiten in zwei Größen und Ansehen in der App:

- **Formulare:** Updates, Git-Sync, Vorlagen sind `SettingsForm`. Dazu bekam `SettingsSection` einen
  Zustand neben der Überschrift („Nicht prüfbar“, die Zahl der Änderungen) und eine Test-Kennung an
  der Überschrift, weil die Kennung eines `Form` nicht im Baum ankommt. Abschnitte ohne Überschrift
  gehen im Abschnitt davor auf (Vorlagen: die Knöpfe bei ihren Bestandteilen).
- **Listen:** Veröffentlichen und Dokumente ohne Kopf über der Liste. ➕ legt an, „Zugänge
  verwalten“ ist ein Symbol, „Jetzt veröffentlichen“ bzw. „Exportieren“ die hervorgehobene Aktion;
  die Erklärungen stehen im Fuß der Liste. Die Ziele der gui-test-Kopie sind echt: angesehen, nicht
  ausgelöst.
- **Übersicht:** `CardGrid` mit `Card`, bei 1200 pt zwei, bei 1680 pt drei Spalten, das Band
  „Alles ok“ bzw. „Handlungsbedarf“ über die volle Breite.
- **Stile, Layout, Plugins:** die Reiter als `PageTabs` (Plugins mit sechs Reitern ist bei 1200 pt
  ein Menü, Layout und Stile Segmente, bei 900 pt alle drei Menüs) und Speichern nach der Regel.
  Den Inhalt der Reiter behandelt der nächste Abschnitt.

## Reiter-Inhalte

Je Seite ein Commit, gebaut und mit `qh-check i18n` und dem Rauchtest (11 von 11) geprüft, jeder
Reiter bei 1200 × 780 angesehen, Basis und Community-Themes auch bei 1680 × 1000:

- **Die Reiter-Leiste ist eine Zeile über dem Inhalt, keine `safeAreaBar`.** Gefunden bei 1200 × 780:
  Navigationen, Zusätzliche Inhalte, Mehrsprachigkeit und Formulare zeichneten ihre Einleitung unter
  das Reiter-Menü. Grund: Der Einschub der `safeAreaBar` kommt in einem `VSplitView` (AppKit) nicht
  an. Seit der Leiste als eigener Zeile beginnt jeder Inhalt darunter, auch auf Konfiguration
  (angesehen). Damit läuft der Scroll-Kanten-Effekt nicht mehr unter den Reitern durch, nur noch unter
  der Symbolleiste.
- **Die Symbolleiste eines inneren Views kommt nach der der Seite.** Gesehen auf Stile ▸ Eigenes CSS:
  Die drei Aktionen des Reiters standen rechts von „Speichern“. Ein Reiter mit eigenen Aktionen
  stellt deshalb auch „Speichern“ selbst hinter sie (`SaveButton`, von der Seite gereicht), und die
  Seite lässt ihres auf diesem Reiter weg. So bei Eigenes CSS und Layout ▸ Frames.
- **Stile:** Die Hinweise der Seite (Speicherfehler, Schriftenhinweis, Umzug nach
  `_quartzcontrol.scss`) stehen als `Callout` über jedem Reiter, statt als `Section` in jedes Formular
  geschoben zu werden. Basis und Community-Themes sind `SettingsForm`, ihre Erklärungen stehen neben
  den Abschnitten, feste Feldbreiten (320 pt) sind weg. Variablen bleibt ein einziges `Form` über die
  volle Breite: Der Sprung aus dem Inspektor scrollt zu einer Zeile, und in den Abschnitten eines
  `SettingsForm` (je ein `Form`, das nicht scrollt) fände er sie nicht. Eigenes CSS: Importieren, Extern
  öffnen und Prüfen sind Symbole in der Symbolleiste, die Bänder `Callout`, der Pfad steht neben den
  Datei-Reitern.
- **Layout:** Bühne und Frame-Editor hatten je eine Kopie desselben Kopfes mit getöntem Rand. Beide
  sind jetzt `WorkspaceHeader` auf dem Hintergrund der Karten. Neuer Frame, Duplizieren und Löschen
  sind Symbole in der Symbolleiste.
- **Plugins:** Die vier Editoren haben keinen Kopf mehr über der Liste. Die Einleitung steht im
  Inspektor, „Neu …“ ist ➕ in der Symbolleiste, das Popover geht darunter auf (angesehen bei
  Navigationen). Die Zahl ist die Überschrift des Listenabschnitts. Marktplatz lädt den Katalog über
  ein Symbol in der Symbolleiste neu. Die Zeile mit Plugin, Schalter und „Alle Optionen“ bleibt: Das
  sind Bedienelemente, kein Kopf.
- **`Callout` enthält seine Kinder** (`children: .contain` statt `.combine`): Einige tragen einen
  Knopf, und zusammengefasst wäre er für die Bedienungshilfen nicht mehr erreichbar.

## Hinweise, Fehler und Erklärungen

`Warning`, `ErrorLine` und rund 90 frei gefärbte Zeilen (rot oder orange gesetzter `Text`, `Label` mit
Warnsymbol) sind ersetzt. Es gibt drei Arten Text neben einem Bedienelement:

- **`Callout`** sagt etwas über den Zustand einer Sache: eine Datei fehlt, ein Laden scheiterte, eine
  Einstellung wirkt nicht. Sein Text ist auswählbar wie vorher der von `ErrorLine`, damit ein Pfad
  oder ein Grund kopiert werden kann. Hat ein Hinweis einen Knopf und scheitert dessen Aktion, wird
  der Kasten selbst zum Fehler (Umzug in Stile, Dev-Server neu starten), statt einen zweiten Kasten
  in sich zu tragen.
- **`FieldProblem`** sagt, was an der eben getippten Eingabe falsch ist, als Zeile direkt unter dem
  Feld (Symbol, rot, klein). Ein Kasten unter jedem Feld eines Popovers oder des Inspektors wog mehr
  als das Feld selbst (angesehen am Popover „Neues Formular“ mit einer vergebenen Kennung).
- **`Note`** erklärt, was ein Feld tut, in sekundärem Text. Erklärungen sind keine Hinweise und
  bleiben ohne Kasten.

Geblieben sind gefärbte Wörter, die Zustand in einer Zeile zeigen, kein Satz über ihn: „ungespeichert“
neben einem Eintrag, „Adresse fehlt“ in einer Empfängerzeile, „nicht installiert“ neben einer Schrift,
die Zeile des Build-Ergebnisses in Grün oder Rot.

## Hell

Alle Seiten und Reiter einmal in Hell aufgenommen (1200 × 780, 2026-11-12). Was auffiel: Karten,
Kennzahl-Kacheln und der Kopf der Arbeitsflächen (`.fill.quinary`) waren auf Weiß kaum zu sehen.
Gemessen gegen den Fensterhintergrund:

| | Hell | Dunkel |
|---|---|---|
| Fenster | 255 | 40 |
| Abschnitt eines gruppierten `Form` | 248 | 49 |
| `.fill.quinary` (vorher) | 253 | 42 |
| `.fill.quaternary` (jetzt, `Surface.card`) | 248 | 46 |

Damit sehen eine Seite aus Karten und eine aus Formularen gleich aus. In Dunkel ist das nach der
Rechnung über `NSColor.quaternarySystemFill` gemessen, nicht an einer neuen Aufnahme. Sonst war in
Hell nichts anders als in Dunkel.

## Nach dem ersten Ausprobieren

Rückmeldung des Nutzers nach dem Start aus Xcode (2026-11-12): Nach einem Reiter- oder Seitenwechsel
sprang die Anordnung im breiten Fenster noch animiert um, und Xcode zeigte viele Warnungen und
Meldungen.

- **Umspringen.** Gemessen bei 1680 × 1000 mit acht Aufnahmen direkt nach dem Wechsel Übersicht →
  Konfiguration: im zweiten Bild die schmale Spalte, im dritten und vierten der Übergang, erst im
  fünften die Anordnung mit der Überschrift daneben. Mitgeschrieben: `SettingsForm` bekam nacheinander
  180, 960 und 1170 pt, das Kartenraster der Übersicht eine, zwei, dann drei Spalten. Nur den ersten
  Wert ohne Animation zu nehmen reichte nicht (es lief von 180 auf 960 weiter). `onWidthChange` nimmt
  deshalb alles in der ersten halben Sekunde einer Ansicht ohne Animation; danach ist eine Änderung
  echt (Fenster, Inspektor, Seitenleiste) und wird animiert. Gegenprobe: Konfiguration steht im
  ersten Bild nach dem Wechsel breit da, die Übersicht mit drei Spalten. Was danach noch nachrückt,
  ist Inhalt (der Streifen „Alles ok“, das Projektbild), nicht die Breite.
- **„Reentrant operation in its NSTableView delegate“** auf Veröffentlichen und Dokumente.
  Veröffentlichen wählte sein erstes Ziel im selben Durchgang, in dem die Liste ihre Zeilen bekam; ein
  Durchlauf später ist die Warnung weg. Bei Dokumente lag es nicht an der Auswahl: Der Aufrufstapel
  (Haltepunkt auf `NSLog`) ist ganz AppKit und SwiftUI, `OutlineListCoordinator.diffRows` →
  `-[NSTableView endUpdates]` → die Zeilenhöhen, die sich selbst noch einmal anstoßen. Ausgelöst hat
  es der Abschnitt „Seiten“ des Ladens, den rund 140 Seiten ersetzten, mit Zeile wie nur mit
  Überschrift; ohne ihn kamen die Seiten ohne Warnung dazu (Versuche einzeln gezählt). Der Hinweis
  „Seiten werden geladen“ steht jetzt unter den Büchern.
- **String-Kataloge.** Die Oberfläche von Xcode gleicht beim Bauen die Kataloge ab und markierte alle
  2.786 Schlüssel als `stale`, weil sie `L10n.t("…")` nicht als Textaufruf kennt; in den Info.plist-
  Katalog trug sie drei Schlüssel nur auf Deutsch ein. Das sind Meldungen im Katalog-Editor, keine
  Fehler, und gehört nicht ins Repository. `xcodebuild` auf der Kommandozeile ändert die Kataloge
  nicht. Für das App-Ziel ist `SWIFT_EMIT_LOC_STRINGS` schon aus; den Abgleich für das Paket
  abzuschalten, ist offen.
- **Compiler-Warnungen.** Ein Neubau zeigte 24 verschiedene, fast alle älter als die Überarbeitung;
  alle behoben. Darunter: `canSave ? { … } : nil` an `.unsavedChanges` (die Closure bekam ihren Typ
  ohne den des Parameters), jetzt `.unsavedChanges(_:canSave:save:)`; `CTFontManagerRegisterGraphicsFont`
  (veraltet seit macOS 15) durch einen Deskriptor aus den Daten, eine variable Schrift auf Stärke 400
  gesetzt (ohne das zeichnete Noto Sans dünn, nebeneinander verglichen). Übrig ist nur die Notiz des
  `appintentsmetadataprocessor`, dass die App keine App Intents nutzt.
- **Laufzeit-Meldungen.** Über alle Seiten mitgeschrieben (`log show`, Default bis Fault): fast alles
  ist das System (WebKit-Sandbox, AppIntents, Spotlight, Netz). Von der App kam nur die Tabellen-
  Warnung oben und auf Stufe Info „ignoring retroactive Equatable conformance“ von AttributeGraph,
  ohne Typnamen im Log; nicht weiter verfolgt.

## Zweite Runde

Rückmeldung des Nutzers nach dem zweiten Start aus Xcode (2026-11-12), vier Punkte.

- **Layout ▸ Übersicht.** Die Tabelle stand in ihrer Karte links, so breit wie ihr Inhalt (1680 × 1000:
  rund die Hälfte der Karte leer). Jetzt teilen sich die Seitentypen, was die Komponentennamen übrig
  lassen (`ViewThatFits`: die Kartenbreite, wenn sie passt, sonst wie bisher seitlich scrollend; bei
  1000 pt scrollt sie). Eine Überschrift wie „Excalidraw-Seiten“ bleibt einzeilig.
- **Geteilte Bereiche.** Die vier Plugin-Editoren waren ein `VSplitView`: dessen Trennlinie ist eine
  Haarlinie zwischen zwei Flächen desselben Graus, und man sah nicht, dass sich etwas ziehen lässt.
  `SplitPanes` stellt jeden Bereich auf eine Karte (`paneCard`), dazwischen ein sichtbarer Griff mit
  dem Zeiger für Zeilenhöhe, Doppelklick stellt zurück, die Aufteilung bleibt je Fenster
  (`@SceneStorage`, Anteil der Höhe), mit Bedienungshilfe-Aktion ±40 pt. Gezogen und gemessen bei
  1680 × 1000: der Griff folgt, an der Mindesthöhe ist Schluss. Durchgesehen auf weitere Stellen:
  Übersicht, Layout und Frames haben schon Karten; die Ausgabe unter Vorschau & Build ist eine feste,
  einklappbare Konsole und ließe sich mit demselben Griff ziehbar machen, ist aber nicht gemacht.
- **Frames-Editor.** Gemessen mit Aufnahmen samt Zeiger (`screencapture -C`), Ziehen per CGEvent:
  - Anfasser zeigen den Zeiger ihrer Kante oder Ecke (`.pointerStyle(.frameResize(position:))`), ein
    Bereich die Hand (`.grabIdle`).
  - Ein Bereich auf einem belegten Platz ließ früher nichts geschehen, ohne Zeichen: der Bereich
    darüber nahm den Drop nicht an, die Zelle darunter bekam ihn nie. Jetzt ist das ganze Raster ein
    Ziel (`DropDelegate`): es kennt den gezogenen Bereich ab Beginn des Ziehens (`onDrag`, der Inhalt
    eines Drops ist erst beim Loslassen lesbar), zeigt während des Ziehens, wo er landet, in der
    Akzentfarbe, und rot gestrichelt mit dem Zeiger „nicht erlaubt“ (`.forbidden`), wo er einen
    anderen überdecken würde.
  - Eine Kante, die ein anderer Bereich aufhält, färbt den Bereich beim Ziehen rot.
  - Ein Klick ins Leere (Seite, Kasten des Rasters, freie Zelle) wählt ab.
  - Die Einstellungen des Frames (Name, Raster, Breite, Spuren, Linien, Breakpoints) standen über dem
    Raster und schoben es aus dem Fenster, während der Inspektor ohne Auswahl leer war. Sie stehen
    jetzt dort (`FrameSettingsInspector`): Ist kein Bereich gewählt, ist der Frame selbst gewählt, wie
    auf einer Zeichenfläche. Das Raster beginnt bei 1680 × 1000 jetzt rund 400 statt 790 pt unter der Fensterkante.
- **Akzentfarbe.** QuartzHub hat eine eigene, Petrol (`App/Assets.xcassets/AccentColor`, hell
  `#1A7F8E`, dunkel `#2A9AAA`, über `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` als
  `NSAccentColorName` im Info.plist). Sie gilt, wenn in den Systemeinstellungen „Bunt“ gewählt ist, wie
  bei Podcasts; eine feste Farbe dort geht vor. Die Töne sind so gewählt, dass weißer Text auf der
  Auswahl so lesbar bleibt wie auf dem System-Blau (Kontrast hell 4,7, dunkel 3,3; Blau rund 4 und
  3,6). Umschaltbar in den Einstellungen ist sie nicht: gemessen mit `.tint(.orange)` am Projektfenster
  wurden Reiter, Schalter, Menüs und alle Knopftexte orange, die Seitenleiste, die Listenauswahl und
  alles, was `Color.accentColor` nimmt, blieben bei der Farbe aus dem Katalog. Eine Wahl zur Laufzeit
  machte die App zweifarbig; eine Schnittstelle, die die Akzentfarbe einer App zur Laufzeit setzt,
  ist nicht bekannt.
