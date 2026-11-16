# Plan: Schritte im Inspektor für die vier eigenen Plugins

Stand 2026-11-16: Punkt 1 bis 3 umgesetzt (Baustein, Modell, Platz-Schritt, Navigationen,
Layout-Box, Formulare), siehe „Umgesetzt“ am Ende; Punkt 4 und 5 offen. Betrifft die Editoren unter **Plugins ▸ Navigationen,
Zusätzliche Inhalte, Mehrsprachigkeit, Formulare** (quartz-navigations, quartz-layout-box,
quartz-multilanguage, quartz-forms).

## Warum

Heute legt ➕ einen Eintrag an (Menü, Box, Formular, Sprache), danach zeigt der Inspektor ein langes
Formular aus dem Schema des Plugins. Wer ein neues Menü baut, muss selbst wissen, in welcher
Reihenfolge die Entscheidungen fallen: erst die Art, dann der Platz, dann welche Seiten, dann die
Darstellung. Das Formular kennt diese Reihenfolge nicht, und der Platz wird gar nicht gefragt
(Navigationen und Boxen setzen ihn stillschweigend, nur Formulare haben eine Auswahl).

## Entscheidungen des Nutzers (2026-11-16)

- Der Assistent lebt **im Inspektor**, nicht in einem Sheet.
- **Schreiben sofort je Schritt**, wie die Editoren heute (`PluginsModel.commit`), damit die
  Vorschau darunter jeden Schritt zeigt. Abbrechen im ersten Durchlauf entfernt den neuen Eintrag.
- **Immer nach Schritten gegliedert**: Auch ein bestehender Eintrag zeigt dieselben Schritte, jeder
  anspringbar. Das heutige Formular verschwindet nicht, es wird auf die Schritte verteilt.

## Grundmuster

### Baustein `InspectorSteps` (App/Components)

- **Kopf**: „Schritt 2 von 6 · Platz“, darunter die Schritte als senkrechte Liste mit Zustand:
  erledigt (Häkchen), aktuell, offen, „wirkt nicht“ (ein Schritt, den die Antworten davor
  überflüssig machen, z. B. „Auf dem Smartphone“ bei einer Variante ohne eigenes Mobilverhalten).
  Jeder Eintrag ist ein Button; die Liste klappt als `Fold` zusammen, sobald der Eintrag fertig ist.
- **Inhalt**: der aktuelle Schritt als `Form` mit `.grouped` wie die Inspektoren heute, Hinweise als
  `Note`/`Callout`, falsche Eingaben als `FieldProblem`.
- **Fuß**: Zurück / Weiter, im letzten Schritt „Fertig“. Weiter ist aus, solange der Schritt
  ungültig ist; der Grund steht als `FieldProblem` am Feld, nicht am Button.
- **Tastatur und Bedienungshilfen**: ⌘[ / ⌘] bleiben dem Fensterverlauf; Schritte über ⌥⌘← / ⌥⌘→
  (Menü „Gehe zu“, nur wenn ein Assistent sichtbar ist). Ein Schrittwechsel wird angesagt
  (`AccessibilityNotification`, Konvention „Was ohne Zutun erscheint“).
- **Wo war ich**: der Schritt je Eintrag in `@SceneStorage` mit stabiler Kennung
  (`"<plugin>:<eintrag>:<schritt-id>"`), nie mit einem Index.

### Modell `SetupSteps` (QuartzHubCore)

- Ein Schritt ist `(id, Titel-Schlüssel, Felder, gültig, wirkt)`; die Felder sind Schlüssel des
  Plugin-Schemas oder ein eigener Teil der App (Platz, Inhaltsdatei, Feld-Editor).
- Die Zuordnung **Schema-Gruppe → Schritt** steht je Plugin im Kern, neben dem Wissen, das dort schon
  liegt (`NavigationVariants`, `LayoutBoxes`, `FormsOptions`, `MultilanguageOptions`). Felder, die
  keinem Schritt zugeordnet sind, landen im letzten Schritt „Weitere Einstellungen“, damit ein neues
  Plugin-Feld nie verschwindet. Test: Jeder Schlüssel des Schemas steht in genau einem Schritt.
