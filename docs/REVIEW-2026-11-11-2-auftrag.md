Du bist als zweites Paar Augen an QuartzHub, der nativen macOS-Nachfolgerin von QuartzControl. Es
gibt noch kein Release. Es geht um ein Review, nicht um Änderungen. Am Ende steht eine Liste von
Befunden, über die der Nutzer entscheidet.

## Warum diese Runde

Das ist die **zweite**, kurze Runde. Die erste (`docs/REVIEW-2026-11-11.md`, Stand `ddcb802`,
abgearbeitet laut `docs/reviews.md` bis `c19628d`) nahm sich Daten, Geheimnisse, Server und das
Paket vor. Seitdem sind 60 Commits dazugekommen (`c19628d..eed348b`, rund 4.900 Zeilen, ein gutes
Drittel davon Tests und Texte). **Jeder ist von demselben Modell gemessen, das ihn geschrieben
hat.** Diese Runde liest nur sie. Sie soll vor dem ersten echten Einsatz beim Nutzer klären, ob
etwas davon seine Projekte, sein QuartzControl-Profil, seine Geheimnisse oder seine Server
beschädigen kann und ob der Release-Bau etwas aus dem Debug-Bau mitnimmt.

Der größte Teil ist die Unterstützung von **Quartz 5.1**. Wichtig ist auch: **QuartzControl ist
seit 2026-11-11 eingestellt** (1.3.0 ist die letzte Fassung). Sein Repo bleibt die Spezifikation,
aber die Dinge, die 5.1 neu bringt, hat QuartzControl nie gekannt. Dort gilt Quartz' eigener Code
als Maßstab (siehe „Das Projekt“).

**Nimm nichts als gemessen hin, nur weil es so dasteht.** Das gilt für Commit-Nachrichten, für
`docs/decisions/phase-5-gleichstand.md` (Abschnitte „Quartz 5.1“ und „Die letzten gebaut-Zeilen“),
für `docs/gleichstand.md` und für diesen Auftrag.

## Das Projekt

- **QuartzHub:** `/Users/boxi/Development/QuartzHub`. Lies zuerst `CLAUDE.md` **und
  `docs/conventions.md`**. Für diese Runde zählen besonders:
  - „Beide Apps lesen dieselben Dateien“;
  - „Was der Quartz eines Projekts kann, liest QuartzHub aus dem Projekt“;
  - „Startschalter kommen nur aus den Startargumenten“;
  - die Pfadregel (Zeichenketten statt `URL`, NFD-Durchgang);
  - „Kann nicht prüfen ist nie alles gut“.
- **QuartzControl:** `/Users/boxi/Development/QuartzControl`, nur lesen.
- **Quartz 5.1:** `~/Documents/QuartzProjekte/gui-test` hat Quartz 5.1.0, `Example` noch 5.0.0;
  zusammen decken sie beide Fassungen ab. Quartz' eigener Code liegt im Projekt unter `quartz/`. Für die neuen Teile gilt er als Maßstab, vor allem:
  - `quartz/plugins/loader/config-loader.ts`;
  - der Typ von `layout.sidebars`;
  - `plugin doctor` und `quartz info` in `quartz/cli/`.

## Umfang

    git -C /Users/boxi/Development/QuartzHub log --oneline c19628d..eed348b
    git -C /Users/boxi/Development/QuartzHub diff --stat c19628d..eed348b -- Packages/QuartzHubCore/Sources App Helpers scripts project.yml

Am meisten Gewicht haben:

- **Kern:**
  - `Config/BuiltinProcessing.swift`;
  - `Updates/CoreUpdate+Release.swift`;
  - `Plugins/PluginDoctorReport.swift` und `Plugins/PluginCommands.swift`;
  - `Layout/LayoutFrames.swift` und `Layout/PageTypeOverride.swift`;
  - `Templates/BuiltinTemplate.swift` und `Projects/ProjectCreator.swift`;
  - `Projects/FormUsages.swift`;
  - `Publishing/Connections.swift`, `Publishing/GitBranchAdapter.swift`, `Publishing/FTP/FTPSession.swift`;
  - `Publishing/Forms/RelayProbe.swift`;
  - `Snapshots/SnapshotStore.swift`;
  - `Build/ServerScan.swift`;
  - `Styles/SiteFonts.swift`;
  - `Environment/Offline.swift`.
