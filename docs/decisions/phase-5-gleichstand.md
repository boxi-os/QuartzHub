# Phase 5: Gleichstand

Was beim Schließen der Lücken aus [`gleichstand.md`](../gleichstand.md) gemessen und entschieden
wurde, ein Abschnitt je Lücke.

## Aufräumen beim Start, Abbrechen beim Beenden

Der Kern hatte seit Punkt 9 alles dafür (`SiteCopy.sweep`, `FormsRelay.sweepTempDirs` und
`removeOpenTempDirs`, `ExportBook.cancelAll`), die App rief nichts davon auf: phase-3-dienste.md
hatte es „für Phase 4“ vorgemerkt, und keine Seite brauchte es. Aufgefallen ist es erst beim
Zusammenstellen der Liste, obwohl die Folge vorher schon zu sehen war: Im Temp-Ordner lagen zwei
Export-Kopien und vier Regel-Ordner vom 2026-11-08 und überstanden Dutzende Starts.

Jetzt wie in QuartzControl (`electron/main/index.ts`):

- **Beim Start**, nach dem Fenster und der Frage nach verwaisten Servern, im Hintergrund:
  `SiteCopy.sweep` (die Kopien und die Regel-Ordner der Exportfenster, gleiches Präfix) und
  `FormsRelay.sweepTempDirs`. Beide lassen alles stehen, was jünger als eine Stunde ist.
- **Beim Beenden** (`applicationWillTerminate`, QuartzControls `will-quit`): die Relay-Ordner, die
  ein Lauf noch hält, sofort löschen, denn in ihnen liegen `config.php` und das Relay-Geheimnis.
  Dazu `ExportBook.cancelAll()`.

Nicht beim Schließen des letzten Fensters, wie es der Kommentar in `ExportBook` vorsah: Unter macOS
läuft die App ohne Fenster weiter, und ein Export gehört dem Projekt (`PublishModel.shared`), nicht
dem Fenster. Geschlossen und wieder geöffnet zeigt die Seite ihn laufen.

Gemessen am 2026-11-09 mit einem Wegwerf-Profil:

- **Start:** Die sechs Ordner vom Vortag und ein `qh-relay-…`, mit `touch` auf den Vortag gesetzt,
  waren danach weg.
- **Gegenprobe:** Ein eben angelegter `quartzhub-export-frisch` und eine Kopie von 16:14 (Start um
  16:53) blieben stehen.
- **Beenden über das Menü** ohne laufenden Lauf beendet sauber.

Nicht gemessen: das Löschen offener Relay-Ordner beim Beenden (braucht einen Relay-Lauf, also das
Netz) und das Beenden während eines Exports. Ein `pkill` ruft `applicationWillTerminate` nicht auf;
was dabei liegen bleibt, räumt der nächste Start nach einer Stunde.

## Handlungsbedarf führt auf den Reiter

`ProjectAttention.Issue.tab` stand seit der Übersicht im Kern („Die Seiten lesen sie, sobald sie
Tabs haben“), gelesen hat es niemand, auch nachdem Konfiguration und Stile Reiter bekamen. Ein
SCSS-Fehler führte damit auf den zuletzt offenen Reiter der Stile, nicht auf Eigenes CSS.

Die Übersicht setzt jetzt vor dem Wechsel den gespeicherten Reiter der Zielseite
(`@SceneStorage("config.tab")` bzw. `"styles.tab"`), so wie Updates Snapshots den offenen Snapshot
übergibt; der Schlüssel hat denselben Typ wie auf der Seite. Ein Reiter, den die Seite nicht kennt,
wird nicht gesetzt. Dazu der Nachbarfall: „Konfiguration ›“ unter „Die Seite“ führt auf Website,
weil alle vier Zeilen dort Felder von Website sind (QuartzControl `config?tab=site`, sein 28. Review,
Befund 5).

