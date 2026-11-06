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

### Projektbild (`projectIconService.ts` → `ProjectIcon`)

`quartz/static/icon.png` bleibt das Projektbild und das Favicon, `icon-dark.png` das zweite Bild,
der Marker `project-icon.json` sagt, was gewählt wurde, `icon-original.png` hält, was „Entfernen“
zurückbringt. ImageIO statt `nativeImage`:

- PNG und JPEG (nach Endung), höchstens 512 px an der längeren Kante, immer PNG. Ein PNG, das
  passt, wird byteweise kopiert. **Ob es ein PNG ist, sagen die Bytes, nicht der Name:**
  QuartzControl kopierte jede `.png`, die passte, auch ein JPEG unter diesem Namen.
- `kCGImageSourceThumbnailMaxPixelSize` skaliert von sich aus nicht hoch, gemessen (40 × 30 bleibt
  40 × 30). Ein eigenes `min()` dafür ließ die Gegenprobe grün und ist wieder raus.
- Die EXIF-Ausrichtung eines Fotos wird angewandt (100 × 50 mit Ausrichtung 6 wird ein 50 × 100
  großes PNG; ohne `WithTransform` scheitert der Test). Was `nativeImage` damit tat, ist nicht
  gemessen.
- Ein SVG unter `.png` und eine Textdatei unter `.jpg` sind „nicht lesbar“, ein `.gif` und ein
  `.svg` „nicht unterstützt“; `icon.png`, Marker und Original bleiben dabei unberührt.
- Geschrieben wird atomar (ein laufender Dev-Server beobachtet `quartz/static`), der Marker ganz und
  in QuartzControls Reihenfolge; nichts mehr zu merken löscht ihn. Ein Marker von vor `customDark`
  gilt wie dort.
- Das Thumbnail hat 128 px, als PNG-Daten, im Speicher bis sich mtime oder Größe ändern.
  `hasUnrecordedIcon` vergleicht die git-Blob-ID mit der von Quartz; der Test nimmt Quartz' Bild
  aus der Geschichte von `gui-test` (nur lesend) und die Blob-ID gegen `git hash-object`.
- Gegenproben: Name statt Bytes, ohne Cache, das Original bei jeder Wahl neu verdrängt, ohne
  Ausrichtung: jede lässt einen Test scheitern.

### Projekt anlegen (`createService.ts` → `ProjectCreator`)

Dieselben Schritte wie in QuartzControl: `git clone` (voll, nicht `--depth 1`), `origin` weg,
`npm install`, `npx quartz create` mit jeder Antwort als Flag (`-t -X -l -b`, `-s` bei einer
Quelle), dann ein Aufwärm-Build. Erfolg ist die geschriebene `quartz.config.yaml`, nicht der
Exit-Code des Assistenten. Die Sätze vor dem gescheiterten Schritt sind QuartzControls.

- **Neu: Fristen.** QuartzControl gab keinem Schritt eine, ein Klon über eine stehende Verbindung
  wartete für immer. Hier: Klon 15 min, `npm install` 20 min, Assistent 5 min, Build 10 min,
  `git remote remove` 30 s. Großzügig gewählt, nicht gemessen; der Test hält, dass eine hängende
  Installation an ihrer Frist endet und das sagt.
- Die Quelle steht hinter `--` (`git clone -- <repo> <ziel>`), wie für Projektdaten üblich.
- Getestet gegen ein lokales Upstream mit zwei Commits und Stellvertreter für `npm`/`npx`, die
  ihre Argumente notieren. Gegenproben: mit `--depth 1` hat die Kopie einen Commit, ohne
  `remote remove` ein `origin`, Erfolg nach Exit-Code meldet den Assistenten ohne Config als
  gelungen: jede lässt einen Test scheitern.
- **Nicht gemessen:** der echte Weg über GitHub, npm und den Assistenten mit dem mitgelieferten
  Node. Der Test dafür steht bereit (`QH_NETWORK_TESTS=1 swift test --filter realQuartz`), lief
  aber noch nicht: Er lädt Quartz und seine Pakete aus dem Netz und führt sie aus, und das
  braucht die Freigabe des Nutzers.

### Config lesen und schreiben (`configService.ts`, `framePaths.ts` → `ConfigFile`, `FramePaths`)

Das YAML macht der Helfer `yaml-edit` mit demselben `yaml` 2.9.0 wie QuartzControl. Seine
Operation `write` ist `writeConfigNow`, Aufruf für Aufruf: `syncMapping` für `configuration` (ohne
`theme`) und `theme`, `doc.set('plugins', …)`, `layout.groups`/`byPageType` nur, wenn die Config
ein `layout` trägt, `lineWidth` 120. Swift macht, was darum liegt: Datei, Sperre
(`ProjectLock.config`), Frame-Pfade (`ownFramePath` vor dem Aufruf), die Sätze. Die Operationen
`set`/`delete` aus Phase 1 sind weg; kein Dienst von QuartzControl schrieb einzelne Pfade.

- **Gemessen gegen QuartzControls eigenen Code.** `scripts/config-golden.mjs` bündelt
  `configService.ts` mit esbuild (Snapshot und `mainT` als Attrappen) und lässt ihn 17 Fälle lesen,
  bearbeiten und schreiben: die Configs von `gui-test` und `Example` (Home maskiert), Randfälle,
  Fehler. `ConfigFileTests` macht dasselbe über `ConfigFile` und vergleicht Objekt und Bytes. Alle
  17 gleich. Ohne Änderung gespeichert sind `gui-test` (649 Zeilen) und `Example` byte-gleich.
- **Was JSON nicht trägt, war der erste Befund.** QuartzControl gab die Config über Electrons
  structured clone weiter; der erhält `.inf`, `.nan`, `-0` und geteilte Objekte. `toJS()` gibt
  einem Alias das Objekt seines Ankers, und yaml schreibt ein wiederholtes Objekt wieder als Anker
  und Alias. `Example` hat einen (`breakpoints: &a1` … `*a1`), und über JSON kam der Alias als
  Kopie zurück. Darum gibt `write` überall dort, wo der ankommende Wert genau das ist, was JSON aus
  dem Wert des Dokuments machte, dessen eigenen Wert zurück (`revive`). Ein geänderter Wert geht so
  hinein, wie er kommt.
- **Was QuartzControls Schreiber auch ohne Änderung umschreibt**, und QuartzHub daher ebenso:
  Kommentare in der Plugin-Liste und in jedem ersetzten Teilbaum fallen weg (`theme.colors` …),
  Flow-Listen werden zu Block-Listen, Anker unter `configuration` werden aufgelöst (jede `setIn`
  baut eigene Knoten), `0x1F` wird `0x1f`, lange Zeichenketten brechen bei 120 um, ein `name:` an
  einem Plugin-Eintrag verschwindet (der Renderer überschreibt ihn mit dem abgeleiteten Namen, das
  Speichern lässt ihn weg). Ein `enabled` wie `yes` oder `0` wird `true`/`false`. Nur für Hand
  geschriebene Dateien sichtbar; was die Quartz-CLI schreibt, hat keines davon.
- **Bewusst anders als QuartzControl:**
  - Ein Eintrag unter `plugins`, dessen `source` nichts nennt (fehlt, eine Zahl, ein Objekt ohne
    `repo` und `name`, ein bloßer String als Eintrag), bekommt einen Satz mit seiner Nummer
    (`main.configPluginEntryInvalid`). QuartzControl hielt an einem TypeError.
  - Ein Schlüssel mit der falschen Art Wert gilt als nicht da und bleibt beim Speichern, wie er
    ist: `layout:` leer (`null`) warf in QuartzControl beim Speichern `null.groups`;
    `configuration: ein Satz` wurde zu `{ 0: "e", … }` gespreizt und ließ sich nicht speichern.
    Wer dort trotzdem einen Schlüssel setzt, bekommt die Ablehnung des Helfers (keinen eigenen
    Satz; der Fall braucht eine kaputte Datei).
  - Atomar mit `fsync` (`JSONStore.writeAtomic`); QuartzControl benannte nur um.
- `ownFramePath` vergleicht wie Node die Schreibweise (`resolve`, kein `realpath`).
- Der Helfer läuft immer unter QuartzHubs Node und mit eigener Umgebung (`HOME`, `PATH`): ein
  `NODE_OPTIONS` aus dem Profil der Shell könnte sonst etwas in den Prozess laden. Fehlt er, heißt
  es `broken`, nicht `refused`. Ein Aufruf kostet rund 50 ms (`read` von `gui-test` 0,05 s, eine
  leere Datei 0,03 s, je Start ein neuer Node-Prozess).
- Gegenproben: ohne `revive` scheitern `Example`, die Anker- und die Sonderfälle; mit `name` im
  Geschriebenen alle Fälle mit Plugins; `enabled` nur als Bool statt JavaScript-Wahrheit die
  Sonderfälle; ohne `ownFramePath` der Frame-Test.
- **Noch nicht:** der Snapshot vor dem Speichern (`configChange`) kommt mit dem Snapshot-Store
  (Punkt 7). Bis dahin schreibt nichts in der App die Config.

### Pfade umbiegen (`projectPaths.ts` → `ProjectPaths`)

`repointProjectPaths(from:to:)` nach Duplizieren und Verschieben, `repointAuthoredFrames` nach einem
Restore, beim Hinzufügen und an der Bau-Tür. Dieselben drei Orte wie in QuartzControl: `source` der
Plugin-Einträge (über `ConfigFile`, Lesen und Schreiben unter der Config-Sperre), `source`/`resolved`
in `quartz.lock.json` (im Format der CLI mit Zeilenende am Schluss) und die Links unter
`.quartz/plugins/`, gegen ihren eigenen Ordner aufgelöst.

- **Gemessen gegen QuartzControls Code.** `scripts/paths-golden.mjs` lädt `projectPaths.ts` über
  dasselbe Bündel wie `config-golden.mjs` (`scripts/lib/qc-bundle.mjs`, `readLockfile` als dritte
  Attrappe) und lässt es fünf Bäume bearbeiten: eine Kopie mit Frame, lokalem Plugin, Pfaden
  außerhalb, `..x`, einem Link relativ zurück ins Original und einem toten Link; Frames nur
  teilweise vorhanden; ohne Config; kaputtes Lockfile; Lockfile mit Liste statt Objekt.
  `ProjectPathsTests` kommt in allen fünf auf dieselben Bytes und Link-Ziele.
- Übernommen, wie es ist: Ein Kind namens `..x` gilt als außerhalb (Nodes
  `relative(...).startsWith('..')`); ein Pfad wird mit `/./` und `../` normalisiert und ohne
  Schrägstrich am Ende geschrieben; eine kaputte Config beendet den Lauf, bevor Lockfile und Links
  drankommen.
- Gegenproben: `..x` als innen, Links gegen den Projektordner statt ihren eigenen, das Lockfile
  ohne Zeilenende, die Liste im Lockfile übergangen: jede lässt einen Fall scheitern.

### Duplizieren (`duplicateService.ts` → `ProjectDuplicator`, `TreeCopy`)

Dieselben Schritte und Sätze wie in QuartzControl: Quelle prüfen (Config da und lesbar, vor dem
Kopieren), Ziel leer, keine Verschachtelung in beide Richtungen, Inhaltsquelle da und das Ziel nicht
darin; dann kopieren ohne die `SKIP`-Liste, `ProjectPaths.repointProjectPaths`, `git remote remove
origin`, Content leer (eine `index.md`), kopiert oder verlinkt, `npm install`, und der
Core-Update-Vermerk verliert sein `installFailed` (`PendingInstall.afterInstallSucceeded`, in der
Form von `markInstallPending`).