- **App:**
  - `App/Components/BuiltinMigration.swift`;
  - `App/Pages/Config/` (ProcessingSections, SiteSettingsSections, ConfigModel);
  - `App/Pages/Updates/`;
  - `App/Pages/Plugins/` (PluginsModel, InstalledTab, PluginInspector, FormsRelaySection);
  - `App/Shell/ExternalOpen.swift`;
  - `App/Components/ScrollMemory.swift`.
- **Helfer und Skripte:**
  - `Helpers/src/yaml-edit.ts` und `Helpers/src/ftp-session.ts`;
  - `scripts/package.sh` und `scripts/template-quartz51.mjs`.

## Abwägungen, die niemand gegengelesen hat

**1. Was QuartzHub an einem 5.1-Projekt schreibt.** Betroffen sind:

- `layout.sidebars` (`8dad2fb`);
- die eingebaute Verarbeitung samt „Übernahme“ von Plugins in Quartz' eigene
  (`5e7eb68`, `BuiltinMigration.swift`);
- die Reihenfolge GitHub vor Obsidian Markdown (`c5d09c6`);
- Frames mit Einstiegsmodul (`2ea4bee`);
- das Entfernen eines von mehreren gleichnamigen Einträgen (`6c67639`).

Fragen dazu:

- Akzeptiert Quartz 5.1 jede Datei, die QuartzHub so schreibt (`npx quartz build`)? Geht dabei
  etwas aus der Config verloren, das der Nutzer von Hand gesetzt hat (Kommentare, unbekannte Felder,
  Reihenfolge)?
- Nimmt jeder dieser Schreiber vorher einen Snapshot?
- Was geschieht an einem **5.0-Projekt**? Schreibt QuartzHub dort je etwas, das nur 5.1 versteht?
  Erkennt `QuartzFeatures` die Fassung am Projekt, nicht an der Versionsnummer?
- Was liest QuartzControl 1.3 an einer Config, die QuartzHub für 5.1 geschrieben hat? Die Frage ist,
  ob ein Nutzer, der QuartzControl noch öffnet, damit etwas kaputt speichern kann.

**2. Kern-Update auf 5.1 und doctor** (`6bfc761`, `388b596`, `fd559be`, `e321194`, `08129c4`).

- Liest QuartzHub die Ausgabe von `plugin doctor`, `quartz info` und den Release-Notes robust?
  Gemeint sind andere Sprache, leere Ausgabe, ein Abbruch und ein Fehler mit Exit ≠ 0.
- Kann ein als „gewollt“ markierter doctor-Befund einen echten Fehler verdecken? Das betrifft vor
  allem die Plugins `quartz-layout-box` und `quartz-navigations`.
- Sagt die Seite Updates je „erfolgreich“, wo Quartz einen Fehler gemeldet hat?

**3. Vorlage und Projekt anlegen** (`3809cb9`, `fec5d18`, `5c06a5d`, `scripts/template-quartz51.mjs`).

- Woher kommt die Vorlage jetzt („online only“)? Ist der Download begrenzt und geprüft (Größe,
  Entpacken mit Obergrenze, Pfade mit `..` oder Symlinks im Archiv)?
- Was geschieht ohne Netz?
- Kann das Anlegen ein bestehendes Verzeichnis überschreiben?

**4. Geheimnisse und Veröffentlichen.** Betroffen sind:

- `2e12fb6`: Zeilenumbruch und Steuerzeichen im Passwort;
- `0842b76`: das abgelehnte FTP-Passwort in einer Meldung;
- `2b9bcc0` und `4500b11`: Relay-Geheimnisse, die im Schlüsselbund fehlen;
- `954e724`: das Zertifikat bei der Relay-Prüfung;
- `ac2bad2`: die eigene Domain bei GitHub Pages.

Fragen dazu:

- Taucht ein Geheimnis in einer Meldung, einem Log oder einer Kindprozess-Zeile auf? Prüf auch
  umkodierte Formen.
- Kann `ac2bad2` (CNAME beim Branch-Deploy) eine fremde oder alte Datei auf dem Branch
  überschreiben oder behalten, die nicht bleiben soll?

