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
