Du bist als zweites Paar Augen an QuartzHub, der nativen macOS-Nachfolgerin von QuartzControl. Es
gibt noch kein Release; das erste kommt erst bei Gleichstand mit QuartzControl 1.3. Es geht um ein
Review, nicht um Änderungen. Am Ende steht eine Liste von Befunden, über die der Nutzer entscheidet.

## Warum diese Runde

Das ist die **erste** Review-Runde an QuartzHub. Die App ist in sechs Tagen in rund 300 Commits
entstanden (2026-11-06 bis 2026-11-11), rund 65.000 Zeilen Swift (Kern 38.500, App 27.000) und
15.700 Zeilen Tests. **Jeder Commit ist von demselben Modell gemessen, das ihn geschrieben hat.**
Gelesen hat ihn noch niemand sonst. Der Plan verlangt vor dem Release eine Runde ohne Befund über
„Niedrig“ (`docs/plan.md`, Phase 5).

Diese Runde nimmt sich die Teile vor, in denen ein Fehler am meisten kostet: was Dateien des
Nutzers, sein QuartzControl, seine Geheimnisse und seine Server berührt, und was im Release-Paket
landet. Oberfläche und Export bekommen eigene Runden; melde dort nur, was dir auf dem Weg begegnet.

**Nimm nichts als gemessen hin, nur weil es so dasteht.** Das gilt für Commit-Nachrichten, für
`docs/decisions/`, für `docs/gleichstand.md` (dort steht bei 643 von 720 Zeilen „gemessen“) und
für diesen Auftrag.

## Das Projekt

- **QuartzHub:** SwiftUI-App und SwiftPM-Kern, `/Users/boxi/Development/QuartzHub`. Lies zuerst
  `CLAUDE.md` **und `docs/conventions.md`**. Für diese Runde zählen besonders:
  - „Beide Apps lesen dieselben Dateien“ und „QuartzControl ist die Spezifikation“;
  - „Pfade sind Zeichenketten mit den Bytes der Platte, nie `URL`s“ (NFD-Durchgang, `CLAUDE.md`);
  - „Kindprozesse (QC)“, „Ein Helfer ist ein Aufruf“, „Jede Dekompression bekommt eine Obergrenze“;
  - „Die Datei ist da ist nicht die Datei lässt sich lesen“ (Temp-Datei, `fsync`, `rename`);
  - „Kann nicht prüfen ist nie alles gut“, „Zwei Arten zu scheitern bekommen zwei Antworten“.
- **QuartzControl** (Electron, Wartung seit 1.3.0): `/Users/boxi/Development/QuartzControl`, Stand
  `main`. Es ist die Spezifikation. Die Begründungen der übernommenen Regeln stehen in
  `docs/decisions/conventions-full.md`, was es bedienen will in `docs/support-matrix.md`.
- `docs/plan.md` (was gewollt war), `docs/formats.md` mit `docs/formats/` (jede Datei, die beide
  Apps lesen oder schreiben), `docs/decisions/phase-{1..5}-*.md` (Messungen und Entscheidungen),
  `docs/gleichstand.md` mit `docs/gleichstand/` (jede Funktion von QuartzControl 1.3 und ihr Stand).

## Umfang

    git -C /Users/boxi/Development/QuartzHub log --oneline cc8ea5c^..ddcb802   # alles
    # Kern: Packages/QuartzHubCore/Sources/QuartzHubCore/
    #   Migration/  Formats/  Storage/  Snapshots/  Locks/  Process/  Environment/  Helpers/
    #   Publishing/ (mit SSH/, FTP/, Forms/)  Git/  Updates/  Projects/  Config/  Templates/
    # App: App/Shell/ (AppDeploy, ServerLifecycle, CoexistenceBand, MigrationSheet), App/Settings/, App/Projects/
    # Helfer: Helpers/src/ (yaml-edit, ftp-session, locale-edit, content-files)
    # Paket: scripts/package.sh, scripts/fetch-runtime.sh, project.yml

## Abwägungen, die niemand gegengelesen hat

