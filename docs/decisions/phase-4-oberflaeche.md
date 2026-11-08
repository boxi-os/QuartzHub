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
