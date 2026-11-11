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

## Fenster „Einstellungen“ an der App gemessen

Zweiter Durchgang über die `gebaut`-Zeilen, am 2026-11-09. Wegwerf-Profil mit zwei Projekten
(`alpha`, `zeta`) und darin vier Veröffentlichungszielen, dazu in `connections.json` ein
GitHub-Eintrag mit `secretInKeychain`, aber ohne Geheimnis (`-QHMemorySecrets YES`), ein
SSH-Zugang mit SSH-Agent und gemerktem Host-Key, ein FTP- und ein SSH-Zugang ohne Geheimnis; in
`theme-docs/` drei `.json` und eine `notes.tmp`; `running-servers.json` kaputt. Dunkel, Hell und
mit dem leeren Profil. Nichts davon ging ins Netz: Die Token-Prüfung endet ohne Geheimnis vor der
Anfrage (`GitHubAPI.api`, 401 wie in QuartzControl), und das Zugangs-Sheet ruft nichts auf.

- **Allgemein:** „relativ/ordner“ und „Speichern“ ergibt „Das ist kein vollständiger Pfad. …“,
  `settings.json` bleibt unverändert. „~/Documents/QH Ü-Test“ und Return speichert
  `/Users/…/Documents/QH Ü-Test` (Ü als NFC-Bytes, wie getippt), der Knopf sagt „Gespeichert.“. Ein
  leeres Feld entfernt `defaultProjectDirectory`. „Auswählen“ öffnet den Ordnerdialog; ⇧⌘G zu
  `home/p/alpha` und „Öffnen“ speichert den Pfad sofort. Die drei Wahlen unter „Beim Beenden“
  schreiben `keep`, `stop`, `ask` und wechseln den Satz darunter. (Was beim Beenden passiert, ist in
  „Hülle und Menü“ gemessen.)
- **Zugänge:** Der GitHub-Eintrag zeigt „Abgelehnt“ mit Hinweis, „Erneut prüfen“ ebenso, „Token
  entfernen“ nimmt den Eintrag aus der Datei, danach das leere Feld. Die Liste: „qchost@debian.invalid:22
  · von 3 Projekten verwendet“, „von 1 Projekt verwendet“, „kein Passwort/Key“ bei den zwei ohne
  Geheimnis. Löschen des genutzten Zugangs fragt „Dieser Zugang wird von 3 Projekten verwendet.“,
  „Abbrechen“ zuerst; der ungenutzte wird nach „Diesen Zugang löschen?“ gelöscht. Das Sheet des
  SSH-Zugangs zeigt „Host-Key bestätigt: SHA256:…“; „Host-Key vergessen“ fragt mit dem Host, danach
  fehlt `hostKey` in der Datei und das Sheet sagt „Host-Key noch nicht bestätigt …“. Ein neuer
  Webhook-Zugang speichert nur den Ursprung (`login: https://api.netlify.com`) in die Datei, die URL
  ins Geheimnis. Leeres Profil: „Noch keine Zugänge angelegt.“
- **Laufzeit:** „Im Einsatz: Node v24.22.2 und npm 11.19.1 aus QuartzHub.“, der Hinweis nennt das
  Node des Rechners (v26.5.1). „Vom System“ schreibt `nodeRuntime: system` und zeigt „Im Einsatz:
  Node v26.5.1 von diesem Rechner.“; zurück ebenso. git: „git 2.54.0 von diesem Rechner. …“.
- **Daten & Wartung:** „4 Einträge · 16 kB“ (16.007 Bytes); „Cache leeren“ löscht die drei `.json`,
  danach „1 Eintrag · 2 B“ für die `notes.tmp`. Leeres Profil: „0 Einträge · 0 B“, der Knopf grau.
  Speicherort mit Pfad, „Im Finder zeigen“ öffnet `home` mit `einst` markiert. Versionszeile
  „QuartzHub 0.1.0 · macOS Version 27.2 (Build 26B123)“. Nach einem Start mit kaputter
  `running-servers.json` steht oben „Eine gespeicherte Datei war nicht lesbar“ mit dem Pfad der
  beiseitegelegten Datei; ohne Vorfall in diesem Prozess (die Datei lag schon beim vorigen Start
  beiseite) steht nichts.

Drei Befunde, alle behoben:

- **Das Feld für den Projektordner war unsichtbar, solange es leer war,** also in jedem neuen
  Profil: Als beschriftetes Feld eines gruppierten Formulars war es randlos und so breit wie sein
  Text, der Platzhalter „~/Documents“ erschien nicht. Mit einem langen Pfad lief es links aus dem
  Abschnitt. Jetzt steht die Beschriftung darüber und das Feld mit Rahmen über die Zeile. Nachmessung:
  leer mit Platzhalter, langer Pfad im Feld, Hell und Dunkel.