- „wirkt“ und das Ausgrauen einzelner Felder kommen aus denselben Regeln wie heute
  (`x-quartz-when` über `OptionSchema.evaluate`, `NavigationVariants.hasNoEffect`,
  `OptionRoot.inactiveReason`).
- Offene Frage: Soll ein Plugin seine Schritte selbst im Schema nennen (`x-quartz-step`), statt dass
  QuartzHub sie zuordnet? Vorteil: neue Optionen landen richtig, ohne QuartzHub-Release. Nachteil: vier
  Plugin-Releases und eine weitere Schema-Erweiterung. Vorschlag: erst im Kern zuordnen, nach dem
  zweiten Plugin entscheiden.

### Schreiben, Abbrechen, Snapshot

- Schritt 1 legt den Eintrag an (wie ➕ heute). Jeder weitere Schritt schreibt sofort.
- **Ein Snapshot je Assistent**, nicht je Feld: beim Anlegen `SnapshotStore.Take` mit dem Namen des
  Assistenten, die folgenden Schreibvorgänge ohne eigenen Snapshot. Bei einem bestehenden Eintrag
  ein Snapshot beim ersten Schreiben nach dem Öffnen.
- **Abbrechen** im ersten Durchlauf fragt (`confirmationDialog`, die sichere Antwort zuerst:
  „Weiter einrichten“, dann „Menü entfernen“) und entfernt den Eintrag über denselben Weg wie der
  Papierkorb heute. Bei einem bestehenden Eintrag gibt es kein Abbrechen, nur Schritte.
- Fehlt das Plugin oder sein erster Eintrag, ist **Schritt 0 „Plugin installieren“** (Marktplatz,
  `boxi-os/<plugin>`) statt der heutigen Leere; ein neuer Eintrag braucht dann kein `source` eines
  bestehenden mehr (heute kopieren Navigationen und Boxen `source` und `order` vom ersten).

### Platz als eigener Schritt

In allen vier Assistenten, mit derselben Komponente:

- Position (sechs Bereiche), Reihenfolge darin (Liste der Nachbarn, „davor/danach“), Anzeige
  (überall / nur Desktop / nur mobil) und, wo es Gruppen gibt, die Gruppe.
- Schreibt über `LayoutEntries.place` sofort, wie `FormsPositionField`
  (`App/Pages/Plugins/FormsSections.swift`) heute. Kein Umweg über den Entwurf der Layout-Seite.
- Vorschlag aus der Variante (`NavigationVariants.Variant.position`, `placedFirst`) bzw. aus dem
  Manifest des Plugins (`quartz.components.*.defaultPosition`, heute ungelesen).
- „Auf der Bühne zeigen“ bleibt als Ausweg zur Layout-Seite.
- Ein Hinweis, wenn der gewählte Bereich im Frame der Inhaltsseiten fehlt oder ausgeblendet ist
  (`LayoutStage` kennt das schon).

## Die Schritte je Plugin

### Menü (quartz-navigations)

| # | Schritt | Inhalt | Quelle |
|---|---|---|---|
| 1 | Art | Kacheln der Varianten (`VariantTiles`, inkl. Randmenü) | `NavigationVariants.offered` |
| 2 | Platz | gemeinsame Komponente, Vorschlag aus der Variante | `LayoutEntries.place` |
| 3 | Welche Seiten | `rootPath`, `scope`, `depth`, `showHome`, `indexEntry`, `folderLink` | Gruppe „Page selection“ |
| 4 | Ausblenden und Reihenfolge | Gruppen „Hide“ und „Order“ | Schema |
| 5 | Darstellung | die Optionen der Variante (Lead-Sektion von heute), z. B. Rail: `rest`, `side`, `expand`, `content`, `pin` | `NavigationVariants.root` |
| 6 | Auf dem Smartphone | `mobile`, `breakpoints` | Gruppe „On smartphones“ |
| 7 | Beschriftung und Icons | `title`, `icons`, `nodeIcons`, `iconNames` | Gruppe „Labels and icons“ |
| – | Fertig | Zusammenfassung, Klasse (`className`), „Alle Optionen“ | Gruppe „Technical“ |