**1. Die Übernahme aus QuartzControl** (`Migration/ProfileMigration.swift`, `ChromiumSafeStorage.swift`,
`Keychain.swift`). Beim ersten Start liest QuartzHub QuartzControls Profil und dessen mit Electrons
`safeStorage` verschlüsselte Geheimnisse und legt sie in den Schlüsselbund.
- Was geschieht bei einem halb gelesenen, kaputten oder von einer neueren QuartzControl-Fassung
  geschriebenen Profil? Bei einem Abbruch mitten in der Übernahme? Bei einem zweiten Start?
- Kann die Übernahme etwas an QuartzControls Profil oder an dessen Schlüsselbund-Eintrag ändern?
- Liegt ein entschlüsseltes Geheimnis je außerhalb des Schlüsselbunds (Datei, Log, Ausgabe,
  Absturzbericht)?

**2. Zwei Apps, dieselben Dateien** (`Formats/`, `Storage/JSONStore.swift`, `Migration/Coexistence.swift`,
`Locks/ProjectLock.swift`, `Snapshots/`). `.quartz-gui/`, `quartz-books/`, die Marker im Stylesheet
und der Snapshot-Index sind mit QuartzControl 1.3 geteilt.
- Schreibt QuartzHub irgendwo etwas, das QuartzControl 1.3 nicht lesen kann oder anders versteht
  (Feldnamen, Zahlenformat, Reihenfolge, Unicode-Normalform, Zeilenenden, Dateirechte)? Miss das an
  einer Kopie mit beiden Apps, wo es geht.
- Was geschieht, wenn beide Apps gleichzeitig am selben Projekt arbeiten (Sperren, Snapshots,
  Build-Server, Ziele)? Was sagt QuartzHub dazu, und stimmt es?
- Halten die Schreiber, was die Regel verspricht (Temp-Datei, `fsync`, `rename`; unlesbare Datei
  weggeräumt statt überschrieben)?

**3. Snapshots und Wiederherstellen** (`Snapshots/`, die Schreiber mit `SnapshotStore.Take`).
- Gibt es einen Schreiber, der Inhalte des Nutzers ändert, ohne vorher einen Snapshot zu nehmen?
- Stellt „Wiederherstellen“ genau den Stand her, auch bei Umbenennungen, Symlinks, NFD-Namen und
  Dateien, die seitdem dazugekommen sind? Kann es außerhalb des Projekts schreiben oder löschen?

**4. Kindprozesse und Pfade** (`Process/`, `Environment/`, `Helpers/`, alle Aufrufer).
- Erreicht ein Wert aus einem Projekt (Pfad, Name, Branch, Plugin-Name, URL, Config-Feld) je eine
  Shell oder eine Option eines Programms (fehlendes `--`, ein Name, der mit `-` beginnt)?
- Hat jeder Kindprozess eine Frist, und wird er bei Abbruch und beim Beenden der App beendet?
- Gibt es Stellen, die trotz `PathHygieneTests` über `URL` oder FileManager gehen und NFD-Namen
  zerlegen?

**5. Geheimnisse** (`Publishing/Connections.swift`, `SecretStore.swift`, `GitHubAPI.swift`, `Git/GitAuth.swift`,
`Publishing/Forms/`).
- Wo taucht ein Passwort, Token, Webhook-Pfad oder Relay-Geheimnis in einer Ausgabe, einem Log,
  einer Fehlermeldung, einer Kommandozeile (`ps`), einer Umgebung eines Kindprozesses oder einer
  Datei auf? Sind die Schwärzungen vollständig (auch in umkodierter Form)?
- Was geschieht, wenn der Schlüsselbund den Zugriff verweigert oder ein Eintrag fehlt?

**6. Veröffentlichen, was auf dem Server löscht** (`Publishing/`: Ordner, SFTP, rsync, FTP, Git-Branch,
Dokument, `DeployManifests.swift`, `DeployStaging.swift`).
- Kann ein Lauf auf dem Server etwas löschen oder überschreiben, das QuartzHub nicht selbst
  hochgeladen hat (Manifest, „Entfernte löschen“, Ausschlüsse, Pfade mit `..`, Symlinks im Build,
  ein Zielpfad, der leer oder `/` ist)?