Gemessen am 2026-11-09 an der gui-test-Kopie mit einer unvollständigen Regel in `custom.scss`
(danach zurückgesetzt), Dunkel, 1400×860:

- Stile auf Basis gestellt, zurück zur Übersicht, „Stile ›“ am Eintrag öffnet Eigenes CSS mit der
  Fehlermeldung.
- Konfiguration auf Übersetzungen gestellt, „Konfiguration ›“ unter „Die Seite“ öffnet Website.
- **Gegenprobe:** Konfiguration auf Übersetzungen, über die Seitenleiste geöffnet, bleibt auf
  Übersetzungen („Wo war ich“).

Nebenbei gesehen: Der Eintrag heißt „Dein CSS lässt sich nicht übersetzen“; das Projekt schreibt
„konnte nicht … werden“. Nicht geändert.

## „Keine passende Seite“

QuartzControls Combobox für die Zielseite eines Formulars zeigte bei einer Eingabe ohne Treffer
die leere Liste mit „Keine passende Seite“. `textInputSuggestions` zeigt bei null Vorschlägen gar
nichts, die Eingabe blieb also ohne Antwort, bis das Feld verlassen und „Keine Seite der Website
hat diesen Slug“ darunter stand. Jetzt sagt die Zeile unter dem Feld schon beim Tippen „Keine
passende Seite“, solange keiner der Slugs den Text enthält.

Gemessen am 2026-11-09 an der gui-test-Kopie (Formular „Kontakt“, Nach dem Senden „Zu einer Seite
wechseln“, die Config danach zurückgesetzt): „xyzq“ getippt, die Zeile sagt „Keine passende Seite“;
**Gegenprobe** „anim“: die Vorschläge erscheinen (`animation/…`, `quellen/artikel/css-animations-mdn` …).

## Das Hilfe-Menü

Wie QuartzControls `menu.ts` (Nutzer, 2026-11-09: alle Einträge): Rückmeldung senden, Quartz-
Dokumentation, Plugin-Katalog, Datenordner von QuartzHub öffnen, Lizenzen öffnen
(`App/Shell/HelpCommands.swift`, `CommandGroup(replacing: .help)`; das Suchfeld des Systems bleibt).
Hilfe ▸ Handbuch kommt mit dem Handbuch. Zoom, Neu laden und Entwicklerwerkzeuge entfallen (Nutzer):
Eine macOS-App zoomt nicht als Ganzes, und ohne Webseite gibt es nichts neu zu laden.

- **Rückmeldung** öffnet ein neues Issue in `boxi-os/QuartzHub` mit Fassung und System im Text, wie
  QuartzControls `sendFeedback`. Solange das Repo privat ist, antwortet GitHub allen außer den
  Mitwirkenden mit 404 (QuartzControl hat das am 2026-09-09 gemessen); der Punkt gehört zur
  Release-Liste.
- **Lizenzen** öffnen den Ordner `Contents/Resources/licenses` (scripts/package.sh), im Debug-Bau den
  des Repos. Fehlt er, sagt ein Dialog es, statt dass der Klick ins Leere geht.
- Zwei Texte nannten noch QuartzControl (`main.menuDataFolder`, `main.licensesMissingDetail`).

Gemessen am 2026-11-09 mit einem Wegwerf-Profil: Das Menü liest „Rückmeldung senden…, —,
Quartz-Dokumentation, Plugin-Katalog, —, Datenordner von QuartzHub öffnen, Lizenzen öffnen“ (System
Events). „Datenordner …“ öffnete im Finder den mit `-QHProfileDir` gesetzten Ordner, „Lizenzen“ den
Ordner im Repo. Nicht geklickt: die drei Web-Links (öffnen den Browser, also das Netz). Nicht
gemessen: der Lizenzordner im Paket und der Dialog, wenn er fehlt.

## Projektkopf in der Seitenleiste

