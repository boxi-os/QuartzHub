# Befunde aus dem Handbuch: was beim Beschreiben jeder Seite auffiel

Stand: `main` bei `6bfb1fa`. Keine Review-Runde mit Auftrag, sondern ein Nebenprodukt des
QuartzHub-Handbuchs (2026-11-12/13): Für die Teile 4 bis 8 haben Explore-Subagenten (Claude Opus 5.5)
den Code je Seite gelesen und Faktenblätter geliefert; was dabei nicht zur Seite passte, ist hier
gesammelt. Dazu kommt, was ich selbst an der laufenden App sah, als ich die Aufnahmen machte.

Wie belastbar ein Befund ist, steht dahinter:

- *(gesehen)*: an der laufenden App (Demo-Projekt aus `scripts/handbook-demo.sh`).
- *(gelesen)*: von mir im Code nachgelesen, mit Ort; nicht an der App nachgestellt.
- *(Faktenblatt)*: nur aus dem Faktenblatt eines Subagenten, nicht nachgelesen. Vor einem Fix
  erst nachstellen; einzelne können falsch sein (zwei waren es, siehe „Verworfen“).

Kurz: **2 Hoch, 5 Mittel, 15 Niedrig, rund 100 nebenbei** (meist Texte und Uneinheitliches; M5, N14 und N15 kamen mit den Büchern dazu). Beide
Hoch-Befunde verlieren Arbeit des Nutzers ohne Frage: Ein Restore mit „Auch den Projekt-Commit
zurücksetzen“ kann ungesicherte Notizen verwerfen, und Speichern eines Frames verwirft ungespeicherte
Änderungen auf der Bühne. Bei H1, H2 und M1 sagt das Handbuch, wie man den Fehler umgeht; nach einem
Fix sind diese Sätze zu streichen. Wo das Handbuch betroffen ist, steht es unter „Handbuch“.

---

## Befunde

### Hoch

**H1. „Auch den Projekt-Commit zurücksetzen“ macht `git reset --hard` im Projekt und verwirft dabei
ungesicherte Änderungen an Notizen, auch wenn „Content-Ordner mitsichern“ aus ist; die Ausgabe sagt
danach, `content/` sei nicht angetastet worden.** *(gelesen)*

- Ort: `Snapshots/SnapshotStore+Restore.swift:126-131` (`projectGit(project, ["reset", "--hard",
  head])` vor dem eigentlichen Restore), `:80-90` und `:168-173` (`contentLeftAlone` hängt
  `main.snapshotContentUntouched` an die Ausgabe).
- Szenario: Ein Projekt mit echtem Content-Ordner (kein Link in einen Vault), der im Projekt-Repo
  versioniert ist; „Content-Ordner mitsichern“ aus. Der Nutzer ändert Notizen, ohne zu committen,
  und holt einen älteren Snapshot mit dem Schalter zurück. `reset --hard` setzt jede versionierte
  Datei unter `content/` auf den Commit des Snapshots; neue, unversionierte Notizen bleiben. Der
  Snapshot „Vor Wiederherstellen“ enthält `content/` nicht (Schalter aus), die Änderungen sind weg.
  Ein Link in einen Vault ist geschützt (`withSymlinkParked`).
- Folge: Datenverlust, und die Ausgabe sagt das Gegenteil. Die Regel aus Review 2026-11-11, H1 („ein
  Restore schreibt nur zurück, was der Snapshot davor hält“) gilt für diesen Weg nicht.
- Vorschlag: Vor dem Reset `git status --porcelain -- content` im Projekt; mit Änderungen dort und
  `includeContent == false` nicht zurücksetzen, sondern fragen oder nur `git reset --soft`/`--mixed`
  plus Restore der Nicht-Content-Pfade. Gegenprobe als Test mit geänderter versionierter Notiz.
- Handbuch: 7.3 Zurückholen (Warnung beim Schalter).

**H2. Speichern oder Löschen eines Frames liest `plugins:` neu von der Platte und verwirft damit
ungespeicherte Änderungen auf der Bühne, ohne zu fragen.** *(gelesen)*

