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