- **Gemessen gegen QuartzControls Code.** `scripts/duplicate-golden.mjs` lädt `duplicateService.ts`
  (Attrappen: `runCommand` notiert und antwortet, `contentDirPath`, `readLockfile`,
  `noteInstallSucceeded`) und dupliziert ein Original mit jedem Eintrag der `SKIP`-Liste, Links,
  Rechten 0755/0600/0700, einem `node_modules` tiefer im Baum, dazu einen Vault mit Link. Zehn Fälle,
  davon sieben Ablehnungen und ein gescheitertes `npm install`. `ProjectDuplicatorTests` kommt in
  allen zehn auf denselben Baum (Eintrag für Eintrag mit Rechten, Link-Zielen, Inhalten), dieselben
  Aufrufe und dieselbe Antwort.
- `TreeCopy` ist `fs.cp` mit `filter` und `verbatimSymlinks`, so weit es hier zählt: Ein Link bleibt
  ein Link; ohne `verbatimSymlinks` (Inhalt kopieren) wird ein relatives Ziel absolut, wie in Node.
  Ein Ordner, den die Kopie anlegt, bekommt die Rechte des Originals. **Anders:** Dateien werden mit
  `COPYFILE_CLONE` geklont (APFS: kein Platz, keine Zeit) und behalten ihre Zeiten; Node schrieb
  neue.
- **Anders, mit Grund:** Liegt am Ziel eine Datei, heißt es „liegen bereits Dateien“; in
  QuartzControl warf `readdir` ENOTDIR. `npm install` hat die Frist aus `ProjectCreator` (20 min),
  `git remote remove` 30 s. Ein Fehler beim Kopieren ist eine Antwort mit Satz statt einer Ausnahme.
- Übernommen, wie es ist: Der Titel der leeren `index.md` steht ohne Anführungszeichen im
  Frontmatter (ein Ordnername mit „: “ ergäbe kaputtes YAML); `contentTargetInsideSource` nennt den
  Projektordner, obwohl der Satz vom Content-Ordner spricht. Beides notiert, nicht behoben.
- Gegenproben: `project-prefs.json` mitkopiert, Projekt-Links nicht wörtlich, Inhalts-Links
  wörtlich, ohne Rechte, ohne `repointProjectPaths`, ohne Vermerk: jede lässt einen Test scheitern.

### Was einem Klon fehlt (`projectDependencies.ts` → `ProjectDependencies`)

`missingDependencies` (Pakete aus `dependencies`, die `node_modules` nicht hat; nil, wenn
package.json unlesbar ist), `halfUnpackedModule` (der erste Ordner im Abhängigkeitsbaum ohne lesbare
package.json, Suche wie Node: eigener `node_modules`, dann aufwärts bis zum Projekt) und
`missingAuthoredFrames` (Frames der Config, deren Ordner fehlt und die `ownFramePath` nicht hierher
holt).

- **Gemessen gegen QuartzControls Code**, `scripts/deps-golden.mjs`, sieben Projekte mit 14 Fragen:
  verschachtelte und kaputte Pakete, ein Zyklus, ein Paket nur über dem Projekt, Frames hier, weg,
  hierher kopiert, anderswo. `ProjectDependenciesTests` gibt dieselben 14 Antworten.
- Übernommen, wie es ist: `dependencies` als Liste meldet `0`, `1` … als fehlend (`Object.keys`).
  Ein `@` am Anfang eines YAML-Werts (`source: @scope/a` ohne Anführungszeichen) macht die Config
  unlesbar und `missingAuthoredFrames` nil; das ist YAML, kein Fehler hier.
- `halfUnpackedModule` schützte in QuartzControl ein `require` im eigenen Prozess (Node merkt sich
  eine fehlende package.json bis zum Neustart). QuartzHub lädt kein Projektpaket in den eigenen
  Prozess; die Frage bleibt, weil sie „packt noch aus“ von „kaputt“ trennt.
- Gegenproben: ohne Suche nach oben, Suche über das Projekt hinaus, ohne `ownFramePath`, Listen ohne
  Schlüssel: jede lässt einen Fall scheitern.

### Plugin-Befehle der CLI (`pluginService.ts` → `PluginCommands`)

`quartz plugin add`/`remove`/`prune` und „Aus quartz.lock.json wiederherstellen“: erst `npm install`,
wenn Pakete fehlen, dann `quartz plugin install`; die Namen aus den „✗ name: …“-Zeilen gehen mit
(die CLI endet mit 0, wenn einzelne Plugins scheitern). Ein Lauf je Projekt (`realpath`), ein
zweiter Aufruf hängt sich an. Schalten und Optionen bleiben Config-Schreibvorgänge (`ConfigFile`),
weil die CLI sie für eingebaute Plugins stillschweigend nicht ausführt.

- **Gemessen gegen QuartzControls Code**, `scripts/plugins-golden.mjs`, neun Fälle: nichts fehlt,
  npm zuerst (vollständig und unvollständig), npm scheitert, keine package.json, CLI scheitert,
  `add`, `remove`, `prune`, mit farbiger und doppelter Ausgabe. `PluginCommandsTests` kommt mit
  Skripten für npm und npx auf dieselben Aufrufe, Ausgaben und Namen. Dazu: ein zweiter Aufruf
  während des Laufs startet kein zweites npm, einer danach einen neuen Lauf.
- `forgetDependencyErrors` des Build-Dienstes ist ein Rückruf (`afterPackagesInstalled`), bis
  `buildService` da ist (Punkt 4). Der Snapshot vor `add`/`remove` kommt mit Punkt 7.
- **Neu: Fristen** (20 min für alles, was klont oder installiert, 5 min für `remove`/`prune`).
- Notiert, nicht behoben: Quelle und Name gehen ohne `--` an die CLI, wie in QuartzControl; ein
  Wert mit führendem `-` würde als Option gelesen. Ob die Quartz-CLI `--` annimmt, ist nicht
  gemessen.
- Gegenproben: Farben nicht entfernt, Namen doppelt, `forget` auch bei unvollständigem npm, kein
  Anhängen, Ausgabe nicht getrimmt: jede lässt einen Test scheitern.

### Quartz' Plugin-Name (`shared/quartzPluginName.ts` → `PluginSource`)

`PluginSource` ist eine `source` in der Form, die QuartzControls Kanal `plugin.optionSchema`
annahm (zod: Text ohne führendes `-`, 1 bis 2048 Zeichen, oder ein Objekt mit `repo` und
optional `name`/`subdir`/`ref`); was zod abwies, wird gar keine `PluginSource`. `quartzName` ist
Quartz' `extractPluginName`, also der Name, unter dem `.quartz/plugins/<name>` liegt und gegen den
`exclude` vergleicht. Das ist nicht `PluginEntry.derivedName`: Eine npm-Quelle mit Scope bleibt ganz.

- **Gemessen gegen QuartzControls Code**, `scripts/option-schema-golden.mjs`, 41 Quellen: alle
  vier Formen, Schrägstriche am Ende, `#ref`, `.git`, `git+` mitten im Text, ein Zeilenumbruch am
  Ende, Windows-Pfade, Objekte mit und ohne Namen. `PluginSourceTests` gibt dieselben Namen.
- Die regulären Ausdrücke laufen über Unicode-Skalare (`matchingSemantics(.unicodeScalar)`), wie
  JavaScript eine Zeichenkette sieht; Swifts `$` passt wie in JavaScript nur am Ende (gemessen mit
  `"https://h/b\n"`).
- Gegenproben: nur ein Schrägstrich am Ende entfernt, `git+` nur am Anfang gestrichen: jede lässt
  einen Fall scheitern.

### Options-Schema: Normalisierer (`shared/pluginOptionSchema.ts` → `OptionSchema`)

Ein Normalisierer für JSON Schema, auf den configSchema, optionSchema, die `.d.ts`-Übersetzung und
die Vorgaben gebracht werden; dazu `applyDefaults`, `withPresentKeys`, `evaluate` (`x-quartz-when`)
und die Pfad-Helfer der Formulare. Unlesbares wird ein JSON-Feld mit Notiz, nie still weggelassen.

- **Gemessen gegen QuartzControls Code**, `scripts/option-schema-golden.mjs`, 26 Fälle, einer mit
  rund 100 Eigenschaften über jeden Zweig (`$ref` mit `$defs`/`definitions`/Escape, Zyklen,
  Tiefe über 16, jeder `x-quartz-*`-Schlüssel gültig und ungültig, Typlisten, `type: 5`), dazu
  Vorgaben, Werte aus der Config, 21 Bedingungen und die Pfad-Helfer. `OptionSchemaTests`
  vergleicht Byte für Byte.
- **Verglichen wird die kanonische Form** (`scripts/lib/option-schema-canon.mjs`): die Schlüssel
  eines Feldes in fester Reihenfolge. QuartzControl baut ein Feld je nach Weg in anderer Reihenfolge
  (ein Schema-Feld anders als ein abgeleitetes, ein Spread hängt `default` hinten an), und niemand
  liest sie; Swift hat ein Struct. Werte des Plugins (`default`, `when`) behalten ihre Reihenfolge.
- **Wo QuartzControl warf, antwortet QuartzHub mit einer Notiz:** Ein `$ref` mit kaputtem
  `%`-Escape warf einen URIError (jetzt „unresolvable $ref“), ein `$ref`, dessen Ziel wieder er
  selbst ist, lief in `annotationsOf` bis zum RangeError (jetzt „refers to itself“). Beide Fälle
  stehen in den Fixtures mit `throws`.
- Schlüssel sind eigene Schlüssel: QuartzControls `key in values` fand auch `constructor` auf jedem
  Objekt.
- Gegenproben: keine Duplikate entfernt, abgeleitete verschachtelte Felder mit falscher Herkunft,
  Annotation neben dem `$ref` verliert, Bedingung ohne Vorgabe, leere Elternobjekte bleiben,
  Verschachtelung nur unter der Config: jede lässt Fälle scheitern.

### Options-Schema: Leser (`pluginSchemaService.ts` → `PluginSchemaReader`)

Wo das Paket eines Plugins liegt (wie Quartz: npm unter `node_modules`, alles andere unter
`.quartz/plugins/<quartzName>`), was es über seine Optionen sagt (configSchema → optionSchema →
`.d.ts` → nur Vorgaben, die Vorgaben darüber), dazu der eingebaute Frame eines Page-Type-Plugins
und die theme.json eines Themes. Die `.d.ts` und die Einstiegsdateien liest der Helfer
`dts-schema` mit TypeScripts Parser; ausgeführt wird nichts.

- **Gemessen gegen QuartzControls Code**, `scripts/option-schema-golden.mjs`:
  - 40 Fragen an ein Projekt aus handgemachten Paketen: jeder Zweig der `.d.ts`-Übersetzung,
    Stimmen der Konstruktoren, das äußerste `…Options`, Zyklen, kaputte, zu große (1 MiB + 1),
    leere und fehlende package.json, Ordner statt Datei, Quellen aus dem Projekt hinaus.
  - 17 Page-Type-Fälle, darunter Lockvögel (`frame: null`, `"iframe"`), Kurzschreibweise,
    Template-Literal, Syntaxfehler und eine Kategorie als Text. Dazu 9 theme.json.
  - Die 64 Plugins, die gui-test verwendet (package.json und `.d.ts` kopiert nach
    `Fixtures/option-schema/real`, 1,9 MB, dazu die Einstiegsdateien von vier Page-Type-Plugins):
    configSchema 11, optionSchema 34, dts 1, nichts 18, dieselbe Verteilung wie QuartzControls
    `check:option-schema`.
  - `PluginSchemaReaderTests` gibt dieselben Antworten.
- **Ein Aufruf je Seite statt je Plugin.** Der Helfer kostet rund 130 ms (gemessen 127 ms für einen
  leeren Aufruf, fast alles das Laden von TypeScript). `optionSchemas` und `pageTypeFrames` fragen
  alles in einem Aufruf; ohne `dist/` gibt es keinen. Der Cache hängt an Größe und mtime von
  package.json und jeder `.d.ts`.