QuartzControls `ProjectLayout` zeigte über der Navigation eine Karte mit Projektbild, Name und
Pfad; in QuartzHub stand der Name nur im Fenstertitel, der Pfad nur im Inspektor der Übersicht.
Jetzt sitzt `SidebarProjectHeader` als `safeAreaInset` oben in der Seitenleiste: `ProjectAvatar`
aus dem Fenster „Projekte“ (eigenes Bild oder Anfangsbuchstabe auf der Farbe der Kennung), der Name,
darunter der Pfad, in der Mitte gekürzt (dort unterscheiden sich lange Pfade am wenigsten) und
ganz als Tooltip. Ein neues Projektbild kommt über `ProjectsModel.reload()`, das die
Konfiguration schon ruft.

Gemessen am 2026-11-09 an der gui-test-Kopie: Dunkel in 1400×860, Hell in 1000×700 (Thema über das
Wegwerf-Profil), der Kopf mit dem Bild von gui-test und „/private/tmp/…pad/pub/proj“. Nicht
gemessen: das Bild nach einer Änderung auf Konfiguration.

## Rollposition je Seite

QuartzControls `useRestoreScroll` merkte sich je Route, wie weit gescrollt war, solange die App
lief, und setzte es beim Zurückkehren wieder, auch während die Seite noch nachlud. In QuartzHub
baut jeder Besuch die Seite neu, sie stand also immer oben. Jetzt hängt `PageScaffold` jeder Seite
`ScrollMemory` an, im Speicher je Projekt und Seite, nicht über einen Neustart.

Was beim Bauen nicht so war wie gedacht, je gemessen:

- **Welche Scrollansicht:** Eine Seite gibt ihre nicht heraus, also nimmt `ScrollMemory` die mit der
  größten Überlappung mit dem Seitenrahmen. Ganz enthalten ist keine: Das Formular der Übersicht
  reicht unter die Symbolleiste (1400×860, so groß wie das Fenster).
- **Die alte Seite steht noch da:** Beim Wechsel war die Scrollansicht der verlassenen Seite einen
  Moment im Fenster, die neue Seite hängte sich an sie und schrieb ihre Bewegungen unter dem
  eigenen Schlüssel. Gesucht wird deshalb erst nach dem nächsten Durchlauf.
- **Nur was der Nutzer scrollt, wird gespeichert:** SwiftUI setzt das Formular nach dem Erscheinen
  noch einmal auf seinen oberen Rand (−52), und gespeichert löschte das die Stelle. Auch der Klick
  in die Seitenleiste ist ein Ereignis, unter dem die neue Seite ihr erstes Layout macht. Es zählen
  Rad, Ziehen und Tasten, die auf diese Scrollansicht zielen. Andere Bewegungen werden in den ersten
  fünf Sekunden rückgängig gemacht, danach gehören sie der Seite.
- **Fünf Sekunden, nicht anderthalb:** Plugins liest die Config länger als anderthalb Sekunden;
  danach blieb die Liste oben.
- **Eine Liste merkt sich die Zeile, nicht den Abstand:** Die Liste ist eine Outline-Ansicht, die
  Höhen nicht gezeichneter Zeilen nur schätzt. Derselbe Abstand landete einen Abschnitt daneben
  („Verarbeitung (25)“ statt „Navigationen (3)“). Gemerkt wird die oberste Zeile mit dem Anteil, wie
  weit sie verdeckt ist, wiederhergestellt mit `scrollRowToVisible`. Die Zeile bestimmt
  `rect(ofRow:)`, nicht `row(at:)`: Das antwortete in SwiftUIs Liste mit einer Zeile, die über dem
  Punkt endete (Anteil 1,0), und die Liste lag zwei Zeilen daneben.

Gemessen am 2026-11-09 an der gui-test-Kopie, 1400×860: Übersicht zwölf Radschritte hinab, Plugins
zwölf hinab, Snapshots, zurück zur Übersicht: dieselbe Stelle („…vor 4 Wochen · boxi-os“, „Plugins“,
„46 von 64 aktiv“); Plugins: dieselbe Stelle („Navigationen (3)“, „quartz-navigations … priority:
20“). **Gegenprobe:** Snapshots, vorher nie gescrollt, öffnet oben.

