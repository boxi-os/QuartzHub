# Konventionen und Architekturentscheidungen

Die Regeln dieses Projekts, kurz. `CLAUDE.md` bindet diese Datei ein. Zwei Quellen für das Warum:

- Regeln, die aus QuartzControl übernommen sind (markiert mit **(QC)**), haben ihre Begründung,
  Messung und das Review, das sie fand, in `../QuartzControl/docs/decisions/conventions-full.md`
  unter derselben oder der genannten Überschrift. Wer von ihnen abweicht, liest dort zuerst.
- Regeln, die hier neu sind, haben ihre Messung in [`decisions/`](decisions/).

Eine neue Regel kommt mit dem Experiment, das sie erzwungen hat: in den Code als Kommentar, in
`decisions/` als Absatz mit Messung, hierher als kurze Regel.

### Grundsatz

- **QuartzControl ist die Spezifikation.** Wer portiert, liest die TS-Datei und ihren Abschnitt in
  `../QuartzControl/docs/decisions/` und übernimmt deren Ränder als Testfälle. Abweichungen sind
  Entscheidungen und stehen mit Grund in `decisions/`.
- **Beide Apps lesen dieselben Dateien.** `.quartz-gui/`, die Profil-Dateien und die Marker im
  Stylesheet behalten das Format von QuartzControl 1.3; QuartzHub schreibt nichts, was 1.3 nicht
  lesen kann, solange es keine Entscheidung dagegen gibt. **(QC)** „`.quartz-gui/` ist ein Name auf
  fremder Platte und bleibt, wie er ist.“
- **Vor Phase 2 schreibt QuartzHub in kein Projekt und kein Profil.** Erst `docs/formats.md` und
  die Golden-File-Tests, dann Schreiber.

### Aufbau und Prozesse

- **Drei Teile, eine Richtung.** `QuartzHubCore` kennt keine UI, die App kennt den Kern, `qh-check`
  kennt den Kern. Logik, die eine Prüfung braucht, steht im Kern und wird geladen, nicht
  abgeschrieben. **(QC)** „Ein Prüfskript, das Logik der App braucht, lädt sie.“
- **Ein Helfer ist ein Aufruf.** JS-Helfer laufen je Anfrage als Kindprozess: ein JSON auf stdin,
  ein JSON auf stdout, dann Ende, mit Frist. `ok: false` heißt „nicht beantwortbar“ (Eingabe,
  Datei), ein anderer Ausgang heißt „Helfer kaputt“; die zwei bekommen zwei Antworten. **(QC)**
  „Zwei Arten zu scheitern bekommen zwei Antworten.“ Kein dauerhafter Helfer-Prozess (der Spike
  lag damit bei 200 MB im Leerlauf).
- **Eine Abschrift aus QuartzControl bleibt wortgleich und sagt es.** Abschnitt mit
  `// ── copied ──` und Herkunft im Kopf (Muster `Helpers/src/dts-schema.ts`); die Gegenprobe ist
  ein `diff` gegen die Quelle. Die Helfer nutzen dieselben Paketfassungen wie QuartzControl.
- **Was mitreist, ist gepinnt, und die Prüfsumme steht im Skript**, nicht in einer Datei vom
  selben Server (`fetch-runtime.sh`, `xcodegen.sh`). Node kommt als offizielles Release mit npm
  aus demselben Tarball; Shims wie in QuartzControl braucht es nicht, `Runtime/node/bin` gehört
  in den PATH der Kindprozesse.
- **Ein Bau, dem etwas fehlt, bricht ab, statt zu warnen. (QC)** `package.sh` endet mit dem
  Schritt, der das Fehlende holt.
- **Werkzeuge projektlokal.** XcodeGen und Downloads unter `.tools/`, nie Homebrew oder global.
- **Kindprozesse (QC):** Argumentliste statt Shell (nur npm/npx brauchen eine), Projektdaten
  hinter `--`, git nie mit Shell, nie ohne Frist. Gilt ab dem Prozessstarter in Phase 3.
- **Was aus einer Datei kommt, wird beim Lesen geprüft wie beim Speichern.** `publish-targets.json`
  reist mit dem Projekt, Zugänge kommen aus QuartzControls Profil: Ziele und Zugänge laufen vor jedem
  Adapter durch dieselbe Regel wie das Formular; ein Name, der einem Programm übergeben wird (Host,
  Benutzer, Branch), beginnt nie mit „-“ und steht, wo das Programm es kennt, hinter `--`
  (decisions/phase-5-gleichstand.md, Review 2026-11-11, M2, N1, N2).
- **Was ein Abbruch verlieren würde, wird vorher notiert.** Ein geparkter Vault-Link steht in
  `.quartz-gui/content-link.json`, bis er zurück ist; laufende Updates, Restores und Deploys kennt
  `RunningWork`, und Beenden fragt (Review 2026-11-11, M1).
