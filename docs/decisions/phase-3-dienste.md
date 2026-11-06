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
- **Ein Test darf keinen festen Deskriptor belegen.** Der erste `childInheritsNoDescriptors` legte
  seinen Deskriptor mit `dup2` auf Nummer 77. Einmal scheiterte daraufhin im Gesamtlauf
  `environmentIsExactlyTheGivenOne` nach 0,03 s, in neun weiteren Läufen und 400 parallelen Starts
  nicht. Die wahrscheinliche Ursache: `dup2` ersetzt still, was dort liegt, auch die Pipe eines
  parallel laufenden Tests. Bewiesen ist das nicht. Jetzt vergibt `F_DUPFD` die nächste freie
  Nummer ab 200.
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

### Log-Puffer (`logBuffer.ts` → `LogBuffer`)

Wortgleich in der Sache: je Projekt und je Art (Server, Build) höchstens 999 Einträge, nur im
Speicher, `history` gibt eine Kopie. In QuartzControl brauchte es ihn, weil ein geschlossenes
Fenster den Renderer samt Store verlor; in QuartzHub leben Kern und Oberfläche in einem Prozess,
der Puffer ist trotzdem die eine Stelle, die die Ausgabe hält, und die Konsole liest ihn. Das Tailen
der Dateien unter `.quartz-gui/logs/` kommt mit `buildService`. Gegenprobe: ohne Kappung scheitert
`capsPerProjectAndKind`.

### Sperren je Projekt (`projectLock.ts`, `styleLock.ts` → `ProjectLock`)

`ProjectLock.styles` und `ProjectLock.config`: je Projekt (`realpath`) ein Schreiber nach dem
anderen, ein späterer wartet, statt abgewiesen zu werden; wiedereintrittsfähig über einen
`@TaskLocal` (Gegenstück zu Nodes `AsyncLocalStorage`); der Fehler eines Vorgängers hält die
Schlange nicht an. Die Warteschlange ist eine Kette von Tasks, die nie scheitern, darum braucht es
QuartzControls schluckende `catch` nicht.

- **Die Falle aus QuartzControl gibt es auch hier, gemessen:** Ein `Task { }`, unter der Sperre
  gestartet, erbt den Task-Local und lief als Halter an der Schlange vorbei (`A start`, `late`,
  `A end`). Mit `Task.detached` wartet er wie jeder andere (`A start`, `A end`, `late`). Regel im
  Kopf von `ProjectLock`: Unter der Sperre wird nichts gestartet, das sie überlebt.
- Zwei Schreibweisen eines Ordners sind ein Schlüssel: ein Symlink und schon der temporäre Ordner
  selbst (`/var` → `/private/var`).
- **Gegenproben:** ohne `realpath`, ohne Wiedereintritt, ohne Warten auf den Vorgänger, eine Marke
  für alle Sperren statt je Sperre: jede lässt einen Test scheitern. Die erste Fassung der Frist im
  Test hing beim fehlenden Wiedereintritt, statt zu scheitern: Eine Task-Gruppe wartet am Ende auf
  jedes Kind, auch auf das hängende; die Frist lässt es jetzt zurück.
- Die dritte Schlange je Projekt (Snapshot-Store, `snapshotService.serialize`) kommt mit dem Dienst.

### Zeitstempel wie `toISOString()` (`JS.isoString`)

Was QuartzControl als Zeit in eine Datei schreibt (`addedAt`, `lastOpenedAt`, der Name einer
beiseitegelegten Datei), ist `new Date().toISOString()`: UTC, immer drei Stellen Millisekunden.
`Date.ISO8601FormatStyle(includingFractionalSeconds: true)` sieht gleich aus und ist es nicht,
gemessen gegen Node 24: Es schneidet die Gleitkommazahl ab, statt zu runden, aus
`1793000000.123` wurde `.122`, aus `-0.001` `.998` (Node: `.123`, `.999`). Ein JavaScript-Datum ist
eine ganze Zahl Millisekunden, also rundet `JS.isoString` zuerst darauf und setzt die Stellen selbst
an. Der Test hält fünf Werte gegen Nodes Ausgabe; mit der alten Fassung scheitern zwei.

### Projektliste (`projectStore.ts` → `ProjectStore`)

`projects.json` im Profil von QuartzHub, in QuartzControls Form (`ProjectEntry`: `id`, `name`,
`path`, `addedAt`, später `lastOpenedAt`), Schlüssel, die es nicht kennt, bleiben stehen, auch ein
Eintrag, der kein Objekt ist. Die Kennung bleibt beim Umziehen (`relocate`), denn Server, Reiter
und Relay-Geheimnisse hängen an ihr.

- **Ein Schreiber nach dem anderen.** Jede Änderung liest, ändert und schreibt die ganze Datei. In
  QuartzControl konnten sich zwei davon zwischen ihren `await` verschränken, hier laufen sie unter
  einem `Mutex` nacheinander. Gegenprobe: ohne ihn kamen von 64 gleichzeitig hinzugefügten Ordnern
  in drei von drei Läufen nicht alle in der Datei an.