Nicht gemessen: Seiten, deren größte Scrollansicht ein Editor ist (Eigenes CSS, Zusätzliche
Inhalte), und Seiten mit Reitern, die sich eine Position für alle Reiter teilen (wie in
QuartzControl, dessen Schlüssel der Pfad ohne Reiter war).

## Rückweg nach einem Verweis

QuartzControls `state/returnLink.ts`: Schickt die App den Nutzer woandershin („Auf der Bühne
zeigen“, „Alle Optionen in der Plugin-Liste“, „Zu den Snapshots“), steht über der Zielseite
„‹ Zurück zu „Plugins › Zusätzliche Inhalte““. In Phase 4 war nur der Verzicht für die Übersicht
entschieden; für die übrigen Verweise wollte der Nutzer ihn (2026-11-09).

`App/Shell/ReturnLink.swift`, ein Objekt je Fenster, mit QuartzControls Regeln:

- **Ein Ort ist eine Seite und, auf den vier Seiten mit Reitern, der Reiter.** Den Reiter kennt das
  Fenster nicht: Eine zweite `@SceneStorage` mit dem Schlüssel der Seite im selben Fenster macht
  deren Schreiben rückgängig (gemessen in Phase 4 am Layout). Jede Seite mit Reitern meldet ihn
  deshalb mit `.returnTab(page:tab:)` und nimmt darüber auch den Reiter an, auf den sie
  zurückgeschickt wird.
- **Gesetzt wird ohne Zutun der Seiten.** `openPage` und `openLayout` setzen den Rückweg, sobald die
  Seite gewechselt hat, nicht wenn die Frage nach ungespeicherten Änderungen mit Abbrechen endete.
  Nur die Sprünge innerhalb einer Seite sagen es selbst: Plugins (alle vier „Alle Optionen“),
  Layout (Übersicht ▸ Komponenten oder Frames, „Frame bearbeiten“).
- **Lebensdauer:** Die Leiste steht, solange der Nutzer auf der Zielseite bleibt, über ihre Reiter
  hinweg; nach einem Sprung innerhalb einer Seite nur auf dem Reiter, zu dem er führte. Jeder andere
  Weg beendet sie. Zurück innerhalb einer Seite ist ein Reiterwechsel und fragt nichts, zwischen
  Seiten fragt es wie die Seitenleiste.
- **Von der Übersicht aus keiner**, wie in Phase 4 entschieden: Dort ist die Seitenleiste der Weg
  zurück.
- Dazu wie in QuartzControl: „Konfiguration“ beim fehlenden `index.md` auf Vorschau & Build führt
  auf den Reiter Website (`openPage(_:tab:)`).

Die Leiste sitzt in `PageScaffold` über der mittleren Spalte, nicht als `safeAreaInset` um die
ganze Seite im Fenster: Dort lagen Seite und Inspektor darunter, der Reiter-Umschalter von Layout
und der Kopf des Inspektors waren verdeckt (gesehen 1400×860).

Gemessen am 2026-11-09 an der gui-test-Kopie, Dunkel in 1400×860:

- Plugins ▸ Zusätzliche Inhalte, Box „mark“, „Auf der Bühne zeigen“: Layout ▸ Komponenten mit
  „Zurück zu „Plugins › Zusätzliche Inhalte““; der Klick führt auf den Reiter, „mark“ gewählt, die
  Leiste ist weg.
- „Alle Optionen in der Plugin-Liste“: Installiert mit quartz-layout-box #1 im Inspektor und
  derselben Leiste. **Gegenprobe:** von Hand auf Navigationen, die Leiste ist weg und kommt auf
  Installiert nicht wieder.
