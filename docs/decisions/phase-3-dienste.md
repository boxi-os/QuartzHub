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
