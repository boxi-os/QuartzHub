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
