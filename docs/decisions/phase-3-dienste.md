# Phase 3: die Kern-Dienste

Gebaut und gemessen ab dem 2026-11-06, ein Abschnitt je Dienst. Was hier steht, war eine
Entscheidung oder anders als erwartet. Die Spezifikation ist jeweils die TS-Datei aus
QuartzControl und ihr Abschnitt in `../QuartzControl/docs/decisions/`.

### Prozessstarter (`runCommand.ts` → `ProcessRunner`)

`ProcessRunner.run(Command)` startet einen Kindprozess und wartet auf ihn; Ergebnis ist
`CommandResult` mit `termination`, `output` (stdout und stderr in Ankunftsfolge) und `stdout`
allein. Übernommen aus QuartzControl: stdin ist `/dev/null`, gewartet wird auf Ende **und** beide
geschlossenen Pipes (Nodes `close`), eine Frist antwortet sofort mit dem bis dahin Angekommenen,
dann SIGTERM und nach 2 s SIGKILL; nie eine Shell.

- **`posix_spawn` statt Foundations `Process`.** `Process` gibt Argumente zerlegt weiter (NFD,
  gemessen in Phase 2). Hier gehen die Bytes des Strings unverändert durch: `printf %s wört` liefert
  `77 c3 b6 72 74`.
- **Eigene Prozessgruppe statt `tree-kill`.** Frist und Abbruch signalisieren die Gruppe. Gemessen
  mit einem Enkel, der die Pipes nicht hält (`sleep 30 >/dev/null &`): Ein Signal nur an die PID
  ließ ihn weiterlaufen, an die Gruppe nicht. Ein Enkel, der stdout hält, stirbt spätestens am
  SIGKILL an die Gruppe.
- **Nichts wird vererbt** (`POSIX_SPAWN_CLOEXEC_DEFAULT`): Ein Deskriptor der App ohne
  close-on-exec auf Nummer 77 kam im Kind nicht an; ohne die Flagge doch. Signale im Kind auf
  Standard, Maske leer.
- **Zwei Arten, nicht zu laufen:** `couldNotStart(.notFound | .directoryMissing |
  .argumentsTooLong | .other)` ist etwas anderes als ein Exit-Code. Exit 127 einer Shell bleibt
  `.exited(127)`. Node meldet einen fehlenden `cwd` wie ein fehlendes Programm (`ENOENT`); hier ist
  er eine eigene Antwort.
- **Der Name wird im PATH der Kind-Umgebung gesucht**, nicht in dem der App (`posix_spawnp` nähme
  den der App). Die Umgebung ist immer die ganze; `adding(_:)` setzt Variablen obendrauf
  (QuartzControls `env`-Argument).
- **Eingabe über stdin** (`input`), für die Helfer: 4 MB durch `cat` hin und zurück ohne
  Verklemmung, weil eine kqueue Schreiben, Lesen und das Ende zugleich bedient.
- **Abbruch über die Task:** `Task.cancel()` beendet die Gruppe und antwortet `.cancelled`.
- Ausgabe wird erst am Ende als UTF-8 gelesen, nicht je Block wie in Node: Ein Umlaut an einer
  Blockgrenze wird so nicht zu U+FFFD.
- **Gegenproben** (je eine Zeile im Code verändert, `ProcessRunnerTests`): ohne
  `CLOEXEC_DEFAULT`, ohne eigene Gruppe, Signal nur an die PID, Argumente als NFD, Antwort schon
  beim Ende des Prozesses, ohne SIGKILL, Abbruch überhört: Jede ließ mindestens einen Test
  scheitern. Die Gegenprobe „nur an die PID“ ließ zuerst alles grün, weil das SIGKILL an die Gruppe
  den Enkel trotzdem traf; daher der Test mit dem Enkel ohne Pipes.
- Nicht übernommen: `needsShell` (nur Windows). Ein Streaming für Builds und Server kommt mit
  `buildService`.