- **Abweichungen:**
  - Der Page-Type-Cache folgt den Dateien. In QuartzControl hielt er bis zum Neustart, weil
    `invalidateBuiltinPageTypeFrameCache` keinen Aufrufer hatte.
  - Ein unlesbarer `dist/`-Ordner oder ein Helfer, der nicht antwortet, ist ein Satz
    (`main.pluginSchemaTypesUnreadable`, neu) und wird nicht gemerkt. In QuartzControl war der
    erste Fall eine Ausnahme aus dem IPC-Handler.
  - Der Grund einer unlesbaren package.json steht in den Worten des Systems (`strerror`, die
    Meldung des JSON-Lesers), nicht in Nodes (`EISDIR: illegal operation …`). Verglichen wird
    deshalb nur „unlesbar, mit Grund“.
  - Was QuartzControl ungeprüft durchreichte, ist getypt: Die Listen einer theme.json behalten nur
    ihre Texte. Wo QuartzControl mit TypeError abbrach (`category: 5`, `main: 5`, eine package.json
    `null`), gibt es keinen Frame.
- Der Helfer bekam einen zweiten wortgleichen Block (`findPageTypeFrameLiteral`, `propName`).
  Beide Blöcke sind gegen `pluginSchemaService.ts` von QuartzControl 1.3.0 verglichen: identisch.
  Einzige Änderung auf dem Weg: JSON kennt kein Infinity, ein Literaltyp `1e999` kommt als
  `const: null` an.
- Gegenproben: das „..x“-Verhalten von `path.relative`, die Größengrenze um ein Byte, Kategorie
  als Text, Version aus dem falschen Feld, ein leeres configSchema gewinnt, `pageType` als Teilwort,
  ohne `exports`, Cache ohne `.d.ts`, eine Style-Settings-Id als Text, der falsche Satz: jede lässt
  Fälle scheitern.

### `qh-check option-schema` (`scripts/check-option-schema.mjs` → `OptionSchemaCheck`)

Wie viele Optionen je Plugin QuartzHub darstellen kann, gezählt gegen alles, was etwas über die
Optionen weiß (Config, Vorgaben, optionSchema, configSchema, gewählte Quelle), eingeteilt in Feld,
nur Text und unsichtbar. Dieselbe Tabelle und dieselben Sätze wie QuartzControls Skript, damit
beide gegen dasselbe Projekt laufen und Zeile für Zeile verglichen werden können. Der Leser wird
geladen, nicht nachgebaut, die Config wie im Skript als ganzer YAML-Wert gelesen (Einträge ohne
`source` gezählt und übergangen).

- **Gemessen an acht Projekten** (gui-test, Example, navigations-testprojekt,
  quartz-plugins-handbuch, QuartzControl-Handbuch, QuartzControl-Web, testmitcss, brain-handbuch;
  nur lesend, hinterland-history nicht): Die Tabelle ist jedes Mal byte-gleich mit
  `npm run check:option-schema`. Die `--dump`-Ausgabe, das ganze Schema jedes Plugins samt den
  Schlüsseln aus seiner Config, ist bei allen 475 Plugins in der kanonischen Form gleich. Der
  Vergleich ist gegengeprüft: Mit einem geänderten `hasDefault` oder `kind` meldet er das Plugin.
- Als Test im Repo: Das Golden-Skript lässt QuartzControls Skript über das handgemachte Projekt
  laufen (mit Config: Doppel, ausgeschaltet, ohne `source`, kaputte package.json, falsches
  Interface, ein unsichtbarer Schlüssel) und legt die Ausgabe nach `handmade/check.txt`.
- **Exit-Code:** 0, wie QuartzControls Skript, auch bei unsichtbaren Optionen (das ist eine Zahl in
  der Tabelle); 3, wenn ein Eintrag oder Paket nicht lesbar war.
- Ein Aufruf des Helfers für das ganze Projekt (den YAML-Leser nicht gezählt): gui-test in 0,36 s,
  QuartzControls Skript in 0,37 bis 0,41 s (gemessen je dreimal bzw. zweimal mit `time`).
- Gegenproben: `enabled` als „wahr“ statt „nicht falsch“, ohne Falsches-Interface-Satz, ohne
  Zählung kaputter package.json, Spaltenbreite, kein Unterschied Text/Feld: jede lässt den Test
  scheitern.

### Marktplatz (`marketplaceService.ts` → `Marketplace`)

Die Repositories der Organisation quartz-community und ihre READMEs, über die GitHub-API. Ein
Actor: Katalog 15 Minuten gehalten, ein fehlgeschlagener Abruf nie; wer während eines Abrufs
fragt, bekommt dessen Antwort; README als Rohtext mit Obergrenze 256 KiB, „hat keine“ (404) und
„GitHub antwortet nicht“ getrennt. Der Token kommt über eine Funktion, die vor jeder Anfrage
gefragt wird (bis `connectionsService` portiert ist, ohne Token: anonym).

- **Gemessen gegen QuartzControls Code:** `scripts/marketplace-golden.mjs` lädt
  `marketplaceService.ts` mit nachgestelltem `fetch`, `Date.now` und `getGithubToken` und
  zeichnet 19 Szenarien auf (Anfragen samt `Accept`/`Authorization`, Antworten): Katalog gut,
  leer, 403, 502, kein Netz, kein JSON, kein Array, 204, Token unlesbar, zwei Aufrufe zugleich,
  Grenze der 15 Minuten (900 000 ms noch gehalten, 900 001 nicht), „neu laden“ leert beide
  Caches; README gut, 404 gehalten, 403/kein Netz/500/204 nicht gehalten, leerer Text gehalten,
  genau an der Grenze (nicht abgeschnitten), ein Byte darüber, weit darüber, Grenze mitten in „ä“
  und „🎉“, ungültiges UTF-8. `MarketplaceTests` liefert dieselben Antworten über ein
  `URLProtocol` aus, in Stücken zu 1000 Bytes wie das Skript. Gleich in jedem Schritt, auch die
  U+FFFD an den Schnittstellen (Swifts `String(decoding:)` ersetzt wie `Buffer.toString`). Dazu
  32 Namen gegen QuartzControls zod-Regel für `owner/repo` (`marketplaceReadmeArgs`).
- **Gegen die echte API** (`QH_NETWORK_TESTS=1 swift test --filter theRealCatalog`, drei anonyme
  GET): 63 Repositories, 47 mit `quartz-plugin`, eines archiviert, wie QuartzControls Messung;
  README von explorer 2396 Bytes; ein Repository, das es nicht gibt, ist „hat keine“.
- **Frist:** `timeoutIntervalForResource` ist die ganze Anfrage samt Body, wie
  `AbortSignal.timeout` in QuartzControl. Ein eigenes Rennen mit `Task.sleep` war daneben
  überflüssig: Ohne es endete ein Kopf, der nie kam, und ein Body, der mittendrin stehen blieb,
  trotzdem an der Frist (gemessen mit 0,3 s, je etwa 0,4 bis 0,8 s), also ist es raus.
- **Abweichungen:** Der Katalog folgt `Link: rel="next"`, höchstens zehn Seiten zu hundert und
  nur auf derselben Origin (der Token reist mit). QuartzControl las nur die ersten hundert und
  hätte den Rest stumm verloren; ein Fehler auf einer weiteren Seite ist ein fehlgeschlagener
  Katalog. Ein Eintrag ohne Name, vollen Namen oder Adresse wird weggelassen, statt mit Lücken
  gelistet; bleibt keiner, ist der Katalog „nicht verfügbar“. Ein unzulässiger Name fragt nie an
  und ist „nicht verfügbar“ (in QuartzControl wies zod den Kanal ab).
- Gegenproben (14, jede lässt einen Test scheitern): Grenze der 15 Minuten mit `<`, README-Grenze
  um eins verschoben, 404 nicht gehalten, „nicht verfügbar“ gehalten, kein Zusammenlegen
  gleichzeitiger Abrufe, ohne Token-Kopf, `_` im Besitzer erlaubt, „neu laden“ ohne READMEs,
  strenges UTF-8, keine Folgeseiten, Folgeseite auf fremdem Host, falscher `Accept`, 204 mit Body,
  404 als „nicht verfügbar“; dazu die Frist: ohne die Grenzen der Sitzung scheitert der Test.

## Punkt 4: Build und Server

Vor dem Build und vor jedem Serverstart bereitet QuartzControl das Projekt vor
(`refreshAuthoredFrames`, `refreshGoogleFonts` in `buildService.ts`): Pfade zu den Frames
umbiegen, alle Frames neu schreiben, die verwalteten Stil-Blöcke reparieren, Schrift-Adressen
umstellen, Google-Schriften auffrischen. Bis auf das Umbiegen (`ProjectPaths`) liegt das in
`layoutFrameService`, `styleService` und `fontService`, also in Punkt 5. Entschieden am
2026-11-06 (Nutzer): Punkt 4 zuerst, mit einer ausdrücklichen Liste von Vorbereitungsschritten,
in die Punkt 5 seine Schritte einträgt. Bis dahin baut QuartzHub mit den Frames, die zuletzt
geschrieben wurden; eine Oberfläche, die bauen lässt, gibt es vor Phase 4 nicht. Die Fragen beim
Start (verwaiste Server) und beim Beenden kommen mit Punkt 4 in die App, nicht erst in Phase 4.

### Prozessstarter, zweiter Teil (`ProcessRunner.run(onOutput:)`, `ProcessRunner.launch`)

- **Ausgabe während des Laufs.** `run` reicht stdout und stderr auf Wunsch stückweise weiter, für
  die Konsole des Builds; die Antwort bleibt, wie sie war (wartet auf das Schließen beider Pipes).
  Ein Zeichen, das eine Lesegrenze zerschneidet, wartet auf sein Ende (`UTF8Stream`).
  QuartzControls Build-Konsole nahm `chunk.toString()` und zeigte dort zwei U+FFFD statt „ä“; nur
  der Tail der Server-Logs hatte einen `StringDecoder`. Die Stücke ergeben zusammen genau
  `String(decoding:)` über alles: 5000 Zufallsfolgen aus den Rändern von UTF-8 (jedes Lead-Byte,
  die Grenzen des zweiten Bytes nach E0/ED/F0/F4, Folgebytes, nie gültige Bytes), zufällig in
  Stücke von 1 bis 4 Bytes geteilt. Zurückgehalten wird nur, was noch ein Zeichen werden kann
  (E0 80 nie).
- **Ein Prozess, auf den keiner wartet** (`launch`, für den Dev-Server): stdout und stderr in
  Dateien, die der Aufrufer öffnet und gleich wieder schließt, stdin /dev/null, eigene
  Prozessgruppe. QuartzControl startete den Server ohne `detached`, also in Electrons Gruppe, und
  beendete ihn mit `tree-kill`. Hier erreicht ihn ein Signal an die Gruppe der App nicht, und
  `stop` erreicht die ganze Gruppe des Servers.
  Abgeholt wird er von einem eigenen Thread mit `waitpid`, also nie ein Zombie.
- **`stop` wartet auf die Gruppe, nicht nur auf den Prozess:** SIGTERM an die Gruppe, SIGKILL an
  den Rest nach der Frist. Gemessen mit einer Shell, die auf SIGTERM endet, und einer Subshell,
  die es ignoriert (wie ein node unter npx): Ohne das Warten auf die Gruppe überlebte die
  Subshell den Stopp.
- Gegenproben (5, jede lässt einen Test scheitern): kein Zurückhalten (2 Tests, 1864 Befunde),
  ohne Prüfung des zweiten Bytes, kein Rest am Ende des Stroms, ohne eigene Prozessgruppe
  (8 Tests; die Schleife, die SIGTERM ignoriert, lief dann ohne Ende, bis sie von Hand beendet
  wurde), `stop` wartet nur auf den Prozess.

