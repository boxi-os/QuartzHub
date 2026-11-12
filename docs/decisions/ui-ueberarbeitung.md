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
„Bewegung reduzieren“ keine Bewegung), `Callout`, `PageTabs` (in einer `safeAreaBar`), `SettingsForm`
und `SettingsSection` (Variante C).

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
  **Noch nicht umgestellt** ist der Inhalt der Reiter: Stile ▸ Basis ist ein `Form`, in das die Seite
  ihre Hinweise als `Section` einschiebt; die Editoren von Plugins und Layout sind eigene
  Arbeitsflächen. Das ist ein eigener Schritt je Reiter.

