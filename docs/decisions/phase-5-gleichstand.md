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