- **Das Token-Feld** hatte dieselbe Form: so breit wie „ghp_…“, bei gespeichertem Token „gespeichert
  (zum Erse“. Ebenso geändert, nachgemessen in Hell.
- **Die Werkzeugzeile im Fenster „Projekte“ blieb nach dem Umschalten der Laufzeit stehen**
  („in QuartzHub: node 24.22.2“ nach „Vom System“). Das Fenster prüfte nur beim Öffnen; QuartzControls
  Startseite fragte bei der Rückkehr aus den Einstellungen neu. Jetzt lässt der Schalter das Fenster
  neu prüfen. Nachmessung: „vom System: node 26.5.1, npm 11.17.0, git 2.54.0“ und zurück.

Nicht gemessen: das mitgelieferte git mit Lizenz und Quelltext-Link (nur ohne git auf dem Rechner),
ein Token speichern und prüfen (Netz).

## Hülle und Menü an der App gemessen

Dritter Durchgang über die `gebaut`-Zeilen, am 2026-11-09, mit einem Wegwerf-Profil und der Kopie
von gui-test (`scratchpad/pub/proj`; ihre Veröffentlichungsziele blieben unberührt). Gestartet wie
immer ohne Netz; der Dev-Server lief lokal auf Port 8080.

- **Menüs:** Die Menüleiste gelesen (QuartzHub, Ablage, Bearbeiten, Darstellung, Anordnen, Fenster,
  Hilfe). „Über „QuartzHub““ zeigt Name, „Version 0.1.0 (1)“ und „GPL-3.0-or-later“. Darstellung ▸
  Vollbildmodus geht in den Vollbildmodus (`AXFullScreen` wahr, die Seite füllt den Bildschirm),
  „Vollbildmodus aus“ zurück; das Kürzel ist das von macOS 27 (Globus-F), nicht ⌃⌘F. Fenster: ⌘M legt
  das Projektfenster ins Dock, sein Eintrag „gui-test (Übersicht)“ holt es zurück; „Zoomen“ macht es
  bildschirmgroß (2560×1410) und wieder 1200×800; „Projekte“ holt das Fenster „Projekte“ nach vorn.
  ⌘, öffnet die Einstellungen.
- **Bearbeiten:** Im Feld „Seitentitel“ sind Ausschneiden, Kopieren, Einsetzen und Alles auswählen
  aktiv, ohne Feld grau. Alles auswählen und Kopieren legt „gui-test“ in die Zwischenablage,
  Ausschneiden und zweimal Einsetzen ergibt „gui-testgui-test“, Ablage ▸ Speichern wird aktiv.
  Widerrufen nimmt ein getipptes Zeichen zurück, Wiederholen ist danach aktiv.
- **Link auf der Seite:** Mit geändertem Titel fragt „Zu den Stilen“ (Konfiguration) wie die
  Seitenleiste: Escape bleibt auf Konfiguration mit der Änderung, „Änderungen verwerfen“ geht zu Stile
  mit der Rückweg-Leiste, `quartz.config.yaml` unverändert (SHA-1 gleich).
- **Speichern scheitert:** Projektordner schreibgeschützt (`chmod a-w`), Titel geändert, Seitenleiste
  „Plugins“, „Speichern“: Die Seite bleibt Konfiguration, die Änderung und „Nicht gespeichert“ bleiben,
  oben steht der Fehler. Die Datei ist unverändert, kein neuer Snapshot.
- **Konsole:** Dev-Server gestartet; die Konsole zeigt die Ausgabe ab „Quartz v5.0.0“. Nach Übersicht
  und zurück steht dieselbe Ausgabe da, mit der ersten Zeile „Cleaned output directory `public`“.
- **„Nicht mehr fragen“:** ⌘Q mit laufendem Server zeigt „Es laufen noch Dev-Server.“ mit
  „gui-test — Port 8080“. Angekreuzt und „Server beenden“: `settings.json` bekommt
  `"serversOnQuit": "stop"`, der Port ist zu, `running-servers.json` leer, die App beendet. Nächster
  Start, Server gestartet, ⌘Q: keine Frage, der Server ist aus.
- **Letzte Seite:** Mit `-NSQuitAlwaysKeepsWindows YES` (sonst schließt macOS die Fenster beim
  Beenden, die Systemeinstellung ist Standard) Plugins geöffnet, beendet, ohne `-QHOpenProject` neu
  gestartet: Das Fenster „gui-test“ kommt auf Plugins zurück. Ohne Wiederherstellung öffnet ein
  Projekt auf der Übersicht.
- **Nicht mehr in der Liste:** Bei offenem Projektfenster im Fenster „Projekte“ „Aus der Liste
  entfernen“: Das Projektfenster heißt „QuartzHub“ und sagt „Dieses Projekt steht nicht mehr in der
  Projektliste.“, „Projekte zeigen“ holt die Liste nach vorn.
- **⌘O:** Öffnet aus jedem Fenster den Ordnerdialog; ⇧⌘G zum Projekt und „Öffnen“ nimmt es in die
  Liste auf (Name nach dem Ordner) und öffnet sein Fenster.
- **Übernahme „Später“:** Gefälschtes QuartzControl-Profil mit einem Projekt und Einstellungen, ohne
  Geheimnis. Der Dialog zeigt „1 Projekt“ und „Einstellungen“; „Später“ schließt ihn, im eigenen Profil
  liegt danach nur `running-servers.json`. Der nächste Start fragt wieder.

Kein Befund, der hier zu beheben war. Nicht gemessen: eine abgelehnte Schlüsselbund-Abfrage bei der
Übernahme (braucht den echten Eintrag von QuartzControl) und die drei Hilfe-Links ins Netz.

## Übersicht an der App gemessen

Vierter Durchgang, am 2026-11-09. Zwei Projekte im Wegwerf-Profil: ein APFS-Klon der gui-test-Kopie
ohne Veröffentlichungsziele (`scratchpad/ov/proj`) und ein eigenes kleines Testprojekt
(`scratchpad/ov/mini`: Config von gui-test, leere Abhängigkeiten, eine Notiz, ein frisches
git-Repository ohne Remote). Unter `content/` des Klons wurde nichts geändert; die Fälle des
Content-Ordners stehen im Testprojekt. Jede Änderung mit Sicherung und danach zurückgestellt; die Seite
liest beim Erscheinen neu, also über eine andere Seite und zurück.

- **Grundzustand gegen die Platte:** Titel, Basis-URL und Sprache wie in `quartz.config.yaml`;
  „Eigener Ordner · 228 Dateien“ (229 Dateien, eine davon `.DS_Store`); Git „v5“, „↑ 0, ↓ 0“,
  „90 noch nicht committete Änderungen“ wie `git status --porcelain`, letzter Commit mit Betreff,
  Alter und Autor; „5 eigene Frames · 14 Stylesheets“, „CSS übersetzt“; Build „465 Dateien · 33 MB“
  (465 Dateien, 32,5 MB). „Alles ok“ oben.
- **Fünf Einträge auf einmal:** Zeile `baseUrl` entfernt, ein Frame-Ordner aus `authored-frames`
  genommen, Syntaxfehler in `custom.scss`, `.git/MERGE_HEAD` angelegt, `node_modules/@clack/prompts`
  beiseite. „Handlungsbedarf (5)“: „1 npm-Paket fehlt“ mit „Installieren“ (nicht geklickt), „1 eigener
  Frame fehlt“, „Ein merge ist angefangen und nicht abgeschlossen“, „custom.scss · Zeile 30 · Expected
  expression.“, „Keine Basis-URL gesetzt“. Darunter „nicht gesetzt“, „merge läuft“, „4 eigene
  Frames“, „CSS-Fehler“.
- **Einzeln:** README.md im Index als Konflikt (`git update-index` mit drei Stufen): „1 Datei im
  Konflikt“. Abgeschnittene `package.json`: „Ob alle npm-Pakete installiert sind, konnte nicht geprüft
  werden“, dazu „CSS ungeprüft“ und kein „Alles ok“. Kaputte `.git/index`: „Der Git-Stand konnte nicht
  gelesen werden“ mit „fatal: .git/index: index file smaller than expected“; kaputtes `.git/HEAD`
  dagegen liest git als „Kein Git-Repository“, wie in QuartzControl. Ohne `public/`: „Noch nie gebaut“.
- **Testprojekt:** ohne index.md „Die Website hat keine Startseite“, „1 Datei“, Git „ohne
  Remote-Branch“. Content als Verknüpfung: das Ziel mit Ketten-Symbol, wie QuartzControl. Ziel
  entfernt: „Der Content-Ordner zeigt ins Leere“ mit dem Pfad, „Ziel fehlt“. Ohne Ordner: „Es gibt
  keinen Content-Ordner“, „nicht vorhanden“. In Hell angesehen.
- **Dev-Server:** Starten zeigt „Läuft“, die Adresse, „Gestartet vor 14 Sekunden · WebSocket 3001 ·
  PID 3749“ (die PID aus `running-servers.json`); Neu starten gibt eine neue PID; Stoppen schließt den
  Port und leert `running-servers.json`. „Snapshots ›“ öffnet Snapshots, „Projektordner öffnen“ den
  Finder im Projektordner.

Ein Befund, behoben:

- **Ein Server-Fehler kam nie in den Handlungsbedarf.** Mit dem fehlenden Paket endete der Start mit
  „Fehler“ und dem Grund im Abschnitt Dev-Server, der Handlungsbedarf blieb bei 5 und hätte ohne die
  anderen Fehler „Alles ok“ gezeigt. Die Seite las den Server-Zustand nur für ihren Abschnitt; die
  Regeln (`ProjectAttention`) bekamen immer „gestoppt“. QuartzControl gibt den Zustand mit
  (`ProjectDashboard.tsx`, `serverError`). Jetzt bekommen die Regeln den Zustand aus dem BuildMonitor.
  Nachmessung: „Handlungsbedarf (6)“ mit „Der Dev-Server ist mit einem Fehler beendet worden“; nach
  einem guten Start und Stoppen wieder „Alles ok“.

Auf `Netz` gestellt: „Installation läuft“ (nur während npm), „Kern-Update angefangen“ und „Nicht
prüfbar“ (beide aus der Update-Prüfung gegen GitHub).

## Vorschau & Build an der App gemessen

Fünfter Durchgang, am 2026-11-09, mit dem Klon und dem Testprojekt aus „Übersicht an der App
gemessen“. Ein belegter Port war ein Python-`http.server` auf 127.0.0.1:8080; der fremde Server ein
`npx quartz build --serve --port 8090 --wsPort 3091`, aus dem Terminal in der gui-test-Kopie
gestartet, die das Profil nicht kennt. Beide danach beendet, alle Ports zu.

- **Server:** Starten, „Gestartet vor 13 Sekunden · WS-Port 3001 · PID 13564 · lädt automatisch
  neu“, Neustarten (neue PID), Stoppen (Port zu). „Kopieren“ legt die Adresse in die Zwischenablage.
  „Vorschau neu laden“ ruft die Seite neu ab (ein weiteres „[200] /“ im Server-Protokoll). Bei
  laufendem Server sind Port, WS-Port und Remote-Host grau, „Zum Ändern zuerst den Server stoppen.“
- **Tunnel:** Remote-Host „tunnel.example.invalid“: Die Adresse zeigt ihn, der Hinweis wechselt auf
  „Mit Remote-Dev-Host weicht der Server nicht aus …“. Mit belegtem 8080 endet der Start in „Fehler“
  mit „Belegte Ports: 8080. …“; ohne Host startet er auf 8081.
- **Liste:** „Von QuartzHub“ mit Projektname, „Außerhalb gestartet“ mit dem Seitentitel und PID, „Port
  8080 ist belegt, aber von keinem erkennbaren Quartz-Server …“. Beenden fragt mit dem Ordner des
  Servers und „Abbrechen“ zuerst; danach ist Port 8090 frei.
- **Build:** „Jetzt bauen“ zeigt „Baue…“ und „Build läuft seit 0:02 · liest die Notizen“, danach
  „Erfolgreich in 12,2s“ und „475 Dateien · 32 MB“ (475 Dateien auf der Platte). „Ordner öffnen“ zeigt
  `public/` im Finder. „Auswählen“ mit einem Ordner aus drei Textdateien: Pfad in
  `project-prefs.json`, „Achtung: In diesem Ordner liegen 3 Dateien …“; „Jetzt bauen“ fragt „In „…“
  bauen?“, Escape lässt die Dateien liegen. „Zurücksetzen“ schreibt `"outputDir": ""`.
- **Testprojekt ohne index.md:** „Im Content-Ordner fehlt die index.md. …“ mit „Startseite anlegen →“,
  das Konfiguration ▸ Website öffnet, mit Rückweg-Leiste.

Zwei Befunde, behoben:

- **Ein beendeter fremder Server blieb in der Liste,** als „Projekt unbekannt … antwortet nicht“, bis
  zum nächsten Aktualisieren. Die Liste las sofort nach dem Signal neu, als der Kindprozess den Port
  noch hielt. Jetzt liest sie eine Sekunde später ein zweites Mal, wie schon bei eigenen Servern.
  Nachmessung: Liste leer. Der Fall selbst trat beim zweiten Versuch nicht wieder auf; der erste
  Durchlauf fand den Prozess dort schon nicht mehr.
- **„Zuletzt gebaut in 13 Sekunden“:** Übersicht und Vorschau & Build rechneten das Alter mit der Zeit
  des letzten 30-Sekunden-Takts. Neu gezeichnet zwischen zwei Takten, war ein eben gewählter Ordner
  „neuer als jetzt“. Jetzt zählt die Zeit des Zeichnens. Nachmessung: 15 Sekunden nach dem Öffnen
  eine Datei angelegt, Ordner gewählt: „vor 4 Sekunden“.

Nicht gemessen: „Im Browser öffnen“ (öffnet den Browser), eine Suche, die `ps` oder `lsof` nicht
beantworten (unvollständig oder unmöglich), und ein Beenden, das scheitert.

## Konfiguration an der App gemessen

Sechster Durchgang, am 2026-11-09, mit dem gui-test-Klon und dem Testprojekt aus „Übersicht an der
App gemessen“. Bild, Content-Ordner und Sprachdateien wurden am Testprojekt geändert; was im Klon
geändert wurde (Config, Sprachdateien), ist zurückgestellt.

- **Website:** Titel-Zusatz „ · Testseite“, Basis-URL „example.org/sub“, beide Schalter aus, ⌘S:
  `diff` zeigt genau `pageTitleSuffix`, `enableSPA: false`, `enablePopovers: false` und `baseUrl`.
  `locale: xx-XX` in der Datei: das Feld sagt „xx-XX (nicht im Projekt)“. Kaputtes YAML: „quartz.config.yaml
  konnte nicht gelesen werden.“ mit dem Grund, Speichern grau. Die Schalter und Felder haben keinen
  eigenen Titel, aber ein verknüpftes Beschriftungs-Element (`AXTitleUIElement`): VoiceOver liest sie
  mit Namen.
- **Content-Ordner (Testprojekt):** „Echter Ordner, 1 Dateien“ mit „Keine Startseite …“ und
  „Startseite anlegen…“. „Quelle ändern…“ auf einen Ordner mit zwei Notizen, „Verknüpfen“: `content`
  ist danach ein Link, der alte Ordner liegt unter `.quartz-gui/content-backups/<Zeit>/content`,
  `.gitignore` nennt `.quartz-gui/`; die Seite zeigt „Symbolischer Link, 2 Dateien“ und das Ziel.
  „Startseite anlegen…“ sagt, dass die Datei im verknüpften Ordner landet, und legt dort `index.md` mit
  Titel und Liste an; danach der Hinweis, dass die Liste ohne npm install die Ausschlussregeln nicht
  kennt. „Quelle ändern…“ mit „Kopieren“: echter Ordner mit den Dateien, der Link ist als
  `symlink.json` gesichert, der Vault unberührt. Link ins Leere: „(Ziel existiert nicht)“; ohne
  Ordner: „Kein Content-Ordner gefunden.“
- **Projektbild (Testprojekt):** wählen (128 × 128, „Liegt als quartz/static/icon.png im Projekt, 128 ×
  128 Pixel.“, `project-icon.json` mit `custom: true`), dunkles wählen (`customDark: true`), hell ersetzen
  (96 × 96), dunkles entfernen, hell entfernen (ohne ursprüngliches Bild ist `quartz/static` leer,
  `project-icon.json` weg). Favicon-Plugin ausgeschaltet: „Das Favicon-Plugin ist ausgeschaltet.“;
  Eintrag entfernt: „… nicht installiert.“; „Zu den Plugins“ öffnet Plugins. Im Klon: „Die Seite zeigt
  ein Bild, das nicht in QuartzHub gewählt wurde …“ und „Angezeigt im Kopfbereich: Eine Layout-Box …“.
- **Übersetzungen:** Reiter und Sprache bleiben über einen Seitenwechsel. Suche „callout.ti“ zeigt nur
  `components.callout.tip`, „zzqq“ „Keine Treffer.“ `readingTime` trägt „JS“; ein abgebrochenes
  Template ergibt beim Speichern den Fehler unter dem Eintrag, die Datei bleibt. Gesperrter Ordner: der
  Fehler beim Speichern, „1 ungespeichert“ bleibt. Sprachwechsel mit „1 ungespeichert“ verwirft ohne
  Frage, wie QuartzControl (`setEdits({})`). Testprojekt: „Keine Locale-Dateien gefunden …“.

Zwei Befunde, behoben:

- **Eine gesperrte Sprachdatei hieß „no such file or directory“.** `LocaleFiles.readText` warf bei
  jedem Lesefehler ENOENT, weil `FileManager.contents` keinen Grund nennt; Node, also QuartzControl,
  sagt EACCES. Jetzt liest es über `open` und reicht `errno` durch. Test `anUnreadableFileSaysWhy`
  (Gegenprobe: ohne den Fix scheitert er). Nachmessung: „Error: EACCES: permission denied, open '…'“.
- **Die Sprachauswahl hieß für VoiceOver doppelt** („Sprache der Website, Sprache der Website“): zum
  versteckten Titel kam ein eigenes Label. Das Label ist weg, nachgemessen: einmal.

## Plugins ▸ Installiert an der App gemessen

Siebter Durchgang, am 2026-11-09, am gui-test-Klon aus „Übersicht an der App gemessen“ (64 Plugins,
fünf eigene Frames), ohne Netz. Config, Lockfile, `.quartz/plugins`, `authored-frames` und die
`package.json` von `description` waren vorher gesichert und sind danach zurückgestellt (`cmp` gleich).
Ansagen mitgelesen über `kAXAnnouncementRequestedNotification`.

- **Liste:** „46 von 64 aktiv“; „Eigene Frames“ (5, „Frame“, „7 Bereiche“), „Sichtbare Komponenten“ je
  Position mit Rohschlüssel und Anzahl, nach `priority` (header 10–70, …), „Verarbeitung“ mit den
  Seitentypen und „Transformer, Filter & Emitter“ (25) nach `order`. Inaktive Zeilen blasser. Bei 1200 pt
  sind die Reiter ein Menü. Inspektor ohne Auswahl: Aktiv 46 von 64, 29, 30, 5.
- **Suche und Filter:** „Inaktiv“ „18 von 64 angezeigt“ mit „Solange gefiltert wird, ist das
  Umsortieren abgeschaltet.“; „Aktiv“ + „layout-box“ 7; „zzzq“ „Kein Plugin passt zu Filter und Suche.“
  Gefiltert: kein Nach oben/unten im Kontextmenü, Anordnen grau, keine Bedienungshilfe-Aktion.
- **Schalter:** „Plugin aktiv“ im Inspektor schreibt `enabled: false` (Snapshot `configChange`), der
  Schalter der Zeile stellt zurück; die Datei ist danach byte-gleich.
- **Umsortieren:** Kontextmenü „Nach oben“ an note-properties nummeriert afterBody in Zehnern
  (10 … 80); die Bedienungshilfe-Aktion „Nach unten: note-properties“ stellt zurück; Ziehen von
  quartz-forms unter note-properties schreibt 40/30/20 wie erwartet. Ansage „note-properties ist jetzt an
  Position 4 von 8.“
- **Platzierung:** `priority` 45 mit Return, `display` desktop-only, `groupOptions.grow` an: genau diese
  Zeilen in der Datei, „Gespeichert“ an Zeile und Inspektor, Ansage „Einstellungen von darkmode
  gespeichert.“ `condition` und `group` schnell nacheinander (Klick, tippen, Klick, tippen, Return):
  beide in der Datei. Snapshots `configChange` werden wie in QuartzControl in einem Zeitfenster
  zusammengefasst.
- **Optionen:** explorer: „Leer setzen“ schreibt `title: ""` („leer gesetzt“, „Zurücksetzen“ nimmt es
  heraus), Zurücksetzen von `folderClickBehavior` nimmt den Schlüssel heraus, das Feld zeigt „Vorgabe:
  link“. quartz-layout-box: Suche ab acht Optionen („byLang“ „Ein Treffer“, „zzzq“ „Keine Option passt
  zur Suche.“), „Selten gebraucht“, `file`/`dir` mit „wirkt nicht“ und dem Grund, Gruppen „2 · 1
  geändert“; „Sprache hinzufügen“ en schreibt `byLang: en: {}`, darin „wie oben“, „„en“ entfernen“
  nimmt es heraus. darkmode (ohne Schema): „Dieses Plugin hat keine Optionen.“; „Weitere Option
  eintragen“ `foo` = `42` (Zahl), `obj` = `{"a": 1}`, `mix` = `[1, "a", null]`; „Diese Option ist bereits
  gesetzt.“; die drei stehen unter „Unbekannte Schlüssel“; `mix` als Liste mit JSON-Feldern: ungültiges
  JSON „Kein gültiges JSON – nicht gespeichert.“, Datei unverändert; Eintrag nach unten, entfernen,
  hinzufügen. `description` ohne `optionSchema` und ohne `.d.ts`: „Das Plugin beschreibt seine Optionen
  nicht. Die Felder kommen aus seinen Vorgaben.“; kaputte `package.json`: „Die Beschreibung der Optionen
  konnte nicht gelesen werden: …“.
- **Entfernen:** roam über das Kontextmenü: „Plugin „roam“ wirklich entfernen? Vorher wird automatisch
  ein Snapshot angelegt.“, danach 63 Plugins, Snapshot `pluginChange` „@quartz-community/roam“. Während
  des Laufs sind Schalter und Wartung grau; die Abweisung „Während ein Plugin entfernt wird …“ ist so über
  diese Seite nicht auslösbar. Frame „drawing“: aus Config, Lockfile, `authored-frames` und
  `.quartz/plugins` weg.
- **Wartung:** ein verwaister Eintrag (Lockfile und Ordner, ohne Config-Eintrag): „Verwaiste
  Plugin-Ordner entfernen“ fragt, danach „Verwaiste Plugin-Ordner entfernt.“ (angesagt); Lockfile und
  Ordner sind danach gleich der Sicherung.
- **Config unlesbar:** „quartz.config.yaml konnte nicht gelesen werden.“ mit dem Grund.
- **Wo war ich:** Reiter Navigationen, Suche „search“, Filter Aktiv, Auswahl search, Platzierung offen;
  ⌘Q und Neustart mit Fensterwiederherstellung: alles wieder da.

Sechs Befunde, behoben:

- **Die Erklärungen unter den Gruppen endeten in „…“** (Eigene Frames, Verarbeitung, Wartung): Sie
  standen im Kopf des Abschnitts, der eine Zeile behält. Jetzt sind sie die erste Zeile des Abschnitts,
  nicht wählbar. Nachgemessen: ganz.
- **Geöffnet mit gespeicherter Suche, waren die Zeilen eine Zeile hoch** (nur der Name, ohne Quelle und
  Kurzangabe; die Wartungs-Erklärung angeschnitten), reproduzierbar mit Seitenwechsel; ohne Suche
  richtig. Die Liste wird neu aufgebaut, sobald die Config da ist. Nachgemessen: ganze Zeilen; Umsortieren
  und Ansagen danach unverändert.
- **Im mehrzeiligen Feld wurden Anführungszeichen typografisch**: `"b"` kam als „b“ an (kein JSON),
  `title="q"` im `html` von layout-box ebenso. `.autocorrectionDisabled()` half nicht (gemessen); beim
  Fokus werden an der Textansicht Anführungs-, Strich- und Textersetzung ausgeschaltet, wie im
  Code-Editor. Nachgemessen: `<b title="q">x</b> -- a` steht so in der Datei.
- **„Sprache hinzufügen | Schlüssel | Hinzufügen“ war im Inspektor gequetscht** („Sch“, „H…“). Jetzt
  kommen Feld und Button darunter, wenn die Breite nicht reicht. Dabei gefunden: schnell getipptes „fr“
  mit Return kam als „f“ an, weil die Aktion den Schlüssel aus dem letzten Zeichnen nahm; jetzt liest sie
  das Feld. Nachgemessen: `byLang: fr: {}`.
- **Ein Frame wurde ohne Snapshot gelöscht**, obwohl die Frage einen ankündigt; QuartzControls
  `deleteFrame` geht über `removePlugin` mit Snapshot. Die CLI-Anbindung der Frame-Befehle reicht ihn
  jetzt durch. Test `addAndRemoveTakeASnapshotFirstWhenAsked` (Gegenprobe: ohne den Fix scheitert er);
  nachgemessen: Snapshot `pluginChange` „frame-editorial“.
- **„… versteht QuartzControl nicht“** (Anzahl unverstandener Schema-Angaben) sagt jetzt QuartzHub.

Hell geprüft (Liste, Inspektor, die umbrechende Zeile). Nicht gemessen: „Repository auf GitHub öffnen“
(öffnet den Browser), „Keine Plugins installiert.“, der Satz „Wirkt nur, wenn …“ einer Schema-Bedingung
(gesehen nur der eigene Grund von layout-box) und die Abweisung während des Entfernens.

## Plugins ▸ Navigationen und die Vorschau an der App gemessen

Achter Durchgang, am 2026-11-09, am selben gui-test-Klon in 1200×800, ohne Netz; der Dev-Server lief
lokal auf Port 8080 und ist danach beendet. Für den leeren Zustand, „nicht platziert“ und den
Fassungshinweis wurden Config und `package.json` der Plugins vorübergehend geändert und danach
zurückgestellt (`cmp` gleich). quartz-forms ist im Klon ein Link auf das echte Repo: Dafür stand
während der Messung eine Kopie (`package.json`, `dist`, `types`) an seiner Stelle. Das Repo hat einmal
eine geänderte `package.json` gesehen und ist zurückgestellt (`git status` sauber).

- **Liste:** „2 Navigationen“, „Akkordeon #1 · Akkordeon · Linke Seitenleiste“, „Test #2 · Baum ·
  Rechte Seitenleiste“. Ohne `layout`-Block: „Akkordeon · nicht platziert“, im Inspektor „nicht
  platziert“. Aus: Abzeichen „aus“.
- **„Navigation aktiv“** schreibt `enabled: false`, noch einmal zurück; die Datei ist danach byte-gleich.
- **Optionen:** die Einstellungen der Variante oben („Einstellungen der Variante „Baum““), darunter die
  Gruppen Seitenauswahl, Ausblenden, Reihenfolge, Beschriftung und Symbole, Auf dem Smartphone,
  Technisches mit Anzahl und „· n geändert“. `persistState` aus und an: eine Zeile, danach byte-gleich.
- **„wirkt nicht“:** bei „Test #2“ (Baum) stehen `align`, `trigger`, `chevrons`, `folderClick`,
  `persistState` mit „wirkt nicht“ und dem Satz „Wirkt nur bei den Varianten …“, bei `chevrons` und
  `persistState` mit „Bei „Baum“ nur, wenn auf dem Smartphone „Akkordeon“ gewählt ist.“ Mit `mobile:
  accordion` in der Gruppe „Auf dem Smartphone“ fällt „wirkt nicht“ bei den beiden weg; Zurücksetzen nimmt
  den Schlüssel heraus, die Datei ist byte-gleich.
- **„Auf der Bühne zeigen“:** Layout ▸ Komponenten mit „Zurück zu „Plugins › Navigationen““ und
  „quartz-navigations #2“ (bzw. #1) im Inspektor.
- **Anlegen, Duplizieren, Entfernen:** „Neue Navigation“ ▸ Leiste: „Leiste #3 · Leiste · Kopfbereich“
  (`nav-bar`, Priorität 80); Duplizieren nummeriert den Kopfbereich neu; Entfernen fragt „Navigation
  „Leiste #4“ entfernen?“. Angesagt: „Navigation „Leiste“ angelegt, im Bereich Kopfbereich.“, „„Leiste
  #3“ dupliziert.“, „„Leiste #4“ entfernt.“
- **Nicht installiert** (Config ohne Einträge): „quartz-navigations ist nicht installiert“ mit dem
  Verweis auf den Marktplatz.
- **Andere Fassung:** mit `version` und `quartz.version` auf 0.9.9 sagen alle vier Editor-Reiter „Dieser
  Editor kennt quartz-navigations 0.4.2 (quartz-layout-box 0.4.2, quartz-multilanguage 0.3.0,
  quartz-forms 0.6.0), installiert ist 0.9.9. Angaben können deshalb abweichen.“ Die Fassung kommt wie in
  QuartzControl zuerst aus `quartz.version`.
- **Vorschau:** „Vorschau starten“ zeigt „Der Dev-Server startet…“ und „Vorschau beenden“, dann die
  Website mit „Gerendert mit 1280 px Breite, gezeigt mit 52 %.“ und „Markiert: „Akkordeon #1“.“ Tablet
  901 px (74 %), Mobil 390 px (100 %) mit „„Akkordeon #1“ steht auf dieser Seite, ist in dieser Ansicht
  aber nicht zu sehen (etwa ausgeblendet oder in einer Schublade).“ (angesagt). Seite
  `animation/view-transitions` mit Return lädt sie, die Markierung folgt; „Vorschau neu laden“ holt sie
  noch einmal (zweiter Abruf im Server-Log). Mit Remote-Dev-Host `example.invalid` (Server mit
  `--remoteDevHost example.invalid`): „Der Dev-Server läuft über einen entfernten Host und lässt sich
  hier nicht einbetten. …“, ohne „Vorschau neu laden“. „Vorschau beenden“: Port frei, „… und der läuft
  gerade nicht.“

Vier Befunde, behoben:

- **Eine Gruppe der Optionen klappte nur über ihren Pfeil auf**; ein Klick auf Titel oder Anzahl tat
  nichts. In QuartzControl ist das ganze Band ein Button (`FoldBox`). Nachgemessen: Titel öffnet, Anzahl
  schließt.
- **„Auf der Bühne zeigen“ wählte beim ersten Besuch von Layout nichts**: der Inspektor blieb bei „Wähle
  eine Komponente aus.“ Die Seite schrieb die Auswahl beim Erscheinen, ihr Body las sie aber nie, nur der
  Inspektor-Abschluss in `PageScaffold`; der blieb auf dem alten Wert. Mit einem Protokoll-`onChange`
  verschwand der Fehler, weil der Body den Wert dann las. Jetzt liest ihn der Body und reicht ihn weiter.
  Vorher drei von drei Kaltstarts ohne Auswahl, nachher drei von drei mit; Wählen auf der Bühne
  unverändert.
- **Der leere Zustand „nicht installiert“ war so schmal wie sein Text**; der Reiter-Wähler darüber
  rückte nach links. Jetzt füllt er die Spalte.
- **Der Satz unter der Vorschau verlor seine zweite Zeile** an der Fensterkante (1200×800, Mobil): Für
  die Website waren 240 pt fest. Jetzt bekommt der Satz zuerst Platz, die Website den Rest bis 160 pt.
  Nachgemessen: ganz.

Hell geprüft (Liste, Inspektor mit „wirkt nicht“). Nicht gemessen: der Sprung der Vorschau auf eine Seite
mit dem Eintrag und „Eigene Klasse vergeben“; beide gibt es nur auf Reitern, deren Einträge Seiten kennen
oder keine eigene Klasse haben (Zusätzliche Inhalte, Formulare).

## Plugins ▸ Zusätzliche Inhalte an der App gemessen

Neunter Durchgang, am 2026-11-09, am selben gui-test-Klon in 1200×800, ohne Netz; der Dev-Server lief
lokal auf Port 8080 und ist danach beendet. `quartz/static` und die Config waren gesichert und sind
zurückgestellt (`diff -r` und `cmp` gleich). Für die Fehlerfälle wurde die Config vorübergehend
geändert, für „Konfiguration nicht schreibbar“ der Projektordner des Klons kurz auf 555 gesetzt. Eine
leere Testdatei (`notiz-neu.md` aus dem Klon) liegt im Papierkorb des Macs.

- **Liste:** „7 Boxen“, „Text · Linke Seitenleiste · Nur Desktop“, „Datei
  quartz/static/snippets/sidebar-note.md · …“, „Text · Nach dem Inhalt · Nur Mobil“. Ohne `layout`:
  „Text · nicht platziert“, im Inspektor „nicht platziert“. „Box aktiv“ aus: Abzeichen „aus“ und
  `enabled: false`; zurück, die Datei ist byte-gleich.
- **Wo das Plugin abbricht** (installiert 0.4.2, ein Wert, der kein Text ist): in der Liste „Fehler:
  „html“ ohne Wert · Text · …“, im Inspektor „„html“ hat keinen Wert, und quartz-layout-box bricht daran
  mit einem Fehler ab. …“, für `byLang.en` „Für en hat „html“ keinen Wert …“. Ein `html` mit eigenem
  Text in `byLang.en` einer Datei-Box: „Für en gilt eine eigene Angabe unter „Je Sprache und Seite“ …“,
  und `sidebar-note.en.md` steht danach „von keiner Box benutzt“.
- **Snippet-Feld:** die Dateiwahl schreibt `file: import-note.html`, die Liste zieht mit. „Neu“ legt
  `neu-schnipsel.md` an (0 Byte), wählt sie und öffnet den Editor. „Importieren…“ mit einem Namen, den
  es gibt: „„import-note.html“ gibt es in quartz/static/snippets schon. Ersetzen?“ mit „Vorhandene
  verwenden“, „Ersetzen“, „Abbrechen“; „Vorhandene verwenden“ wählt die Datei. Getippt zeigt der Editor
  „Ungespeichert“; „Schließen“ fragt „Änderungen an „neu-schnipsel.md“ verwerfen?“, „Abbrechen“ behält
  den Text, „Verwerfen“ lässt die Datei bei 0 Byte.
- **„Bild einfügen…“** mit einem Bild, das es gibt: Frage, „Vorhandene verwenden“ setzt `<img
  src="{{root}}/static/images/testbild.png" alt="">` ein und speichert. Eine SVG-Datei: „Die SVG-Datei
  als Code einfügen?“, „Als Code einfügen“ setzt `<svg … class="svg-kreis">` ohne `onload` und
  `<script>` ein, darunter „2 Stellen aus dem SVG-Code entfernt, …“. Das Kopieren eines neuen Bilds lief
  über „Bild hinzufügen“ (derselbe Kern-Aufruf), nicht über das Feld.
- **Dateien:** „Neue Datei“ legt `testnotiz.md` an; mit einem vergebenen Namen kommt dieselbe Frage,
  „Abbrechen“ lässt alles, wie es war. „Datei hinzufügen“ kopiert `import-note.html` byte-gleich,
  angesagt „„import-note.html“ hinzugefügt.“ „Bild hinzufügen“ legt `quartz/static/images` an (vorher
  „Den Ordner gibt es noch nicht; die erste Datei legt ihn an.“), ein zweites Mal kommt die Frage.
  Umbenennen auf einen vergebenen Namen: „„sidebar-note.md“ gibt es in diesem Ordner schon. …“; sonst
  „„testnotiz.md“ heißt jetzt „notiz-neu.md“.“ Ein Bild, das eine Box zeigt, fragt vorher („Benutzt von
  Über diese Website. Diese Verweise stehen im Text, QuartzHub ändert sie nicht. …“), danach steht es
  „von keiner Box benutzt“. Papierkorb: „Benutzt von Über dieses Handbuch. Dort fehlt die Datei danach.“
  bei einer benutzten Datei, ohne den Satz bei einer unbenutzten; angesagt „… liegt im Papierkorb.“
  Mit nicht schreibbarer Config heißt die umbenannte Datei wieder wie vorher: „„import-x.html“ heißt
  wieder „import-note.html“: … (Meldung oben).“ „renameStuck“ (auch das Zurückbenennen scheitert) ist
  nicht ausgelöst.
- **Projektbild:** `icon.png` und `icon-dark.png` mit `{{root}}/static/icon.png`, Schloss und „benutzt von
  mark“, ohne Umbenennen und Papierkorb.
- **Ordner:** `images` als Verknüpfung: „Der Ordner liegt hinter einer Verknüpfung. Lesen funktioniert,
  QuartzHub ändert hier nichts.“, ohne Buttons. Ein `dir: ../aussen`: „QuartzHub liest und schreibt in
  diesem Ordner nicht.“
- **„Auf der Bühne zeigen“** nach einem Kaltstart: Layout ▸ Komponenten mit „quartz-layout-box #2“ im
  Inspektor, der Rückweg führt auf den Reiter mit derselben Box. „Alle Optionen in der Plugin-Liste“:
  Installiert mit „quartz-layout-box #2“, zurück ebenso.
- **Vorschau:** „Über diese Website“ und „Über dieses Handbuch“ teilen `layout-box-note`: „„Über diese
  Website“ teilt seine CSS-Klasse mit anderen Einträgen. Markiert ist jeder davon, auf dieser Seite 2.“
  „Eigene Klasse vergeben“ schreibt `className: layout-box-note layout-box-ueber-diese-website`, angesagt
  „… hat jetzt die Klasse layout-box-ueber-diese-website.“, danach „Markiert: „Über diese Website“.“ Auf
  einer 404-Seite: „„Weiterlesen“ kommt auf dieser Seite nicht vor.“ Der Sprung zu einer Seite mit dem
  Eintrag kommt hier nicht: Nur Formulare gibt der Vorschau die Seiten eines Eintrags mit (`pages:`).

Sieben Befunde, behoben:

- **Der Hinweis nannte eine Gruppe, die es nicht gibt:** „Je Seite und Sprache“; quartz-layout-box nennt
  sie „Je Sprache und Seite“. Und die Bild-Frage nannte „Vorhandenes verwenden“ neben dem Button
  „Vorhandene verwenden“. Beides kam so aus QuartzControl 1.3.
- **Die Bild-Frage unter der Liste nannte den Ordner doppelt:** „„images/testbild.png“ gibt es in
  quartz/static/images schon“ (in QuartzControl ebenso). Jetzt „„testbild.png“ gibt es in …“.
- **Ein Snippet aus dem Feld fehlte unter „Dateien“:** „Neu“ und „Importieren…“ in der Box schreiben die
  Datei und nennen sie, die Liste darunter las aber nur beim eigenen Tun neu. Jetzt gehören die Dateien
  der Boxen zu ihrem Schlüssel; nachgemessen mit `fokus-test.md`, „benutzt von Über dieses Handbuch“.
- **Die Zeile „Neu“ zerfiel im Inspektor:** „Name des neuen Snippets“ stand über drei Zeilen neben dem
  Feld, das Feld zeigte „z. B. hinw“. Der Fokus kam nie im Feld an; was man tippte, ging in die Suche
  der Optionen oder ins Leere (auch unter „Dateien“). Jetzt ist das Etikett nur für VoiceOver, wo die
  Zeile nicht passt, steht der Name über Format und Button, und der Fokus wird einen Takt später
  gesetzt. Nachgemessen an beiden Stellen.
- **`quartz/static/images` als Datei** zeigte „Der Vorgang konnte nicht abgeschlossen werden.
  (QuartzHubCore.NodeFileError-Fehler 1.)“. `NodeFileError` ist jetzt ein `LocalizedError` und liest
  sich wie in QuartzControl: „Error: ENOTDIR: not a directory, scandir '…/quartz/static/images'“. Wie
  dort leert der Fehler die ganze Liste der Dateien.
- **Der leere Zustand „nicht installiert“** war so schmal wie sein Text, wie bei Navigationen.
- **Der Satz neben „Eigene Klasse vergeben“** brach nach einer Zeile ab („Markiert ist jeder…“): Die
  Vorschau bekommt hier bei 1200×800 nur ihre 310 pt, die Website hielt 160 davon. Jetzt gibt sie bis
  120 pt nach. Eine größere Vorschau (360 pt) ließ von der Liste der Boxen eine Zeile; verworfen.
  Nachgemessen: zwei Zeilen, ganz.

Hell geprüft (Liste, Inspektor einer Datei-Box, Dateien). Nebenbei, nicht behoben: Nach „Eigene Klasse
vergeben“ sagt die Vorschau vor dem Neubau kurz „„Über diese Website“ kommt auf dieser Seite nicht vor.“
an. Die Frage vor dem Umbenennen eines benutzten Bilds hat drei Sätze. Die Meldung bei nicht
schreibbarer Config ist Nodes Text („Error: EACCES: permission denied, open '…'“), wie die schon
gesammelten Parser-Meldungen.

## Plugins ▸ Mehrsprachigkeit an der App gemessen

Zehnter Durchgang, am 2026-11-09, am selben gui-test-Klon in 1200×800, ohne Netz. Config und die
`package.json` von quartz-multilanguage (im Klon ein Ordner, kein Link) waren für die Hinweise
vorübergehend geändert und sind zurückgestellt (`cmp` gleich).

- **Kopf und Liste:** „quartz-multilanguage“ mit „Eingeschaltet“ schreibt `enabled: true`, zurück
  byte-gleich. „2 Sprachen“, „Deutsch · de · de-DE“ mit „Standard“, „English · en · en-US“.
- **Standardsprache:** bei English eingeschaltet schreibt `defaultLanguage: en`, angesagt „English ist
  jetzt die Standardsprache.“; das Abzeichen wandert, bei English steht dann „Um das abzugeben, mache
  eine andere Sprache zur Standardsprache.“
- **Veröffentlichen:** Deutsch aus schreibt `publishLanguages: [en]`, Abzeichen „nicht
  veröffentlicht“. Bei English steht „Die einzige veröffentlichte Sprache bleibt aktiv.“; ein Klick auf
  den Schalter ändert nichts (`cmp` gleich).
- **Reihenfolge:** die Bedienungshilfe-Aktion „Nach oben: English“, das Kontextmenü „Nach oben“ und
  Ziehen mit der Maus tauschen die Einträge, je angesagt („English steht jetzt an Stelle 1 von 2.“);
  hin und zurück ist die Datei byte-gleich.
- **Einstellungen:** sechs Bereiche mit ihrer Zeile („Erkennung: Ordner, Suffix, Frontmatter“,
  „Aufklappmenü · Eigenname“, „hreflang an · og:locale an“ …). Ohne Auswahl zeigt der Inspektor den
  Überblick (Sprachen, Standardsprache, Veröffentlicht „alle“, Erkennung).
- **Sprachwechsler:** „Steht im Bereich Kopfbereich.“; ohne `layout` „Steht noch nirgends auf der
  Seite.“ „Auf der Bühne zeigen“ wählt quartz-multilanguage in Layout ▸ Komponenten, der Rückweg führt
  auf denselben Bereich. „Alle Optionen“ wählt den Eintrag unter Installiert.
- **Hinweise:** `defaultLanguage: xx`: „Die Standardsprache „xx“ ist keine der Sprachen. Das Plugin
  nimmt deshalb die erste, Deutsch.“ Zwei Einträge: „Die Konfiguration nennt quartz-multilanguage 2-mal.
  …“ Eine unlesbare `package.json`: „Die Beschreibung der Optionen konnte nicht gelesen werden: …“ und
  „Ohne die Beschreibung des Plugins gibt es keine Gliederung. …“. Ohne `configSchema`, aber mit den
  Typ-Dateien, gibt es nur den Bereich „Weitere Optionen“ und keinen Hinweis; so auch QuartzControl
  (`!schema`).
- **Nicht installiert:** „quartz-multilanguage ist nicht installiert“ mit Verweis auf den Marktplatz.

Ein Befund, behoben: Der leere Zustand war so schmal wie sein Text, wie bei Navigationen und
Zusätzliche Inhalte; der Reiter-Wähler steht jetzt wieder in der Mitte. Hell geprüft (Liste, Inspektor
einer Sprache). Die Vorschau dieses Reiters ist dieselbe wie auf den anderen.

## Plugins ▸ Formulare an der App gemessen

Elfter Durchgang, am 2026-11-09, am selben gui-test-Klon in 1200×800, ohne Netz. quartz-forms ist
im Klon ein Link auf das echte Repo `~/Development/quartz-forms`; für die Messung zeigten Link,
`source` und Lock auf eine Kopie im Scratchpad (Ordnername `quartz-forms`: unter einem anderen Namen
hält der Reiter das Plugin für nicht installiert, die Kennung kommt aus dem Ordner). Danach Config und
Lock aus der Sicherung (`cmp` gleich), der Link wieder auf das Repo, dessen `git status` leer blieb.
Geheimnisse nur mit `-QHMemorySecrets`; Ziele gibt es im Testprofil keine, „Relay hochladen“ war
gesperrt und wurde nicht gedrückt. Unter `content/` wurde nichts geschrieben. Testschlüssel mit gpg
in einem eigenen Wegwerf-Schlüsselbund, danach gelöscht.

- **Kopf und Liste:** „Eingeschaltet“ schreibt `enabled: false` und zurück; „Alle Optionen“ öffnet
  „Installiert“ mit quartz-forms, der Rückweg behält die Auswahl. Abzeichen „Layout“, „anonym“,
  „2 Probleme“; zwei Einträge von Hand: „Die Konfiguration nennt quartz-forms 2-mal. …“.
- **Allgemein und Versand:** Titel, Betreff, Text je Sprache (`title: {de: …, en: …}`),
  „Zu einer Seite wechseln“ mit Vorschlägen und „Keine Seite der Website hat diesen Slug. …“, eigener
  Versandweg endpoint (format wirkt dann), „Neuer Empfänger …“ mit „@example.“-Warnung.
- **Felder:** Skala, Eine Wahl, Einwilligung, Schlüssel des Besuchers (ein zweites gesperrt, die Hilfe
  nennt den Grund). Bedingung auf die Skala; nach max 3 „„5“ (gibt es dort nicht)“, über der Skala
  „„bewertung“ (steht nicht davor)“. Umsortieren über Kontextmenü und Bedienungshilfe-Aktion,
  angesagt „„Eine Wahl“ steht jetzt an Stelle 3 von 3.“ Fassung 0.3.0 (nur die Versionsnummer der
  Kopie): „Breite, Anordnung, Bedingungen und Seitenumbrüche gibt es ab quartz-forms 0.4.0 …“. Ohne
  Felder: „Das Formular hat keine Felder. Ohne Feld bricht der Build ab.“
- **Schlüssel:** aus einer Datei nach `quartz-forms/keys/probe.asc`, ein privater abgewiesen, bevor
  etwas geschrieben ist, dieselbe Datei erneut fragt „… ersetzen?“; „läuft ab am 2027-01-15“,
  „verschlüsselt für: kontakt“; ein kaputter Block „Nicht übernommen: …“; ohne `dist/cli.js`
  „Konnte nicht geprüft werden: …“.
- **Texte:** Suche, Ersatzsprache („Für „fr“ hat quartz-forms keinen eigenen Wortlaut; grau steht der
  aus „en-US“.“, fr nur mit eingeschaltetem quartz-multilanguage), mehrere Einträge (de, de-DE),
  unbekannter Text als Hinweis des Plugins. Die ältere Fassung lässt sich mit der Kopie nicht
  nachstellen: ihr Code liefert die Texte trotz Versionsnummer.
- **Relay:** Unterordner „..“ abgewiesen; Absender und „https://quartzmac.borkel.net eintragen“ in
  `.quartz-gui/forms-relay.json`; Adressen und Captcha-Secret gespeichert, ersetzt, entfernt
  (`relay-secrets.json` nur mit Namen); sendmail, Zähler-Ordner, 0644, `-f`; „Neues Secret erzeugen“
  mit Rückfrage; „Noch nicht bereit: Kein Ziel gewählt. Kein Absender. …“; als Ordner gespeichert
  (send.php, config.php, config.generated.php, counters/), mit Problemen abgewiesen.
- **Vorschau:** „Zeigen“ und der Sprung von der Startseite auf /kontakt; „Neu suchen“.

Zehn Befunde, behoben:

1. Ein Teil im Inspektor klappte nur am Pfeil auf, in QuartzControl über die ganze Kopfzeile. Jetzt
   faltet die Kopfzeile.
2. Farbige Abzeichen blieben auf einer ausgewählten Zeile in ihrer Farbe: „Layout“ grün auf Blau, hell
   kaum zu lesen. `WordBadge` nimmt die Farbe jetzt als `tint` und lässt sie auf einer Auswahl weg
   (alle 13 Aufrufer).
3. Nach Return in „Zielseite“ blieb „Keine passende Seite“ stehen, solange das Feld den Fokus hielt,
   und verdeckte, dass der Build abbricht. Der Satz gilt nur noch beim Tippen.
4. Wählte man ein Formular, wurde der Inspektor 22 pt breiter und die Mitte sprang: „Dank anzeigen |
   Zu einer Seite wechseln“ ist 282 pt breit. Wo die Segmente nicht passen, steht ein Menü
   (Optionsfelder zeigten in der Form nur eine der zwei Möglichkeiten).
5. Die Adresse von send.php stand als „quartz-mac.bor-kel.net“ da, ein Empfänger als „probe-empf“:
   Text trennt nach der Sprache der Oberfläche. `verbatimLineBreaks()` setzt die Satzsprache „zxx“
   (kein sprachlicher Inhalt), dann bricht die Zeile ohne Bindestrich; nebeneinander gerendert
   verglichen. Der Name hat dazu Vorrang vor den Abzeichen.
6. Der Hinweis zum Unterordner blieb, wenn man wieder den gespeicherten Wert eintippte: `CommitField`
   schreibt dann nichts. Es meldet das jetzt (`revert`). QuartzControl hat denselben Fehler
   (`DraftInput` ruft `onCommit` nur bei einer Änderung); nicht kritisch, nur notiert.
7. „Adresse für … gespeichert.“ und „Captcha-Secret gespeichert.“ standen nur da; in QuartzControl
   ist die Zeile eine Statusmeldung und wird vorgelesen. Jetzt beim Speichern angesagt.
8. Der leere Zustand „nicht installiert“ war so schmal wie sein Text, wie auf den anderen Reitern.
9. Das Seitenfeld der Vorschau hatte keinen Namen, nur den Platzhalter; gefüllt las VoiceOver
   „kontakt, Textfeld“. Gilt für alle Reiter mit Vorschau.
10. Nach dem Sprung zu einer Seite mit dem Formular wurde „„Umfrage“ kommt auf dieser Seite nicht
    vor.“ angesagt, dann „Markiert“: quartz-forms baut das Formular erst per Skript, der erste Bericht
    der Seite findet es noch nicht. Der Satz unter der Vorschau wird jetzt erst angesagt, wenn er
    sich 0,8 s gehalten hat. Das war auch der Nebenbefund nach „Eigene Klasse vergeben“.

Kein Befund, aber beim Messen gelernt: Entfernen-Buttons per Bedienungshilfe gedrückt, während eine
Rückfrage offen war, stellten die Rückfragen in eine Warteschlange, und jede spätere Bestätigung galt
einer älteren mit dem alten Feldstand. Mit Maus oder Tastatur geht das nicht, die Rückfrage sperrt das
Fenster.

Offen geblieben (die Zeilen stehen weiter auf `gebaut`): der Grund bei nicht gebauten Seiten unter
„Einbinden“ (bräuchte eine Seite unter `content/`), die ältere Fassung bei den Texten, Ziel und
rsync beim Unterordner und der rsync-Konflikt (kein Ziel im Testprofil), Captcha-Secrets je
Formular, „Noch nicht bereit“ mit Konflikt oder ohne verschlüsselte Ablage.

Nebenbei aufgefallen, nicht behoben: Ein Reiterwechsel liest die Config nicht neu, die Prüfung des
Plugins aber schon; nach einer Änderung von außen zeigten Hinweise und Editor kurz verschiedene
Stände. „Ein eigener Text“ hängt als Satzteil am Hinweis der Texte (so auch QuartzControl). Der
Platzhalter „neue Adresse, ersetzt die gespeicherte“ ist im Inspektor abgeschnitten. Getippte „-----“
werden im Feld „Öffentlicher Schlüssel im Textformat“ zu Geviertstrichen (gehört zu den Ersetzungen in
Texteditoren; eingefügter Text wird nicht ersetzt). Ist der Eintrag des Relays im Schlüsselbund weg,
scheitert jedes Speichern mit „Die gespeicherten Zugangsdaten fehlen …“, und „Neues Secret erzeugen“
hilft nicht; der Satz verweist auf Einstellungen ▸ Zugänge (ob das Relay dort zu heilen ist, nicht
geprüft). „Geändert“ steht
auch an Werten, die der Vorgabe gleichen, aber in der Config stehen (frontmatterKey `form`). Andere
Monospace-Namen und -Pfade der App können ebenso getrennt werden; geprüft ist nur dieser Reiter.

## Updates, Snapshots und Git-Sync an der App gemessen

Zwölfter Durchgang, am 2026-11-09, an den Wegwerf-Projekten aus Phase 4 in 1200×800, ohne Netz
(`-QHNoUpdateCheck`): `upd` (zwei Plugin-Repos über `file://`) für Updates und Snapshots, die Kopie
`sync` mit einem lokalen Bare-Repository als origin (`pre-receive` wartet 8 s) für Git-Sync. Von den 18
Zeilen dieser drei Seiten, die noch `gebaut` hießen, sind 16 gemessen; alles in Dunkel und Hell. Beide Projekte stehen danach wieder wie vorher (Notiz,
Lock-Datei, Snapshot-Speicher, HEAD und Remote-Branch, `content` ein echter Ordner).

- **Updates:** Ohne Update-Notiz sagt der Kern „Nicht prüfbar“ (grau, „Installiert: — · Neueste
  Version: —“), „Update durchführen“ bleibt an wie in QuartzControl. „Erneut prüfen“ liest neu: Aus
  „Nicht abgeschlossen“ wurde nach dem Wegräumen der Notiz „Nicht prüfbar“, nach Leeren von `plugins`
  in der Lock-Datei kam „Keine über den Marktplatz oder per Kommandozeile hinzugefügten Plugins
  gefunden.“ Nicht gemessen: ein zweiter Lauf neben einem laufenden; ohne Netz hält ein Lauf am Fetch
  sofort an.
- **Snapshots:** Ohne Speicher „Snapshots (0)“ und „Noch keine Snapshots. …“, und das Ansehen legt
  keinen an. „Content-Ordner mitsichern“ aus schreibt `includeContent: false`, der Snapshot danach hat
  kein `content/index.md`; an, und der nächste hat es. Ohne Content-Ordner ist der Schalter gesperrt
  und lesbar mit „Es gibt keinen Content-Ordner, den man mitsichern könnte.“ Ein eben angelegter
  Snapshot: „Keine Unterschiede zum heutigen Stand.“ Der Inspektor ohne Auswahl: „2, davon 2 von
  dir“, Neuester, Ältester, „wird mitgesichert“. Entwurf und offener Snapshot überstehen den Weg über
  Updates.
- **Git-Sync:** Letzter Commit mit Autor und Zeit, der Erklärsatz mit „v5“, „vorgemerkt“ nach
  `git add`. 430 neue Dateien: „519 lokale Änderungen“, 500 Zeilen und „… und 19 weitere“ (ein neuer
  Ordner zählt als ein Eintrag, wie `git status` ohne `-uall`). Mit einem GitHub-origin der Link „Auf
  GitHub öffnen“, nicht geklickt. „Aktualisieren“ liest ohne Fetch neu. „Push + Pull“ ohne Commit
  holte einen Remote-Commit von `v5` und pushte den Branch, die lokalen Änderungen blieben. Mit
  `content` als Link auf eine Wegwerf-Kopie und Commit: „Erfolgreich.“, im Remote die Notizen als
  Dateien, danach wieder der Link, die Kopie unverändert (`diff -r`).

Kein Befund an QuartzHub; was auffiel, verhält sich in QuartzControl genauso (gegen dessen Code
gelesen):

- **Wiederherstellen löscht Notizen, die ein älterer Snapshot nicht kannte.** Ein Snapshot von
  „mitsichern“ aus, später wieder an, dann „Alles wiederherstellen“ aus dem alten: Der Vergleich nennt
  `content/index.md` „seitdem neu“, und `read-tree -u --reset` löschte den ganzen Content-Ordner.
  Die Frage sagt „Dateien, die es damals nicht gab, werden dabei gelöscht“, und der Snapshot „Vor
  Wiederherstellung“ holte ihn zurück; dass damit die Notizen gemeint sind, sagt sie nicht.
- **Ein Content-Ordner als Link zählt in Git-Sync jede Notiz als gelöscht**, weil git dem Link nicht
  folgt: vor dem Sync 139 statt 89 Änderungen, danach 229, und „Alle 229 lokalen Änderungen werden in
  einem Commit zusammengefasst“ stimmt nicht.
- „Kein Textunterschied (z. B. eine Binärdatei).“ erscheint bei einer Binärdatei nicht: git schreibt
  „Binary files a/probe.bin and b/probe.bin differ“, und das Sheet zeigt diese Zeile.

Eine Abweichung ohne Entscheidung: Ohne hinzugefügte Plugins fehlt auf Updates „Alle aktualisieren“;
in QuartzControl steht der Button grau da.

## Layout an der App gemessen

Dreizehnter Durchgang, am 2026-11-10, an der Layout-Kopie aus Phase 4 (`layout/proj`, APFS-Kopie
von gui-test mit echtem Content-Ordner) in 1400×860, ohne Netz. Config, Lock, `authored-frames` und
`layout-breakpoints.json` vorher gesichert und danach zurückgelegt (`cmp` und `diff -r` gleich).
Gezogen wurde mit synthetischen Mausereignissen: SwiftUIs `draggable` startet erst mit einer
Ereignisquelle `hidSystemState`, Klickzustand 1, einigen kleinen Anfangsschritten und Verweilen
am Ziel (`drag3.swift` im Scratchpad); ohne das kam kein Zug zustande. Für den Neustart-Hinweis lief
der Dev-Server der Kopie kurz (über die App gestartet und gestoppt).

- **Seite und Übersicht:** Reiter, Seitentyp und Auswahl überstehen den Weg über die Seitenleiste.
  „darkmode“ in der Tabelle öffnet die Bühne mit darkmode im Inspektor, der Frame-Chip „editorial“
  den Frame-Editor mit Rückweg. Ohne `template` für Canvas-Seiten zeigt die Spalte den Frame
  „canvas“ des Plugins und „?“ in den Zellen; Excalidraw liegt unter `.quartz/plugins` und zählt,
  wie in QuartzControl, nicht. Die Tabelle scrollt seitlich bis „404-Seite“.
- **Bühne:** Desktop, Tablet (rechte Leiste unter dem Inhalt), Mobil (einspaltig, „Nur Desktop“
  gestrichelt). Aus dem Vorrat ein Duplikat und ein Einschalten, in den Vorrat ein Ausschalten und
  ein entferntes Duplikat, jedes angesagt. Inspektor: „Nur Mobil“, eine eigene Bedingung, Gruppe
  mit ihren Optionen, Optionen des Plugins, „In den Vorrat legen“ mit dem Satz für ein ganzes Plugin,
  „Einschalten“ (ans Ende, wie QuartzControl), „Duplizieren“ und „Duplikat entfernen“. Flex-Gruppe
  angelegt und eingestellt. Seitentyp: Frame wählen, „Minimal“ nennt die fehlenden Positionen,
  „Anpassung entfernen“, ein toter Ausschluss mit Hinweis. „Leer: hierher ziehen“ in einer
  geleerten Leiste.
- **Frames:** Maße, Ausrichtung, Spur- und Zeilengrößen, „Spurgrößen zurücksetzen“, „Auf Tablet
  kopieren“, benannte Grid-Lines, neue Breakpoint-Breiten (alle fünf Frames neu geschrieben).
  Bereich: Name, Belegung, „Eigener Bereich“, eine überschneidende Spanne abgewiesen, „Sichtbar auf
  Desktop“ aus, „Aus Raster lösen“, aus der Liste auf eine Zelle, ein Bereich mit Spanne 3 auf die
  letzte Spalte gekürzt und angesagt, auf einen belegten Platz abgewiesen und angesagt, löschen mit
  Rückfrage. Nicht gemessen: Frame anlegen, anpassen, duplizieren und löschen; das läuft über
  `quartz plugin add/remove`.

Fünf Befunde, behoben:

1. **Ablagefläche zu klein.** In einer Spalte mit wenigen Chips nahm die leere Fläche darunter nichts
   an; QuartzControl macht die ganze Fläche unter dem Namen zum Ziel (`flex-1`, dort mit Messung).
   Jetzt füllt die Ablage ihren Kasten.
2. **„bei left abgelegt“.** Ein Bereich ohne Gruppe hieß in der Ansage mit dem Namen aus dem Frame;
   QuartzControl sagt die Position („bei Linke Seitenleiste abgelegt.“), nur ein Bereich mit eigener
   Gruppe heißt nach sich.
3. **Flex-Gruppen ohne Beschriftung.** Abstand und Priorität standen als „0.75rem“ und „10“ da; ein
   `TextField` außerhalb eines `Form` zeigt seinen Titel nicht. Jetzt „Abstand“ und „Priorität“ davor.
4. **Rohe Werte für VoiceOver.** Ein Chip las „all“ und „desktop-only“ vor, die Bedingung und „aus“
   gar nicht, und die Gruppe hing so an „Ausgeblendet auf: 404-Seite“, dass „custom-8“ wie ein
   weiterer Seitentyp klang. Jetzt „Nur Desktop“, die Bedingung, „aus“ und „Flex-Gruppe „custom-8““,
   auf der Bühne und in der Zusammenfassung.
5. **Neustart-Hinweis ohne Server.** Nach jedem Speichern eines bestehenden Frames stand „Der
   laufende Dev-Server zeigt die Änderung erst nach einem Neustart.“ in der Symbolleiste, ohne
   Abstand an „Gespeichert“, auch ohne laufenden Server; ein Neustart wurde nicht angeboten. Jetzt
   QuartzControls `DevServerRestartHint` (`App/Components/DevServerRestartHint.swift`): nur mit
   laufendem Server, mit „Dev-Server neu starten“, im Reiter Frames; auch nach den Breakpoints. Die
   frühere Zeile „anders“ ist damit gemessen.

Nebenbei, nicht behoben (QuartzControl verhält sich gleich, gegen dessen Code gelesen):

- „Duplizieren“ im Inspektor und „Auf Tablet kopieren“ werden nicht angesagt.
- Der rote Satz einer abgewiesenen Ablage steht oben über dem Editor, außer Sicht, während man unten
  am Raster arbeitet; angesagt wird er.
- Nach den Breakpoints steht oben noch „Dev-Server neu gestartet“ vom Frame davor, unten schon wieder
  „… erst nach einem Neustart“.

Nur QuartzHub: Ein Feld der Zeilenhöhen, durch das der Fokus nur lief, schreibt einen leeren Eintrag
(`rowSizes: ['4rem', '']`); leer heißt „auto“, es ist also nur Rauschen in der Datei.

## Stile an der App gemessen

Vierzehnter Durchgang, am 2026-11-10, an der Stile-Kopie aus Phase 4 (`styles/proj`, gui-test mit
Fonts-Plugin) in 1400×860, ohne Netz, in Dunkel. Config, Lock, `quartz/styles`, `.quartz-gui` und
das gebaute Stylesheet vorher gesichert und danach zurückgelegt (`cmp`, `diff -r`; `git status`
danach wie davor). Gespeichert wurde nur, was die Config nicht berührt: In dieser Kopie steht die
Font-Quelle auf Google mit lokaler Auslieferung, und jedes Speichern der Config holt dann die
Schriften erneut von Google. Deshalb sind Community-Themes (Katalog und Theme brauchen Netz oder
ein aktives Theme) und die Schriftfelder offen geblieben.

- **Seite:** Ein Entwurf übersteht den Reiterwechsel, das Verlassen fragt, der Inspektor nennt die
  Kaskade („Kein Community-Theme aktiv … 68 Variable(n) überschrieben“). Die gelöschte Zeile
  `@use "./quartzcontrol";` kommt beim Speichern zurück, mit Satz.
- **Basis:** Umschalten auf „Eigene lokale Schriftart“ mit seinem Satz (nicht gespeichert); ohne
  Basis-URL und mit lokaler Auslieferung die rote Warnung; Schriftimport mit „weight 400 aus der
  Datei gelesen“, ohne die Config zu ändern.
- **Variablen:** Filter, Teilen und Zusammenführen der Modi, Zurücksetzen, Entfernen einer eigenen
  Variable mit Rückfrage, der Hinweis auf custom.scss, ohne Build-Output und „Neu einlesen“,
  „nicht auflösbar (eine Variable darin hat hier keinen Wert)“ an einer Probe im gebauten CSS.
- **Eigenes CSS:** Umbenennen, Nach oben/unten, Einbinden einer fremden Datei, Importieren, die
  verwaltete Datei mit Warnung, der veraltete Entwurf (Entwurf in `_quartzcontrol.scss`, dann ein
  Schriftimport) mit „Von Festplatte neu laden“, „Komponente wählen“, das Nachschlagen (Suche,
  `var(--…)`, Wert, ⌥-Klick kopiert), Callout-Grundgerüste, Original-Styles eines Plugins, Kopieren
  aus „Aktuell geltende Farben und Schriften“.

Vier Befunde, behoben:

1. **Absturz bei ⌘Z.** Im Editor getippt, Reiter gewechselt, zurück, ⌘Z: QuartzHub stürzte in
   `-[_NSUndoStack popAndInvoke]` ab (Bericht `QuartzHub-2026-11-10-005913.ips`). Der `NSTextView`
   legte seine Schritte in den Undo-Manager des Fensters, und die überlebten den abgebauten Editor.
   Jetzt hat jeder `CodeEditor` einen eigenen (`undoManager(for:)`), der beim Abbau geleert wird;
   derselbe Ablauf läuft durch, ⌘Z und ⇧⌘Z im Editor wirken weiter. Betrifft jeden Code-Editor der App.
2. **„Seit 1.1“** im Hinweis auf custom.scss: eine Versionsnummer von QuartzControl. Jetzt ohne.
3. **Verschieben ohne Ziel:** Nach oben/unten sagte nur den Dateinamen. Jetzt „„foundation.scss“
   steht jetzt an Stelle 1 von 14 in der Ladereihenfolge.“ (QuartzControl sagt hier nichts.)
4. **Namenlose Farbfelder** bei den Callout-Typen: drei Knöpfe je Zeile ohne Namen. Jetzt
   „[!note] --color: Wert einfügen“.

Nebenbei, nicht behoben:

- Eine Änderung von außen an custom.scss wird beim Speichern eines Entwurfs ohne Hinweis
  überschrieben; der Schutz gilt nur für QuartzHubs eigene Schreiber (in QuartzControl ebenso).
- Einmal zeichnete der Editor von Eigenes CSS nichts, obwohl die Bedienungshilfen den Text lasen;
  in fünf Versuchen danach nicht wieder nachzustellen.
- Die Gruppe „Callout-Typen“ im Inspektor klappt nur am Pfeil auf, nicht an der Beschriftung.
- Der Satz zum Zusammenlegen alter Vorlagen-Stylesheets spricht von „bis 1.0“ und „seit 1.1“; da
  sind Fassungen von QuartzControl gemeint, das sagt er nicht.
- Messwerkzeug: Synthetische Klicks fokussierten Editor und Felder auf dieser Seite nicht immer;
  `AXFocused` über die Bedienungshilfen setzen ging (`focusarea.swift`, `focusfield.swift`).

## Vorlagen an der App gemessen

Fünfzehnter Durchgang, am 2026-11-10, an der Vorlagen-Kopie aus Phase 4 (`tpl/proj`) in 1400×860,
ohne Netz, hell. Angewendet wurde nichts: Ein Paket kann Plugins hinzufügen, und das läuft über
`quartz plugin add`. Gespeichert wurde eine Vorlage nach `tpl/out/messung.qtpl` und danach gelöscht.

- **Erstellen:** Name „Messvorlage“ und Beschreibung landen in `manifest.json`; ohne „Inhalt“ fehlt
  der Baustein; „Alle Texte (1293)“ statt „Nur deine Änderungen (11)“ gibt 30 Sprachen mit 1293
  Einträgen, darüber der Hinweis, dass für 29 Sprachen die Vergleichsbasis fehlt.
- **Anwenden:** Vier Pakete aus `~/Documents/QuartzProjekte` über „Vorlage wählen…“ geladen, nur
  gelesen. Der Plan sagt, welche Plugins eingeschaltet werden, welche Schriftdateien gehen, und bei
  quartz-forms, was das Projekt behält und welches Formular es schon hat.

Kein Befund. Offen bleiben die Zeilen, die ein gebautes Paket oder ein Anwenden bräuchten:
Obergrenzen, verknüpfter Content-Ordner, Pfade außerhalb des Projekts, ungültige Frames und
unbekannte Bausteine, ein Seitenwechsel während des Imports; dazu die Plan-Sätze für ausgeschaltete
Plugins und fehlende CSS-Variablen, die in keinem der vier Pakete vorkamen.

Messwerkzeug: Die Felder für Name und Beschreibung haben ihren Namen über das Titel-Element (wie
Schalter im `Form`), nicht als Beschreibung; `focusfield.swift` nimmt deshalb auch die Kennung.

## Veröffentlichen an der App gemessen

Sechzehnter Durchgang, am 2026-11-10, an der Veröffentlichen-Kopie aus Phase 4 (`pub/proj`) in
1400×860, dunkel, ein Blick hell. Ohne Netz: Die echten Ziele der Kopie (borkel.net, GitHub, Ordner
auf dem Schreibtisch) waren für den Durchgang aus `publish-targets.json` genommen. Im Wegwerf-Profil
standen dazu erfundene Zugänge mit Hosts unter `.invalid` (Passwort, Schlüsseltext, gespeicherter
Host-Key, FTP ohne Passwort, Webhook ohne URL). Gelaufen ist nur das Ordner-Ziel in den Scratchpad.
`quartz-forms` zeigte für den Durchgang auf eine Kopie. Danach war alles zurückgesetzt.

- **Formular:** Bearbeiten und Speichern, Abbrechen mit und ohne Änderung. Der Remote-Pfad lehnt
  leer, „/“ mit Löschen, `..` und für rsync Leerzeichen und `$` mit QuartzControls Sätzen ab.
  Die drei Anbieter haben ihre Hinweise, und ein eigener Branch bleibt beim Anbieterwechsel.
- **rsync:** Gesperrt mit Grund für „kein Zugang“, „Host-Key nicht bestätigt“, „Passwort“ und
  „Schlüsseltext“, frei mit gespeichertem Host-Key. „rsync fehlt“ ist nicht gemessen, weil macOS
  rsync mitbringt.
- **Inspektor:** Die Warnung „kein Passwort“ und der Host-Key-Zustand. „Host-Key vergessen“ fragt
  mit dem Host und entfernt `hostKey` aus dem Profil.
- **Löschen und Webhook:** Ziel löschen fragt, und der Zugang bleibt. Ein Webhook ohne URL zeigt
  „keine URL hinterlegt“. Die Frage vor dem Auslösen ist gesehen und abgebrochen worden.
- **Ordner-Ziel:** Der Zielordner fehlt, oder er hat nur eine `.DS_Store`: Beide Läufe brechen mit
  ihrem Satz ab und legen nichts an. Mit Löschen an verschwinden 14 entfernte Dateien. Mit Löschen
  aus bleibt `404.html`, und der Hinweis steht unter dem Knopf.
- **Seite:** Die Basis-URL-Warnung bei `localhost`. Der Ausgabeordner ist mit Vorschau & Build
  geteilt, in beide Richtungen; „../x“ wird abgelehnt. Ist `origin` nicht auf github.com, sagt die
  GitHub-Pages-Karte das, ohne GitHub zu fragen.

Zwei Befunde, behoben:

- **Escape verwarf ein geändertes Ziel ohne Frage.** Der Knopf „Abbrechen“ fragte, Escape schloss
  das Sheet selbst (zweimal gesehen). Das Sheet hält jetzt still (`interactiveDismissDisabled`),
  solange der Entwurf vom geöffneten abweicht. Dann kommt Escape beim Abbrechen-Knopf an und
  fragt. Unverändert schließt es weiter still.
- **Die Frage vor dem Lauf zählte falsch, wenn Löschen aus ist.** Sie sagte in Rot „1 Datei(en)
  werden auf dem Server gelöscht“, der Lauf löschte nichts. Gezählt wird jetzt nach der Regel des
  Laufs (`deleteRemoved == true`). Danach hieß es „0 … gelöscht“, nicht rot; mit Löschen an wieder
  „1 … gelöscht“ in Rot. QuartzControl zählt genauso falsch (`Publish/index.tsx`), dort nicht
  behoben, weil es kein kritischer Fehler ist.

Nebenbei, nicht behoben:

- Ein Webhook-Zugang ohne URL bekommt „(kein Passwort/Key hinterlegt)“. In QuartzControl ist
  das genauso.
- Ein SFTP-Ziel auf rsync behält `transfer: rsync`, wenn der Host-Key danach vergessen wird. Der
  Inspektor sagt nicht, dass rsync jetzt gesperrt ist.
- Die Frage vor dem Lauf sagt auch bei einem Ordner-Ziel „auf dem Server“.
- Im Inspektor heißt die Zeile mit den Ausschlüssen „Nie veröffentlichen (ein Pfad pro Zeile)“,
  die Werte stehen dort mit Kommas. In QuartzControl ist das genauso.

Noch offen bleiben die Netz-Zeilen (SFTP, rsync, FTP, Host-Key-Dialog, Branch-Push, Webhook
auslösen, GitHub Pages mit Token, nicht löschbare Dateien auf dem Server).

## Dokumente und Export an der App gemessen

Siebzehnter Durchgang, am 2026-11-10, an derselben Kopie (`pub/proj`) mit dem Testbuch. Exportiert
wurde über das Dokument-Ziel in den Scratchpad, ohne Netz. Die echten Ziele waren wieder aus der
Datei genommen. Danach waren Buchdateien, Exportordner und Ziele zurückgesetzt.

- **Seiten:** „Wieder der Navigation folgen“ und „Verwerfen“ in beide Richtungen. Eine Seite, die
  in `order` fehlt, steht unter „Neu in der Navigation“, und der Export hängt sie an.
- **Inspektor:** Deckblatt, Papierformat, Querformat, Rückverweise, Register und „Als Text“ landen
  in der Datei, und der Export folgt ihnen. Getestet wurde mit `bases-beispiele`, weil `animation`
  keine Tags hat; das Register steht im PDF mit Seitenzahlen. 510 Zeichen im Untertitel lehnt
  QuartzHub mit dem Satz aus QuartzControl ab.
- **Wege:** „Zu Veröffentlichen“ hat einen Rückweg. Ohne Build steht „Zu Vorschau & Build“, so
  gemessen mit dem Ausgabeordner „nicht-da“.
- **Export:** Ein Abbruch nach 0,7 s schreibt nichts (gleiche Prüfsumme). Der Bericht nennt alles,
  was die Einstellungen versprechen.

Behoben:

- **Absturz beim Löschen des offenen Buchs.** Der Inspektor band seine Zeilen mit
  `Binding($model.draft)`, das ein Optional erzwungen auspackt. Nach „Buch löschen“ las eine Zeile
  die Bindung noch einmal, und QuartzHub stürzte in `BindingOperations.ForceUnwrapping` ab
  (`QuartzHub-2026-11-10-063329.ips`). Jetzt fällt die Bindung auf den Entwurf zurück, mit dem sie
  gebaut wurde. Danach lief das Löschen des offenen Buchs ohne Absturz. Die Form kam in der App
  nur hier vor.
- **„1 Seiten“ im Bericht.** Die 18 zählenden Sätze haben jetzt eine Einzahl, de und en. Die
  Mehrzahl ist QuartzControls Wortlaut. Ein Test prüft „1 Seite“, die Gegenprobe ohne die
  Katalog-Änderung scheitert.

Entschieden mit dem Nutzer (2026-11-10), eine Abweichung von QuartzControl:

- **Das Deckblatt richtet sich nach dem Papier.** `.cover { height: 230mm }` passte nur in A4 hoch
  (257 mm Satzspiegel). In A5 quer (108 mm) stand das Bild abgeschnitten auf Seite 1, Titel,
  Untertitel und Datum auf Seite 2, mit Fußzeile. Auch A4 quer, A5 hoch und Letter quer liefen über.
  QuartzControl hat dieselbe Zeile (`documentHtml.ts`). Jetzt ist die Höhe der Satzspiegel des
  Papiers minus dieselben 27 mm (`DocumentHTML.coverHeightMM`). A4 hoch bleibt damit QuartzControls
  230 mm, byte-gleich. Die Golden-Tests erwarten QuartzControls Ausgabe mit genau dieser einen
  Ersetzung, ein Test hält die Höhen je Format fest; mit der alten Zeile scheitern 14 Prüfungen.
  An der App: A5 quer, A4 quer, Letter quer und A4 hoch haben das Deckblatt ganz auf Seite 1, ohne
  Fußzeile.

Nebenbei, nicht behoben:

- Nach einem Abbruch steht in Rot „Veröffentlichung fehlgeschlagen.“ In QuartzControl ist das
  genauso.
- Beim Exportieren heißt der Knopf „Speichere…“.
- Ein Kerntest scheiterte einmal in vier Läufen. Welcher es war, ist nicht festgehalten; die
  drei Läufe danach waren grün.

Nicht gemessen: Seiten aufnehmen, die die Navigation nicht zeigt, weil gui-test keine hat. Die
Sprachwahl nicht, weil gui-test nur eine Sprache hat. Ebenso nicht die HTML-Datei, die
Ablehnungen vor dem Export und „Dokumente mit hochladen“.

## Export ohne Netz an der App gemessen

Achtzehnter Durchgang, am 2026-11-10, an derselben Kopie. Es gab nur das Dokument-Ziel und das
Ordner-Ziel im Scratchpad. Zurückgesetzt wurden danach Ziele, Exportordner, Zielordner, Manifest
und der Zeitstempel von `public/index.html`.

- **HTML:** Eine Datei mit 0,2 MB, ohne Skripte und Stylesheets. Das Deckblatt steckt als `data:`
  darin; nach außen zeigen nur die Verweise auf die Website.
- **Ablehnungen:** Ein Zielordner in `public/` und der Projektordner werden schon beim Diff
  abgelehnt, und der Knopf ist dann gesperrt. Beim Projektordner greift zuerst die Prüfung
  „Build-Ordner oder umgekehrt“, vor der eigenen für das Projekt (wie in QuartzControl). Fehlt
  der Ordner darüber oder das Buch, bricht der Lauf mit einem Satz ab. Das Formular nennt ein
  fehlendes Buch.
- **PDF:** Lesezeichen, `/Lang` und „Titel im Fenster“ aus dem App-Export gelesen.
- **Dokumente mit hochladen:** Die Dokumente landen unter `downloads/` im Ordner-Ziel. Ist der
  Build neuer, steht „… ist älter als der Build …“ je Datei. „Kopieren“ legt den Markdown-Link in
  die Zwischenablage.
- **⌘Q während eines Exports:** QuartzHub beendet sich ohne Frage und ohne Absturz und schreibt
  nichts.

Behoben:

- **Ein Klick auf die leere Liste hob die Auswahl auf.** Danach fehlte alles unter der Liste, und
  der Inspektor sagte „Noch kein Ziel … Lege eins an“, obwohl zwei Ziele da waren. In QuartzControl
  ist immer ein Ziel gewählt. Jetzt bleibt die Auswahl, solange ihr Ziel existiert. Gegenprobe
  am alten Bau: derselbe Klick, kein Ziel gewählt.
- **Drei Knöpfe hießen für VoiceOver nur „Kopieren“.** Jetzt heißen sie „Kopieren: Als PDF
  herunterladen“ usw., gelesen über die Bedienungshilfen. QuartzControl hat dort nur „Kopieren“.

Nebenbei, nicht behoben:

- Nach ⌘Q während eines Exports bleibt die Website-Kopie (32 MB) mit ihrem Regel-Ordner im
  Temp-Ordner. Der Start räumt sie erst nach einer Stunde.
- Ein leerer Ordner `.quartz-gui/staging/` bleibt nach einem Lauf mit „Dokumente mit hochladen“.

Nicht gemessen: Ersatzsätze für Formular, Video und Leinwand, weil kein Buch mit solchen Seiten
exportiert wurde. Ebenso nicht „Keine fremden Ressourcen“ mit Netz und epubcheck (VM).

## Frames anlegen und löschen an der App gemessen

Am 2026-11-10 an der Layout-Kopie (`layout/proj`) in 1400×860, mit Freigabe des Nutzers für
`quartz plugin add/remove` (bei einem Frame ein lokaler Ordner, kein Netz). quartz-forms war für
den Lauf auf eine Kopie umgebogen, weil `regeneratePluginIndex` alle Plugins liest. Config, Lock,
`package.json`, `.quartz-gui` und die Liste unter `.quartz/plugins` vorher gesichert und danach
zurückgelegt (`cmp`, `diff -r`, `git status` gleich). In Hell, die Ablehnung zusätzlich in Dunkel.

- **Neuer Frame:** ohne Namen „Bitte einen Frame-Namen vergeben.“, mit einem vergebenen Namen
  „Dieser Name ist bereits vergeben …“; beide schreiben nichts. Mit Namen: Ordner unter
  `authored-frames`, Symlink unter `.quartz/plugins`, Eintrag in Config und Lock in derselben Form
  wie die vorhandenen Frames.
- **Duplizieren:** „Probe Frame-kopie“ als Entwurf, gespeichert wie ein neuer Frame.
- **Als eigenen Frame anpassen:** Entwurf „standard“ mit den Maßen des Projekts (320px · 1fr ·
  320px, 5px, 1500px) und den Breakpoints des Projekts, wie der Satz darüber sagt.
- **Löschen:** fragt mit Namen; danach sind Ordner, Symlink, Config- und Lock-Eintrag weg, Lock und
  `index.ts` byte-gleich mit vorher. Ein Seitentyp, der den Frame benutzte (404, von Hand auf ihn
  gestellt), behält den Namen in der Config. Die Übersicht zeigt ihn als Chip, der nichts öffnet,
  und rechnet die Zellen mit dem Standard-Frame. So macht es auch QuartzControl
  (`frameShape`/`openable` in `LayoutOverview.tsx`).

Ohne Befund. Nebenbei, nicht behoben:

- Einmal hatte ein Duplikat ein Leerzeichen am Ende des Namens („Probe Frame-kopie “); `duplicate`
  hängt keins an. Nachgestellt in drei Versuchen nicht: mit und ohne Fokus im Namensfeld, nach
  Tippen und nach Speichern. Wie QuartzControl trimmt QuartzHub den Namen beim Speichern nicht.
- Die Frage beim Verlassen eines nie gespeicherten Frames sagt „Der Frame bleibt, wie er zuletzt
  gespeichert wurde.“ (QuartzControl ebenso).
- Messwerkzeug: Die Tippsuche in einem geöffneten Picker-Menü traf das Ziel nicht; das Menüelement
  über die Bedienungshilfen drücken ging (`menupick.swift`).

## Stile mit Google Fonts an der App gemessen

Am 2026-11-10 an der Stile-Kopie (`styles/proj`) in 1400×860, mit Freigabe des Nutzers für Google
Fonts, in Dunkel, die Hinweise auch in Hell. quartz-forms war für den Lauf auf eine Kopie umgebogen.
Config, Lock, `quartz/styles`, `quartz/static` und `.quartz-gui` vorher gesichert und danach
zurückgelegt (`cmp`, `diff -r`, `git status` gleich). Tippen in die Schriftfelder kam diesmal an:
erst auf das Feld klicken, dann `keystroke` in einem eigenen Aufruf.

- **Schriftfelder:** „lora“ schlägt Lora, Explora, Grandiflora One mit Kategorie vor und sagt
  „Google unterscheidet Groß- und Kleinschreibung. Gemeint ist vermutlich „Lora“.“; „Quatschfont
  Sans“ sagt „Diesen Namen führt Google nicht (Liste vom 2026-11-05) …“. Bei lokaler Quelle kommen
  die Familien des Projekts mit ihrer Datei. Ein eigener Wert für `--headerFont` auf Variablen graut
  das Feld aus, mit „Die Variable --headerFont im Projekt überschreibt diese Schrift …“ und einem
  Sprung zurück.
- **Speichern holt bei Google:** Quatschfont Sans: „Google kennt diese Schrift nicht und hat sie
  stillschweigend weggelassen …“, keine Datei; Lora: sieben Dateien, kein eigener Satz (wie in
  QuartzControl); zurück auf Noto Sans: „Nicht mehr gewählt und aus dem Projekt entfernt: Lora
  (7 Dateien).“ Der verwaltete Block kommt jedes Mal neu von Google, mit Googles heutigen
  `unicode-range`-Werten.
- **Auslieferung:** Schalter an setzt beim Fonts-Plugin `fontOrigin: selfHosted`. Aus: der Kern auf
  `googleFonts`/`cdnCaching: true`, „Die lokalen Kopien der Google-Schriften sind entfernt
  (20 Dateien) …“; die drei eigenen `noto-sans-*.woff2` bleiben. Wieder an holt dieselben 20
  Dateien. Mit `fontOrigin: googleFonts` von Hand erscheint „Jetzt ins Projekt holen“ mit Warnung;
  der Knopf schreibt `local`, die Warnung geht.
- **Font-Quelle:** „Eigene lokale Schriftart“ gespeichert nimmt die 20 Google-Dateien weg, die Config
  bleibt gleich (wie in QuartzControl unterscheidet nur der verwaltete Block die beiden Quellen).
  Zurück auf Google holt sie wieder.

Der Schalter „lokal ausliefern“ hat keinen eigenen Titel, sein Label hängt über `AXTitleUIElement`
an ihm; VoiceOver liest es. Ohne Befund. Nebenbei, nicht behoben:

- Beim Wechsel auf „Eigene lokale Schriftart“ sagt die Meldung „… die Website lädt sie jetzt von
  Google“, obwohl dann nichts mehr von Google kommt (QuartzControl ebenso, derselbe Schlüssel
  `styles.googleFontsDropped` für beide Wege).
- Kein Hinweis zur Schreibweise bei „noto sans“: Das Projekt deklariert Noto Sans selbst, und dazu
  zählt auch der verwaltete Google-Block. Absicht in QuartzControl (dreiunddreißigstes Review), hier
  gleich; ein falsch geschriebener Name einer schon geholten Familie bleibt so ohne Satz.
- Nicht gemessen: „Theme-Schriften“ und „vom Theme“ (brauchen ein Theme, also `npm install`),
  „n ungenutzte Schriftdateien“ ohne entfernte Familie, „Die Datei nennt kein ‚weight‘“.

## Themes mit npm an der App gemessen

Am 2026-11-10 an der Stile-Kopie (`styles/proj`) in 1400×860, Dunkel, mit Freigabe des Nutzers für
`npm install`. `package.json`, `package-lock.json`, `node_modules` (APFS-Klon), Config, Lock,
`quartz/` und `.quartz-gui` sowie das Testprofil vorher gesichert und danach zurückgelegt (`diff -r`
leer, `git status` gleich). Ob npm lief, zeigt sein Log unter `~/.npm/_logs` (`argv`, `exit 0`).

- **Wieder aktivieren:** minimal stand mit `enabled: false`; der Knopf und ⌘S ändern nur `enabled`.
- **Theme-Schriften (Basis):** an nimmt `themeFonts: false` heraus, und die Zeile „Community-Theme:
  lädt seine Schriften von unpkg.com.“ erscheint; aus schreibt es an dieselbe Stelle zurück. „Wird
  vom aktiven Theme überschrieben“ stand mit minimal an allen drei Schriftfeldern.
- **Installieren & aktivieren:** nord aus dem Katalog (Suche „nord“: nord, obsidian-nord), npm
  `install @quartz-themes/core @quartz-themes/nord` in rund 3 s. `package.json` bekommt nord, und
  npm hebt dabei core von `^2.0.0` auf `^2.0.1` (npm, nicht QuartzHub; QuartzControl ruft dasselbe).
  Gespeichert ist `theme: nord`, `mode` und `themeFonts` bleiben wie bei QuartzControls
  `{...base.options, theme}`. nord hat keine Style Settings: „Das Theme nord bietet keine eigenen
  Farbeinstellungen an.“, ohne Sprung, wie QuartzControl (Theme.tsx:260); „Zu den Variablen →“
  steht in beiden Apps unter den Style Settings und springt zum Reiter Variablen.
- **Preset anwenden:** bei aktivem nord „Basis — dunkel“: npm `install @quartz-themes/core
  @quartz-themes/minimal`, danach die Optionen des Presets (`theme: minimal`, `mode: dark`,
  `fonts`). Ist das Theme des Presets aktiv, steht „Aktiv“ statt „Anwenden“; das vergleicht in
  beiden Apps `options.theme`, also stehen beide minimal-Presets auf „Aktiv“.
- **Style Settings von ultra-lobster** (installiert über den Katalog): „139 Optionen“; die Suche
  „gap“ lässt „Column gap“ in seiner Gruppe; ein gesetzter Wert zeigt „Zurücksetzen“, das ihn
  wieder nimmt. „Doku neu laden“ schreibt `theme-docs/ultra-lobster.json` im Profil neu: dieselben
  139 Felder, nur `repo` ist upstream umgezogen (`7368697661/…` → `ble-ss/Ultra-Lobster`).

**Befund, behoben (c45b5e8):** Ein Zahlenfeld der Style Settings verlor nach jeder Taste den
Fokus (Bedienungshilfen: nach „2“ hatte das Fenster den Fokus, die „4“ ging verloren), und eine
aufgeklappte Gruppe klappte bei jeder Änderung darin wieder zu. Ursache: `StyleSettingsValues.Group`
nahm `ObjectIdentifier(self)` als Kennung, und `groups()` baut bei jedem Zeichnen neue Objekte;
SwiftUI baute damit jede Zeile neu. QuartzControl schlüsselt die Gruppen nach Position
(`key={i}`). Jetzt ist die Kennung der Platz im Baum („/0/2“); die Suche behält alle Überschriften,
also bleibt er gleich. Nachher gemessen: „Canvas“ bleibt beim Umschalten darin offen, das Feld
behält den Fokus über drei Tasten. Test `aGroupKeepsItsIdAcrossRendersAndSearches`, Gegenprobe mit
`UUID()` als Kennung lässt ihn scheitern.

Nebenbei, nicht behoben:

- Return in einem leeren Zahlenfeld schreibt `styleSettings: {}` in die Config, ohne dass sich ein
  Wert ändert: SwiftUIs Feld meldet den leeren Text, und `apply` legt das Objekt an. QuartzControl
  schreibt dasselbe `{}`, aber nur bei einer echten Eingabe. Quartz liest `{}` wie kein Eintrag.
- Der Inspektor zeigt nach „Preset anwenden“ weiter das zuvor installierte Katalog-Theme (nord) mit
  „Installieren & aktivieren“ und der alten Erfolgsmeldung, obwohl nord nicht mehr aktiv ist.
- `ServerScanTests.aPortNobodyHoldsIsClosedAndAPortSomeoneHoldsIsOpen` scheiterte einmal im vollen
  Lauf (der Port war nach dem Belegen nicht offen); allein läuft die Suite grün.
- Nicht gemessen: „Katalog nicht ladbar“ (braucht einen gescheiterten `npm search`).

## Veröffentlichen gegen debian-vm gemessen

Am 2026-11-10 an der Publish-Kopie (`pub/proj`, 465 Dateien in `public/`), Dunkel, mit Freigabe des
Nutzers für SFTP, rsync und FTP gegen debian-vm. Vorher `.quartz-gui`, Testprofil und Config
gesichert, die Ziele auf Testbuch und Scratch-Ordner gefiltert, quartz-forms auf die Kopie
umgebogen; danach alles zurück (`diff -r` leer, `git status` gleich), auf der VM die Testordner
gelöscht. Einen eigenen Testschlüssel bei `qchost` einzutragen hat die Rechteprüfung abgelehnt;
SFTP und rsync liefen deshalb als `boxi` mit dessen Schlüsseldatei (die App bekommt nur den Pfad),
FTP als `qchost` mit dem Testpasswort, Geheimnisse nur im Speicher (`-QHMemorySecrets`).

- **macOS fragt nach dem lokalen Netz.** Der erste Lauf scheiterte sofort mit `ssh: connect to host
  debian.local port 22: No route to host`, dazu die Systemfrage „Darf „QuartzHub“ nach Geräten in
  lokalen Netzwerken suchen?“. Erst nach „Erlauben“ (durch den Nutzer) erreichen die Kindprozesse
  der App die VM; das Terminal hatte die Freigabe schon. `project.yml` setzt keinen
  `NSLocalNetworkUsageDescription`, der Dialog zeigt also nur den Systemsatz.
- **SFTP:** Ziel und Zugang im Formular angelegt; der erste Kontakt fragt „debian.local ist zum
  ersten Mal kontaktiert worden.“ mit dem Fingerprint, der `ssh-keyscan` entspricht. „Verbinden und
  merken“ legt `hostKey` (fingerprint, blob) am Zugang ab, der Inspektor zeigt „Host-Key bestätigt“
  mit „Host-Key vergessen“. 465 Dateien, alle sha-256-gleich, 644 und Ordner 775 (umask der VM).
  `~/.ssh/id_ed25519` wird wie in QuartzControl zum absoluten Pfad.
- **rsync:** erst wählbar, wenn der Zugang eine Schlüsseldatei hat (mit Passwort: „rsync ist mit
  Passwort-Anmeldung nicht möglich …“). 465 Dateien, gleich, Ordner 755. Nach Änderungen von Hand
  sagt der Diff vom Server „Geändert: 1 · Entfernt: 3“; der Lauf löscht die fremden Dateien, auch
  aus einem Ordner von boxi mit 555 (rsync gibt sich selbst Schreibrecht).
- **FTP:** als qchost mit relativem Pfad `qhp5-ftp`, der ab dem Anmeldeverzeichnis zählt: 465
  Dateien, gleich, 644/755. Ohne FTPS steht die Warnung zum Klartext am Zugang. Mit FTPS gegen
  vsftpd ohne TLS: `FTPError: 530 Please login with USER and PASS.`, roh wie bei QuartzControl
  (`${output}\n${String(err)}`, auch mit derselben leeren ersten Zeile). Ein FTPS-Lauf mit TLS ist
  nicht gemessen.
- **Nicht löschbare Datei** (Ordner von root im Ziel, bei SFTP und FTP dazu ein Eintrag im
  Manifest): SFTP „gesperrt/alt.html konnte auf dem Server nicht gelöscht werden (delete:
  Permission denied …). Der nächste Upload versucht es wieder.“, FTP ebenso mit „550 Delete
  operation failed“; der Eintrag bleibt im Manifest, der Lauf zählt als erfolgreich.

**Befund, behoben (06be3b7):** Bei rsync stand über `delete_file: unlink(gesperrt/alt.html)
failed: Permission denied (13)` der Satz „Der Server hat die Anmeldung als boxi@debian.local
abgelehnt … Prüfe, ob genau dieser Schlüssel …“, obwohl die Anmeldung geklappt hatte.
`SSHFailure` nahm jedes „Permission denied (“ für ssh's abgelehnte Anmeldung; QuartzControl prüft
„(publickey“, was einen Server nur mit Passwort verfehlt. Jetzt muss die Klammer Namen von
Anmeldeverfahren enthalten. Test `aRefusedDeletionIsNotARefusedLogin` mit der Ausgabe von der VM,
Gegenprobe mit der alten Regel scheitert; an der App nachgemessen: nur noch rsyncs eigene Zeilen.

Nebenbei, nicht behoben:

- `NSLocalNetworkUsageDescription` fehlt (siehe oben); solange die Frage offen oder abgelehnt ist,
  sieht man nur die rohe ssh-Meldung. Behoben im nächsten Abschnitt.
- Nach dem Ändern eines Zugangs in den Einstellungen zeigt der Inspektor auf Veröffentlichen bis
  zum nächsten Lauf den alten Stand („(kein Passwort/Key hinterlegt)“). QuartzControl liest die
  Zugänge beim Betreten der Seite; dort sind die Einstellungen eine Route, hier ein eigenes Fenster.
- „von 2 Projekten verwendet“ an einem Zugang, den zwei Ziele desselben Projekts nutzen: gezählt
  werden Ziele. QuartzControl zählt genauso (`usage.length`) mit demselben Text.
- Ohne gewähltes Ziel sagt der Inspektor „Noch kein Ziel … Lege eins an“, obwohl es Ziele gibt.
- Eine Return-Taste bei geschlossenem Menü speichert das Zugangsformular (Standardtaste), so
  entstand der Zugang zuerst mit Passwort-Anmeldung; das ist macOS-Verhalten, kein Fehler.
- Ein Lauf ging versehentlich an das Ziel „Scratch-Ordner“ (die Auswahl war nach dem Neustart eine
  andere); `pub/out/site` im Scratchpad hat seitdem diesen Stand, das Manifest ist zurückgesetzt.

## Freigabe „Lokales Netzwerk“

macOS fragt, bevor QuartzHub einen Rechner im eigenen Netz erreicht; ssh und Node, die QuartzHub
startet, zählen dazu. Ohne `NSLocalNetworkUsageDescription` stand unter der Frage kein Grund, und
solange sie offen oder abgelehnt war, kam bei jedem Lauf nur die rohe Meldung an.

- **Der Grund** steht jetzt in `project.yml` (Deutsch) und in `App/InfoPlist.xcstrings` (Englisch).
  Das ist die eine Ausnahme vom einen Katalog: macOS liest Texte der `Info.plist` aus
  `<sprache>.lproj/InfoPlist.strings` im Bundle, nicht über `L10n`. Im gebauten Bundle geprüft
  (beide `lproj`, Wert in der `Info.plist`). Den Dialog selbst zeigt macOS nicht noch einmal: Die
  Freigabe vom ersten Lauf galt auch für den Neubau (ad hoc signiert); gesehen ist der Text also
  nicht.
- **Der Hinweis** „debian.local ist nicht erreichbar. Liegt der Server in deinem Netzwerk, erlaube
  QuartzHub den Zugriff in den Systemeinstellungen unter Datenschutz & Sicherheit ▸ Lokales
  Netzwerk.“ steht über der rohen Meldung. Gemessen mit ausgeschalteter Freigabe gegen debian-vm:
  - SFTP (ssh): `ssh: connect to host debian.local port 22: No route to host`.
  - FTP (Node): `AggregateError:  (control socket)`, ohne jede Adresse oder Ursache: debian.local
    hat mehrere Adressen, Node probiert alle und wirft einen AggregateError mit leerer Meldung und
    dem Code des ersten Versuchs. Der Helfer `ftp-session` gab nur bei FTP-Antworten einen Code
    weiter, der erste Einbau (über den Text, `EHOSTUNREACH`) griff deshalb an der App nicht. Jetzt
    trägt die Antwort `nodeCode`, und der Satz hängt an `EHOSTUNREACH`. Test
    `aRefusedConnectionCarriesNodesCode` (localhost hat ebenfalls zwei Adressen, ein geschlossener
    Port ergibt dieselbe Form mit `ECONNREFUSED`); Gegenprobe ohne `nodeCode` scheitert.
  - rsync läuft über dasselbe ssh und dieselbe Übersetzung (`SSHFailure`), nicht eigens gemessen.
- **Abgrenzung:** Ein Rechner im selben Netz, der aus ist, meldet bei ssh `Host is down`, nicht
  `No route to host` (ssh auf eine freie Adresse im Subnetz der VM); er behält seine rohe Meldung.
  Ein Text ohne Freigabe-Bezug wäre für den häufigeren Fall der falsche Rat gewesen.

Nebenbei: Der Relay-Test (`RelayProbe`) übersetzt `EHOSTUNREACH` in Chromiums
`net::ERR_ADDRESS_UNREACHABLE` wie QuartzControl und sagt nichts zur Freigabe; nicht geändert.


## Vorlagen: Grenzfälle an der App gemessen

Nachtrag zu „Vorlagen an der App gemessen“, am 2026-11-10, an derselben Kopie (`tpl/proj`), ohne
Netz, hell. Die Fälle, die kein vorhandenes Paket enthielt, kamen aus gebauten Paketen im
Scratchpad (`tpl/grenz/`), geladen über „Vorlage wählen…“:

- **`grenzfaelle.qtpl`**: ein Frame mit zwei Bereichen „header“, ein Plugin-Eintrag
  `created-modified-date` mit `enabled: false`, ein Stylesheet mit `var(--tpl-fehlt)`, je ein Pfad
  mit `..` in Inhalt, Eigenem CSS und Statischen Dateien, dazu ein Baustein `zukunft`. Der Plan
  nennt jeden Fall mit QuartzControls Satz: „1 Frame nicht lesbar“ mit Grund, „Schaltet
  „created-modified-date“ aus.“, die fehlende Variable, dreimal „Wird abgelehnt: … würde außerhalb
  des Projekts geschrieben werden.“ und die unbekannten Bausteine. Ohne `source.projectName` steht
  „aus dem Projekt „unbekannt““, wie dort (`templates.unknownProject`).
- **Ordner im alten Format** (`manifest.json` mit `categories`, `colors.json`): Abzeichen „Altes
  Format“, Farben als „1 wird ersetzt“.
- **Verknüpfter Content-Ordner:** `content` der Kopie kurz als Symlink; „Inhalt, ändert nichts“ mit
  „Wird übersprungen: Der Content-Ordner dieses Projekts ist ein Link …“. Danach zurückgestellt.
- **Seitenwechsel im Import:** Ein reiner Farb-Import ist in unter einer Sekunde fertig, ein Inhalt
  mit 4000 Dateien in rund 1,4 s; beides zu kurz. Mit 400 MB Zufallsbytes in der Kopie braucht der
  Snapshot davor rund 10 s. 0,57 s nach „Anwenden“ zu Stile und zurück: „Wird angewendet…“ und
  „Snapshot wird angelegt…“, danach „Fertig: alles übernommen, nichts blieb offen.“ Die Config war
  8,6 s nach der Rückkehr geschrieben, der Lauf also wirklich noch offen.
- **Obergrenzen:** Mit 27 MB unter `quartz/static` fehlt „Statische Dateien“ in „Vorlage
  erstellen“, mit 106 MB im Content „Inhalt“; beide Male „11 von 11 Bausteinen“ und kein Satz.
  QuartzControl tut dasselbe: `inspectProject` fängt den Fehler von `collect` ab und lässt den
  Baustein weg. Gleichstand, aber der Satz „eine Vorlage ist keine Mediathek“ erscheint so in
  keiner der beiden Apps (Nebenbefund, nicht geändert).

Kein Befund. Aufgeräumt: Config und Ziele md5-gleich mit der Sicherung, die großen Dateien und
`content/importlauf/` gelöscht, die drei Snapshots des Durchgangs entfernt.

## Stile: Grenzfälle an der App gemessen

Nachtrag zu „Stile an der App gemessen“, am 2026-11-10, an derselben Kopie (`styles/proj`), ohne
Netz, in Dunkel. `quartz/styles`, `.quartz-gui` und die Config vorher gesichert und danach
zurückgelegt (`diff -r`, `cmp`); gespeichert wurde nichts, was die Config berührt (sie holt in dieser
Kopie bei jedem Speichern die Google-Schriften neu).

- **Verschachtelter Import-Block:** In custom.scss ein `Quartz-GUI`-Importblock innerhalb eines
  `QuartzControl`-Blocks, beide mit `@use "./custom/callouts-2"`. Die Prüfung meldet `There's already
  a module with namespace "callouts-2".` mit QuartzControls Satz und „Ladereihenfolge neu
  schreiben“; der Link macht custom.scss wieder byte-gleich mit dem Stand davor, danach „SCSS
  kompiliert fehlerfrei.“ In der ersten Messung hieß das „nicht nachstellbar“; es braucht kein
  Projekt von 1.0, nur den Block.
- **Zusammenlegen:** Die 30 Stylesheets des Stands vor 1.1 kamen aus QuartzControls
  `minimal-lesbar.qtpl` im Commit 57b0f843, als Paket nur mit „Eigenes CSS“ über Vorlagen
  eingespielt (der Plan sagte vorher „10 Stylesheets aus der Aufteilung von 1.1 lädt das Projekt
  danach nicht mehr …“). Danach der Hinweis mit „Zusammenlegen“, die Frage, ein Snapshot
  `styleMigration`, 13 Dateien in der Ladereihenfolge, und die liegengebliebenen Dateien der 1.1-Form
  weichen als `-2` aus, mit je einem Satz. Das mit dem Sass des Projekts übersetzte CSS hat vorher und
  nachher dieselben Zeilen (sortiert gleich), nur in anderer Reihenfolge: QuartzControl legt als reine
  Verkettung nach Bereichen zusammen und hat dort am gerenderten Ergebnis „kein Wert anders“ gemessen
  (`styles-and-fonts.md`, „Bestehende Projekte zusammenlegen“); der Kern ist gegen dessen Funktion
  über `style-files-golden.mjs` geprüft.
- **Nicht schreibbarer Wert:** `3px; color: red` als eigener Wert von `--tpl-accent-bar`, Speichern:
  „Nichts wurde gespeichert: …“, Stylesheet und Config md5-gleich.
- **Ladefehler:** custom.scss mit `chmod 000`: „Die Stile konnten nicht geladen werden.“, darunter
  `Error: EACCES: permission denied, open '…'`.
- **Schrift ohne Gewicht:** eine Systemschrift mit `usWeightClass` 0 (außerhalb 1…1000, so liest
  der Kern kein Gewicht) importiert, „Direkt verwenden für“ leer: der Satz „Die Datei nennt kein
  „weight“ …“, die Regel ohne `font-weight`, die Config unverändert.
- **Suche über 150:** 160 eigene Variablen `--grenz-NNN` im `css-vars`-Block, Suche „grenz“: 150
  Zeilen und „10 weitere Treffer. Weiter tippen zum Eingrenzen.“
- **Anspringen ohne Auswahl:** `--tpl-accent-bar` unter „Von dir geändert“: Suche, Auswahl und
  Inspektor folgen.

Kein Befund. Offen bleiben „Extern öffnen“ (öffnet CotEditor, in dem gerade eigene Dokumente
offen waren), „nur in einem Selektor“ (eine solche Variable steht nicht in der Liste), der
Theme-Katalog ohne Netz und die Meldung „n ungenutzte Schriftdateien“ (braucht ein Speichern mit
Google-Schriften).

Messwerkzeug: Tastenanschläge ohne Fokus im Suchfeld gingen an die Tippsuche der Seitenleiste
(„grenz“ sprang auf Git-Sync); vor dem Tippen `focused.swift` fragen.

## Dokumente: Navigation und Sprache an der App gemessen

Nachtrag zu „Dokumente und Export an der App gemessen“, am 2026-11-10, an APFS-Klonen von
navigations-testprojekt und Example im Scratchpad. Die Symlinks unter `.quartz/plugins` (Frames und
`quartz-navigations`) zeigten in den Klonen auf die Originale und wurden vorher auf Kopien
umgebogen; Example hatte ein GitHub-Pages-Ziel, das aus der Kopie genommen wurde. Example-`content`
ist ein Link in den Vault; geschrieben wurde dort nichts.

- **Seiten ohne Navigation:** navigations-testprojekt nimmt seine Reihenfolge aus
  quartz-navigations. Ein neues Buch zeigt unter „Diese Seiten zeigt die Website nicht in ihrer
  Navigation. …“ die Seiten aus `ausgeblendeter-ordner/`, `optionen/` und andere; nach „Eigene
  Reihenfolge“ hat jede „Aufnehmen: <Titel>“. „Versteckt per navHide“ aufgenommen und gespeichert:
  der 43. Eintrag in `order`.
- **Sprache:** Example (de/en) zeigt „Hauptsprache der Website (Deutsch)“, „Deutsch“ und
  „English“. Mit „English“ sind alle 137 Einträge Seiten unter `en/`; gespeichert `"language":
  "en"`. Exportiert wurde nicht (siehe unten).

Kein Befund.

**Nicht ohne Netz, wie vorher angenommen:** Ein Export der pub-Kopie mit einem Buch an der Wurzel
lief durch alle 137 Seiten und wurde nach 29 abgebrochen („Der Export wurde abgebrochen. Es wurde
nichts geschrieben.“, die Dateien danach gleich; der Abbruch griff erst nach rund 10 s). Dabei fiel
auf: Das Exportfenster lässt nach QuartzControls Regel fremde Stylesheets, Schriften, Bilder und
Mermaid-Skripte durch, und jede gebaute Seite von gui-test bindet `katex.min.css` von jsdelivr ein,
die Seiten mit Diagrammen Mermaid von cdnjs. Dieser Export hat also wahrscheinlich bei jsdelivr und
cdnjs geladen, und die Export-Durchgänge vorher an dieser Kopie, die oben „ohne Netz“ heißen, haben
mindestens das KaTeX-Stylesheet geholt. Nur Abrufe, hochgeladen wurde nichts. Wer künftig ohne Netz
exportieren will, braucht einen Build ohne diese Verweise (wie `cdn-build.mjs` für die Kerntests).
Deshalb offen: die Ersatzsätze für Formular, Video und Leinwand und das Zählen fremder Anfragen an
der App (im Kern gemessen, P3 9b), ePub mit epubcheck (VM).

## Einstellungen ▸ Laufzeit: git an der App gemessen

Am 2026-11-10, an der styles-Kopie mit Wegwerf-Profil. Auf diesem Rechner liegt nur `/usr/bin/git`
(Xcode). Ohne Eingriff steht dort „git 2.54.0 von diesem Rechner. QuartzHub bringt zwar eines mit,
benutzt es aber nur, wenn keines installiert ist. …“. Für den anderen Fall wurde die App mit
`open --env DEVELOPER_DIR=/nonexistent` gestartet: Xcodes git antwortet dann mit „missing
DEVELOPER_DIR path“, `xcode-select -p` aber nicht mit einem Fehler, also gilt es nicht als
Platzhalter, und `GitRuntime.resolve` fällt auf das mitgelieferte zurück. Dann steht dort
„git 2.53.0 aus QuartzHub. Auf diesem Rechner ist keines installiert, deshalb wird das
mitgelieferte benutzt.“, darunter „git steht unter der GPL v2; der vollständige Lizenztext liegt
in QuartzHub.“ und der Link „Quelltext ansehen“ auf `https://github.com/git/git/tree/v2.53.0`
(über die Bedienungshilfen gelesen, nicht geklickt). In Hell und Dunkel gesehen; Hell über die
eigene Einstellung im Wegwerf-Profil, danach zurückgestellt. Der Lizenztext liegt im Release-Paket
(`Contents/Resources/licenses/git-LICENSE.txt`, `package.sh`), nicht im Debug-Bau.

Kein Befund. Das Werkzeug-Band mit fehlendem oder kaputtem git bleibt offen: Dafür müsste auch das
mitgelieferte fehlen.

## Plugins ▸ Installiert: leere Liste und Schema-Bedingungen

Am 2026-11-10. **Leere Liste:** ein Mini-Projekt im Scratchpad (die `configuration` von gui-test,
`plugins: []`, eine Notiz) zeigt „Keine Plugins installiert.“, „0 von 0 aktiv“ und im Inspektor
„Aktiv 0 von 0“, darunter weiter die Wartung. In Hell (eigene Einstellung im Wegwerf-Profil) und
Dunkel gesehen.

**Schema-Bedingungen:** an der styles-Kopie (gui-test). quartz-multilanguage hat zwei Optionen mit
`x-quartz-when`. `switcher.separator` (`"style": "links"`) steht bei der Vorgabe mit „wirkt
nicht“ und „Wirkt nur, wenn „style“ auf Links steht.“ Das Feld `style` hat keinen Titel und heißt
deshalb mit seinem Schlüssel; der Wert kommt aus dem deutschen Enum-Text. `seo.xDefault`
(`"hreflang": true`) hat bei eingeschaltetem `hreflang` keinen Satz; nach dem Ausschalten steht
dort „Wirkt nur, wenn „hreflang“ eingeschaltet ist.“, in der Config `hreflang: false`. Das
Wiedereinschalten machte die Config byte-gleich mit der Sicherung; den einen Snapshot, den der
Schalter anlegte, habe ich danach entfernt.

Kein Befund. „Während ein Plugin entfernt wird …“ bleibt offen (die Felder sind dabei grau, die
Abweisung ist auf dieser Seite nicht auslösbar).

## Snapshots: leerer Unterschied an der App gemessen

Am 2026-11-10, am Mini-Projekt aus „Plugins ▸ Installiert: leere Liste …“. Der Satz „Kein
Textunterschied (z. B. eine Binärdatei).“ kommt nur, wenn `git diff --cached <snapshot> -- <pfad>`
nichts ausgibt; eine Binärdatei gibt „Binary files … differ“ aus (gemessen am 2026-11-09). Die
leere Ausgabe ist so nachgestellt: einen Snapshot angelegt, `content/notiz.md` geändert, den
Snapshot gewählt („1 Datei unterscheidet sich“, „content/notiz.md, geändert“), die Datei auf
der Platte zurückgesetzt und dann „Unterschied in content/notiz.md anzeigen“ gedrückt. Das Sheet
zeigt den Pfad, den Satz und „Schließen“, in Hell und Dunkel. Die Liste sagt dabei weiter
„geändert“: Sie ist der Vergleich vom Zeitpunkt der Auswahl, das Sheet fragt git neu.

Kein Befund.

## Fenster „Projekte“: Entfernen mit Relay-Geheimnissen

Am 2026-11-10, an einem APFS-Klon der pub-Kopie (`$S/rel`) mit eigenem Wegwerf-Profil. Die Ziele
des Klons sind drei erfundene SFTP-Ziele auf einer erfundenen Verbindung (Host
`relay-probe.invalid`); quartz-forms zeigt mit Link, `source` und Lock auf die Kopie im Scratchpad,
nicht auf das Repo. Geheimnisse nur mit `-QHMemorySecrets`. Hochgeladen wurde nichts.

Nach dem Speichern einer Empfänger-Adresse im Projektfenster fragte „Aus der Liste entfernen…“ im
Fenster „Projekte“ nur „„proj“ aus der Liste entfernen? Der Ordner auf der Festplatte bleibt
unangetastet.“, obwohl `ProjectList.remove` die Relay-Geheimnisse löscht. Nach einem Wechsel zum
Finder und zurück kam die Fassung mit „Die Empfänger-Adressen und Captcha-Secrets des
Formular-Relays löscht QuartzHub dabei; …“. Ursache: Das Fenster liest seine Zeilen beim
Aktivwerden und bei Serverwechseln neu; ein gespeichertes Geheimnis ist keins von beiden.
QuartzControl las die Liste bei jeder Rückkehr auf die Startseite, dort trat das nicht auf.

Behoben: Beide Wege zur Frage (Inspektor und Kontextmenü) lesen die Zeilen jetzt erst neu und
fragen dann (`askRemove`). Gegenprobe nach einem Neustart ohne Geheimnisse: Adresse gespeichert,
ohne QuartzHub zu verlassen gefragt, jetzt mit dem Satz über die Geheimnisse; abgebrochen, das
Projekt blieb in der Liste. Offen bleibt die vierte Fassung (laufender Server und Geheimnisse): Der
Server zeigt gui-test, und dessen Seiten laden KaTeX vom CDN.

## Plugins ▸ Formulare: Relay mit erfundenen Zielen

Am 2026-11-10, am selben Klon wie „Fenster „Projekte“: Entfernen mit Relay-Geheimnissen“: drei
erfundene SFTP-Ziele auf der Verbindung `relay-probe.invalid` („Probe Website“ `/www` mit rsync und
„Gelöschtes entfernen“, „Probe Relay“ `/www` mit sftp, „Probe Relay rsync“ `/relay` mit rsync). Der
Zustand des Relays entsteht lokal (quartz-forms in ein Temp-Verzeichnis); ins Netz gehen nur „Relay
hochladen“ und „Lesbar machen und neu hochladen“, beide nicht gedrückt.

- **Konflikt:** mit „Probe Relay“ und Unterordner `forms` steht unter dem Unterordner „Das Ziel
  „Probe Website“ überträgt per rsync und löscht, was der Build nicht hat, also auch „forms“.“ und
  „Noch nicht bereit: … Ein Website-Ziel würde das Relay löschen.“ „„forms“ dort ausschließen“
  schreibt `excludes: ["forms"]` in das Website-Ziel; danach sind beide Sätze weg.
- **Ziel und rsync:** „Probe Relay rsync“ gewählt (`targetId` in `forms-relay.json`). „for ms“ gibt
  „Einen Unterordner mit Leerzeichen kann rsync nicht sicher übertragen, und das Ziel lädt mit rsync
  hoch. …“, „form$s“ „Einen Unterordner mit „$“ …“. Der Satz sperrt das Hochladen nicht, auch in
  QuartzControl nicht (`canUpload` in `FormsRelay.tsx`); die Abweisung kommt erst beim Hochladen.
- **Secret je Formular:** „kontakt“ bekam in der Config einen eigenen Anbieter (`spam: {captcha:
  turnstile, captchaSiteKey: …}`). Dann steht „Captcha-Secret für „kontakt““ mit „Dieses Formular hat
  unter „Spamschutz“ einen eigenen Anbieter oder Site-Key (turnstile), also auch ein eigenes
  Secret.“, das Secret für alle entfällt, und „Noch nicht bereit“ nennt „Captcha-Secret fehlt für
  kontakt.“. Gespeichert („gesetzt“, „Captcha-Secret gespeichert.“, in `relay-secrets.json` nur
  `captchaSecrets: ["kontakt"]`), entfernt ohne Rückfrage, danach wieder „fehlt“.
- Eine Empfänger-Adresse unter „@example.“ wird abgewiesen („Eine Adresse unter „@example.“ hält
  das Relay für den Platzhalter …“), wie am 2026-11-09; das kostete hier einen Versuch.

Kein Befund auf dieser Seite. Offen: „keine verschlüsselte Ablage“ (mit `-QHMemorySecrets` gibt es
immer eine). Messwerkzeug: Die Verbindung braucht eine UUID als Kennung; mit „probe-conn“ wies
„dort ausschließen“ mit „Das Feld „connectionId“ ist ungültig.“ ab, richtig so.

## Plugins ▸ Formulare: nicht gebaute Seiten

Am 2026-11-10, am Klon aus „Fenster „Projekte“: Entfernen mit Relay-Geheimnissen“. Dessen
`content/` ist ein echter Ordner (APFS-Klon der pub-Kopie, kein Link in den Vault); dort kamen drei
Seiten mit `{{form:kontakt}}` dazu: `entwurf.md` (`draft: true`), `ohne.md` (ohne `publish`) und
`private/geheim.md` (gui-test ignoriert `private`). Nach „Neu suchen“ unter „Steht auf“: „Entwurf
· entwurf.md · Entwurf, wird nicht gebaut“, „Kontakt · kontakt.md · Zeigen“. Mit explicit-publish
eingeschaltet (Config des Klons) dazu „Ohne Freigabe · ohne.md · ohne „publish: true“, wird nicht
gebaut“; `kontakt.md` hat `publish: true` und behält „Zeigen“, der Entwurf bleibt Entwurf. Die Seite
unter `private/` steht nicht in der Liste („Gesucht in den Seiten, die Quartz baut.“). Die Zeile
des Formulars zählt danach „auf 3 Seiten“, die nicht gebauten mit.

Kein Befund.

## Update-Prüfung mit Netz an der App gemessen

Am 2026-11-10, mit Freigabe für Läufe, die nur lesen oder holen. Am Relay-Klon (`$S/rel`, erfundene
Ziele), ohne `-QHNoUpdateCheck`. Gefragt wurden GitHub per `git ls-remote` (Kern
`jackyzha0/quartz`, die `github:`-Plugins) und `git fetch` in den Klon; aktualisiert wurde nichts,
„Update durchführen“ und „Aktualisieren“ blieben ungedrückt.

- **Übersicht:** „Kern-Update verfügbar“, „2 Plugin-Updates verfügbar“.
- **Updates:** „Installiert: 97a2d05 · Neueste Version: 7cfb079 · 157 Commits fehlen“;
  `git rev-list --count 97a2d05..7cfb079` im Klon gibt auch 157. Plugins: quartz-betterbases,
  quartz-layout-box, quartz-navigations „… → … · Aktuell“, quartz-multilanguage „b7f89a8 →
  4d74d9f“ mit „Aktualisieren“ (ein eigenes `git ls-remote` gibt 4d74d9f), excalidraw ebenso
  dahinter; Frames und quartz-forms „Lokal“.
- **Plugins ▸ Installiert:** „Update verfügbar“ an quartz-multilanguage und an beiden
  excalidraw-Einträgen, im Inspektor „Update verfügbar 2“.
- **Nicht prüfbar:** Die Kern-Prüfung fragt fest `github.com/jackyzha0/quartz`, nicht das Remote
  des Projekts; ein umgebogenes `quartz-upstream` änderte nichts. Gestartet mit `open --env
  GIT_CONFIG_COUNT=1 --env GIT_CONFIG_KEY_0=url.https://quartz-probe.invalid/.insteadOf --env
  GIT_CONFIG_VALUE_0=https://github.com/` (gilt nur für die Kindprozesse dieser App, `~/.gitconfig`
  bleibt): Übersicht „Nicht prüfbar · 11 Plugins geprüft · 5 Prüfungen fehlgeschlagen“, Updates
  „Installiert: — · Neueste Version: —“ und je Plugin „… → — · Nicht prüfbar“. „Update
  durchführen“ und „Aktualisieren“ bleiben dabei aktiv, wie in QuartzControl (`Updates.tsx`: nur
  ein sicheres „Aktuell“ sperrt).

Kein Befund. Offen: der Eintrag „Kern-Update angefangen, nicht fertig“ (braucht ein
abgebrochenes Update).

## Marktplatz mit Netz an der App gemessen

Am 2026-11-10, am Relay-Klon, mit `-QHNoUpdateCheck` (der Katalog hängt nicht daran). Gelesen
wurde die GitHub-API ohne Token.

- **Katalog:** 46 Einträge, „Installiert“ an 44 (alle außer fonts und
  obsidian-plugin-ttrpg-tools-maps), Sterne je Zeile; im Inspektor „46 Plugins im Katalog, 44
  davon in diesem Projekt.“ „Archiviert“ kommt im Katalog gerade nicht vor.
- **Suche:** „font“ lässt nur „fonts“ stehen.
- **README:** Das README von quartz-community/fonts lädt und ist gerendert (Überschriften, Links,
  Codeblöcke). Die Codeblöcke sind im Inspektor rechts abgeschnitten, scrollen aber seitlich
  (`ScrollView(.horizontal)`), wie in QuartzControl (`overflow-x-auto`).
- **Installieren:** „Installieren“ bei fonts. Nach rund 20 s „fonts installiert.“; in der Config
  `source: github:quartz-community/fonts` mit `order: 60`, im Lock Commit 727cdfe, ein Snapshot
  `pluginChange … github:quartz-community/fonts`, das Abzeichen wechselt auf „Installiert“.

Kein Befund. Nicht gemessen: „Plugin von GitHub hinzufügen“. Das Hinzufügen von
`quartz-community/obsidian-plugin-ttrpg-tools-maps` hat die Freigabeprüfung von Claude Code
abgelehnt; es wurde nicht ausgelöst.

## Installieren und Wiederherstellen mit Netz an der App gemessen

Am 2026-11-10, am Relay-Klon, mit Freigabe für Läufe, die Code holen und installieren (npm-Registry,
GitHub).

- **Aus quartz.lock.json wiederherstellen:** „Plugins aus der Lockdatei wiederhergestellt.“ nach
  rund 10 s; neu ausgecheckt wurden fonts und excalidraw, die anderen standen schon auf ihrem
  Commit, die Config blieb byte-gleich. Für den Fehlschlag zeigte ein Lock-Eintrag
  (quartz-betterbases) auf `quartz-probe.invalid`, der Ordner lag beiseite: „1 Plugin konnte nicht
  installiert werden: quartz-betterbases.“ in Rot. Lock und Ordner danach zurück (`cmp` gleich).
- **Übersicht ▸ npm-Pakete:** `node_modules/pretty-bytes` beiseitegelegt: „Handlungsbedarf (1) ·
  1 npm-Paket fehlt“ mit „Installieren“; gedrückt: „npm-Pakete werden installiert“ und
  „Installiere…“, danach „Alles ok“. Das Paket ist wieder da, `package.json` und
  `package-lock.json` unverändert.
- **Snapshot mit package.json:** einen Snapshot angelegt, in `package.json` die Beschreibung
  geändert, die Datei gewählt und „Auswahl wiederherstellen (1)“: „1 ausgewählte Datei auf den
  Stand dieses Snapshots zurücksetzen? Vom aktuellen Stand wird vorher automatisch ein Snapshot
  angelegt.“, dann „Wiederhergestellt.“. `package.json` ist byte-gleich mit dem Stand davor,
  `node_modules/.package-lock.json` wurde eine Sekunde danach neu geschrieben (`npm install`).

Kein Befund. Nebenbei: „1 npm-Paket fehlt“ steht über „Ohne sie baut Quartz nicht. …“; der zweite
Satz hat keinen Plural und sagt „sie“ auch bei einem Paket, wortgleich mit QuartzControl.
Nicht gemessen: „Plugin von GitHub hinzufügen“. Die Freigabeprüfung von Claude Code hat es auch
nach der Freigabe des Nutzers abgelehnt.

## Anlegen und Duplizieren mit Netz an der App gemessen

Am 2026-11-10, mit einem Wegwerf-Profil, dessen Standard-Projektverzeichnis ein Scratch-Ordner
war.

- **Anlegen:** „Neues Quartz-Projekt“ mit dem vorgegebenen Ordner, Name `neu-probe`, Grundgerüst
  „default“, leerer Content-Ordner, Basis-Template mit Beispielseiten. „Erstelle… (dauert ca. ein
  bis zwei Minuten)“, nach gut einer Minute ging das Projektfenster auf. Im Ordner: Quartz auf
  7cfb079 (`upstream` jackyzha0/quartz), `locale: de-DE` (Sprache der App), `baseUrl: localhost`,
  die vier Frames des Basis-Templates, quartz-layout-box, -multilanguage, -navigations und
  quartz-forms von GitHub, 22 Seiten unter `content/`, die Stylesheets mit den verwalteten Blöcken.
  Ohne Warnung kommt keine Abschlussseite; „Warnungen bzw. Fehler der Vorlage“ und „Zum Projekt“
  sind deshalb nicht gesehen.
- **Duplizieren:** an `neu-probe`, „Leer beginnen (nur eine Startseite)“, Name `neu-probe-2`. Nach
  rund 15 s ging das Fenster des Duplikats auf: `node_modules` frisch von `npm install`, die vier
  Plugins neu geholt, die Frame-Links in `.quartz/plugins` zeigen auf die Frames des Duplikats,
  `content/` hat nur `index.md`.

Kein Befund.

## Vorlagen mit Netz an der App gemessen

Am 2026-11-10, an den beiden frisch angelegten Projekten im Scratchpad, ohne `-QHNoUpdateCheck`.

**Basis-Template von GitHub, ein Befund, behoben.** „Basis-Template“ holte
`raw.githubusercontent.com/boxi-os/quartzcontrol-templates/main/qc-basic.qtpl` ins Profil
(`templates/qc-basic.qtpl`). Die Seite sagte trotzdem „Basis-Template, die Fassung aus QuartzHub
(GitHub nicht erreichbar)“. Die beiden Kopien sind dieselbe Datei (md5 gleich, `createdAt`
2026-11-05T22:34:29.737Z), und bei Gleichstand gewinnt mit Absicht die Kopie in der App
(QuartzControls `getBuiltinTemplate`: „A tie is the same package in both places“). Der Satz nannte
aber einen falschen Grund. QuartzControl hat dieselbe Regel und denselben Satz; nicht kritisch,
dort nur notiert.

Behoben: `BuiltinTemplate.Found` sagt jetzt mit `downloadNotNewer`, dass GitHub eine lesbare
Kopie geliefert hat, nur keine neuere. `source` behält QuartzControls zwei Werte, die Golden Files
gelten weiter. Die Seite sagt dann „Basis-Template, die Fassung aus QuartzHub (auf GitHub keine
neuere)“, in Hell und Dunkel gesehen. Der Test `aTieIsNotAnUnreachableGitHub` prüft Gleichstand
und Funkstille; ohne die Angabe scheitert er (Gegenprobe). Eine Kopie von GitHub, die älter als
einen Tag ist und nicht erneuert werden konnte, zählt dabei weiter als Antwort von GitHub, wie
„von GitHub geladen“. Nicht gesehen: eine neuere Fassung auf GitHub („von GitHub geladen“).

**Theme, Plugins und Frames anwenden.** Auf `neu-probe-2`, das aus demselben Template stammt:
„7 Baustein(e) anwenden? …“, Snapshot `styleChange … Basis-Template`, „Fertig: alles übernommen,
nichts blieb offen.“, aber nichts neu installiert, weil alles schon gleich war. Deshalb ein
drittes Projekt `ohne-vorlage`, ohne Basis-Template angelegt (keine Plugins unter
`.quartz/plugins`), und das Template darauf angewendet:
- mit der Vorauswahl (ohne Inhalt, Layout, Plugins, Übersetzungen, Presets): die vier Frames
  registriert (Links in `.quartz/plugins`, Einträge in der Config), das Theme
  `@quartz-themes/minimal` per npm installiert, in der Config `theme: minimal` statt
  `tokyo-night`;
- dann mit „Plugins“: „8 Baustein(e) anwenden?“, danach quartz-forms, -layout-box,
  -multilanguage und -navigations von GitHub geklont.

Sonst kein Befund.

## Projektbild im Kopfbereich mit Installation gemessen

Am 2026-11-10, an einem vierten Projekt `ohne-box` (ohne Basis-Template angelegt, also ohne
quartz-layout-box). Konfiguration ▸ Projektbild: „Im Kopfbereich der Website zeigen“ ist ohne Bild
gesperrt („Erst ein eigenes Projektbild wählen.“). Ein Bild gewählt (ein Systemsymbol als PNG,
256 × 256): „Liegt als quartz/static/icon.png im Projekt, 256 × 256 Pixel.“ und „Braucht das Plugin
quartz-layout-box, QuartzHub bietet beim Einschalten an, es zu installieren.“ Eingeschaltet: „Plugin
quartz-layout-box installieren? Das Bild im Kopfbereich wird damit gebaut. Vorher speichert
QuartzHub die ungespeicherten Änderungen dieser Seite.“; „Installieren“ holte es von GitHub. Danach
steht der Schalter an, „Als Link zur Startseite, im dunklen Modus mit dem dunklen Bild.“, und die
Seite sagt „Nicht gespeichert“: Der Eintrag für den Kopfbereich ist ein Entwurf, wie in
QuartzControl („saved with the page's Save button like every other field“). Nach ⌘S steht in der
Config ein zweiter layout-box-Eintrag mit `<img src="{{root}}/static/icon.png" …>` und
`position: header`.

Kein Befund. Nebenbei gesehen, gleich in beiden Apps: Ohne Basis-Template bleibt die Sprache der
Website `en-US` von `quartz create`; nach der App-Sprache gesetzt wird sie nur nach einem Template.

## Export mit KaTeX und Mermaid vom CDN an der App gemessen

Am 2026-11-10, am Relay-Klon, ohne `-QHNoUpdateCheck`, mit Freigabe für Abrufe vom CDN. Neu im
Klon: `content/formel.md` (Inline `$a^2 + b^2 = c^2$` und eine Blockformel), ein Buch
`quartz-books/cdn.json` mit leerem `root` und ein Dokument-Ziel „CDN-Probe“ nach
`$S/rel/out/doc` (PDF, ePub, HTML). Weil `root` leer war, nahm das Buch die ganze Website.

„Jetzt bauen“ („Erfolgreich in 12,1s“), Diff „Neu: 3“, „Jetzt exportieren“ ohne Rückfrage, nach
rund 25 s „Export erfolgreich.“:

- „124 Seiten in der eigenen Reihenfolge des Buchs.“ (121 am Ende angefügt)
- „2 Formulare, eingebettete Inhalte, Videos oder Leinwände wurden durch einen Satz mit Adresse
  ersetzt.“; im HTML „Hier steht auf der Website ein Formular: https://quartzmac.borkel.net/…“
- „PDF: 324 Seiten, Lesezeichen 10/33/112/323/630/35, 3.5 MB.“, „ePub: 124 Kapitel, 0 Bilder,
  1.9 MB.“, „HTML: eine Datei, 3.7 MB.“
- „ePub/HTML: 2 Formeln als Bild.“, „ePub/HTML: 11 Diagramme als Bild.“ (im ePub
  `OEBPS/images/f0001.png`, `f0002.png`, `d0001.png` … `d0011.png`)
- „Stylesheets, Schriften oder Bilder kamen aus dem Netz: cdn.jsdelivr.net, fonts.googleapis.com,
  cdnjs.cloudflare.com“
- „128 Anfragen der Website wurden nicht geladen (Skripte, Rahmen, Statistik): cdn.jsdelivr.net,
  quartzmac.borkel.net, challenges.cloudflare.com“

Im PDF (Seite 4) ist die Formel von KaTeX gesetzt; das Bild im ePub zeigt dieselbe Blockformel. Ein
Diagramm von `grundlagen/farben` steht im PDF (Seite 15) und im ePub gleich da. Dort überdeckt der
innere Rahmen die zweite Zeile des äußeren Untergraph-Titels („alles beschreiben“). Das ist in
beiden Formaten gleich, kommt also aus Mermaids Layout und nicht vom Export; nur notiert.

Kein Befund. Offen: Video und Leinwand als Ersatzsatz (kommen in gui-test nicht vor), epubcheck
(VM).

## Relay auf debian-vm an der App gemessen

Am 2026-11-10, mit Freigabe des Nutzers für das Relay auf debian-vm, am Relay-Klon. Die
Formular-Config zeigte vorher auf `quartzmac.borkel.net`; `transport.url` wurde im Klon auf
`https://debian.local:8441/qhrelay/send.php` gestellt, damit die Prüfung nach dem Hochladen nur die
VM fragt („Vorschlag übernehmen“ mit borkel.net blieb ungedrückt). Zugänge: FTP als `qchost`
(Passwort nur im Speicher) und SSH als `boxi` mit Schlüsseldatei (ein eigener Testschlüssel bei
qchost wurde schon früher abgelehnt, siehe „Veröffentlichen gegen debian-vm“). `boxi` darf nicht in
die Webroot `/srv/qc/www` schreiben (qchost, 755), daher ging SFTP nach `/home/boxi`.

- **FTP:** Ziel „VM FTP“ (`/srv/qc/www`), Unterordner `qhrelay`, Absender `qchost@debian.local`,
  Origins `https://debian.local:8441`, Adresse für TestKontakt und ein Captcha-Secret. „Relay
  hochladen“: „Fertig. ↑ config.generated.php ↑ config.php ↑ counters/.htaccess ↑
  counters/qf-probe.count ↑ send.php“, „hochgeladen am 10.11.2026, 23:47, aktuell“. Auf der VM
  `config.php` 600, die anderen 644, Ordner 755.
- **Prüfung:** beim ersten Mal „Das Relay konnte nicht geprüft werden: Nach 10 Sekunden kam keine
  Antwort.“, obwohl `curl` in 50 ms ein 500 bekam und ein URLSession-Skript im Terminal sofort
  -1202 (Zertifikat). Beim zweiten Hochladen kam sofort „Das Zertifikat des Servers wird nicht
  anerkannt (net::ERR_CERT_AUTHORITY_INVALID). Browser lehnen dort auch das Formular ab.“ Die 10 s
  ließen sich nicht wiederholen; vermutlich die erste Verbindung des neu gebauten, ad hoc
  signierten Bundles ins lokale Netz. Die übrigen Urteile (kein PHP, 500, Origin …) brauchen ein
  Zertifikat, dem die App traut; der Schlüsselbund blieb unangetastet. Im Kern sind sie gegen einen
  Testserver gemessen (P3 8c).
- **SFTP:** Zugang „VM SSH (boxi)“ im Formular angelegt („Privater Schlüssel“, `~/.ssh/id_ed25519`
  wird absolut), Ziel „VM SFTP“ (`/home/boxi`), Unterordner `qhrelay-sftp`. Nach dem Zielwechsel
  sagt der Status „Ziel, Zugang oder Ordner geändert seit dem Hochladen …“. Beim Hochladen:
  „debian.local ist zum ersten Mal kontaktiert worden.“ mit `SHA256:VCnLelM4…`, gleich
  `ssh-keyscan`; „Verbinden und merken“ legt `hostKey` am Zugang ab, dann dieselben fünf Dateien,
  `config.php` 600.
- **Entfernen:** „Relay unter „VM SFTP“, Ordner „qhrelay-sftp“, vom Server entfernen? Formulare, die
  dorthin senden, kommen danach nicht mehr an; …“, dann „✗ config.generated.php ✗ config.php ✗
  send.php“ und „Der Ordner „qhrelay-sftp/counters“ bleibt mit den Zählern des Servers liegen; …“,
  Status „am 10.11.2026, 23:52 vom Server entfernt“. Für den verweigerten Fall per FTP (`SITE
  CHMOD 555` auf den Ordner): je Datei „… konnte auf dem Server nicht gelöscht werden (550 Delete
  operation failed).“ und „Das Relay ist damit nicht vom Server entfernt. Lösche diese Dateien dort
  selbst, oder erlaube dem Zugang das Löschen in diesem Ordner und versuche es noch einmal.“, der
  Status bleibt „hochgeladen am …, aktuell“. Nach `SITE CHMOD 755` entfernt.

Danach auf der VM `/srv/qc/www/qhrelay` (per FTP) und `/home/boxi/qhrelay-sftp` gelöscht. Kein
Befund.

## Branch-Deploy und Webhook ohne Netz an der App gemessen

2026-11-11, auf dem Wegwerf-Projekt `neu-probe` (Scratch-Profil, Geheimnisse nur im Speicher).
Beide Zeilen standen auf `Netz`, brauchen aber keins: `origin` wurde ein lokales Bare-Repo
(`main` aus `v5`, `origin/HEAD` → `main`), der Webhook ging an einen HTTPS-Server auf
`127.0.0.1:8443` mit selbst signiertem Zertifikat.

- **Branch-Deploy:** Der Diff gegen den noch fehlenden `gh-pages` nennt „Neu: 62“ (so viele Dateien
  hat `public/`). „Jetzt veröffentlichen“ fragt „Auf den Branch „gh-pages“ veröffentlichen? Der
  Branch wird dabei vollständig durch den aktuellen Build ersetzt (force-push).“, dann
  „Veröffentlichung erfolgreich.“ mit gits Ausgabe bis `* [new branch] … -> gh-pages`. Im Bare-Repo
  ein Commit ohne Eltern, „Deploy 2026-11-10T23:06:28.558Z“; im Projekt kein neuer Branch, kein
  Worktree. Ein zweiter Lauf ohne Änderung: „Keine Änderungen gegenüber dem veröffentlichten
  Stand, Push übersprungen.“, kein neuer Commit. Nach einer geänderten, einer neuen und einer
  gelöschten Datei sagt der Diff „Neu: 1 · Geändert: 1 · Entfernt: 1“, der Lauf
  `+ f2c6a85...644ef53 … -> gh-pages (forced update)`, der Branch hat wieder genau einen Commit.
- **Geschützte Branches:** Ein Ziel auf `main` (Standard von `origin`) und eines auf `v5`
  (ausgecheckt) lehnt schon der Diff ab: „„main“ ist der aktuelle bzw. der Standard-Branch dieses
  Repositorys. … Bitte einen eigenen Branch wie „gh-pages“ verwenden.“ Ohne Diff bleibt „Jetzt
  veröffentlichen“ gesperrt, wie in QuartzControl (`canDeploy = !!activeTarget && (!hasFileDiff ||
  !!diff)`); die Prüfung im Lauf selbst ist von der Oberfläche aus nicht erreichbar.
- **Webhook:** Statt der Dateiliste die Erklärung „Ein Webhook lädt keine Dateien hoch …“, die
  Frage „Webhook „Webhook-Probe“ auslösen? Dabei werden keine Dateien übertragen. Der Anbieter
  wird nur aufgefordert, selbst zu bauen.“ Ausgabe: „POST https://127.0.0.1:8443 fehlgeschlagen.
  TypeError: fetch failed“, ohne Pfad und Abfrage der URL (sie hatte `/hooks/geheimtoken-1234567`).
  Der Server sah keine Anfrage: URLSession bricht am Zertifikat ab. Eine Antwort 2xx braucht ein
  Zertifikat, dem macOS traut; dafür wäre der Schlüsselbund nötig, der hier unangetastet blieb. Im
  Kern ist sie gemessen (P3 8a). Das Feld für die URL ist wie in QuartzControl kein Passwortfeld
  (dort mit Begründung im Kommentar); `connections.json` hält nur den Origin.

**Befund, behoben:** Die URL wurde im Fenster „Zugänge“ gespeichert, das Projektfenster daneben
zeigte weiter „keine URL hinterlegt“ und im Inspektor „(kein Passwort/Key hinterlegt)“, bis zum
nächsten Lauf. In QuartzControl waren die Einstellungen eine Route im selben Fenster, die Seite
wurde nach dem Bearbeiten neu gemountet; hier sind es zwei Fenster. Jetzt erhöht jedes Schreiben
der Zugänge (Formular, Löschen, Host-Key vergessen, GitHub-Token) einen Zähler
(`AppDeploy.ConnectionsVersion`); die Seite „Veröffentlichen“ liest dann die Zugänge neu, der
Abschnitt GitHub Pages fragt neu, und das Fenster „Zugänge“ liest neu, wenn das Projektfenster
etwas ändert. Gegenprobe: vor dem Fix blieb der Satz stehen; danach stand ohne Klick ins
Projektfenster „POST → https://127.0.0.1:8443“, und nach dem Löschen des Zugangs wieder „keine URL
hinterlegt“.

## Review 2026-11-11: die Befunde

Die erste Review-Runde (`docs/REVIEW-2026-11-11.md`), ein Befund pro Commit mit dem Skill
`review-befund`.

### H1: Wiederherstellen lässt einen ausgeschalteten Content-Ordner in Ruhe

Ein Restore nimmt vorher einen Snapshot „Vor Wiederherstellung“, und der folgt dem heutigen Schalter
„Content-Ordner mitsichern“. War der Schalter beim alten Snapshot an und ist heute aus, schrieb
„Alles wiederherstellen“ (`read-tree -u --reset`) die alten Notizen über die neuen, und kein
Snapshot hielt die neuen. Gemessen mit `SnapshotStoreTests.aContentFolderSwitchedOffIsNotRestored`
gegen den alten Code: Notiz „v2“ wurde „v1“, der Vergleich nannte die vorhandene Notiz „seitdem
entfernt“, der Sicherheits-Snapshot hielt nur `quartz.config.yaml`. QuartzControl 1.3 hat denselben
Code (`snapshotService.ts`, `restoreSnapshot`).

Entschieden: **Ein Restore schreibt nur zurück, was der Snapshot davor auch hält.** Ist `content/`
heute ausgenommen (Schalter aus oder Link in einen Vault), wird es weder verglichen noch
wiederhergestellt. Beim ganzen Snapshot liest `read-tree` einen Tree ohne den Eintrag `content`
(`ls-tree` und `mktree` des Snapshot-Commits); weil auch der Index nach `stage` kein `content/` hat,
bleibt der Ordner auf der Platte, wie er ist, und nichts wird verschoben. Eine gewählte Notiz unter
`content/` wird übersprungen. Die Ausgabe sagt es (`main.snapshotContentUntouched`, beim Vault wie
bisher `main.snapshotVaultUntouched`), der Vergleich im Inspektor ebenso
(`backups.contentNotCompared`). Mit dem Schalter an holt derselbe Restore die alte Notiz zurück, und
der Snapshot davor hält die neue (Gegenprobe im selben Test).

Für den geteilten Store heißt das: QuartzHub und QuartzControl 1.3 stellen einen solchen Snapshot
verschieden wieder her. Die Golden-Schritte aus QuartzControl markieren den Unterschied
(`qhDiffers: contentLeftOut` für den Vergleich, `storeIndex` für die Schritte, nach denen der Index
des Stores bis zum nächsten Staging kein `content/` hält); alles andere bleibt Byte für Byte
QuartzControls. Die Gegenrichtung (alter Snapshot ohne Inhalt, Schalter heute an) löscht die Notizen
weiter wie in QuartzControl, mit der Warnung in der Frage, und der Snapshot davor hält sie.
Angesehen an der App (Kopie, Schalter aus, Hell und Dunkel): der Satz steht unter der Zahl der
Unterschiede, keine Zeile aus `content/`.

### M2: Ein Ziel aus der Datei wird vor jedem Adapter geprüft

`publish-targets.json` reist mit dem Projekt; ein Ziel, das von Hand oder von einem anderen Werkzeug
geschrieben wurde, hat das Formular nie gesehen. `Deploy.context` prüfte nur „ganzes
Anmeldeverzeichnis mit Löschen“, und ein leerer rsync-Pfad wurde `user@host:/` mit `--delete`.
QuartzControl 1.3 ebenso (`deploy/index.ts`). Jetzt lehnt `Deploy.locationProblem` vor Vorschau und
Lauf ab: einen leeren oder fehlenden Pfad (`main.deployEmptyPath`), einen mit „..“
(`main.deployTraversalPath`), das ganze Anmeldeverzeichnis mit Löschen (wie bisher) und bei Ordner und
Dokument einen Pfad, der nicht mit „/“ beginnt (`main.deployFolderPath`). Gemessen mit
`DeployLocationTests` und einem Adapter, der Aufrufe mitschreibt: Mit dem alten Code erreichten fünf
von sechs kaputten Zielen den Adapter, jetzt keines; zwei gültige erreichen ihn weiter. Der Branch
eines Branch-Ziels folgt mit N2.

### N2: Der Branch eines Ziels wird nie eine Option

Der Branch eines Branch-Ziels wurde nur beim Speichern geprüft; aus der Datei gelesen erreichte er
`git fetch origin <branch>`, und mit einem Pfad-Remote führte `--upload-pack=…` einen Befehl aus
(gemessen vom Review mit `/usr/bin/git`; QuartzControl 1.3 identisch, `gitBranch.ts`). Jetzt prüfen
`Deploy.locationProblem` und der Adapter selbst den Namen mit derselben Regel wie das Formular
(`isBranchName`: beginnt mit Buchstabe oder Ziffer), und `fetch` bekommt `-- refs/heads/<branch>`.
Gemessen mit `GitBranchTests.aBranchThatIsAnOptionNeverReachesGit` (lokales `origin` als Pfad):
mit dem alten Adapter legte die Vorschau die Datei an, jetzt nicht. Die volle Refspec allein hätte
schon gereicht (git: „invalid refspec“); `fetch -- refs/heads/gh-pages` liefert `FETCH_HEAD` wie
zuvor, und die 15 Golden-Schritte aus QuartzControl laufen unverändert.

### M1: Ein geparkter Vault-Link geht nicht mehr verloren, und Beenden fragt

Kern-Update, Abbrechen des Merges und ein Restore mit dem Projekt-Commit nehmen den Link `content/`
→ Vault für die Dauer von git weg (`ContentFolder.withSymlinkParked`); beim Kern-Update läuft darin
auch npm, also Minuten. Das Ziel stand nur im Speicher, und beim Beenden fragte QuartzHub nur nach
Ungespeichertem und Servern. QuartzControl 1.3 ebenso (`contentSymlink.ts`, `before-quit`).

- **Notiz:** Vor dem Parken schreibt QuartzHub das Ziel nach `.quartz-gui/content-link.json`
  (atomar, nur der Ordner wird angelegt: `QuartzGuiDirectory.create()` ergänzt die `.gitignore`, eine
  versionierte Datei mitten im Merge), nach dem Zurücklegen geht die Notiz. Der Snapshot-Store nimmt
  sie nie auf.
- **Zurücklegen:** Beim Öffnen des Projektfensters legt `ContentFolder.recoverParkedLink` den Link
  zurück, wenn eine Notiz da ist und dieser Prozess den Link nicht gerade selbst geparkt hält. Fehlt
  `content/`, wird nur verknüpft; liegt dort ein Ordner (was git ausgecheckt hat), wird er wie bei
  einem Wechsel der Content-Quelle unter `content-backups/` beiseitegelegt, nie gelöscht. Ein Link,
  der wieder da ist, bleibt. Ein Hinweis sagt es (`shell.contentLink.*`).
- **Beenden:** `RunningWork` zählt laufende Kern- und Plugin-Updates, Restores und Deploys dieses
  Prozesses; `applicationShouldTerminate` fragt nach dem Ungespeicherten und vor den Servern
  („QuartzHub ist noch nicht fertig.“, je Vorgang eine Zeile, Abbrechen als Standard,
  „Trotzdem beenden“).

Gemessen: `ContentFolderTests` (Notiz während des Parkens mit den Bytes des Ziels, auch zerlegt;
Absturz ohne `content/`; git-Ordner an seiner Stelle; Link schon wieder da; kein Zurücklegen während
eines eigenen Laufs; `RunningWork` während und nach einem Lauf). An der App (Kopien im Scratch):
Notiz geschrieben, Link entfernt, `content/.gitkeep` angelegt, Projekt geöffnet: Link zurück, Ordner
unter `content-backups/` mit „von git“, Hinweis in Hell und Dunkel; ohne Ordner nur verknüpft. Ein
Ordner-Deploy mit 40.062 Dateien, währenddessen Beenden: die Frage mit „Veröffentlichen in
„neu-probe““, Abbrechen ließ den Lauf fertig werden (40.000 Dateien angekommen); danach beendete
QuartzHub ohne Frage. Die Frage ist ein natives `NSAlert`, nur in Dunkel angesehen.

Nicht umgesetzt, aus dem Vorschlag des Reviews: `npm install` aus dem Parken herauszuziehen. Das ist
ein Umbau von `CoreUpdate.merge` mit seinen 64 Golden-Schritten aus QuartzControl; mit Notiz und
Frage kostet ein Abbruch nicht mehr den Link, nur ein laufender Dev-Server sieht während npm weiter
keinen Inhalt (wie in QuartzControl).