### Layout-Box (quartz-layout-box)

| # | Schritt | Inhalt |
|---|---|---|
| 1 | Art des Inhalts | Text in der Konfiguration / Datei / Ordner (heute zwei Kacheln im `BoxInspector`) |
| 2 | Inhalt | Code-Editor bzw. Dateiwahl (`SnippetFileField`), Bilder, Platzhalter |
| 3 | Platz | gemeinsame Komponente (heute fest `left`) |
| 4 | Darstellung | `title`, `collapsible`, `collapsed`, Klasse |
| 5 | Sprachen | `byLang`, nur mit quartz-multilanguage, sonst „wirkt nicht“ |
| – | Fertig | Zusammenfassung |

### Formular (quartz-forms)

Die sieben `Fold`-Teile des `FormInspector` werden Schritte:

| # | Schritt | Inhalt |
|---|---|---|
| 1 | Vorlage | Kontakt, Feedback, Zusage, Umfrage, leer (heute `AddFormForm`) |
| 2 | Name | ID mit `FormsOptions.formIdProblem` |
| 3 | Felder | `FormFieldsEditor` |
| 4 | Versand | geerbter globaler Versand; fehlt er, wird er hier eingerichtet (Relay, Schlüssel) |
| 5 | Datenschutz und Spam | die Teile „Datenschutz“ und „Spam“ |
| 6 | Einbetten | Seite (Code-Schnipsel, `FormUsages`) oder Layout-Platz (gemeinsame Komponente) |
| – | Fertig | Prüfung des Plugins (`FormsCLI.check`) als Abschluss, Zusammenfassung |

### Sprachen (quartz-multilanguage)

Zwei Assistenten, weil das Plugin ein Eintrag für die ganze Website ist:

- **Mehrsprachigkeit einrichten** (solange weniger als zwei Sprachen eingetragen sind):
  1 Sprachen wählen → 2 Standard und veröffentlichte → 3 Inhalt je Sprache (Ordner, Startseite) →
  4 Sprachumschalter platzieren (gemeinsame Komponente) → Fertig.
- **Sprache hinzufügen** (➕ danach): 1 Code (`MultilanguageOptions.codeProblem`) → 2 Name, eigener
  Name, Locale → 3 Startseite → 4 Veröffentlichen → Fertig.

Die Gruppen-Zeilen der Liste (`settingsGroups`) bleiben für alles Weitere.

## Reihenfolge der Umsetzung

Je Punkt ein Commit mit Bau, `qh-check i18n`, Tests und Ansehen (Skill `run-app`, Hell und Dunkel).

1. `SetupSteps` im Kern und `InspectorSteps` in der App, mit dem Menü als erstem Nutzer (das meiste
   Wissen liegt schon in `NavigationVariants`). Die gemeinsame Platz-Komponente gehört dazu.
2. Layout-Box (Platz-Schritt ersetzt das feste `left`).
3. Formular (die Teile sind schon geschnitten; der Versand-Schritt ist der aufwendigste).
4. Sprachen (zwei Assistenten).
5. Handbuch: je Editor-Seite die Schritte statt des Formulars, neue Aufnahmen
   (`scripts/handbook-shots.sh`).

## Messen

- Kern: Jeder Schema-Schlüssel steht in genau einem Schritt (je Plugin, gegen die echten Schemas in
  `Fixtures/option-schema/real`). „wirkt“ je Schritt für jede Variante.
- App: Rauchtest legt je Plugin einen Eintrag über alle Schritte an und bricht einen zweiten ab
  (der Eintrag ist danach weg, die Config gleich der vorherigen).
- Ein Snapshot je Assistent: Zahl der Snapshots vor und nach einem Durchlauf.

## Umgesetzt

### Punkt 1, 2026-11-16: Navigationen