- **Ein Restore schreibt nur zurück, was der Snapshot davor hält.** Ist `content/` heute aus dem
  Store ausgenommen, wird es weder verglichen noch wiederhergestellt; damit weicht QuartzHub
  bewusst von QuartzControl 1.3 ab (Review 2026-11-11, H1).
- **Startschalter kommen nur aus den Startargumenten** (`LaunchArgument`), nie aus dem
  Defaults-Bereich der App; der Release-Bau kennt nur sein Bundle (Review 2026-11-11, N4).
- **Jede Dekompression bekommt eine Obergrenze, und die Datei selbst liefert sie nicht. (QC)**
- **Ja/Nein-Fragen sind native Dialoge, die sichere Antwort zuerst, der bestätigende Button nach
  der Aktion benannt. (QC)** In SwiftUI `confirmationDialog`/`alert` mit `role: .cancel`.

### Oberfläche

- **Rechts ist der Inspektor, und nur er.** Jede Seite ist ein `PageScaffold`
  (`App/Components/PageScaffold.swift`): in der Mitte eine Spalte, rechts der native Inspektor.
  Ist auf der Seite etwas ausgewählt, zeigt er dessen Details, Einstellungen und Aktionen; sonst
  den Kontext der Seite (`InspectorPageContext`: was die Seite tut, Zustand, Hinweise, Handbuch).
  Es gibt keine eigene Detail-Leiste neben einer Liste und kein Kartenraster mit rechter Spalte
  mehr; was in QuartzControl dort stand, kommt in den Inspektor oder untereinander in die Mitte.
- **Der Inspektor ist einmal je Fenster sichtbar oder nicht**, nicht je Seite
  (`@SceneStorage("inspector.presented")`). Ein- und ausblenden über den Button in der
  Symbolleiste und Darstellung ▸ Inspektor ein-/ausblenden, ⌃⌘I (`InspectorCommand`).
- **Eine Auswahl im Inspektor zu verlassen ist ein Verlassen wie jedes andere. (QC,
  „Eine Liste mit Leiste …“)** Ungespeichertes übernimmt oder fragt, nie still verwerfen; der
  Inspektor sagt selbst, ob er sofort schreibt.
- **Eine Seite besitzt ihr Dokument. (QC, „Eine Route ist gemountet …“)** Beim Erscheinen lesen,
  explizit speichern, `dirty` per Vergleich mit dem Gelesenen, nach jedem eigenen Schreiben neu lesen.
- **„Wo war ich“ (QC):** `@SceneStorage` mit stabilen Kennungen (`rawValue`), nie Listenindizes.
- **Verlassen mit ungespeicherten Änderungen fragt (QC):** Abbrechen, Speichern, Verwerfen, an
  Seitenleiste, Link, Fenster schließen und Beenden (`UnsavedGuard`, `.unsavedChanges`);
  scheitert das Speichern, bleibt man auf der Seite.
- **Jedes Bedienelement hat einen Namen**, auch ohne sichtbaren Text (`Label` statt bloßem
  `Image`); der Spike las SwiftUI-Buttons über System Events namenlos. Test-Kennungen
  (`accessibilityIdentifier`) sitzen an einem konkreten Element, nicht an einem `Form`: dessen
  Kennung kommt im Bedienungshilfe-Baum nicht an. Eine Kennung an einem Stack braucht
  `accessibilityElement(children: .contain)`, sonst bekommt jedes Kind sie.
- **Ein `@SceneStorage`-Schlüssel hat einen Typ**, auch über Seiten hinweg; und kein
  `fixedSize(vertical:)` an umbrechendem Text außerhalb einer Scrollansicht. Beides ließ das ganze
  Fenster leer, ohne Meldung (decisions/phase-4-oberflaeche.md, Snapshots).
- **Was ohne Zutun erscheint, wird angesagt (QC)**, hier über `AccessibilityNotification`.
- **Ein deaktiviertes Control muss noch lesbar sein; was nicht wirkt, sagt das mit einem Wort,
  nicht nur mit Grau. (QC)**
- **Farben nach Rolle (QC):** Systemstile (`.secondary`, `.tint`, Materialien) statt fester
  Farben; Hell und Dunkel folgen dem System bzw. der Einstellung.
- **Code bearbeitet man in NSTextView mit TextKit 2, ohne Editor-Paket.** Zeilennummern
  (`NSRulerView`), Färben und Einrückungslinien sind eigene Teile. Der Färber steht im Kern und
  wird je Tastendruck gemessen: Färben, nicht der Editor, ist das Teure (Messung in
  `decisions/phase-4-oberflaeche.md`, 4b).