### Laufende Server merken (`runningServersStore.ts` → `RunningServersStore`)

- QuartzHubs eigene `running-servers.json` im eigenen Profil, in QuartzControls Form
  (`{pid, port, startedAt}` je Projekt-ID). QuartzControls Datei liest weiter nur `Coexistence`.
- **Gemessen gegen QuartzControls Code:** `scripts/running-servers-golden.mjs` lädt
  `runningServersStore.ts` mit nachgestelltem `app.getPath` und zeichnet sieben Szenarien auf, je
  Schritt die Antwort, den Text der Datei und wie viele Dateien beiseitegelegt wurden: eintragen,
  überschreiben (die Reihenfolge der Schlüssel bleibt), entfernen, Unbekanntes entfernen (schreibt
  nichts), `takeAll` zweimal; keine Datei (`takeAll` schreibt `{}`, wie dort); fremde Einträge
  und Nicht-Objekte bleiben, wie sie sind; kaputtes JSON, leere Datei, `null` und eine Liste werden
  beiseitegelegt. Gleich in jedem Schritt, byte-gleich.
- **Abweichungen:** Jede Änderung liest, ändert und schreibt unter einer Sperre (dort liefen die
  Schreibvorgänge mit `void` durcheinander; gemessen mit 64 gleichzeitigen Einträgen, alle in der
  Datei). `remove` nimmt auf Wunsch eine PID und lässt dann den Eintrag eines neueren Starts
  desselben Projekts stehen; dort hielt nur die Map in `forgetServer` diese Regel.
- Gegenproben (4, jede lässt einen Test scheitern): `takeAll` schreibt nur, wenn etwas da war;
  `remove` übergeht die PID; ohne Sperre; Unlesbares wird nicht beiseitegelegt.

### Ausgabeordner prüfen (`buildOutputGuard.ts` → `BuildOutputGuard`)

- `quartz build --output` beginnt mit `rm(output, { recursive: true, force: true })`
  (`quartz/build.ts:79`, gelesen in gui-test). Abgelehnt werden das Projekt, ein Ordner, der es
  enthält, das Home und alles in `content`, `quartz`, `.git`, `.quartz-gui`, `.quartz-cache`,
  `node_modules`; ein Ordner mit etwas anderem als einem Build wird erst nach Rückfrage geleert.
- **Gemessen gegen QuartzControls Code:** `scripts/build-output-golden.mjs` legt 44 Fälle unter
  einem frischen Ordner an (HOME gestellt) und zeichnet `assessOutputDir` auf, dazu sechs Fälle
  von `looksLikeQuartzBuild`: fehlt, leer, `""`, gebaut, nur `index.html`, mit `404.html`/
  `index.xml`/`sitemap.xml`, Notizen, eine Datei, `.`/`./`/absolut, `..`, `/`, Home mit und ohne
  Schrägstrich, elf geschützte Pfade, vier ähnliche, die es nicht sind (`contents`,
  `content-old`, `.quartz-gui-x`, `quartz2`), ein Nachbar mit gleichem Anfang, ein unlesbarer
  Ordner. Gleich in jedem Fall bis auf die sieben unten.
- **Abweichung, gemessen:** QuartzControl verglich die Pfade als Text. Unter APFS ist „Content“
  aber `content`, und ein Pfad durch einen Symlink erreicht dessen Ziel. Dort fragte es nur
  „2 Einträge?“, und Quartz' `rm` hätte nach einem Ja die Notizen gelöscht: gemessen mit Node 24,
  `rm("CONTENT/sub")` entfernte `content/sub`, `rm` auf einen Link nur den Link. QuartzHub prüft
  die Ablehnungen auch am echten Pfad (`realpath` des längsten vorhandenen Teils, der Rest
  angehängt) und lehnt in sieben Fällen ab, wo QuartzControl fragte: `Content`,
  `NODE_MODULES/x`, das Home in anderer Schreibweise, ein Link auf `content`, ein Pfad unter so
  einem Link, ein Link aufs Home, ein Link aufs Projekt. Dazu ein neuer Ordner hinter einem Link
  auf `content` (dort schriebe der Build die Website in die Notizen).
- Ein unlesbarer Ordner ist weiter „ok“: Quartz' `rm` kann ihn ebenso wenig auflisten, der Build
  endet mit dessen Fehler, bevor etwas weg ist.
- `ProjectPrefs.buildDirectory` nimmt jetzt dieselbe Funktion (`BuildOutputGuard.buildDirectory`).
- Gegenproben (6, jede lässt einen Test scheitern): nur der geschriebene Pfad, Präfix ohne „/“,
  `index.html` allein als Build, Home vor „enthält das Projekt“, kein Gang hinauf zum vorhandenen
  Teil, eine Datei als „ok“.

### Laufende Server finden (`serverDiscovery.ts` → `ServerScan`)

- Findet Quartz-Dev-Server, wer sie auch gestartet hat: Prozesstabelle (`ps -ww -Ao
  pid=,ppid=,etime=,command=`), die Ports aus den Argumenten oder, ohne `--port`, aus `lsof`, der
  Ordner aus `lsof -d cwd`, dazu eine HTTP-Probe (Titel, `generator`-Meta) und TCP-Proben für die
  Ports, nach denen gefragt wurde. „Kann nicht prüfen“ bleibt eine eigene Antwort: `unavailable`
  ohne `ps`, `partial`, wenn für einen Kandidaten `lsof` fehlte oder scheiterte.
- **Gemessen gegen QuartzControls Code:** `scripts/server-discovery-golden.mjs` lädt
  `serverDiscovery.ts` mit nachgestellten `execFile` (ps, lsof), `net`, `http`, `tree-kill`,
  `projectStore`, `buildService` und `Date.now` und zeichnet zwölf Szenarien auf: ein Server der
  App über npx (zwei Prozesse, einer gelistet), einer aus dem Terminal ohne Flags (8080/3001 aus
  `lsof`), ohne Flags auf anderem Port oder ohne Port (weggelassen), `lsof` fehlt oder meldet etwas
  (`partial` mit Grund), die Nadeln (`QuartzProjekte` mit großem Q, `--serve=yes`, `--serves`,
  `--SERVE --PORT`, `--port=`, Ports 0, 70000, 81370, doppelte Leerzeichen), `etime` in allen
  Formen und unlesbar, ein Prozess als eigener Elternteil, ein Zyklus in der ppid-Kette (zwei
  Einträge, wie dort), die HTTP-Probe (Groß geschriebene Tags, leerer Titel, Zeitablauf, Abbruch
  nach dem Kopf, Titel erst nach 64 KiB, kein schließendes Tag, `<` im Titel), belegte Ports, `ps`
  fehlt; dazu `killServer` für den eigenen Server, einen fremden, den Listener statt der Wurzel,
  etwas ohne Nadeln, eine PID, die es nicht gibt, ein Signal, das scheitert. Gleich in jedem
  Szenario, auch in der Zahl der `lsof`-Aufrufe (ein Server mit `--port` kostet keinen für Ports).
- **Am echten System:** ein `sh` mit beiden Nadeln in der Kommandozeile, darunter `python3 -m
  http.server` und ein `sleep`. Gefunden mit Port, Ordner (über `lsof`), Titel und Generator;
  `stop` beendet die Shell und ihre Kinder (SIGTERM an den Baum aus der eben gelesenen Tabelle,
  wie `tree-kill`). Die TCP-Probe gegen einen eigenen Listener, offen und geschlossen.
- **Abweichung:** Ein Projekt wird auch über seinen echten Pfad erkannt (über einen Symlink
  eingetragen, andere Schreibweise); dort nur über den Text des Pfads, `lsof` nennt aber den echten
  Ordner.
- **Offen:** Ob ATS im App-Bundle die HTTP-Probe auf `127.0.0.1` zulässt, ist nicht gemessen. Die
  App ruft den Scan noch nicht auf. Gemessen wird das mit der ersten Oberfläche, die ihn zeigt
  (oder mit der Vorschau, die dieselbe Frage hat).
- Nebenbei gefunden, im eigenen Test: Ein `close` auf einen schon geschlossenen Deskriptor traf
  die Pipe eines parallel laufenden Tests, der dann „abgebrochen“ meldete. Der Test schließt jetzt
  einmal.
- Gegenproben (10, jede lässt einen Test scheitern): Nadel ohne Kleinschreibung, `--serve` als
  Teilwort, der erste statt des tiefsten Prozesses als Listener, 8080 ohne Bestätigung, `lsof`s
  Exit 1 als Fehler, auch erklärte Ports geprüft, kein neuer Blick vor dem Signal, keine Grenze für
  die Seite, Projekt nur über den Text, nur die Wurzel signalisiert.

### Build (`buildService.ts`, erster Teil → `BuildService`, `BuildActivityTracker`)

- **Ein Actor für alle Projekte**, der hält, was läuft: Aktivität je Projekt (`build`, `serve`,
  `rebuild` mit Phase), laufende Builds, Konsole (in `LogBuffer` und als Ereignis). „Jetzt bauen“
  ein zweites Mal in denselben Ordner hängt sich an den laufenden Build; in einen anderen Ordner
  wird abgelehnt, mit dem Satz `buildDirBusy`. Fehlen npm-Pakete, gibt es den Satz
  `dependenciesMissing` und keinen Lauf. Vor dem Lauf die Vorbereitungsschritte (bis Punkt 5 nur
  `repointAuthoredFrames`, siehe oben); was sie melden, steht in der Konsole vor Quartz' Ausgabe.
  `assertOutputFree` (der Server schreibt in denselben Ordner) kommt mit dem Server.
- **Gemessen gegen QuartzControls Code:** `scripts/build-activity-golden.mjs` lädt
  `buildService.ts` und macht dabei `followQuartzOutput` und `setActivity` beim Bündeln sichtbar
  (`qc-bundle.mjs` hat dafür `expose`; die Datei bleibt, wie sie ist). Zwölf Szenarien,
  aufgezeichnet je Schritt die Aktivität und die gesendeten Ereignisse: der Build mit seinen
  Phasen, der weiche und der harte Rebuild, ein gescheiterter Rebuild, der erste Build des
  Servers, viele Zeilen in einem Stück, ein Rebuild ersetzt einen, ein Rebuild neben einem Build
  (still), dieselbe Phase noch einmal (kein Ereignis), „Filtered out“ nur mit Zahl, Farbcodes.
  Gleich in jedem Schritt bis auf zwei.
- **Abweichung:** Eine Zeile wird gelesen, wenn sie ganz ist. QuartzControl prüfte jedes Stück
  für sich; „Emitting files“ oder ein Farbcode, die über eine Lesegrenze fallen, bewegten dort
  nichts. Das Ende einer Quelle liest den Rest ohne Zeilenumbruch.
- **Gegen einen nachgestellten `npx`** (druckt Quartz' Zeilen, eine über zwei Schreibvorgänge
  geteilt): Phasen `preparing` → `parsing` → `emitting` → keine, stdout und stderr getrennt und in
  der Reihenfolge, ein Lauf für zwei gleichzeitige Aufrufe in denselben Ordner (`dist` und
  `./dist/`), Ablehnung für einen anderen Ordner, während ein anderes Projekt baut, Exit-Code 3,
  ein Signal ergibt keinen Code (wie Nodes `code: null`), `npx` fehlt (`spawn npx ENOENT` in
  stderr), Vorbereitungsschritte in Reihenfolge vor der Ausgabe.
- **Gegen das echte Quartz** (`QH_QUARTZ_TESTS=1`): `quartz build` einer APFS-Kopie von gui-test
  (`cp -cR`, mit node_modules) unter der Node-Laufzeit aus `Runtime/`: gelungen in 13,7 s,
  dieselben vier Phasen, `public/` ist danach ein Quartz-Build.
