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