- Updates ▸ „Zu den Snapshots“: „Zurück zu „Updates““. **Gegenprobe:** über die Seitenleiste zu
  Konfiguration und zurück zu Snapshots, keine Leiste.
- Layout ▸ Übersicht, Spalte „Tag-Seiten“: Komponenten mit „Zurück zu „Layout › Übersicht““, der
  Klick stellt den Reiter Übersicht wieder ein.

Hell in 1000×700: Updates ▸ Snapshots mit der Leiste und zurück; **Gegenprobe:** „Konfiguration ›“
auf der Übersicht öffnet Konfiguration ohne Leiste.

Nicht gemessen: der Rückweg zwischen Seiten mit ungespeicherten Änderungen (die Frage), der Weg von
Vorschau & Build auf Website (braucht ein Projekt ohne `index.md`) und der Verweis von
Konfiguration zu den Stilen (erschien an gui-test nicht).

Nebenbei gesehen: `CoexistenceBand` sitzt noch als `safeAreaInset` um die ganze Seite und dürfte
Seite und Inspektor genauso verdecken; nicht geprüft, weil es dafür ein laufendes QuartzControl
braucht. Nicht geändert.

## Frames mit der Tastatur

QuartzControl platzierte und verschob einen Bereich im Frame-Editor auch mit der Tastatur: dnd-kits
Griff aufnehmen, Pfeile, ablegen (`placeArea`, `moveArea`; Handbuch „Das geht auch mit der
Tastatur“). Die Entscheidung 4b gibt der Tastatur dafür in Raster und Board den Inspektor; auf der
Bühne war das gebaut, im Frame-Editor fehlte es (Lücke 12).

Jetzt hat der Inspektor eines Bereichs unter den Spannen einen Abschnitt mit Zeile, Spalte und
einem Knopf (`App/Pages/Layout/FramesTab.swift`):

- **„Verschieben nach“** mit „Bereich … verschieben“ für einen Bereich im Raster. Der Knopf ist
  aus, solange Zeile und Spalte sein jetziger Platz sind.
- **„Platzieren auf“** mit „Bereich … platzieren“ für einen Bereich im Vorrat. Angeboten wird sein
  eigener Platz, wenn er nur ausgeblendet ist (Platzieren zeigt ihn dann wieder, wie das Ablegen
  auf dem Raster), sonst die erste Zelle Zeile für Zeile, auf der er landen darf.
- **Erst wählen, dann anwenden:** Zeile und Spalte gelten zusammen. So springt ein Bereich über
  einen anderen hinweg, statt auf halbem Weg abgelehnt zu werden, was bei zwei sofort wirkenden
  Wählern passiert wäre.
- **Eine Regel mit dem Ablegen:** Beide Wege gehen durch `FramePlacing.place`, also
  `FrameEditing.dropping` (Spannen am Rasterrand gekürzt, abgelehnt über einem anderen Bereich),
  und sagen denselben Satz an (`dnd.dropped`, `dropNarrowed`, `dropRefused`). Eine Ablehnung steht
  im Inspektor wie die der Spannen.

Gemessen am 2026-11-09 an der gui-test-Kopie, Frame „boxi-test“ (5 × 3, alle Zellen belegt).
Zeile und Spalte wurden über die Tastatur im Menü des Wählers gesetzt (Ziffer, Return), der Knopf
geklickt:

- **Dunkel, 1400 × 860:** „right“ (4/3) nach Zeile 2: **abgelehnt** mit „right bleibt, wo es war:
  Dort überschneidet es sich mit einem bestehenden Bereich.“ Dann „right“ aus dem Raster gelöst,
  „after-body“ von 4/2 nach 4/3 verschoben. „right“ im Vorrat bot 4/2 an, „Platzieren“ legte ihn
  dorthin. Raster und „Beginnt in Zeile 4, Spalte 2“ stimmen überein.