- Ort: `App/Pages/Layout/LayoutModel.swift:149-156` (`syncPluginsFromDisk`: `config?.plugins =
  fresh.plugins`, `saved = fresh`), aufgerufen in `saveFrame` (`:226-227`) und `deleteFrame`
  (`:245-246`). Die Bühne schreibt ihre Änderungen genau dorthin: `StageTab.swift:111`,
  `ComponentInspector.swift:40` (`model.config?.plugins = …`).
- Szenario: Auf Layout ▸ Komponenten eine Komponente verschieben (nicht speichern), dann auf
  Layout ▸ Frames einen Frame speichern. Die Verschiebung ist weg, und weil `saved` mitgesetzt wird,
  zeigt auch der Ungesichert-Punkt nichts mehr. Der Kommentar über der Funktion verspricht das
  Gegenteil („edits of the stage still count as unsaved“); er gilt nur für Änderungen außerhalb von
  `plugins:`.
- Vorschlag: Nur die Einträge übernehmen, die das CLI hinzugefügt oder entfernt hat (Abgleich über
  Name und Quelle, wie `pluginsSignature` `:112`), die übrigen aus `config` behalten; oder vor dem
  Frame-Speichern über `UnsavedGuard` fragen. Gegenprobe: Bühnen-Änderung, Frame speichern, Änderung
  noch da und ungesichert.
- Handbuch: 5.4 Layout-Frames (Hinweis: vorher Komponenten speichern).

### Mittel

**M1. Ungespeicherte Übersetzungen schützt keine Nachfrage: Ein Wechsel der Sprache im Reiter
verwirft sie still, Beenden und Fenster schließen ebenso.** *(gelesen)* **Erledigt** (`5cacfa8`).

- Ort: `App/Pages/Config/LocalizationTab.swift:39` (`onChange(of: model.code)` → `loadEntries`),
  `:198-203` (`edits = [:]`, wenn die Sprache wechselt), `:220` (`dirtyKeys`); `ConfigPage.swift:61`
  (`.unsavedChanges(model.dirty …)` kennt nur `ConfigModel`, nicht die Übersetzungen).
- Szenario: Drei Texte geändert („3 ungespeichert“), dann oben eine andere Sprache gewählt: Die
  Änderungen sind weg. Ein Wechsel auf eine andere Seite behält sie (Kopfkommentar `:8`), Beenden
  nicht.
- Vorschlag: `dirtyKeys` in den `UnsavedGuard` der Seite aufnehmen und den Sprachwechsel durch
  dieselbe Frage leiten.
- Handbuch: 4.4 Übersetzungen.

**M2. Beim ersten Einrichten von GitHub Pages geht eine eingetragene eigene Domain verloren.**
*(gelesen)* **Erledigt** (`5f92c12`).

- Ort: `Publishing/GitHubAPI.swift:185-188` (`POST …/pages` nur mit `source`; `cname` wird nur im
  `PUT`-Zweig gesendet). QuartzControl hat denselben Fehler (`githubService.ts:177-179`).
- Szenario: Neues Repo, Pages noch nicht eingerichtet, im Formular eine Domain eingetragen, „Pages
  einrichten“. Die Ausgabe meldet Erfolg ohne Satz zur Domain; GitHub kennt keine. Erst ein zweites
  Speichern setzt sie.
- Vorschlag: Nach erfolgreichem `POST` mit `cname` ein `PUT` mit `source` und `cname` hinterher
  (GitHubs `POST` nimmt `cname` nicht an, vorher nachlesen), mit dem Satz `main.githubDomainSet`.
- Handbuch: 6.8 GitHub Pages erwähnt den Fehler nicht und beschreibt den Weg, nach dem er auftritt.

**M3. „Build ausführen“ auf der Übersicht baut immer nach `public/`, „Jetzt bauen“ auf Vorschau &
Build in den eben getippten, noch nicht übernommenen Ausgabeordner.** *(gelesen)* **Erledigt** (`7341206`).