- **Kern**: `SetupStep`/`SetupSteps` (`Plugins/SetupSteps.swift`): Zuordnung erst nach Schlüssel, dann
  nach Gruppe, sonst letzter Schritt; `unplaced` nennt, was nur die Ausweichregel gefangen hat.
  `NavigationVariants.steps` und `stepHasEffect`. `LayoutEntries.restoringPriorities` für das
  Abbrechen. Tests in `SetupStepsTests` gegen das Schema von 0.4 (QuartzControls Fixture) und 0.5.0
  (`Fixtures/navigations/schema-0.5.0.json`, aus der package.json des Plugins).
- **App**: `InspectorSteps` (App/Components), `PlacementStep` (App/Pages/Plugins),
  `NavigationInspector` in Schritten; Gehe zu ▸ Vorheriger/Nächster Schritt (⌥⌘← ⌥⌘→, nur solange
  ein Assistent im Inspektor steht); `PluginsModel.commit(snapshot:)` mit `.each`, `.labeled`, `.none`;
  `OptionsForm(searchable:)`; `Confirm.ask(cancel:)` für „Weiter einrichten“.
- **Wörter**: Die App sagt „Navigation“ und „Variante“, nicht „Menü“ und „Art“ (ein Wort, ein Name).
  Die Schritte heißen Variante, Platz, Welche Seiten, Ausblenden und Reihenfolge, Darstellung, Auf dem
  Smartphone, Beschriftung und Icons, Zusammenfassung.

**Anders als oben geplant:**

- **➕ beantwortet Schritt 1.** Das Popover mit den Kacheln bleibt; der Inspektor beginnt danach mit
  „Platz“, „Variante“ ist abgehakt. Wechselt man im ersten Durchlauf die Variante und steht die
  Navigation noch am Platz der alten, zieht sie an den Platz der neuen mit.
- **„Auf dem Smartphone“ wirkt auch bei `select` und `pager`**: Beide bekommen die Klasse
  `quartz-nav--mobile-<wert>` (render.tsx 0.5.0, `rootClass`), `mobile: hidden` blendet sie aus. „Wirkt
  nicht“ steht nicht in einer Tabelle, sondern folgt aus den Feldern: Ein Schritt wirkt nicht, wenn
  keines seiner Felder für die Variante wirkt (`hasNoEffect`, `x-quartz-when`). Gemessen: „Darstellung“
  wirkt nicht bei `tree` (ohne `mobile: accordion`) und bei `columns`, denn das Plugin liest
  `columns.max` und verwendet es nirgends.
- **Abbrechen stellt die Datei wieder her**, nicht nur den Eintrag: Der Platz-Schritt nummeriert die
  Nachbarn neu (`LayoutEntries.place`), und ohne Rückgabe blieben ihre Prioritäten verschoben.
  `restoringPriorities` gibt Einträgen, die sich nur in der Priorität unterscheiden, den Wert von
  vor ➕ zurück; jede andere Änderung bleibt. An der App gemessen: Anlegen, „Später“, Abbrechen,
  danach `diff` gegen die Konfiguration von vorher leer.
- **Ein Snapshot je Assistent**: ➕ nimmt ihn mit eigenem Namen („Navigation einrichten: Randmenü“),
  die Schritte danach keinen. Ein bestehender Eintrag nimmt ihn beim ersten Schreiben nach dem
  Öffnen des Inspektors. An der App gezählt: 13 vor dem Anlegen, 14 danach, 14 nach Verschieben, einem
  Schalter und dem Abbrechen. Ein zweiter Durchlauf vom selben Stand legte keinen weiteren an: Der
  Snapshot-Store legt einen inhaltsgleichen Stand nicht doppelt an.
- **Kein „gültig“ je Schritt**: Bei Navigationen kann kein Schritt ungültig sein; das Feld kommt mit
  dem Formular (Name, `formIdProblem`).
- **Gruppen im Platz-Schritt** aus der Konfiguration und den Frames (`LayoutBoard.groupNames`); der
  Hinweis auf einen fehlenden Bereich gilt dem Frame der Inhaltsseiten, je Breite
  (`LayoutStage.missingPositions`).