- **Hell, 1000 × 700:** „Sichtbar auf Desktop“ für „right“ aus. Der Vorrat zeigt „right
  ausgeblendet“, der Inspektor „Platzieren auf“ mit 4/3; „Platzieren“ zeigt ihn dort wieder, und
  der Abschnitt heißt danach „Verschieben nach“.
- Nichts gespeichert. Alle `frame.json` der Kopie sind byte-gleich, in der Kopie wurde nichts
  geschrieben.

Nicht gemessen: Tab bis zu den Wählern, das hängt an der Systemeinstellung
„Tastaturnavigation“ und ist dieselbe wie bei jedem Formular des Inspektors; die Ansage mit
VoiceOver.

## Fenster „Projekte“ an der App gemessen

Der erste Durchgang über die `gebaut`-Zeilen (docs/gleichstand.md, „Wie weiter“, Punkt 2). Gemessen
am 2026-11-09 mit einem Wegwerf-Profil (`-QHProfileDir`) und sieben Einträgen: die gui-test-Kopie
mit eigenem Bild, vier kleine Ordner mit nur einer `quartz.config.yaml` (mit und ohne Basis-URL),
ein Ordner ohne sie und ein Pfad, den es nicht gibt. Zuletzt geöffnet vor zwei Stunden, gestern,
vor drei und vor neun Tagen, drei nie. Dunkel 1000 × 640, Hell 1000 × 640 und leer.

- **Liste:** Bild bzw. Buchstabe, Name, „„Titel“ · Adresse“ (ohne Adresse nur der Titel), der in
  der Mitte gekürzte Pfad, „Zuletzt geöffnet vor 2 Stunden / gestern / vor 3 Tagen / letzte
  Woche“, „Noch nie geöffnet“. Reihenfolge wie `Home.tsx`: nach dem Öffnen absteigend, dann die nie
  geöffneten nach Namen.
- **Warnzeilen:** „Ordner nicht gefunden …“ und „Kein Quartz-Projekt …“ in Liste und Inspektor;
  bei beiden ist „Öffnen“ grau, ohne Ordner fehlt „Duplizieren…“. Ein Doppelklick auf den Ordner
  ohne Quartz öffnet kein Fenster.
- **„Ordner suchen…“:** Ein Ordner, der schon in der Liste steht, ergibt „Dieser Ordner ist
  bereits als anderes Projekt registriert.“ unter dem Knopf; ein neuer setzt Pfad und Namen
  (der Ordnername, wie in QuartzControl), Kennung und Farbe bleiben, die `quartz.config.yaml` im
  Ziel bleibt byte-gleich.
- **Suche:** sieben Einträge zeigen das Feld. „gärten“ findet „Mein Gärten-Blog“ über den Titel,
  „HOME/P“ die fünf Ordner unter `home/p` über den Pfad, „xyzq“ zeigt „Keine Ergebnisse für
  „xyzq““. Gegenprobe der Schwelle: nach zwei Mal Entfernen, bei fünf Einträgen, ist das Feld weg,
  mit einem neu aufgenommenen Ordner wieder da.
- **Entfernen:** aus dem Kontextmenü und aus dem Inspektor; „Abbrechen“ lässt den Eintrag, die
  Ordner bleiben. Mit laufendem Dev-Server lautet die Frage „Der laufende Dev-Server wird dabei
  beendet. …“, und nach „Aus der Liste entfernen“ ist der Prozess weg, Port 8080 frei,
  `running-servers.json` leer. Das offene Projektfenster sagt danach „Dieses Projekt steht nicht
  mehr in der Projektliste.“ mit „Projekte zeigen“. Die zwei Fassungen mit Relay-Geheimnissen
  brauchen ein eingerichtetes Relay und sind nicht gemessen.
- **Kontextmenü:** Öffnen, Im Finder zeigen, Duplizieren…, Entfernen…; beim Ordner ohne Quartz
  sind Öffnen und Duplizieren grau. „Im Finder zeigen“ öffnet den übergeordneten Ordner mit dem
  Projekt markiert.