- Ort: `App/Pages/Overview/OverviewModel.swift:149` (`BuildAction.run` ohne `outputDir`);
  `App/Pages/Server/BuildServerModel.swift:111,117` (nimmt `outputDir`, das Feld, nicht
  `savedOutputDir`); übernommen und geprüft wird erst in `commitOutputDir` (`:141-142`, beim Verlassen
  des Felds oder Return). `PublishModel.swift:176` nimmt den gespeicherten.
- Szenario: (a) Ausgabeordner `dist` gespeichert, auf der Übersicht bauen: Die Website landet in
  `public/`, die Übersicht meldet Erfolg, Veröffentlichen lädt den alten Stand aus `dist`. (b) Im
  Feld einen ungültigen Pfad tippen und sofort „Jetzt bauen“: gebaut wird mit dem ungeprüften Wert.
- Vorschlag: Alle drei Wege lesen `ProjectPrefsStore.read(project:).outputDir`; „Jetzt bauen“
  übernimmt das Feld vorher über `commitOutputDir` und baut nur ohne `outputDirError`.
- Handbuch: 3.1 und 6.2 erwähnen den Fehler nicht; 6.2 beschreibt den Ausgabeordner so, wie ihn die Seite Vorschau & Build verwendet.

**M4. ⌘S und „Speichern“ im Dialog beim Verlassen überspringen auf der Seite Stile, was der Knopf
in der Symbolleiste danach tut (SCSS-Prüfung des eigenen CSS, Schriften neu lesen).** *(gelesen)* **Erledigt** (`2144a5f`).

- Ort: `App/Pages/Styles/StylesPage.swift:60-62` (`.unsavedChanges { await model.save(from: tab) }`)
  gegen `:197-202` (`save()`: dazu `savedRound += 1` und `runCssCheck()` auf Eigenes CSS).
- Szenario: Auf Eigenes CSS einen SCSS-Fehler tippen, ⌘S. Gespeichert wird, die Prüfung läuft nicht,
  der Fehler erscheint erst beim nächsten Build.
- Vorschlag: `.unsavedChanges` ruft dieselbe `save()` wie der Knopf.
- Handbuch: 5.8 Eigenes CSS sagt „nach jedem Speichern prüft es“; mit ⌘S stimmt das erst nach dem Fix.

### Niedrig

**N1. Eine von Hand eingetragene Quelle im Marktplatz geht ungeprüft an `npx quartz plugin add`,
auch mit „-“ am Anfang.** *(gelesen)* **Erledigt** (`98c7a97`). `App/Pages/Plugins/MarketplaceTab.swift:158-162` →
`Plugins/PluginCommands.swift:41`, ohne `--`. `PluginSource.swift:16` hat die Prüfung
(`!source.hasPrefix("-")`, Länge), wird hier aber nicht benutzt. Getippt vom Nutzer selbst, daher
Niedrig; widerspricht der Regel „ein Name, der einem Programm übergeben wird, beginnt nie mit -“.
Dazu: Die Beschreibung sagt „owner/repo“, der Platzhalter „github:owner/repo“.

Die folgenden nur aus Faktenblättern *(Faktenblatt)*:

Am 2026-11-13 von einem Agenten im Code nachgelesen und alle abgearbeitet; was dabei nicht hielt, steht
in der Chronik (`docs/reviews.md`). **Alle erledigt.**

- **N2.** Frame umbenennen bricht `byPageType.*.template`, das auf den alten Namen zeigt, ohne
  Warnung; Frame löschen lässt solche Verweise verwaist zurück.
- **N3.** „Duplizieren“ im Frame-Editor fragt nicht nach ungespeicherten Änderungen des offenen
  Frames.
- **N4.** Der Snippet-Entwurf (Zusätzliche Inhalte) ist nicht vom `UnsavedGuard` geschützt.
- **N5.** Stile ▸ „Datei importieren…“ überschreibt eine gleichnamige Datei still und trägt sie
  doppelt in die Reihenfolge ein.