- Sagt QuartzHub je „erfolgreich“, wenn etwas fehlte oder liegen blieb?
- Stimmen Diff, Frage und Lauf überein? Ist der Host-Key-Abgleich dicht?
- Weicht ein Adapter von QuartzControls `deploy/*.ts` ab, ohne dass die Abweichung in
  `docs/decisions/` steht?

**7. Git und Updates** (`Git/`, `Updates/CoreUpdate.swift`, `Updates/PluginUpdates.swift`).
- Kann ein Kern-Update oder Plugin-Update Änderungen des Nutzers verlieren (Stash, Merge, Abbruch
  mitten im Lauf, Konflikt)? Lässt es ein Projekt in einem Zustand zurück, den QuartzControl nicht
  versteht?

**8. Das Release-Paket** (`scripts/package.sh`, `fetch-runtime.sh`, `project.yml`, `#if DEBUG`).
- Kommt ein Debug-Schalter (`-QHMemorySecrets`, `-QHNoUpdateCheck`, `-QHMigrationSource`,
  `-QHProfileDir`, `-QHOpenProject` …) in den Release-Bau? Was davon wäre dort gefährlich?
- Sind Node, git und die Helfer gepinnt und geprüft, wie die Regel sagt? Was findet die Release-App
  zur Laufzeit außerhalb ihres Bundles?
- Steht etwas im Bundle, das nicht hineingehört (Testdaten, Pfade dieses Rechners, Quellkarten)?

## Worauf es ankommt, in dieser Reihenfolge

1. **Was Daten des Nutzers verliert oder verändert, die es nicht ändern soll**: Inhalte,
   QuartzControls Profil und Projekte, Dateien auf einem Server (1, 2, 3, 6, 7).
2. **Was ein Geheimnis offenlegt oder einem Wert aus einem Projekt Ausführung erlaubt** (4, 5).
3. **Was Erfolg sagt, wo keiner war**, und was QuartzControl 1.3 danach falsch liest (2, 6).
4. **Was im Release anders ist als im Debug-Bau** (8), und alles Übrige.

## Schon bekannt, nicht neu melden

Diese Punkte kennt der Nutzer. Melde einen nur, wenn er mehr kostet als hier steht:

- Die vier `fehlt`-Zeilen der Gleichstand-Liste (Handbuch-Links, Hinweis auf eine neuere Fassung)
  und die `gebaut`- und `Netz`-Zeilen mit ihren Gründen.
- Ungemessen: das Relay über FTPS, die Relay-Urteile hinter einem Zertifikat, dem macOS traut,
  eine Webhook-Antwort 2xx an der App, alles, was bei GitHub schreibt.
- „1 npm-Paket fehlt“ mit „Ohne sie baut …“ (Plural wie in QuartzControl); ohne Vorlage bleibt die
  Sprache der Website `en-US` (wie in QuartzControl); in einem Mermaid-Diagramm überdeckt ein Rahmen
  einen Subgraph-Titel; der Systemdialog trennt den Namen als „Quartz-Hub“.
- Der Debug-Bau findet Node, git und die Helfer im Repository (`ToolEnvironment`), der Release-Bau
  im Bundle. Die Debug-Schalter stehen unter `#if DEBUG`; prüf, ob das überall stimmt.

## Wenn du misst

Ändere nichts in diesem Repo, in QuartzControls Repo, in einem Vault oder in einem Projekt unter
`~/Documents/QuartzProjekte`. Arbeite in Kopien in deinem Ordner (im Folgenden `<r1>`, der Pfad
steht in der Nachricht, mit der du gestartet wurdest).

- **Lies nie etwas aus einem Projekt oder Vault namens `HinterlandHistory`/`hinterland-history`**,
  auch nicht in einer Schleife oder einem `grep` über alle Projekte. Nimm es aus jeder Liste,
  **bevor** du sie durchläufst. Nenn den Namen nicht in deinem Bericht.
- **Keine Anfrage an einen Host außerhalb dieses Rechners** außer an `debian-vm`. Kein `git push`,
  kein `gh`, keine Änderung an einem Repository bei GitHub.