- Gegenproben (10, jede lässt einen Test scheitern): jedes Stück für sich gelesen, Build-Ausgabe
  bewegt jede Aktivität, ein Rebuild neben dem Build spricht, „Done rebuilding“ löscht jede
  Aktivität, kein Ordnervergleich beim Anhängen, kein Anhängen, keine Prüfung der Pakete, nur der
  erste Vorbereitungsschritt, ein Signal als Exit-Code, Aktivität bleibt nach dem Build stehen.
  Die beiden zum Anhängen hingen anfangs, statt zu scheitern (der erste Build wartete auf eine
  Freigabe, die der Test erst nach der Erwartung gab); der Test gibt jetzt nach spätestens 3 s
  frei.

### Dev-Server (`buildService.ts`, zweiter Teil → `BuildService`, `ServerPorts`, `ServerLogFiles`, `LogTail`)

- **Start:** sofort `starting` (sonst bot die Seite während des Wartens wieder „Starten“ an, und
  zwei Klicks starteten zwei Server). Läuft ein Build nach `public/`, wartet der Start auf ihn und
  sagt es (`serverWaitsForBuild`); „Stoppen“ während des Wartens sagt den Start ab. Dann die
  Vorbereitung, dann in einer Warteschlange für die Ports: Läuft für dieses Projekt ein Server,
  den QuartzHub nicht gestartet hat (Terminal, QuartzControl, ein Rest nach Absturz), wird
  abgelehnt (`serverAlreadyRunningOutside`, auf „QuartzHub“ umgestellt), ein zweiter würde
  denselben `public/` leeren. Fehlende Pakete sind ein Fehler mit Satz, bis `npm install` sie
  holt (`forgetDependencyErrors`). Mit Remote-Dev-Host wird ein belegter Port abgelehnt statt
  verlegt (der Tunnel reicht genau diese Ports weiter). Sonst rückt ein belegter Port auf den
  nächsten freien, die Konsole sagt wohin; die Ports der eigenen anderen Server zählen ohne
  Nachfrage als belegt.
- **Frei** heißt: Bind auf die Wildcard-Adresse (Dual-Stack, `SO_REUSEADDR` wie Node) gelingt
  *und* auf 127.0.0.1 und ::1 antwortet niemand. Gemessen: Ein Listener nur auf 127.0.0.1 ließ
  den Wildcard-Bind zu und wäre ohne die zweite Frage als frei durchgegangen.
- **Ausgabe in Dateien** unter `.quartz-gui/logs/`, je Lauf ein Paar mit der PID im Namen
  (erst unter `tmp-<ms>`, nach dem Spawn umbenannt), getailt alle 200 ms über einen eigenen
  Deskriptor und `UTF8Stream`. Vor dem Öffnen werden die Dateien beendeter Läufe entfernt, die
  eines noch laufenden Servers bleiben (PID lebt und ist ein Quartz-Server). Lässt sich nichts
  schreiben, läuft der Server ohne Konsole und sagt das (`serverLogUnavailable`).
- **„läuft“** erst, wenn der Seitenport antwortet *und* Quartz' Zeile „Started a Quartz server
  listening at http://localhost:<port>“ kam, oder ohne die Zeile, sobald auch der WebSocket-Port
  offen ist; nach 5 s ohne beides sagt die Konsole, worauf gewartet wird (`serverWaitsForWsPort`,
  auf „QuartzHub“ umgestellt). Keine Frist: Ein erster Build kann Minuten dauern.
- **Ende:** Stirbt der Server von selbst, bleibt `error` mit seinem Ende stehen (Exit-Code oder
  Signal). Eingetragen in `running-servers.json` beim Spawn, entfernt beim Ende, nur der Eintrag
  dieses Prozesses. **Stoppen** schickt SIGTERM an die Prozessgruppe und SIGKILL an den Rest nach
  `stopGrace` (5 s); QuartzControl schickte nur SIGTERM über `tree-kill`. **Neustart** wartet bis
  zu 3 s, bis beide Ports frei sind, und startet mit denselben Optionen.
- **Build und Server teilen sich `public/`:** „Jetzt bauen“ nach `public/` wird abgelehnt,
  solange der Server dorthin schreibt oder sein Start darauf wartet (`buildDirServerRunning`);
  in einen anderen Ordner geht es.
- **Gegen einen nachgestellten Server** (`Fixtures/fake-quartz-server.py`, Python, beantwortet
  HTTP und hält den WebSocket-Port; über eine Datei: stirbt, ohne Zeile, ohne Zeile und
  WebSocket): Start, „läuft“, Eintrag in `running-servers.json`, Logdatei mit PID, Konsole,
  Aktivität `serve`, Stopp samt Prozess und Eintrag; belegter Port rückt, zweites Projekt nimmt
  andere Ports, auch gleichzeitig; Tunnel lehnt ab; fehlende Pakete; ein fremder Server desselben
  Projekts (über den echten Scan gefunden) wird genannt; Build und Server nacheinander auf
  `public/`; Absage eines wartenden Starts; Tod mit Exit 2; ohne `npx`; ohne Logdatei; ohne
  Zeile; nur der Seitenport (bleibt `starting`, Satz nach 5 s); Aufräumen der Logdateien; zwei
  Klicks ein Server; Neustart mit denselben Ports.
- **Gegen das echte Quartz** (`QH_QUARTZ_TESTS=1`): `quartz build --serve` einer APFS-Kopie von
  gui-test, „läuft“ nach 14,0 s, die Seite trägt das Generator-Meta; `stop` beendet npx und das
  node-Kind darunter, der Port ist danach frei.
- Gegenproben (11, jede lässt einen Test scheitern): der Seitenport allein gilt als „läuft“,
  keine Warteschlange für die Ports, ein wartender Start zählt nicht für `public/`, kein Warten
  auf den Build, kein Abbruch-Check nach dem Warten, keine Prüfung auf einen fremden Server
  desselben Projekts, keine Tunnel-Regel, ein Ende von selbst liest sich als „gestoppt“, kein
  Eintrag in `running-servers.json`, Logdateien nie aufgeräumt, der WebSocket-Port darf auf den
  Seitenport fallen. Zwei davon (Abbruch-Check, WebSocket-Port) fing anfangs kein Test; der Test
  der Absage zählt jetzt die Vorbereitung, ein neuer Test lässt die Seite auf den erbetenen
  WebSocket-Port rücken.

### Beenden und verwaiste Server (`killAllServers`, `detectOrphanedServers` → `BuildService.stopAllServers`, `OrphanedServers`)

- **Beim Beenden** (wenn die Antwort „Server beenden“ ist): jeder wartende Start wird abgesagt,
  jeder Server gestoppt (SIGTERM an die Gruppe, SIGKILL nach 2 s), insgesamt höchstens 3 s. Ein
  Stopp, der nicht antwortet, hält die App nicht fest; was überlebt, bleibt in
  `running-servers.json` und ist die Frage beim nächsten Start. Gemessen mit einem Server, der
  SIGTERM ignoriert: zurück nach rund 0,5 s (Frist im Test), der Server lebt, sein Eintrag bleibt.
- **Beim Start:** verwaiste Server sind die eingetragenen, deren PID lebt und noch ein
  Quartz-Server ist; die Datei wird dabei geleert, gleich was geantwortet wird (wer „Weiterlaufen
  lassen“ sagt, wird nicht noch einmal gefragt). „Beenden“ fragt die PID unmittelbar vor dem Signal
  noch einmal und schickt SIGTERM an die Prozessgruppe (QuartzHub startet jeden Server als deren
  Kopf; QuartzControl lief `tree-kill`). Gemessen: ein nachgestellter Server wird gefunden, ein
  `sleep` unter einer eingetragenen PID und eine PID, die es nicht gibt, nicht; nach dem Leeren ist
  die zweite Abfrage leer; mit „PID hat inzwischen gewechselt“ geht kein Signal hinaus.
- `SettingsFile.serversOnQuit` ist jetzt auch schreibbar (für „Nicht mehr fragen“).
- Gegenproben (5, jede lässt einen Test scheitern): Datei nicht geleert, jede eingetragene PID
  zählt, kein zweiter Blick vor dem Signal, keine Frist beim Beenden, wartende Starts laufen weiter.

### Die Fragen in der App (`index.ts` `promptForOrphanedServers`, `before-quit` → `App/Shell/ServerLifecycle.swift`)

- `AppServices` hält einen `BuildService` für die ganze App (Umgebung einmal aufgelöst, die
  Node-Einstellung beim Start gelesen), `AppDelegate` stellt die beiden Fragen.
- **Beim Start**, nach dem Fenster: die verwaisten Server, je Zeile Projektname und Port. Erster
  Knopf und Return ist „Weiterlaufen lassen“, der zweite „Beenden“. QuartzControl hatte „Beenden“
  vorn (`defaultId: 0`); die Regel „die sichere Antwort zuerst“ gilt hier.
- **Beim Beenden**, wenn Server laufen: `applicationShouldTerminate` antwortet `.terminateLater`
  und fragt (oder nimmt die gespeicherte Antwort aus `serversOnQuit`): „Abbrechen“ (erster Knopf),
  „Weiterlaufen lassen“, „Server beenden“, dazu „Nicht mehr fragen“, das die geklickte Antwort
  speichert. Ein zweites Cmd+Q, während die Frage offen ist, öffnet keine zweite.
- **Gemessen im UI-Test** (`UITests/ServerQuestionsTests.swift`, Debug-Argument
  `-QHStartServerFor <projekt>`, echter `quartz build --serve` einer Kopie von gui-test, eigenes
  Profil über `-QHProfileDir`): Cmd+Q zeigt die Frage mit „ui-gui-test — Port 8080“; Escape
  schließt sie und die App bleibt (gemessen, nicht angenommen: Escape trifft „Abbrechen“);
  „Weiterlaufen lassen“ beendet die App, der Server antwortet weiter; der nächste Start fragt nach
  ihm, „Beenden“ beendet ihn, der Port ist danach zu, `running-servers.json` leer; der Start
  danach fragt nicht mehr, und Cmd+Q beendet ohne Frage. macOS 27 stapelt die Knöpfe des NSAlert
  untereinander und gibt ihnen eigene Kennungen (`action-button-1` …), daher sucht der Test sie
  über die Beschriftung. Die UI-Automation verlangte einmal die Bestätigung des Nutzers.
- Gegenproben (4, jede lässt den UI-Test scheitern): keine Frage beim Start, keine Frage beim
  Beenden, „Weiterlaufen lassen“ stoppt die Server doch, „Beenden“ bei verwaisten Servern tut
  nichts. Der Rauchtest (`SmokeTests`, drei Tests) läuft mit dem neuen Delegate weiter grün.

### Wackelige Server-Tests (nach Punkt 4)

- Beim Gesamtlauf nach dem App-Commit scheiterten zwei Prüfungen in `BuildServerTests`; in
  Schleifen von 12 bis 20 Läufen der Server-Suiten (sie laufen parallel) waren es zunächst vier
  verschiedene Tests. Behoben, je mit Ursache:
  - Ports aus dem kurzlebigen Bereich des Systems: Ein Test, dessen Server auf „den nächsten
    freien“ rückte, traf den Port, den ein anderer gerade bekommen hatte. Jetzt bekommt jeder
    Aufruf einen eigenen Block von zehn Ports unterhalb davon.
  - Der Test-Listener nahm nichts an: Nach einigen Proben war seine Warteschlange voll, die nächste
    Probe lief in ihre Frist und las „frei“. Er nimmt jetzt an wie ein Server und wird mit
    `shutdown` beendet.
  - Der „sture“ Nachbau-Server bekam SIGTERM, bevor Python es ignorierte; er ignoriert es jetzt
    vor der Zeile, auf die der Test wartet.