- **Ein Ordner, eine Zeile, auch in der anderen Unicode-Form.** Swifts `==` vergleicht nach
  kanonischer Äquivalenz, also sind „Gärten“ mit vorkomponiertem und mit zerlegtem „ä“ ein Pfad,
  so wie APFS sie als einen Namen nimmt. QuartzControls `===` verglich Code-Einheiten. Groß- und
  Kleinschreibung zählt weiter, wie dort.
- Geschrieben wird nur, was sich ändert: ein `touch` oder `remove` mit unbekannter Kennung lässt die
  Datei, wie sie ist (QuartzControls `removeProject` schrieb dieselben Bytes neu).
- Was beim Hinzufügen und Umziehen sonst passiert (Frames umbiegen, Server stoppen,
  Relay-Geheimnisse löschen), gehört den Diensten, die es tun, und kommt mit ihnen.

### `.quartz-gui/` anlegen (`projectDirs.ts` → `QuartzGuiDirectory.create`)

Die eine Stelle, die den Ordner anlegt, und mit ihm die Zeile `.quartz-gui/` in der `.gitignore`
des Projekts, nur in einem Repository (`.git` als Ordner oder als Datei eines Worktrees) und nur,
wenn keine Zeile es schon sagt. Ob die Regel da ist, entscheidet die Regelzeile, nie der Kommentar
darüber; der Kommentar sagt jetzt „QuartzHub“, ein Projekt mit QuartzControls Zeile behält sie.

- **Gefunden beim Test, nicht in QuartzControl:** `split(separator: "\n")` trennt in Swift nicht
  bei `\r\n`, denn das ist dort *ein* Zeichen. Eine `.gitignore` mit Windows-Zeilenenden wäre eine
  einzige Zeile gewesen und hätte bei jedem Anlegen einen weiteren Block bekommen. Getrennt wird
  über `components(separatedBy:)`, der Test hat die Zeile mit `\r`.
- **Bytes statt Text:** QuartzControl las die Datei als UTF-8 und schrieb sie ganz zurück, ein
  Byte, das kein UTF-8 ist, kam als U+FFFD wieder. Hier bleiben die Bytes, der Block wird
  angehängt; gelesen als Text wird nur für die Prüfung. Eine `.gitignore`, die ein Symlink ist,
  bleibt einer (geschrieben wird an Ort und Stelle wie mit `writeFileSync`).
- JavaScripts `trim()` nimmt auch das BOM; die Prüfung tut es ebenso.
- Ein Testfehler auf dem Weg: Ein `Scratch`, an `_` gebunden, wird sofort freigegeben und sein
  Ordner gelöscht. Die Tests der Projektliste liefen trotzdem grün, weil das Schreiben den Ordner
  neu anlegte (und ihn liegen ließ). Den Ordner hält jetzt die Suite selbst: Swift Testing legt je
  Test eine eigene Instanz an.

### Projekt-Einstellungen (`projectPrefsService.ts` → `ProjectPrefsStore`)

`project-prefs.json` mit `outputDir`, gelesen ohne `.quartz-gui/` anzulegen, geschrieben über
`create()`. Geschrieben wird in das gelesene Objekt, ein späterer Schlüssel bleibt also stehen
(QuartzControl schrieb das Objekt des Renderers, das nur `outputDir` hatte). Die Golden-Datei aus
`gui-test` kommt byte-gleich zurück. `buildDirectory` ist `resolveBuildDir`; die sieben Fälle des
Tests sind Nodes Antworten auf dieselben Eingaben, darunter `../site` neben dem Projekt und ein
absoluter Pfad, der unverändert bleibt.

### Content-Ordner, lesender Teil (`contentService.ts`, `contentSymlink.ts` → `ContentFolder`)

`status` ist `getContentStatus`: über `lstat`, damit ein Link auf ein nicht eingehängtes Laufwerk
ein Link bleibt und nicht als „kein Ordner“ gilt; ein relatives Ziel wird vom Ordner des Links aus
aufgelöst; gezählt wird ohne Verstecktes und durch Links hindurch, ein Link auf einen schon
besuchten Ordner wird abgeschnitten, ein hängender zählt nicht; `hasIndex` fragt nur oben und ohne
Groß-/Kleinschreibung. `withSymlinkParked` ist `withContentSymlinkParked`: Link weg, Körper laufen
lassen, was git dort angelegt hat weg, Link mit dem Ziel in seiner geschriebenen Form zurück, auch
wenn der Körper scheitert.

- Gegenproben: ohne den Schnitt bei besuchten Ordnern zählt der Test zu viel (die Rekursion endet
  erst an `ELOOP`), ein relatives Ziel gegen das Arbeitsverzeichnis aufgelöst lässt den Test zum
  `../vault` dreimal scheitern.
- Noch nicht hier: Quelle wechseln (braucht Snapshot und Sicherung), Startseite anlegen und
  Formular-Verwendungen (brauchen Config und das globby des Projekts). Sie kommen mit Punkt 3 und 7.