- **Der echte Schlüsselbund bleibt unangetastet.** Starte QuartzHub immer mit
  `-QHMemorySecrets YES`, einem eigenen `-QHProfileDir <r1>/…`, `-QHMigrationSource` (leer oder eine
  Kopie eines Profils in `<r1>`, nie das echte unter `~/Library/Application Support/`),
  `-QHNoUpdateCheck YES` und `-ApplePersistenceIgnoreState YES`. Für das Ansehen gilt der Skill
  `.claude/skills/run-app/SKILL.md`. Beenden mit `pkill -x QuartzHub`.
- **Die App:** Eine Kopie des Debug-Baus von `ddcb802` liegt unter `<r1>/QuartzHub.app`; er findet
  Node, git und die Helfer im Repository (nur lesend). Bau nicht im Repository. Brauchst du einen
  eigenen Bau, klone nach `<r1>` und nimm `-derivedDataPath <r1>/…`; `Runtime/`, `.tools/` und
  `Helpers/node_modules` darfst du aus dem Repository kopieren. Die Kerntests laufen mit
  `swift test --package-path <dein Klon>/Packages/QuartzHubCore`. `xcodebuild … test` bewegt Maus und
  Tastatur; lass es weg.
- **QuartzControl nicht starten** (weder die installierte App noch einen Bau). Was nur ein Lauf von
  QuartzControl zeigen würde, prüfst du gegen dessen Quellcode oder mit dessen Node-Diensten in
  einem eigenen Klon unter `<r1>` und nennst es als gelesen bzw. so gemessen.
- **Klicke nie „Aktualisieren“ oder „Update durchführen“** in der App, auch nicht in einer Kopie.
- Als Projekte nimm Kopien per `cp -RL` (ohne `node_modules`) von `Example` und `gui-test` aus
  `~/Documents/QuartzProjekte`. In einer Kopie mit Symlink auf einen Vault schreibst du nichts unter
  `content/`, bevor der Symlink aufgelöst ist. Entferne vor dem Start jedes Veröffentlichungsziel aus
  `.quartz-gui/publish-targets.json` der Kopie, das nicht auf `<r1>` oder `debian-vm` zeigt; die
  Kopien von `gui-test` enthalten echte Ziele.
- **`debian-vm`** (per `ssh debian-vm`, Debian 13) ist die lokale Test-VM. Antwortet sie nicht, ist
  sie aus; nenn dann, was dadurch ungemessen bleibt. SFTP und rsync als `boxi` in eigenen Ordnern
  `~boxi/review1-*`; FTP (vsftpd) als `qchost` (Passwort in der Nachricht, mit der du gestartet
  wurdest) in `/srv/qc/www/review1-*`. Lege keine Konten an und ändere keine Passwörter, Schlüssel
  oder Server-Konfiguration. Räum deine Ordner dort am Ende weg.
- Mach Bildschirmfotos nur von Fenstern (`screencapture -o -l <id>`), nie vom ganzen Bildschirm.
  Öffne keine Links im Browser.
- Hat die Rechteprüfung einen Schritt abgelehnt, umgeh ihn nicht auf anderem Weg. Nenn ihn im
  Bericht als nicht gemessen. Fragt macOS nach einer Freigabe, entscheide nicht selbst; nenn es.

## Was du ablieferst

Einen Bericht auf Deutsch in `<r1>/review.md`, im Aufbau wie QuartzControls
`docs/REVIEW-2026-11-05.md`:

- Kopf mit Stand (Commit), Modell, was erreichbar war.
- Befunde nach Gewicht (Hoch, Mittel, Niedrig), je mit Ort (`datei:zeile`), Szenario, Beleg
  (gemessen oder gelesen, und womit) und einem Vorschlag.
- Getrennt davon eine Liste „Nebenbei“ für Kleinigkeiten.
- Zu jeder der acht Abwägungen eine Antwort, auch wenn sie „kein Befund“ lautet.
- Am Ende ein Urteil: was davon vor dem ersten Release behoben sein muss.
- Was du auf dem Mac und auf `debian-vm` angelegt hast und was davon noch liegt.

Kennzeichne bei jedem Befund, ob du ihn gemessen oder nur gelesen hast.