- **Nicht erklärt:** Ein Port, der eben geschlossen oder geprüft wurde, liest sich unter der Last
  der parallelen Tests gelegentlich kurz falsch (offen ohne Listener, `lsof` leer, eine
  blockierende Verbindung im selben Moment scheitert; einmal belegt statt frei). Allein
  nachgestellt in 1000 Durchgängen nie. Geprüft und verworfen: doppeltes `close` (keins gefunden),
  `FileHandle.nullDevice` (hat keinen Deskriptor), EINTR oder Zeitablauf im `poll` (in zehn Läufen
  nie). Die Tests warten dort bis zu 1 s bzw. prüfen nur, dass der WebSocket-Port weiter oben
  liegt. Übrig: etwa ein Fehlschlag in 20 bis 30 Läufen der Server-Suiten. Im Betrieb hieße es,
  dass ein Server einmal einen Port weiter rückt (und das sagt).

## Punkt 5: Stile und Layout

Entschieden am 2026-11-06 (Nutzer): drei Teile in einem Zug. 5a, was der Build braucht (Frames,
verwaltete Stil-Blöcke, Google-Schriften als Schritte der Vorbereitung), 5b die Stile-Seite
(Stylesheets, Import-Reihenfolge, Zusammenlegen, SCSS-Prüfung, Variablen-Graph), 5c der Rest
(Snippets, SVG-Bereiniger, Style Settings, Presets, Theme-Marktplatz). Sass läuft über einen
eigenen JS-Helfer `sass-check` mit dem Sass des Projekts; die Gegenprobe des SVG-Bereinigers in
WebKits HTML-Parser als `qh-check inline-svg`; echte Netzläufe (Google, GitHub) werden einzeln
gefragt. Die Sperre der Stylesheets (`styleLock.ts`) gab es schon seit Punkt 1
(`ProjectLock.styles`).

### Frames (`layoutFrameService.ts`, `shared/gridFrameCss.ts` → `LayoutFrames`, `GridFrameCss`, `GroupLayouts`, `FrameDefinitionCheck`, `FrameModule`)

- **Byte-gleich mit QuartzControl, weil beide Apps dieselben Dateien vor jedem Build neu
  schreiben.** Wer ein Projekt abwechselnd in beiden öffnet, sähe sonst bei jedem Wechsel eine
  Änderung an `frame.json`, `package.json` und `dist/frames.js`. Deshalb arbeitet der Port auf der
  Definition als JSON (Reihenfolge der Schlüssel, unbekannte Schlüssel), und das Modul ist eine
  wörtliche Abschrift aus QuartzControls Ausgabe mit vier Platzhaltern (`FrameModule`, in einem
  Durchgang eingesetzt, damit ein Frame-Name „@@AREAS@@“ ein Name bleibt).
- **Gemessen gegen QuartzControls Code:** `scripts/layout-frames-golden.mjs` lädt
  `layoutFrameService.ts` (Config und CLI nachgestellt) und `gridFrameCss.ts` und zeichnet auf:
  17 Projekte durch `writeAllFrames` (die fünf Frames von gui-test und zwei von Example, nur
  gelesen, mit ihrer echten Config; dazu eigene Breiten, kaputte Breiten-Datei, unlesbare Config,
  ein Name mit Anführungszeichen und `</script>`, Spuren und Linien-Namen, schiefe Werte, das alte
  Format, unlesbare frame.json, unbekannte Schlüssel, eine fehlende Breakpoint-Ebene, eine ID mit
  `..`), neun Schritte Speichern und Löschen mit den CLI-Aufrufen, 63 kaputte Definitionen durch
  `frameDefinitionProblem`, 13 Configs durch `groupLayoutCandidates`, 13 Breiten-Dateien. Alles
  gleich, die Dateien byte-gleich.
- **Die Prüfung ist das zod-Schema, ausgeschrieben** (`FrameDefinitionCheck`), mit zods
  Reihenfolge, wie das Golden-Skript sie zeigte: Schlüssel in der Reihenfolge des Schemas; bei
  Text erst der Typ, dann die Prüfungen wie deklariert (`max` vor `regex`); bei Zahlen Typ, dann
  „ganzzahlig“ (als Typfehler gemeldet), dann `min`, `max`; bei Listen erst die Elemente, dann die
  Länge; bei Records die Schlüssel in JavaScripts Reihenfolge, ein falscher Schlüssel als
  `invalid_key` ohne Blick auf seinen Wert. Die Muster sind in ASCII geschrieben, weil ICU anders
  liest als JavaScript: `\d` sind dort die Ziffern jeder Schrift, `[a-z]` mit Groß/Klein-Faltung
  nimmt das Kelvin-Zeichen, `$` passt auch vor einem letzten Zeilenumbruch, und `\s` kennt U+000B
  und U+FEFF nicht.
- **Was nicht geprüft wurde, liest der Port wie JavaScript.** Eine frame.json, die nie durch die
  Prüfung ging (von Hand, aus einer alten Fassung), geht trotzdem in den Build: Eine fehlende
  Lücke heißt dort „undefined“, ein fehlender Name „“ in `grid-template-areas` und „undefined“ in
  der Klasse, ein Zeilenanfang 1,5 wirft. Für die Formen, die eine frame.json plausibel hat, wirft
  der Port denselben Satz wie V8 („Cannot read properties of undefined (reading 'columnSizes')“);
  bei seltsameren kann der Wortlaut abweichen. Die Gruppen-Reihenfolge sortiert wie V8 (ein Lauf,
  dann binäres Einfügen, `JS.sort`): Eine fehlende Priorität lässt den Vergleich NaN antworten,
  und dann ordnet eine gewöhnliche stabile Sortierung anders (Fall „missing priority, V8 order“).
- **Abweichungen:**
  - Ein Frame, dessen Modul sich nicht erzeugen lässt, bekommt keine seiner drei Dateien. Dort
    liefen zwei atomare Schreibvorgänge schon, als der dritte warf, und ließen ihre Temp-Dateien
    liegen (gemessen: `frame.json.tmp-…` und `package.json.tmp-…` nach einem Frame ohne
    `tablet`).
  - Eine Spanne über eine Million Zeilen besucht nur die Zellen, die landen können; QuartzControl
    lief die Schleifen ganz durch und hätte die Bau-Tür aufgehalten.
  - Die Warteschlange der Frames ist `ProjectLock.frames`, je `realpath` statt je geschriebenem
    Pfad.
  - Der Snapshot vor `quartz plugin add` kommt mit Punkt 7; bis dahin gehen „mit“ und „ohne“
    Snapshot denselben Weg (`Plugins.add` bekommt die Angabe schon).
- **An der Bau-Tür:** zweiter Schritt von `BuildService.preparation`; was schiefging, steht als
  Warnung in der Konsole (gemessen: ohne quartz.config.yaml „Die Gruppen des Layouts konnten nicht
  gelesen werden …“, und das Modul wird trotzdem geschrieben).
- Gegenproben (21, jede lässt einen Test scheitern): Kompat-Blöcke immer bzw. ohne Schicht,
  `hidden` übergangen, Spuren nicht getrimmt, `template` übergangen, `exclude` nach roher Quelle,
  gewöhnliche Sortierung (erst ungefangen; der Fall mit fehlender Priorität kam dazu), Länge der
  Liste vor den Elementen, Pfad-Stücke bei 50 gekürzt, unbekannte Schlüssel im alten Format
  behalten, Schreiben vor dem Erzeugen, Breiten ohne Prüfung, `AREAS` eingerückt, jeder Frame neu
  angemeldet, Löschen ohne CLI, unlesbare Config verschwiegen, keine Prüfung doppelter Gruppen,
  geleerte Positionen behalten, kein Frame-Schritt an der Bau-Tür, dessen Sätze als stdout.

### Verwaltete Blöcke und Ladereihenfolge (`styleService.ts`, erster Teil → `ManagedBlocks`, `VariableOverrides`, `StyleSheets`)

- **Was dazugehört:** die Blöcke zwischen den Markern (beide Namen, `QuartzControl` und
  `Quartz-GUI`), der Ladereihenfolge-Block mit den Sass-Namensräumen, die Variablen (drei Regeln:
  beide Modi, dunkel, nur hell), der Umzug nach `_quartzcontrol.scss` samt `@use`-Zeile, die
  Reparatur an der Bau-Tür und die Umstellung der Schrift-Adressen. Die Stylesheet-Dateien selbst
  (anlegen, umbenennen, „Zusammenlegen“), die SCSS-Prüfung und die Schriften folgen.
- **Text wie in JavaScript (`JSText`).** Die Blöcke werden an UTF-16-Stellen geschnitten, gesucht
  wird wörtlich: Swifts `String` sucht nach Zeichen, und „\r\n“ ist eines, eine Suche nach „\n“
  fände in einer Datei mit Windows-Zeilenenden nichts. Die Muster sind für ICU so geschrieben,
  dass sie treffen, was V8 trifft (`\s` ausgeschrieben, `\w` als ASCII, `$` als `\z`, `^` unter
  `m` ohne U+0085). Gegenprobe: das Teilen der Zeilen nach Zeichen statt nach UTF-16 lässt den
  CRLF-Fall scheitern.
- **Gemessen gegen QuartzControls Code:** `scripts/managed-styles-golden.mjs` lädt
  `styleService.ts` und zeichnet auf: die Textfunktionen auf 30 Texten (custom.scss und
  `_quartzcontrol.scss` von gui-test und Example, gui-test in die Form von 1.0 zurückgebaut, mit
  altem Namen, mit CRLF; zwei Kopien unter einem und unter zwei Namen, verschachtelt, beta.2s
  Block im eigenen, ohne Ende, Ende vor Anfang, Umlaute, CJK und Emoji vor den Markern, absolute
  Schrift-Adressen, die Formen der `@use`-Zeile, Regeln mit Klammern), je Text fünf Blöcke und
  15 Funktionen; acht Variablen-Listen gerendert; 16 Abläufe auf Projekten (gui-test und Example
  umgezogen, gui-test in der Form von 1.0 und mit altem Namen, alle Reparaturfälle, Schrift-Adressen
  in beiden Dateien, Kopien in beiden Dateien, eine Zeile für eine gelöschte Datei,
  Namensraum-Kollisionen, Variablen-Kollisionen mit Kommentaren, ein Partial ohne Unterstrich
  genannt), je Schritt die Antwort und jede geänderte Datei. Alles gleich. Die 470 Zeilen
  `google-fonts` von gui-test sind dabei auf ihre ersten fünf Regeln gekürzt, die Stylesheets
  unter custom/ auf eine Zeile: Für diese Funktionen zählt nur, dass sie da sind.
- **Abweichung:** Der Umzug mit Snapshot (`migrate(snapshot: true)`, der Weg der Stile-Seite)
  wird abgelehnt, bis der Snapshot-Speicher da ist (Punkt 7); ohne Snapshot (für ein eben
  angelegtes Projekt) geht er.
- **An der Bau-Tür:** dritter Schritt von `BuildService.preparation`, erst die Reparatur, dann die
  Schrift-Adressen (die zweite liest die Blöcke durch die Zeile, die die erste zurückbringt); beide
  unter der Sperre der Stylesheets. Gemessen: ein umgezogenes Projekt ohne `@use`-Zeile und mit
  `/static/fonts/` bekommt beides und beide Sätze in der Konsole; der zweite Lauf sagt nichts.
- Gegenproben (24, jede lässt einen Test scheitern; vier waren erst ungefangen und bekamen einen
  Fall: der Partial-Kandidat `_name.scss`, das Entfernen von Blockkommentaren bei den Kollisionen,
  die Klammertiefe bei einer schließenden Klammer vorweg, die Anführungszeichen der `@use`-Zeile).

### Schriftdateien lesen (`fontFile.ts` → `FontFile`)