- **N6.** Content-Ordner ▸ zurückholen (geparkte Quelle) nimmt keinen Snapshot, kennt keine
  Beenden-Warnung (`RunningWork`), und der Eintrag bleibt danach stehen.
- **N7.** Git-Sync: „Merge abbrechen“ nach einem fehlgeschlagenen Pull kann neue Notizen in
  `content/` löschen (im Code kommentiert, im UI nicht gesagt); der Dialog zeigt die Texte des
  Kern-Updates.
- **N8.** Entfernen eines von mehreren gleichnamigen Plugin-Einträgen verspricht einen Snapshot,
  macht aber nur `configChange` (der nach 15 Minuten-Regel keinen nehmen kann).
- **N9.** `FormsRelay.state()` setzt `storageAvailable` fest auf `true`; der Hinweis `noStorage` ist
  damit nie sichtbar, und sein Text widerspricht dem Export.
- **N10.** Layout: Ein Bereichsname wird im Feld so gezeigt, wie getippt, gespeichert aber als Slug
  („Fußzeile“ → „fu-zeile“).
- **N11.** Veröffentlichen: „Token entfernen“ ohne Rückfrage; „Speichern & prüfen“ behält einen
  abgelehnten Token.
- **N12.** rsync: „Alles neu hochladen“ ist wirkungslos, der Hinweis bei ausgeschaltetem Löschen gilt
  für rsync nicht, und der Text des Löschschalters verschweigt, dass rsync alles Fremde im Zielordner
  löscht.
- **N13.** Konfiguration: Der Kopierfortschritt beim Wechsel der Content-Quelle kann über 100 %
  gehen (zählt Ordner und versteckte Dateien mit).

### Nachtrag: aus den Büchern des Handbuchs (Plan, Handbuch 6; 2026-11-13)

Beim Anlegen und Exportieren der zwei Bücher über **Dokumente** und **Veröffentlichen** am Projekt
QuartzHub-Web *(gesehen)*:

**M5. Im PDF ist „ff“ als Text verloren: Die Suche findet „Veröffentlichen“ und „öffnen“ nicht.**
*(gesehen, gemessen)* **Erledigt** (Chronik in `docs/reviews.md`).

- Messung: Text des deutschen PDFs über PDFKit (`PDFDocument.string`): „Verö!entlichen“ 42-mal,
  „ö!nen“ 33-mal; `findString("Veröffentlichen")` trifft 2-mal, obwohl das Wort auf rund 40 Seiten
  steht. Englisch dasselbe („di!erently“, „o!ers“). „fi“ und „fl“ sind heil. Die Glyphen sehen
  richtig aus; nur die Zuordnung zum Text fehlt (Ligatur „ff“ der Noto Sans, `fontOrigin: local`).
- Folge: Suchen, Kopieren und Vorlesen im PDF scheitern an jedem Wort mit „ff“. ePub und HTML sind
  nicht betroffen (dort ist es Text).