**5. Debug-Schalter und Release** (`f09a9ee`, `2766bf4`, `d16a8f5`, dazu jeder neue `LaunchArgument`).

- Steht jeder neue Schalter (`-QHOpenLog`, `-QHOffline`, `-QHScanFails` und weitere seit
  `c19628d`) vollständig unter `#if DEBUG`, auch der Aufruf?
- Prüf am Release-Bau (`strings`), ob einer übrig ist.
- Ändert `Offline.registerForShared()` oder `ExternalOpen` im Release irgendein Verhalten?
- Geht seit der Umstellung **jeder** Aufruf, der etwas nach außen öffnet, über `ExternalOpen`? Gibt
  es einen Weg, auf dem ein Wert aus einem Projekt (eine URL aus der Config oder einem Plugin) ohne
  Prüfung ein Programm oder eine `file://`-Adresse öffnet?

**6. Was sonst Daten berührt.** Betroffen sind:

- `c114f6c`: der Snapshot-Index ohne Sperre;
- `4bfbacb`: ServerScan in einem Ordner mit Umlaut;
- `24cb3cd`: Tests beenden nur eigene Prozesse;
- `eed348b`: SiteFonts liest `index-<hash>.css`;
- `b8d2850`: ScrollMemory.

Fragen dazu:

- Kann `c114f6c` QuartzControls Index oder einen Snapshot beschädigen, wenn beide Apps
  gleichzeitig arbeiten?
- Kann ServerScan einen fremden Prozess als Server eines Projekts ansehen und beenden?

## Worauf es ankommt, in dieser Reihenfolge

1. **Was Daten des Nutzers verliert oder verändert, die es nicht ändern soll.** Gemeint sind
   Config, Inhalte, QuartzControls Profil und Dateien auf einem Server (1, 3, 4, 6).
2. **Was ein Geheimnis offenlegt oder einem Wert aus einem Projekt Ausführung erlaubt** (4, 5).
3. **Was Erfolg sagt, wo keiner war** (2).
4. **Was im Release anders ist als im Debug-Bau** (5), und alles Übrige.

Oberfläche ist kein Schwerpunkt; melde dort nur, was dir auf dem Weg begegnet.

## Schon bekannt, nicht neu melden

- Alles aus der ersten Runde, was in `docs/reviews.md` steht, auch das ausdrücklich nicht
  Umgesetzte.
- `plugin doctor` meldet „configured twice“ für `quartz-layout-box` und `quartz-navigations`. Das
  ist gewollt: In 5.1 hat ein Eintrag genau eine `layout.position`. Beobachtet wird es bei jedem
  Quartz-Update (`docs/plan.md`). Melde es nur, wenn die Markierung mehr verdeckt.
- Die `fehlt`- und die eine `gebaut`-Zeile der Gleichstand-Liste. Der Abbruch der
  Schlüsselbund-Abfrage bei der Übernahme ist ungemessen.
- Im ePub steht der Kapiteltitel doppelt über dem H1 der Seite, und benachbarte Fußnoten lesen sich
  wie eine Zahl. Beides ist byte-gleich mit QuartzControl.
- Die Werkzeugleiste kann „fehlt/inkompatibel“ auf diesem Mac nicht zeigen, weil Homebrew-Node und
  `/usr/bin/git` im PATH liegen.

## Wenn du misst

Ändere nichts in diesem Repo, in QuartzControls Repo, in einem Vault oder in einem Projekt unter
`~/Documents/QuartzProjekte`. Arbeite in Kopien in deinem Ordner. Im Folgenden heißt er `<r2>`; der
Pfad steht in der Nachricht, mit der du gestartet wurdest.

- **Lies nie etwas aus einem privaten Projekt oder Vault des Nutzers.**
  Das gilt auch für eine Schleife oder ein `grep` über alle Projekte: Nimm es aus jeder Liste,
  **bevor** du sie durchläufst. Nenn den Namen nicht in deinem Bericht.