- Gewicht und Schnitt aus OS/2, head und der `wght`-Achse von fvar, in sfnt, WOFF (zlib je
  Tabelle) und WOFF2 (ein Brotli-Strom). Entpackt wird mit Apples Compression-Framework: Brotli
  direkt, zlib als roher Deflate-Strom hinter dem geprüften Kopf, mit der Adler-32-Prüfsumme danach,
  wie Node sie prüft. Die Obergrenze (64 MiB oder die kleinere Länge aus der Datei) beendet den
  Decoder, bevor er mehr hält; eine Bombe von 80 MiB Nullen in 600 Bytes endet in Millisekunden
  bei nil.
- **Gemessen gegen QuartzControls Code:** `scripts/font-file-golden.mjs` baut Schriften in allen
  drei Formaten (statisch, kursiv nach OS/2 oder nach head, variabel mit Achsen in jeder Lage,
  Achse bei genau ,5, Gewicht 0 und 1001, zu kurze und falsch lange Tabellen, kaputter und fehlender
  zlib-Kopf, falsche Prüfsumme, Bomben in WOFF und WOFF2, ein abgeschnittener Strom, Base128 mit
  mehr als fünf Bytes, Daten hinter dem Strom) und liest vier echte WOFF2 von gui-test (Noto und
  Google, SIL OFL). 48 Fälle, alle gleich.
- Gegenproben (11, jede lässt einen Test scheitern; vier waren erst ungefangen und bekamen ihren
  Fall: zlib-Kopf, Rundung bei ,5, abgeschnittener Strom, Base128-Länge). Der Zweig „Decoder
  meldet OK ohne Fortschritt“ ist nur ein Schutz vor einer Endlosschleife: Ein abgeschnittener
  Strom endet bei Apples Decoder im Fehlerstatus (gemessen über die Gegenprobe dieses Zweigs).

### Schriften im Projekt (`fontService.ts`, die Schrift-Teile von `styleService.ts`, `shared/googleFontRequest.ts` → `FontService`, `FontFaces`, `GoogleFontRequest`)

- **Was dazugehört:** eine Schriftdatei importieren (Regel nach dem, was die Datei sagt),
  ungenutzte importierte Schriften finden und entfernen, die Dateien ersetzter Regeln, die
  Google-Schriften holen und entfernen, und die Auffrischung an der Bau-Tür.
- **Gemessen gegen QuartzControls Code:** `scripts/fonts-golden.mjs` lädt `fontService.ts` mit einem
  nachgestellten Google (`google.json`: CSS-Antworten und Schriftdateien je URL, auch die Antworten
  400, 404, „nicht erreichbar“, eine zu große Datei, 801 Dateien, ein unbrauchbarer Name) und
  zeichnet auf: `parseFontFaces` auf zwölf Texten, `fontFileIn` auf 17 Adressen, die CSS2-Anfrage
  für neun Typografien, und zwölf Abläufe (Import echter Schriften aus `Fixtures/font-file`,
  ungenutzte Familien mit Kommentaren, Strings, tiefen Stylesheets und Bindestrich-Namen, ersetzte
  Regeln mit Sass-Pfad, Google holen, unverändert lassen, wechseln, entfernen, ein Torso, eigene
  Regeln, die Latin abdecken, eine eigene Regel ohne Bereich, alle Fehlerfälle, die Bau-Tür mit
  `fontOrigin` lokal und cdn, mit kaputter Config). Je Schritt Antwort, geänderte Dateien (eine
  Schriftdatei als Größe und SHA-1) und die Anfragen samt User-Agent. Alles gleich.
- **JavaScript-Regeln, wo sie zählen:** `decodeURIComponent` und `encodeURIComponent` selbst
  geschrieben (`JSURI`, wirft wie URIError), der Vergleich „nennt die Familie“ mit JavaScripts
  Groß/Klein-Regel des `i`-Flags (Canonicalize je UTF-16-Einheit, nicht ICUs Faltung), Nodes
  `path.join`/`basename`/`extname` (`NodePath`).
