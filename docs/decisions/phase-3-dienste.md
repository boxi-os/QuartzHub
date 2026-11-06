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

### PATH (`environmentService.ts` → `HostPath`)

`HostPath.resolve` ist `ensureToolPath`: Findet der geerbte PATH ein git, das antwortet, bleibt er;
sonst kommt der PATH der Login-Shell dazu (`$SHELL -ilc`, Marke `__QH_PATH__`, Frist 5 s), dann die
üblichen Orte. Anders als QuartzControl ändert das nicht die Umgebung von QuartzHub selbst, sondern
ist ein Wert, aus dem die Umgebung der Kindprozesse entsteht (nächster Abschnitt).

- **Das erste git im PATH entscheidet, wie in QuartzControl.** Ist es der Stub `/usr/bin/git` (kein
  `xcode-select -p`), zählt auch ein späteres git nicht, weil Kindprozesse `git` beim Namen rufen
  und sonst den Installer-Dialog bekämen; dann nimmt die git-Laufzeit das mitgelieferte und stellt
  es nach vorn. Mein erster Test hatte das Gegenteil erwartet.
- Die üblichen Orte ohne die Linux-Pfade (Snap, Flatpak), dafür mit Nix
  (`/nix/var/nix/profiles/default/bin`, `~/.nix-profile/bin`): QuartzControls Kommentar nennt Nix,
  seine Liste nicht.
- **Gegenproben:** `known` erst nach der Schleife wachsen lassen (doppelte Ordner), Stub nicht
  prüfen, Marke ignorieren, `skipping` ignorieren, keine Login-Shell: jede lässt einen Test
  scheitern. „Marke ignorieren“ ließ auch den Test mit der echten Login-Shell scheitern: Die Shell
  dieses Rechners gibt vor dem PATH etwas aus.
- Nicht gemessen: welchen PATH QuartzHub aus dem Finder erbt; das misst die App, sobald sie die
  Umgebung zeigt. Der Stub-Fall ist wie in QuartzControl nur mit einem nachgebauten `xcode-select`
  geprüft, nicht auf einem Mac ohne Kommandozeilenwerkzeuge.

### Node- und git-Laufzeit (`nodeRuntime.ts`, `gitRuntime.ts` → `ToolEnvironment`, `GitRuntime`)

`ToolEnvironment.resolve` macht beim Start, was QuartzControls `index.ts` in drei Schritten tat (PATH,
git, Node), und ergibt die ganze Umgebung der Kindprozesse: `node/bin` vorn (außer bei
`nodeRuntime: system`), dann das mitgelieferte git, wenn es gebraucht wird, dann der PATH des
Rechners. `command(…)` baut daraus einen `Command`. `EnvironmentReport.probe` ist
`getEnvironmentInfo` für Startseite und Einstellungen. `RuntimeLocation` findet Node, git und Helfer
im Paket (`Contents/Resources`) oder im Repository.

- **Keine Shims.** QuartzControl schrieb bei jedem Start `node`/`npm`/`npx` als Skripte, die Electron
  als Node starten. Hier liegen die drei in `node/bin`; npm (`#!/usr/bin/env node`) findet das `node`
  daneben, weil der Ordner vorn im PATH steht. Gemessen mit einem PATH wie aus dem Dock
  (`/usr/bin:/bin:/usr/sbin:/sbin`, kein anderes node): `node` ist das aus `Runtime/`, v24.22.2,
  `npm --version` antwortet 11.19.1 wie die `package.json` daneben; im Modus `system` findet dieselbe
  Umgebung gar kein npm.
- **git:** das des Rechners, wenn es auf `--version` antwortet (der Stub wird nicht ausgeführt),
  sonst das mitgelieferte mit `GIT_EXEC_PATH` und `GIT_TEMPLATE_DIR`, und nur, wenn auch
  `git-remote-https` lädt. „Unverträglich“ (Loader-Meldung, Exit 127) und „kaputt“ sind zwei
  Antworten; der Bericht nennt das mitgelieferte git, das nicht läuft, mit Pfad statt „nicht
  gefunden“. Auf diesem Mac gewinnt `/usr/bin/git` (Kommandozeilenwerkzeuge da).
- **Mitgeliefertes git gemessen:** `git init` ohne Warnung und mit `.git/hooks`; ohne
  `GIT_TEMPLATE_DIR` kommt „templates not found“ zurück (die Messung aus Phase 1).
  `ls-remote https://github.com/jackyzha0/quartz.git` in `env -i` mit den zwei Variablen: Antwort;
  ohne sie „'remote-https' is not a git command“, wie QuartzControl es gemessen hat.
- `GitRuntime.textVariables` ist `gitTextEnv` (`LC_MESSAGES=C`, `LANGUAGE` leer, ein gesetztes
  `LC_ALL` wandert nach `LC_CTYPE`), für die git-Aufrufe, deren Text QuartzHub liest.
- **Gegenproben:** Helfer-Prüfung übersprungen, Stub ausgeführt, `GIT_TEMPLATE_DIR` fehlt, kein
  Ersatz für das nicht laufende git im Bericht, mitgeliefertes git nicht im PATH: jede lässt einen
  Test scheitern. „`GIT_TEMPLATE_DIR` fehlt“ ließ zuerst alles grün, weil der Test sein git selbst
  baute statt das von `resolve` zu nehmen.
- Noch nicht in der App: Die Umgebung wird aufgelöst, sobald der erste Dienst sie braucht; die
  Einstellung `nodeRuntime` liest dann `SettingsFile`.