- **Öffnen:** ⌘O mit einem Ordner ohne `quartz.config.yaml` nimmt ihn auf und öffnet nichts; der
  Knopf in der Symbolleiste mit einem Quartz-Ordner öffnet sein Fenster, stempelt
  `lastOpenedAt` und schreibt nichts in den Ordner. Ein zweiter Doppelklick holt das offene Fenster
  nach vorn, ein zweites entsteht nicht. ⇧⌘0 holt „Projekte“ nach vorn.
- **„Neues Quartz-Projekt“** (⌘N): Ort aus `defaultProjectDirectory` der Einstellungen, „Angelegt
  wird:“ mit dem vollen Pfad, die vier Grundgerüste, drei Notizenquellen (bei „kopieren“ der
  Quellordner, und „Projekt anlegen“ bleibt grau, bis er gewählt ist), drei Wikilink-Formen,
  Basis-URL „localhost“. „Basis-Template mitinstallieren“ mit „Mit Beispielseiten“ (22 Seiten);
  bei „kopieren“ ist das aus und grau, mit dem Satz, warum. Ein Name, unter dem schon Dateien
  liegen, ergibt im Dialog „In „…/blog“ liegen bereits Dateien. …“, bevor ein Prozess startet; der
  Ordner bleibt unverändert. Esc bricht ab, ohne etwas anzulegen.
- **Duplizieren:** „„zeta“ duplizieren“, Name „zeta-2“ vorgeschlagen, die drei Inhaltsarten, bei
  „hineinkopieren“ der Quellordner und „Duplizieren“ grau, darunter „Nicht mitkopiert werden: …“.
- **Leere Liste (Hell):** „Erste Schritte“ mit den drei Schritten, „Neues Projekt erstellen“
  hervorgehoben vor „Vorhandenes Projekt öffnen“. Im Inspektor ohne Auswahl „Werkzeuge bereit ·
  in QuartzHub: node 24.22.2, npm 11.19.1 · vom System: git 2.54.0“, „Was ist Quartz?“ mit den
  zwei Links (gelesen, nicht geöffnet) und „Was du hier tun kannst“.

Zwei Befunde, beide behoben:

- **Das Abzeichen „Dev-Server auf Port …“ kam nicht.** Das Fenster las die Liste beim Start und
  wenn QuartzHub wieder aktiv wurde. Ein Server, der im Projektfenster startete, erschien erst,
  nachdem QuartzHub den Fokus verloren und wiederbekommen hatte (Gegenprobe: Finder aktiviert,
  zurück, da war es). QuartzControl las die Liste bei jeder Rückkehr auf die Startseite neu; hier
  steht das Fenster daneben offen. Jetzt liest es neu, sobald ein Server zur Ruhe kommt
  (`BuildMonitor.settledServers`, wie die Liste der Server auf dem Rechner). Nachmessung ohne
  Fokuswechsel: Starten im Projektfenster, das Abzeichen steht im hinteren Fenster; Stoppen, es ist
  weg.
- **Der Assistent lud die Beispielvorlage aus dem Netz,** auch mit `-QHNoUpdateCheck YES`: Ohne
  frische Kopie im Profil fragt `BuiltinTemplate.find` GitHub. Die Seite Vorlagen kannte den
  Schalter, der Assistent nicht, und der Rauchtest öffnet ihn. Beide nehmen jetzt
  `BuiltinTemplate.app()`. Nachmessung: Dialog geöffnet, die Vorlage mit 22 Seiten angeboten, im
  Profil entstand kein `templates/`.

Nicht gemessen: das Werkzeug-Band (fehlend, kaputt, inkompatibel), weil es sich nur durch einen
Eingriff in Runtime oder PATH herstellen ließe; was nach einem echten Anlegen oder Duplizieren
kommt (Netz).