**Nicht geprüft**: Hell (nur Dunkel angesehen, die Bausteine nutzen nur Systemstile); VoiceOver-Ansagen
nur im Code. Das Handbuch beschreibt den Inspektor noch ohne Schritte (Punkt 5).

### Punkt 2, 2026-11-16: Layout-Box

- Sechs Schritte (`LayoutBoxes.steps`): Art des Inhalts (die zwei Kacheln Text / Datei), Inhalt
  (Gruppe „Content“, unter „Inhalt: Text“ bzw. „Inhalt: Datei“ wie bisher), Platz, Darstellung
  (Gruppe „Box“), Je Sprache und Seite (der Name der Plugin-Gruppe), Zusammenfassung (Gruppe
  „Technical“). Ein „Ordner“ als dritte Art, wie oben geplant, gibt es nicht: `dir` ist der Ordner der
  Datei und steht im Schritt „Inhalt“.
- ➕ legt die Box an wie bisher (Text, links, zuletzt); der Inspektor beginnt bei „Art des Inhalts“.
  Den festen Platz `left` ändert jetzt der Platz-Schritt.
- „wirkt“ je Schritt über dieselbe Regel wie bei den Navigationen (`SetupSteps.hasEffect`), mit
  `LayoutBoxes.silenced` als Regel des Plugins. Alle sechs Schritte wirken bei einer Text-Box.
- Gemeinsam mit Punkt 1: `SetupRun` (App/Components/InspectorSteps.swift), `PluginsModel.cancelSetup`,
  die Texte `inspectorSteps.cancelKeep` und `inspectorSteps.summaryChanged`. Die Nachbarn im
  Platz-Schritt heißen wie in ihren Listen (Navigation, Box), sonst nach dem Plugin.
- Fehlerhafte Optionen (`brokenOptions`) stehen jetzt im Kopf des Inspektors, in jedem Schritt: Der
  Bau scheitert daran.
- An der App: Anlegen, Weiter bis „Platz“, zweimal „Früher“, Abbrechen; `diff` gegen die
  Konfiguration von vorher leer.

### Punkt 3, 2026-11-16: Formulare

- Sieben Schritte (`FormsOptions.steps`): die sechs Teile, die vorher als `Fold` untereinander
  standen (Allgemein, Felder, Versand, Datenschutz und Verschlüsselung, Spamschutz, Einbinden), dann
  eine Zusammenfassung (Vorlage, Zahl der Felder, Versandart, Seiten, die es einbinden, und die
  unbekannten Schlüssel, vorher ein eigener Teil). Die Schlüssel je Schritt sind nur Zuordnung; ein Test
  prüft, dass jeder Schlüssel von `formKeys` in genau einem Schritt steht und dass die Meldungen des
  Plugins (`FormsOptions.part`) zum selben Schritt gehen.
- **Anders als oben geplant:** „Vorlage“ und „Name“ bleiben im Popover von ➕, wie bisher; der
  Inspektor beginnt bei „Allgemein“. Die Kennung steht weiter über den Schritten, weil Umbenennen
  jederzeit geht und Seiten betrifft. Der Versand-Schritt richtet keinen fehlenden globalen Versand
  ein: Das bleibt der Abschnitt „Versand“ der Einstellungen für alle Formulare, auf den die Meldung
  zeigt. „Einbinden“ bietet keinen Layout-Platz über den Platz-Schritt: Das Layout-Formular ist ein
  Schalter des Plugins (`layoutForm`), sein Platz der Abschnitt „Layout-Formular“.
- **Probleme am Schritt**: `InspectorStep.problems`, gezählt wie vorher je Teil. An der App: Ein neues
  „Kontakt“ mit Relay ohne Empfänger zeigt „ein Problem“ an „Versand“.
- Umbenennen im ersten Durchlauf nimmt den Lauf und „wo war ich“ mit zur neuen Kennung.
- `@SceneStorage("forms.parts")` (welche Teile offen standen) ist ersetzt durch `forms.step`.
- An der App: Anlegen, alle Schritte bis zur Zusammenfassung, Abbrechen; `diff` gegen die
  Konfiguration von vorher leer.