- Ursache: Die Schrift (latin-Subset) hat für keinen Ligatur-Codepunkt U+FB00–FB04 einen
  cmap-Eintrag (CoreText `CTFontGetGlyphsForCharacters`); WebKits PDF bekommt für die Ligaturglyphe
  so keinen Text. „ffi“ war ebenso betroffen („Su"x“ statt „Suffix“).
- Fix: `font-variant-ligatures: no-common-ligatures` im Druck-Stylesheet (`webKitPrintRules`), nur
  für `body.pdf`. Gemessen mit `qh-check export-book --pdf` am Handbuch: 200 Wörter unlesbar vorher,
  keins nachher; „Veröffentlichen“ 2 → 59 Treffer der Suche; Seiten und Lesezeichen gleich.
- Handbuch: nicht betroffen, aber das PDF des Handbuchs selbst.

**N14. ➕ Neues Buch fragt nicht nach einem Namen: Die Datei heißt immer `neues-buch.json`
(englisch `new-book.json`), und so heißen auch PDF und ePub.** *(gesehen)* **Erledigt** (`731bc55`).
`App/Pages/Documents/DocumentsModel.swift:184` legt das Buch sofort mit dem Platzhaltertitel an;
der Name entsteht daraus (`BookFile.id(fromTitle:)`) und bleibt. Wie QuartzControl
(`routes/Documents/index.tsx:136`). Umbenennen geht nur im Finder. Vorschlag: wie ➕ Neues Formular
zuerst nach dem Titel fragen. Für die Bücher des Handbuchs von Hand umbenannt.
Handbuch: 6.6 beschreibt es jetzt so, wie es ist.

**N15. Die drei Format-Schalter im Ziel „Dokument“ sind für die Bedienungshilfen ein einziges
Element.** *(gesehen)* **Erledigt** (`83e2271`; was VoiceOver vorliest, nicht gemessen). `App/Pages/Publish/TargetSheet.swift:264-269`: Die Toggles stehen in einem
`LabeledContent`; System Events sieht drei Markierungsfelder, alle mit dem Namen „Formate“ und an
derselben Position, und ein Klick auf das zweite schaltete PDF aus. VoiceOver erreicht ePub und HTML
damit nicht. Vorschlag: jedem Toggle sein eigenes Label lassen (`accessibilityLabel` mit dem
Format) oder die Gruppe mit `accessibilityElement(children: .contain)` öffnen; danach per
System Events nachmessen.

---

## Nebenbei

Nach Bereich. Ohne Kennzeichnung: *(Faktenblatt)*.

**Selbst gesehen** *(gesehen)*

- Fenster Projekte (Zeile der Website) und Übersicht (Git-Karte): „…“ deutsche Anführungszeichen fest
  im Code, auch im englischen UI (`ProjectsWindow` `siteLine`, `OverviewPage` `gitSection`).
- Einstellungen ▸ Allgemein: „Speichern“ zeigt „Gespeichert.“ daneben (gegen die Regel der
  Symbolleiste); Daten & Wartung spricht von „verschlüsselten Zugänge(n)“, die Geheimnisse liegen aber
  im Schlüsselbund.
- `EnvironmentBand` (Projekte) und das Handlungsbedarf-Band der Übersicht: eigene orange Bänder statt
  `Callout`.
- „Base-URL“ (`dashboard.attention.noBaseUrlDetail`, Hinweis auf Konfiguration) neben „Basis-URL“.
- Menü Projekt, Englisch: „Run build“ klein neben „Start Server“.
- Die Vorschau der Website rendert dunkel, obwohl QuartzHub auf Hell steht (folgt sie dem System statt
  der Einstellung?).
- Neues Projekt anlegen und vorhandenes aufnehmen: rund 15 s ohne Rückmeldung.

**Konfiguration**

- `content.filesCount` ohne Plural („1 Dateien“).
- Reiter heißt englisch „Localization“ statt „Translations“; die Sprachwahl im Reiter heißt für
  VoiceOver „Sprache der Website“, ändert sie aber nicht.
- Übersetzungen: Fehlertexte englisch aus dem Kern; die Suche findet nur den gespeicherten Wert.
- Rückmeldungen nur über VoiceOver: „Gespeichert.“, Projektbild gesetzt, Startseite angelegt,
  „quartz-layout-box ist installiert … mit Speichern übernommen“.
- „Wiederherstellungspunkt“ in Ladefehlern statt „Snapshot“.
- Update-Schutz ohne git-Repo bleibt „nicht aktiv“, ohne zu sagen, warum.
- Links/Frontmatter (5.1): einmal ausgeschaltet nicht wieder einschaltbar.
- Inspektor-Beschreibung des Reiters Website unvollständig; Kopfkommentar von `ConfigPage` falsch.
- Statistik-Felder mit rohen Schlüsseln als Beschriftung.
- Relative Quellpfade bei „Quelle ändern“ werden gegen das Arbeitsverzeichnis der App geprüft.

**Plugins: Installiert und Marktplatz**

- Leerer Grund bei unlesbarer Quelle; ein fehlendes Paket erscheint als „hat keine Optionen“.
- Die Zusammenfassung der Platzierung zeigt „undefined“ bzw. eine leere Priorität.
- Gruppe „Im Inhalt“ ohne passenden Wert im Positions-Picker.
- Englisch „Open in Layout“ gegen deutsch „Im Layout-Editor“.
- Filter-Picker heißt für VoiceOver „Alle“.
- Entfernen im Kontextmenü ist während der Wartung möglich.
- „Andere Repositories“ bieten Installieren an, obwohl „meist nicht installierbar“; „Keine Plugins
  gefunden.“, obwohl es andere Treffer gibt.
- „Gespeichert“ nur bei Feldern, nicht bei Schalter und Umordnen.
- Wartungstext „ändern nichts“, ein Restore kann aber `npm install` laufen lassen.

**Plugin-Editoren**

- „Die Optionen konnten nicht gelesen werden: “ mit leerem Grund (Navigationen, Boxen).
- Dateien-Bereich: „Vorhandene verwenden“ tut dort nichts.
- Inspektor sagt „speichert ohne Button“, obwohl Snippet, Relay-Adressen und Schlüssel eigene Knöpfe
  haben; das Aufblitzen von „Gespeichert“ ist uneinheitlich.
- „Neu suchen“ steht im eingeklappten Teil, der Satz unter der Vorschau verweist darauf.
- Uneinheitlich: aktiv/enabled/On/Switched on; duplizieren/kopieren; „Alle Optionen (in der
  Plugin-Liste)“; Listenkopf „Navigation“ ohne „Eine“; Leerzustände mit und ohne owner/repo;
  „Snippet“/„Schnipsel“.
- Englische Platzhalter „danke“, „kontakt“, „owner“, „code“ unübersetzt; „Unterordner“ = „Folder“.
- `main.secretMissingInKeychain` verweist auf Einstellungen ▸ Zugänge, wo es nicht hilft.

**Layout**

- ⌥⌘↑/↓ doppelt belegt (Früher/Später gegen Anordnen-Menü, auf Layout deaktiviert).
- Inspektor-Hinweis zum Quartz-Standard falsch; die Übersicht verspricht klickbare Frames.
- Die Zusammenfassung prüft nur Desktop; die Breakpoint-Prüfung nennt einen falschen Grund; Gap
  schreibt `""`, statt den Schlüssel zu entfernen; Gruppe löschen lässt die Mitglieder gruppiert;
  „Hinzufügen“ mit vorhandenem Namen tut still nichts.
- Englisch „Bereich“ mal area, mal slot; „Quartz’ built-in“; „Gespeichert.“ gegen „Gespeichert“.
- Kein Snapshot bei Frame-Bearbeitung und Breakpoints.

**Stile**

- Die Kaskadenzeile „Variablen → eigenes CSS“ stimmt für `custom/` und `imported/` nicht (laden vor
  `css-vars`); die Kollisionswarnung prüft nur `custom.scss`.
- Der Theme-Hinweis verspricht eine „Vorschau“, die Seite hat keine.
- Preset „Aktiv“ vergleicht nur die Theme-ID; „Anwenden“ übergeht npm-Fehler; Löschen still.
- „Jetzt ins Projekt holen“ speichert alle Entwürfe mit.
- Rohe Schlüssel als Beschriftung (header/body/code, lightMode); „QuartzControl-Marker“ im UI;
  englisch „Import your own font“ gegen die Überschrift.

**Vorlagen**

- Fortschritt zeigt „Inhalt — content:25“.
- Häkchen beim Erstellen werden nur einmal gesetzt: neue Bausteine nicht gewählt, „12 von 11“, zu
  große Bausteine trotzdem exportiert; Größengrenzen still (ein Baustein verschwindet ohne Satz).
- „Ausgewählt ist alles“ stimmt nicht für Übersetzungen; der Basis-Hinweis bleibt bei „Alle Texte“.
- „Projekt gewinnt“ überspringt Farben & Schriften und Layout ganz; die Hinweise zu Nachinstallieren
  und Klonen passen nicht zur Strategie.
- „Abgebrochen.“ grün; Dateiname „vorlage“ auch englisch; Inspektor-Beschreibung unvollständig;
  „Inhalt“ als Gruppen- und als Bausteinname.

**Vorschau & Build**

- Übersicht „Starten“ übergeht Port und Host der Seite.
- `discovery.portTaken` behauptet ein Ausweichen auch mit Remote-Host; der Remote-Host-Text verweist
  auf die eigene Seite; „Karte“ statt Inspektor-Abschnitt; englisch „Quit“ im Start-Dialog stoppt
  Server; „Port 8080, 3001 ist belegt“.
- ⌘B aktualisiert die Ergebniszeile der Seite nicht; fehlende Pakete erscheinen als „Fehlgeschlagen
  in 0,0 s“ in Orange.

**Git-Sync und Dokumente**

- Git-Sync lädt mit „Prüfe auf Updates…“.
- „Jeder Sync … holt … pusht“ stimmt nicht für Push oder Pull allein.
- Der Buch-Dateiname folgt dem Titel nicht („neues-buch.pdf“), gegen „Die Dateien heißen wie das Buch“.
- Export-Knopf „Speichere…“; ein abgebrochener Export erscheint als „Veröffentlichung
  fehlgeschlagen.“ in Rot.

**Veröffentlichen und Zugänge**

- Pages-API-Fehler in der normalen Ausgabe statt als Fehler-`Callout`.
- Nach „Diff aktualisieren“ steht „Seit dem Öffnen noch kein Lauf“; „auf dem Server“ auch bei
  Ordner-Zielen; die Nutzung zählt Ziele statt Projekte; Webhook ohne URL heißt „kein Passwort/Key“;
  rsync-Fehler mit Debian-Tipp; „Speichere…“ auf Knöpfen, die nicht speichern; Ausschlüsse
  kommagetrennt; Zahlen in der Bestätigung können veraltet sein; das Manifest bleibt nach dem Löschen
  eines Ziels liegen.

**Updates und Snapshots**

- Der Status prüft fest die jackyzha0-URL, der Lauf holt vom Remote `quartz-upstream` (kann
  abweichen).
- Das Ausdünnen der Snapshots ist nirgends erwähnt; gemeinsame Fächer können „Vor Kern-Update“
  entfernen; „vor jedem Update“ stimmt nicht, wenn nichts geändert war.
- Leertext und Popover-Hinweis der Snapshots unvollständig; die Spalte „Commit“ zeigt den Commit des
  Stores, nicht den des Projekts; der Reset-Schalter erscheint nur bei nichtleerer Dateiliste.
- Das Kern-Update stasht nur `package.json` und `package-lock.json`; die Konflikt-Überschrift setzt
  den Locale-Schutz voraus; „Merge abbrechen“ und Plugin-Updates ohne Rückfrage.
- Updates englisch „Check failed“, Übersicht englisch „Cannot check“ für dasselbe „Nicht prüfbar“.

**Menüs und Texte allgemein**

- Großschreibung der Menüs englisch gemischt; „licence“ und „license“ gemischt.
- Ungenutzter Schlüssel `main.aboutLicense` mit QuartzControl-URL.
- `docs/gleichstand/einrichtung.md:128` veraltet.
- Merge-Betreff „(via QuartzControl)“ sichtbar in der git-Geschichte (bewusst, gemeinsames Format;
  nur festgehalten).

---

## Verworfen

Beim Nachlesen nicht bestätigt, nicht in die Liste übernommen:

- „Port-Felder ohne Bereichsprüfung, `UInt16(port)` kann abstürzen“: In `App` und im Kern gibt es
  keine solche Umwandlung eines Ports aus einem Feld (gesucht nach `UInt16(`).
- „`main.snapshotContentUntouched` wird nie angezeigt“: `SnapshotStore+Restore.swift:172` hängt den
  Satz an (`contentLeftAloneNote`); bei H1 erscheint er sogar zu Unrecht.

Schon behoben: Bilder fehlten im PDF-Export außerhalb des Fensters (`content-visibility`), `6ebd851`.