- **Die Sätze im Block bleiben QuartzControls** („QuartzControl: every family is declared by the
  project itself …“, „QuartzControl: left out what the project's own rules cover <Abdruck>“):
  Beide Apps lesen sie zurück, also sind sie Format. Der Satz in der Konsole
  (`googleFontsRefreshOwn`) sagt jetzt „QuartzHub“.
- **Netz:** URLSession mit den Proxy- und Zertifikat-Einstellungen des Systems, wie dort Electrons
  `net.fetch`; 20 s je Anfrage über Kopf und Körper. Gemessen nur gegen das nachgestellte Google;
  ein echter Lauf gegen Google wird einzeln gefragt (Nutzer, 2026-11-06).
- **An der Bau-Tür:** vierter Schritt von `BuildService.preparation`. Gemessen mit dem echten
  Config-Leser und ohne Netz: Ein Projekt, das jede Familie selbst einbindet, bekommt den Block
  „nichts von Google“, die Google-Datei geht, beide Sätze stehen in der Konsole; der zweite Lauf
  sagt nichts.
- Gegenproben (23, jede lässt einen Test scheitern; vier waren erst ungefangen und bekamen einen
  Fall: der Abdruck der eigenen Regeln bei gleicher Anfrage, eigene Familien in „nicht geliefert“
  und in „entfernt“, `fontOrigin: cdn` mit anderer Typografie).

### Stylesheet-Dateien und „Zusammenlegen“ (`styleService.ts`, zweiter Teil, `shared/stylesheetConsolidation.ts` → `StyleFiles`, `StylesheetConsolidation`)

- Auflisten (Ladereihenfolge zuerst, dann was nicht geladen ist), lesen, schreiben, anlegen,
  umbenennen (die Reihenfolge vor dem Umbenennen gelesen), löschen (die Reihenfolge zuerst), ein
  Stylesheet nach imported/ holen, die Referenz-Stylesheets eines Plugins, und das Zusammenlegen
  der 31 Vorlagen-Stylesheets von 1.0 zu den zwölf von 1.1.
- **Die Tür prüft die Namen.** QuartzControls IPC-Schemas ließen nur `custom/…` und `imported/…`
  mit `.scss`/`.css` durch (und `_quartzcontrol.scss` zum Lesen und Speichern), Dateinamen aus
  einem Segment. Ohne IPC stehen dieselben Regeln am Dienst (`StyleFiles.InvalidName`).
- **Ein Verzeichnis lesen heißt hier: nach Bytes sortiert.** Node liest Verzeichnisse über libuvs
  `scandir`, das nach `strcmp` sortiert; `readdir` gibt die Reihenfolge des Dateisystems. Gemessen
  an den 22 Referenz-Stylesheets eines Plugins: in Hash-Reihenfolge statt nach Namen. Das gilt
  jetzt für jede Verzeichnisliste des Kerns (`LayoutFrames.directoryEntriesWithKind`), auch für die
  Frames.
- **Zusammenlegen braucht einen Snapshot, und den gibt es erst mit Punkt 7.** Bis dahin lehnt
  `consolidate` ab, bevor etwas bewegt wird; die Tests geben einen nachgestellten Snapshot mit, um
  den Lauf selbst gegen QuartzControl zu messen. Die Kopfzeile der zwölf („put together by
  QuartzControl …“, auch die frühere Fassung) bleibt QuartzControls: An ihr erkennen beide Apps
  ein zusammengelegtes Projekt.
- **Gemessen gegen QuartzControls Code:** `scripts/style-files-golden.mjs` holt die 31
  Stylesheets aus QuartzControls git-Geschichte (`f2cdb69~1`) und zeichnet auf: den Plan für 15
  Reihenfolgen (mit eigenen Dateien davor und dahinter, eine abgeschaltet, nur drei geladen,
  `base` mit nur einem Anteil, eine unbekannte Überschrift, eine eigene Datei hinter `base`, eine
  eigene `layout.scss`, beide Kopfzeilen, die erste Zeile der Vorlage, nicht geladen, imported/ und
  `.css`), dazu fünf Abläufe auf Projekten (zusammenlegen, umgezogen und mit einer abgeschalteten,
  nichts zu tun, alle Datei-Aufrufe, Referenzen mit ausgelassenen Ordnern, Tiefe und mehr als 20
  Dateien). Alles gleich.
- Gegenproben (19, 18 fangen; eine war erst ungefangen und bekam den Fall „eigene Datei hinter
  `base`“). Ungefangen bleibt, dass das Ausweichen beim Umbenennen auch die eben geschriebenen
  Namen meidet: Kein Name der zwölf endet auf „-<Zahl>“, die Abfrage ist eine Vorsicht aus
  QuartzControl, die nie greift.

### SCSS-Prüfung und Quartz' Maße (`checkStyles`, `checkStyleSource`, `readQuartzFrameMeasures` → `ScssCheck`, Helfer `sass-check`)

- **Sass des Projekts im Kindprozess** (Nutzer, 2026-11-06): Der neue Helfer `sass-check` lädt
  `sass` per `createRequire` aus dem Projekt und kompiliert, was er gefragt wird; die Bedeutung
  (Diagnose, Maße, „nicht verfügbar“) entsteht in Swift. QuartzControl lud dasselbe Sass in seinen
  Hauptprozess; hier läuft es in einem kurzen Prozess, der nichts zu schützen hat. Mehrere
  Übersetzungen gehen in einem Aufruf (die Maße mit und ohne `.page`-Obergrenze). Frist 120 s.
  Antwortet der Helfer selbst nicht, heißt es „Die SCSS-Prüfung konnte nicht ausgeführt werden“
  (neu, `styles.sassCheckBroken`), getrennt von „Sass fehlt“ und „npm entpackt noch“.
- **Ein Sass zum Messen:** `sass@1.104.1` (gui-tests Fassung) liegt als Entwicklungsabhängigkeit in
  `Helpers/node_modules`; die Testprojekte verlinken `node_modules/sass` darauf. Es reist nicht
  mit der App.
- **Gemessen gegen QuartzControls Code:** `scripts/scss-check-golden.mjs` lässt QuartzControls
  Funktionen mit demselben Sass auf 22 Projekten laufen (die Stylesheets von gui-test und Example,
  Syntaxfehler, ein Fehler in einer geladenen Datei und in einer außerhalb von quartz/styles, eine
  unbekannte Variable, beta.2s Block im eigenen, die fehlende `_quartzcontrol.scss`, kein Sass,
  Sass halb entpackt, `.css`-Dateien, und für die Maße: keine variables.scss, keine base.scss,
  keine, eine nicht auswertbare und eine Obergrenze in px, ein fehlendes Raster, Breakpoints in em,
  eine Spur mit Klammern, kaputte variables.scss). 34 Antworten, alle gleich.
- Gegenproben (13, jede lässt einen Test scheitern; zwei waren erst ungefangen und bekamen ihren
  Fall: der Fehler außerhalb von quartz/styles, die Spur mit Klammern).

### Variablen-Graph und Variablen-Katalog (`variableGraphService.ts`, `shared/cssVariables.ts` → `VariableGraph`, `CssVariables`)

- Die Tabelle der Variablen-Seite: jede Variable mit hellem und dunklem Wert, Herkunft (Theme,
  Build, eigenes Stylesheet) und wer sie referenziert. Quellen: das `theme.json` eines
  installierten Themes, das CSS des letzten Builds, die geladenen Stylesheets des Projekts; was
  ungeschichtet steht, gewinnt über jede Schicht. Gelesen mit einem Klammerzähler, der Strings und
  Kommentare kennt, wie in QuartzControl; die Tabelle hält QuartzControls Schlüsselreihenfolge.
- Der Katalog (Quartz' Variablen aus `joinStyles()`, `hexToHsl` mit Quartz' Rundung, die
  Vorgaben je Modus, die Callout-Farben, „darf so in ein Stylesheet“) ist ein reiner Port.
- **Gemessen gegen QuartzControls Code:** `scripts/variable-graph-golden.mjs` nimmt die
  Stylesheets und das Build-CSS von gui-test (26 Dateien) und das Theme `minimal` (nur gelesen,
  in die Fixtures kopiert) und dazu erfundenes CSS: Klammern in Strings und Kommentaren, `@layer`,
  `@media`, `@supports` in `@layer`, Mehrfach-Selektoren, Regeln mit Bereich, Minifiziertes ohne
  letztes Semikolon, Data-URLs mit `;`, numerische Namen, umbrochene Werte, ein offener String,
  eine überzählige Klammer mit zwei Regeln danach, ein ungeschichteter heller Wert über einem
  geschichteten dunklen, kaputte und leere Theme-Dateien, ein eigener Ausgabeordner, mehr als 50
  Build-Dateien. Elf Graphen (bis 1141 Variablen) und der Katalog, alles gleich.
- Gegenproben (18, jede lässt einen Test scheitern; zwei waren erst ungefangen und bekamen ihren
  Fall: der dunkle Rückfall auf den hellen Wert, der Abbruch nach der überzähligen Klammer).

### Schriften der Website, Vorschau, belegte Klassen (`collectFontFaces`, `readPreviewFonts`, `projectStylesheets`, `takenClasses` → `SiteFonts`)

- Welche `@font-face` die gebaute Website haben wird (Theme-Schriften aus `meta.fontFiles`, die
  eigenen Regeln, was ein Build schrieb), die Dateien dahinter für die Vorschau (ein Link ist keine
  Schriftdatei des Projekts; 64 MiB je Datei, 32 MiB zusammen), und welche Klassennamen mit einem
  Präfix Stylesheets und Plugin-Code schon benutzen. Die Präfixe prüft der Dienst wie dort das
  Schema (höchstens acht, ein Bezeichner).
- **Gemessen gegen QuartzControls Code:** `scripts/site-fonts-golden.mjs` auf gui-tests
  Stylesheets, Schriften, Build-CSS und dem Theme `minimal`, auf erfundenen Rändern (verlinkte
  Schriftdatei, Dateien über beiden Grenzen, kaputtes Theme, eine Familie, die der Build
  wiederholt, Plugin-Code in `.js`, `.mjs` und `.css`, Variablen mit dem Präfix) und auf einem
  leeren Projekt; alles gleich, die Vorschau-Dateien nach Länge und SHA-1.
- Gegenproben (11, zehn fangen). Ungefangen bleibt die Grenze je Datei: 64 MiB liegen über der
  Gesamtgrenze von 32 MiB, also entscheidet sie nie allein; eine doppelte Vorsicht aus
  QuartzControl.

### Snippets und Bilder (`snippetService.ts`, `containedPath`/`writableTarget` aus `templatePackage/shared.ts` → `Snippets`, `PackagePaths`)

- Die Dateien einer Layout-Box (`dir` + `file`) und die Bilder unter quartz/static/images:
  auflisten, lesen, schreiben, holen, umbenennen, in den Papierkorb. Jeder Name und jeder Ordner
  wird gegen das Projekt aufgelöst: nichts außerhalb, nichts durch einen Link, nichts in einen
  Ordner eines Werkzeugs oder in die Build-Ausgabe. `PackagePaths` nimmt Punkt 6 mit.
- **Fehlermeldungen von Node, wo sie im Satz stehen** (`NodeFileError`: „Error: ENOENT: no such
  file or directory, stat '…'“), weil QuartzControl `String(err)` weitergab. Der Papierkorb ist
  der des Systems (`FileManager.trashItem`); die Tests geben einen eigenen mit.
- **Sortiert wie `localeCompare` mit `numeric`**: Foundations Vergleich mit Zahlen und Gebietsschema
  (`file2` vor `file10`, `_under` vor `10-start`, `apfel` vor `Äpfel`), gleich mit Node in allen
  Fällen.
- **Gemessen gegen QuartzControls Code:** `scripts/snippets-golden.mjs`, ein Projekt mit
  Snippet-Ordnern, Bildern, Links nach innen und außen (auf Datei, auf Ordner, aus dem Projekt
  hinaus), reservierten Ordnern in jeder Schreibweise, der Build-Ausgabe und einem verlinkten
  content/; 74 Aufrufe (auch zu groß, falsche Endung, `key.txt` als `key.md`, ein Ordner als
  Quelle, Umbenennen nur in der Schreibweise, ein Papierkorb, der scheitert) und 20 Pfad-Fälle.
  Alles gleich, samt geänderter Dateien und Papierkorb.
- Zwei übernommene Texte sagen jetzt „QuartzHub“ (`snippetDirLink`, `snippetDirOutside`).
- Gegenproben (15, jede lässt den Test scheitern).

### SVG-Bereiniger und `qh-check inline-svg` (`src/utils/inlineSvg.ts`, `scripts/check-inline-svg.mjs` → `InlineSvg`, `SvgTree`, `InlineSvgCheck`)

- **Der Parser ist libxml2** (`SvgTree`), die Bibliothek, auf der Chromes XML-Parser steht.
  QuartzControl lief im Renderer auf Chromes DOMParser. Foundations `XMLDocument` verwirft Textknoten, die nur
  Leerraum enthalten, in jeder Einstellung (gemessen: zwischen zwei Elementen fehlte das „\n“; ein
  Leerzeichen zwischen zwei `<tspan>` wäre so verloren), `XMLParser` verliert die Reihenfolge der
  Attribute. libxml2 direkt (`import libxml2`, `-lxml2` aus dem SDK) hat beides. Ohne
  `XML_PARSE_NOENT`: Damit läse libxml2 eine externe Entity von der Platte (XXE). Interne Entities
  setzt `SvgTree` selbst ein, wie Chrome, mit einer Obergrenze von 200.000 Knoten, sodass „Billion
  Laughs“ (10¹⁰ Texte) in Millisekunden bei „nicht lesbar“ endet.
- **Gemessen gegen QuartzControls Code in Chrome:** `scripts/inline-svg-golden.mjs` lässt
  `inlineSvg.ts` über QuartzControls playwright-core in Chrome laufen, auf dem Korpus von
  `check:inline-svg` und den Rändern der XML-Seite (DOCTYPE mit interner und externer Entity,
  Inkscape- und Figma-Dateien, `svg:`-Präfix, falscher oder fehlender Namensraum, `parsererror` als
  Element, Attributnamen in jeder Schreibweise, `href` und `xlink:href` zugleich, CSS-Escapes, Ids
  mit Sonderzeichen, Leerzeilen, Kommentare und PIs überall, Unicode). 74 Fälle, Markup, Zahl und
  `styled` gleich.
- **`qh-check inline-svg [projekt]`** ist QuartzControls `check:inline-svg` mit WebKit statt Chrome
  (Nutzer, 2026-11-06, Variante A): jedes Ergebnis als HTML in einer Box, mit einem Projekt auch
  durch die Markdown-Kette seines quartz-layout-box (`scripts/lib/layout-box-markdown.mjs` lädt
  dessen `dist/index.js`, wie dort) in drei Lagen; gefragt wird die Seite nach Elementen außerhalb
  des SVG, Ereignis-Attributen, Verweisen, `url()`, Animationen auf Verweise, Skript beim Laden und
  nach einem Klick auf jedes Element, Navigation und Laden von außen. Gemessen mit gui-test
  (quartz-layout-box 0.4.2): 53 Prüfungen bestanden, Exit 0; ohne Projekt Exit 3 (114 Lagen
  ausgelassen).
- **Was WebKit ohne App anders macht:** Ein WKWebView läuft in einem Kommandozeilenwerkzeug, wenn
  sich die Haupt-RunLoop dreht; das async-Hauptprogramm dreht sie nicht und lässt sie nicht drehen
  (gemessen: die erste Seite lud nie fertig), also ist die oberste Ebene von `qh-check` jetzt
  synchron (`runAndExit`). Ohne Fenster malt er keine Frames: `requestAnimationFrame` kam nie, die
  Prüfung wartet dort mit einem Timer. Laden von außen fragt sie über die Resource Timing der Seite,
  nicht über Netzereignisse wie Playwright. Links nach http(s), `mailto:`, `tel:` und `ftp:` gelten
  wie dort als erlaubt (remark-gfm macht sie aus Text); jede Navigation wird abgebrochen, damit
  nichts ein Mail-Programm öffnet.
- Gegenproben: am Golden 10 (eine erst ungefangen, `href` neben `xlink:href`, bekam ihren Fall);
  an der WebKit-Prüfung fünf Lücken im Bereiniger (Ereignis-Attribute, `javascript:`-Links,
  ungeschützter Text, Animationen auf `href`, fremde `url()`), jede gemeldet.

### Themes: Presets, Style-Settings-Schema, Marktplatz (`themePresetsService.ts`, `styleSettingsSchemaService.ts`, `themeMarketplaceService.ts` → `ThemePresets`, `StyleSettingsSchema`, `ThemeMarketplace`)

- **Gemessen gegen QuartzControls Code:** `scripts/themes-golden.mjs` lädt die drei Dienste mit
  gespieltem Netz (Obsidians Theme-Registry, `theme.css`/`obsidian.css` auf
  raw.githubusercontent.com, GitHubs Repo-Liste der Organisation, jsDelivr), gespieltem `npm search`
  und `npm install` und einem `userData` im Temp-Ordner. Je Schritt sind Antwort, Anfragen (URL,
  `Accept`, `Authorization`), Befehle und geänderte Dateien festgehalten (56 Schritte). Der
  Swift-Test antwortet aus derselben Netz-Datei, nach URL (`ThemeNet`, ein URLProtocol), und
  vergleicht alles davon, JSON mit Schlüsselreihenfolge.
- **Presets** liegen im Projekt (`.quartz-gui/theme-presets.json`), über `JSONStore`: ein Preset
  mit derselben Id wird an seinem Platz ersetzt, eine kaputte Datei beiseitegelegt.
- **Style Settings:** Das YAML im `@settings`-Kommentar liest der Helfer (`yaml-edit read`), also
  dasselbe `yaml` wie dort; ein Block, der nicht lesbar ist, kostet das Theme nicht seine anderen.
  Die Registry hält einen Tag im Speicher und liegt als Kopie im Profil (`theme-docs/`), die
  antwortet, wenn das Netz fehlt. `repo` muss `owner/name` sein (es geht in einen URL-Pfad), eine
  Antwort über 16 MiB wird nicht gelesen. Die Antwort wird je Theme gecacht, auch „keins“.
  Wie in QuartzControl bleibt „keins“ auch dann im Cache, wenn die Registry nicht erreichbar war
  und ihre Kopie geleert ist (letzter Schritt des Goldens), bis jemand den Cache leert; übernommen,
  nicht behoben (Wartung, nicht kritisch).
- **Marktplatz:** `npm search` mit 30 s Frist (npm hat keine eigene); ohne Antwort die sieben
  bekannten Themes mit `unavailable`, und das wird nie gecacht. Wie dort zählt die Ausgabe auch
  bei einem Exit-Code ungleich 0, und ein Eintrag ohne Namen kostet die ganze Antwort. GitHub
  ergänzt Sterne und Topics (höchstens fünf Seiten, ohne Token bis Punkt 8). Details kommen erst
  aus dem installierten `theme.json`, dann von jsDelivr; ein Netzfehler wird nicht gecacht, eine
  Antwort ohne Datei eine Stunde lang. Die Theme-Id (`[a-z0-9][a-z0-9._-]*`, höchstens 128) prüft
  dort das IPC-Schema, hier der Dienst selbst, in `schema`, `detail` und `install`: Es gibt keine
  IPC-Grenze mehr, an der das geschähe.
- Gegenproben (21, jede lässt den Test scheitern). Fünf waren erst ungefangen und bekamen ihren
  Fall: die Registry von der Platte, ein Registry-Eintrag ohne Autor, ein 404 von jsDelivr zweimal
  (gecacht), eine Antwort `null` zweimal (nicht gecacht), ein npm-Eintrag ohne Namen.