- **Umsortieren hat drei Wege zu einer Funktion.** Mit der Maus wird gezogen (`onMove`, im
  Raster `draggable`/`dropDestination`). In einer Liste gibt es dazu „Nach oben“ und „Nach unten“
  im Menü (⌥⌘↑/⌥⌘↓), im Kontextmenü und als Bedienungshilfe-Aktion. In Raster und Board übernimmt
  der Inspektor diese Rolle. Jede Bewegung wird angesagt.

### Texte

- **Ein Katalog, ein Aufruf.** `L10n.t("bereich.schlüssel", ["name": …], count: n)` aus
  `QuartzHubCore`, für App und Kern. Der Schlüssel ist ein Literal, sonst kann `qh-check i18n` ihn
  nicht prüfen (Muster: `ProjectPage.title` als `switch`). Platzhalter heißen `{{name}}`, Plurale
  hängen an `count`.
  Einzige Ausnahme: Texte der `Info.plist` (Grund einer Systemfrage) liest macOS aus dem Bundle;
  Deutsch steht in `project.yml`, Englisch in `App/InfoPlist.xcstrings`
  (decisions/phase-5-gleichstand.md, Freigabe „Lokales Netzwerk“).
- **Schlüssel aus QuartzControl behalten ihren Namen** (Renderer wie gehabt, `mainT` unter
  `main.`), damit Code und Doku beider Apps über denselben Namen auffindbar bleiben. Neue
  Schlüssel bekommen einen Bereich (`shell.`, …) und einen `comment`, der sagt, wo der Text steht.
- **Beim Portieren einer Seite sagen ihre Texte „QuartzHub“.** Die übernommenen Texte nennen
  „QuartzControl“; wer einen Schlüssel in Gebrauch nimmt, prüft das.
- **Ein Wort, ein Name (QC)** — auch für Wörter, die SwiftUI mitbringt. Liefert ein
  Systembefehl ein anderes Wort als dieses Projekt (macOS 27: „Informationen Hide“ statt
  „Inspektor“), bekommt er einen eigenen Befehl. Festgelegt zusätzlich zur Tabelle in
  QuartzControl: „Inspektor“. Anführungszeichen Deutsch „…“, Englisch “…”.
- **Ein Hinweis sagt, was passiert, nicht warum es technisch so ist; höchstens zwei Sätze. (QC)**
  „konnte nicht … werden“ statt „ließ sich nicht …“.

### Tests und Messen

- **Vor jedem UI-Urteil die App wirklich starten** (Skill `run-app`); Hell und Dunkel.
- **Der Rauchtest öffnet jede Seite in zwei Fenstergrößen** und prüft, dass er sie erreicht hat.
  Sprache und Fenstergröße setzt er über Startargumente (`-QHLanguage`, `-QHWindowSize`), nicht
  über Ziehen: Unter XCUITest (macOS 27) bewegte kein Ziehen an Kante, Ecke oder Symbolleiste das
  Fenster, und ein gespeicherter Fensterrahmen schlägt `defaultSize`.
- **Eine Prüfung, die nie scheitern kann, prüft nichts.** Jede neue Assertion bekommt einmal ihre
  Gegenprobe (so fiel auf, dass die zweite Fenstergröße nie erreicht wurde).

### Arbeitsweise, die sich bewährt hat (QC)

Unverändert übernommen; Begründungen in QuartzControls Langfassung.

- „Kann nicht prüfen“ ist nie „alles gut“: eigene Antwort, auch in Prüfungen (`qh-check` Exit 3).
- Wer fragt, ob etwas noch gebraucht wird, sucht breit; wer löscht, löscht schmal.
- Ein fremder Dienst, der nicht scheitert, hat nicht unbedingt geliefert.
- Zwei Arten zu scheitern bekommen zwei Antworten („fehlt“ ≠ „kaputt“).
- „Die Datei ist da“ ist nicht „die Datei lässt sich lesen“: schreiben über Temp-Datei, `fsync`,
  `rename`; Unlesbares wegräumen.
- Wer fremdem Code eine Lücke nachsagt, liest erst, was er schon tut.
- Gemessen, nicht angenommen; eine Zahl, die einen Fix belegt, nennt einen Fall mit Ursache und das
  Instrument; wer einen Nutzen misst, misst auch den Preis.
- Ein Wert, den ein fremdes Programm vergleicht, wird nach dessen Regel gebildet und gegen das
  fremde Programm geprüft; liegt es im Projekt, fragt die App es selbst.
- Eine PID trägt nicht über die Zeit; ein Lesepfad legt nie `.quartz-gui/` an; ein Symlink-Schutz
  prüft jedes Segment mit `lstat`.
- Ein Handgriff, der nur in einer Commit-Nachricht steht, wird beim nächsten Mal vergessen: in ein
  Skript oder in die Doku.