- **Keine Anfrage an einen Host außerhalb dieses Rechners** außer an `debian-vm`. Ausnahme: der
  Download, den QuartzHub selbst beim Anlegen aus der Vorlage macht, falls du ihn messen willst.
  - Kein `git push`, kein `gh`, keine Änderung an einem Repository bei GitHub.
  - Für Messungen ohne Netz gibt es den Debug-Schalter `-QHOffline YES`.
  - Für „was würde geöffnet“ gibt es `-QHOpenLog <datei>`.
- **Der echte Schlüsselbund bleibt unangetastet.** Starte QuartzHub immer mit:
  - `-QHMemorySecrets YES`;
  - einem eigenen `-QHProfileDir <r2>/…`;
  - `-QHMigrationSource ""`;
  - `-QHNoUpdateCheck YES`;
  - `-ApplePersistenceIgnoreState YES`.

  Für das Ansehen gilt `.claude/skills/run-app/SKILL.md`. Beenden mit `pkill -x QuartzHub`, nie mit
  einem synthetischen ⌘Q.
- **Bau nicht im Repository.**
  - Klone nach `<r2>` und baue mit `-derivedDataPath <r2>/…`.
  - `Runtime/`, `.tools/` und `Helpers/node_modules` darfst du aus dem Repository kopieren.
  - Die Kerntests laufen mit `swift test --package-path <dein Klon>/Packages/QuartzHubCore`.
  - Lass `xcodebuild … test` weg: Es bewegt Maus und Tastatur.
- **QuartzControl nicht starten.**
- **Klicke nie „Aktualisieren“ oder „Update durchführen“** in der App, auch nicht in einer Kopie.
  Ein Kern-Update misst du, wenn überhaupt, mit `CoreUpdate` im Test an einer Kopie.
- **Projekte:**
  - Nimm Kopien per `rsync -aL --exclude node_modules` von `Example` und `gui-test` aus
    `~/Documents/QuartzProjekte`.
  - Für einen Build braucht eine Kopie `node_modules`. Kopiere es dann mit oder lass
    `npm ci --offline` laufen.
  - In einer Kopie mit Symlink auf einen Vault schreibst du nichts unter `content/`, bevor der
    Symlink aufgelöst ist.
  - Entferne vor dem Start jedes Veröffentlichungsziel aus `.quartz-gui/publish-targets.json` der
    Kopie, das nicht auf `<r2>` oder `debian-vm` zeigt; die Kopien von `gui-test` enthalten echte
    Ziele.
  - Biege alle git-Remotes der Kopie auf einen lokalen Ordner um.
- **`debian-vm`** (`ssh debian-vm`): SFTP und rsync als `boxi` in eigenen Ordnern
  `~boxi/review2-*`. Für FTP gibt es in dieser Runde kein Passwort; FTP bleibt ungemessen. Lege keine
  Konten an und ändere nichts an der Konfiguration. Räum deine Ordner am Ende weg.
- **Bildschirmfotos nur von Fenstern** (`screencapture -o -l <id>`). Öffne keine Links im Browser.
  Fass die Zwischenablage nicht an.
- **Abgelehnte Schritte nicht umgehen.** Hat die Rechteprüfung einen Schritt abgelehnt, umgeh ihn
  nicht auf anderem Weg; nenn ihn im Bericht als nicht gemessen. Fragt macOS nach einer Freigabe,
  entscheide nicht selbst; nenn es.

## Was du ablieferst

Einen Bericht auf Deutsch in `<r2>/review.md`, im Aufbau wie `docs/REVIEW-2026-11-11.md`:

- Kopf mit Stand (Commit), Modell und dem, was erreichbar war.
- Befunde nach Gewicht (Hoch, Mittel, Niedrig). Zu jedem:
  - Ort (`datei:zeile`);
  - Szenario;
  - Beleg: gemessen oder gelesen, und womit;
  - ein Vorschlag.
- Getrennt davon eine Liste „Nebenbei“ für Kleinigkeiten.
- Zu jeder der sechs Abwägungen eine Antwort, auch wenn sie „kein Befund“ lautet.
- Am Ende ein Urteil: was davon vor dem ersten echten Einsatz beim Nutzer behoben sein muss.
- Was du auf dem Mac und auf `debian-vm` angelegt hast und was davon noch liegt.

Kennzeichne bei jedem Befund, ob du ihn gemessen oder nur gelesen hast.
