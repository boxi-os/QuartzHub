> Bestandsaufnahme vom 2026-11-06 aus dem Code von QuartzControl `fix/1.3.x` (`0bbdb8cd`), Zeilenangaben
> relativ zu `../QuartzControl`. Erstellt von einem Lese-Agenten, Stichproben gegen den Code geprüft
> (Verschlüsselung, Relay-Fingerprint, `connections.json` lesen, Relay-Manifest `{}\n`, Marker-Namen).
> Überblick und was QuartzHub damit tut: [`../formats.md`](../formats.md).

# Formate in `<projekt>/.quartz-gui/` (QuartzControl 1.3, Stand `fix/1.3.x` @ 0bbdb8cd)

Quelle: Code unter `../QuartzControl` (nur gelesen). Zeilenangaben beziehen sich
auf diesen Stand. Gegengeprüft an echten Dateien (nur gelesen) in
`~/Documents/QuartzProjekte/gui-test/.quartz-gui/` und
`~/Documents/QuartzProjekte/Example/.quartz-gui/` — welche Datei wofür, steht je Abschnitt
unter „Geprüft“. Werte aus Dateien sind maskiert.

## Gemeinsame Regeln (gelten für alle Abschnitte)

### Verzeichnis anlegen: `quartzGuiDir` vs. `quartzGuiPath`

`electron/main/services/projectDirs.ts`:

- `quartzGuiDir(projectPath, ...sub)` (`projectDirs.ts:39`): `join(projectPath, '.quartz-gui', ...sub)`,
  `mkdirSync(recursive)` falls nicht vorhanden, danach **immer** `ensureIgnored(projectPath)`.
  Nur Schreiber rufen das.
- `quartzGuiPath(projectPath, ...sub)` (`projectDirs.ts:49`): nur `join`, legt nichts an. Alle Lesepfade.
  Regel (conventions.md): „Ein Lesepfad legt nie `.quartz-gui/` an.“
- Falle: `quartzGuiDir(p, 'datei.json')` legt ein *Verzeichnis* dieses Namens an. Darum schreiben alle
  Dateischreiber `join(quartzGuiDir(p), FILE)` (Kommentar `layoutFrameService.ts:46-48`).
- `ensureIgnored` (`projectDirs.ts:18-35`): nur wenn `<projekt>/.git` existiert. Liest `.gitignore`
  (fehlt = `''`), prüft zeilenweise (getrimmt) auf `.quartz-gui/` **oder** `.quartz-gui`. Fehlt beides,
  wird angehängt:
  ```
  <"\n" falls Datei nicht leer und nicht mit \n endet>\n# <mainT('gitignoreComment')>\n.quartz-gui/\n
  ```
  Kommentar de: `Arbeitsverzeichnis von QuartzControl (Backups, Presets, Deploy-Manifest)`,
  en: `QuartzControl working directory (backups, presets, deploy manifest)` (`electron/main/i18n.ts:190`,
  `:771`). Entscheidend ist nur die Regelzeile, nie der Kommentar. Schreiben mit `writeFileSync`
  (nicht atomar). Geprüft: `gui-test/.gitignore` endet mit `\n# Arbeitsverzeichnis … \n.quartz-gui/\n`.

### JSON-Stores (`electron/main/services/jsonStore.ts`)

- `writeJsonFile(path, v)` (`jsonStore.ts:111`) = `writeFileAtomic(path, JSON.stringify(v, null, 2))`:
  **2 Leerzeichen Einrückung, KEIN abschließender Zeilenumbruch.** Atomar: Temp-Datei
  `<path>.tmp-<pid>-<8 hex aus randomUUID>` im selben Ordner, `writeFile`, `fsync`, `close`, `rename`;
  bei Fehler wird die Temp-Datei gelöscht (`jsonStore.ts:121-139`).
- Plain `writeFile(..., JSON.stringify(v, null, 2), 'utf-8')` (nicht atomar) benutzen: Deploy-Manifeste,
  `.modes.json`, `.tilde.json`, `snapshot-settings.json`, `content-backups/<id>/symlink.json`. Format
  identisch (2 Leerzeichen, kein `\n` am Ende) — Ausnahme: das *erste* Relay-Manifest `'{}\n'`.
- `readJsonFile(path)` (`jsonStore.ts:70`): `missing` bei ENOENT; sonst `unreadable`, wenn nicht
  lesbar, kein gültiges JSON oder weder Objekt noch Array (auch `null`). Bei `unreadable` wird die Datei
  **beiseitegelegt**: `rename(path, <path>.corrupt-<ISO-Zeit, ':' und '.' durch '-' ersetzt>)`, z. B.
  `theme-presets.json.corrupt-2026-11-06T10-00-00-000Z`; Eintrag in eine Sitzungsliste
  (`listQuarantinedFiles`, Einstellungen-Seite).
- `readJsonFileOr(path, fallback)` (`jsonStore.ts:97`): `missing`/`unreadable` → `fallback`; außerdem
  quarantäniert, wenn Array/Objekt nicht zur Form des Fallbacks passt (`Array.isArray` verschieden).
- Schlüsselreihenfolge = Einfügereihenfolge der JS-Objekte (siehe je Abschnitt).

### Snapshot- und Kopierregeln (Übersicht, Details je Abschnitt)

- **Snapshot** (`snapshotService.ts:115-125`, `isSnapshotWorthy(entryName)` auf die *Einträge der
  obersten Ebene* von `.quartz-gui/`): ausgeschlossen sind `snapshots.git`, `snapshot-settings.json`,
  `backups`, `content-backups`, `logs`, `staging` und alles, was mit `deploy-manifest-` beginnt.
  Alles andere wird per `git add -f -- .quartz-gui/<name>` mitgenommen (`snapshotService.ts:156-157`).
  `-f` übergeht die Excludes, also landen auch `.DS_Store`, `backups.migrated/`, `*.corrupt-*`,
  `*.tmp-*`, `project-icon.json`, `icon-original.png`, `branch-worktree-*` im Snapshot.
  **Gemessen** am neuesten Snapshot von gui-test (`refs/snapshots/2026-11-04T19-57-54-592Z-cc90`):
  `.quartz-gui/` enthält `.DS_Store`, `authored-frames/`, `backups.migrated/` (39 Dateien),
  `core-update.json`, `forms-relay.json`, `layout-breakpoints.json`, `locale-baseline/`,
  `project-prefs.json`, `publish-targets.json`, `theme-presets.json`.
  Achtung: Der Legacy-Name `deploy-manifest.json` (ohne Bindestrich danach) beginnt **nicht** mit
  `deploy-manifest-` und wäre also im Snapshot (vermutlich unbeabsichtigt; im Code nicht ausgeschlossen).
- **Kopie** (`duplicateService.ts:31-84`): `fs.cp` mit Filter auf den Pfad relativ zur Projektwurzel.
  `SKIP` (exakt): `node_modules`, `public`, `content`, `.quartz-gui/snapshots.git`,
  `.quartz-gui/content-backups`, `.quartz-gui/publish-targets.json`, `.quartz-gui/deploy-manifest.json`,
  `.quartz-gui/project-prefs.json`, `.quartz-gui/logs`, `.quartz-gui/staging`,
  `.quartz-gui/forms-relay.json`. `SKIP_PREFIX`: `.quartz-gui/deploy-manifest-`,
  `.quartz-gui/branch-worktree-`. Alles andere wird kopiert (`verbatimSymlinks: true`). Danach
  `repointProjectPaths(source, target)` (absolute Pfade in Config/Lockfile/`.quartz/plugins`-Symlinks),
  `git remote remove origin`, `npm install`, `noteInstallSucceeded(target)`.
  Ausdrücklich **mitkopiert**: `core-update.json` (Begründung `duplicateService.ts:59-75`).

---

### `.gitignore`-Eintrag (Seiteneffekt, nicht in `.quartz-gui/`)

Siehe „Verzeichnis anlegen“. Jeder Schreiber in `.quartz-gui/` geht über `quartzGuiDir` und prüft damit
den Eintrag bei jedem Schreiben erneut (auch `ensureStore` des Snapshot-Stores, `snapshotService.ts:138`,
und `captureBaseline`). Gefunden wurde kein Schreiber, der `.quartz-gui/` an `quartzGuiDir` vorbei
anlegt. Die `.gitignore` ist eine normale Projektdatei: im Snapshot (über `git add -A`) und in der Kopie.

---

### `logs/` (Dev-Server-Ausgabe)

1. **Pfad** `.quartz-gui/logs/`. Schreiber: `openServerLog()` (`buildService.ts:371-439`), angelegt per
   `quartzGuiDir(projectPath, 'logs')` (`:379`). Leser: Main tailt die Dateien (`tailFile`) und gibt
   sie als Log-Events weiter; der Renderer liest nie direkt (Historie in `services/logBuffer.ts`, im
   Speicher).
2. **Layout/Namen** (`buildService.ts:324-328`):
   ```ts
   const LOG_FILE = /^dev-server(?:-(tmp-\d+|\d+))?\.(?:out|err)\.log$/
   // je Lauf ein Paar:
   `dev-server-${owner}.out.log`   // stdout
   `dev-server-${owner}.err.log`   // stderr
   ```
   Ablauf: Dateien werden zuerst als `owner = tmp-<Date.now()>` mit `openSync(path, 'w')` geöffnet, die
   Deskriptoren gehen als stdout/stderr an den Kindprozess; nach `spawn` werden beide auf
   `owner = <pid>` umbenannt (`adopt`, `:401-414`). Schlägt das Umbenennen fehl, bleibt der tmp-Name.
   Inhalt: rohe Ausgabe von Quartz (`npx quartz build --serve`), keine eigene Struktur.
3. **Rotation/Aufräumen** `pruneServerLogs(dir)` (`:335-356`) bei jedem Serverstart: löscht jede Datei,
   die auf `LOG_FILE` passt, **außer** `owner` ist eine Zahl, deren Prozess lebt *und* nach
   `looksLikeQuartzServer(pid)` noch ein Quartz-Server ist. Die alten festen Namen
   `dev-server.out.log`/`dev-server.err.log` (ohne Owner) und `tmp-…`-Paare werden immer gelöscht.
   Fremde Dateinamen bleiben liegen. Kann nicht geschrieben werden (EACCES etc.), startet der Server
   ohne Konsole und meldet `serverLogUnavailable` als `warn` (`:430-438`).
4. **Legacy**: früher ein festes Paar `dev-server.out.log`/`.err.log` (wird beim Start gelöscht).
5. **Snapshot**: nein (`isSnapshotWorthy`). **Kopie**: nein (`SKIP`).

Geprüft: `gui-test/.quartz-gui/logs/` = `dev-server-13404.err.log`, `dev-server-13404.out.log`;
`Example/.quartz-gui/logs/` = `dev-server-23127.{err,out}.log`.

---

### `authored-frames/<id>/` (eigene Frames als lokale Quartz-Plugins)

1. **Pfad** `.quartz-gui/authored-frames/<id>/` mit `frame.json`, `package.json`, `dist/frames.js`.
   Schreiber: `writeFrameFiles()` (`layoutFrameService.ts:459-480`), aufgerufen von `saveFrame()`
   (`:653`), `saveBreakpointWidths()` (`:68`, schreibt alle Frames neu), `writeAllFrames()` (`:499`,
   vor jedem Build und jedem `--serve`-Start, aus `buildService.refreshAuthoredFrames`) und dem
   Vorlagen-Import (`templatePackage/parts.ts:851`, via `saveFrame(…, {snapshot:false})`). Löschen:
   `deleteFrame()` (`:680-687`: `quartz plugin remove <id>`, dann `rmSync(dir, recursive)`).
   Leser: `listFrames()` (`:523-548`), `authoredFrameDir()`; `framePaths.ownFramePath()`.
   Schreibreihenfolge serialisiert je Projekt (`serialised`, `:441-457`).
2. **id**: `FRAME_ID_RE = /^[a-z0-9][a-z0-9-]{0,63}$/i` (`:38`); in der Praxis `frame-<ms-Zeitstempel>`
   oder `frame-<name>`. Die id ist Verzeichnisname **und** Plugin-Name (Quartz leitet ihn vom Basename
   des lokalen Pfads ab). Registrierung nur beim Neuanlegen: `quartz plugin add <absoluter Pfad>`
   (`pluginService.addPlugin`, mit Snapshot) bzw. `installPluginSource` (Vorlagen-Import, ohne).
   Quartz legt `.quartz/plugins/<id>` als **Symlink** auf dieses Verzeichnis an; `quartz.config.yaml`
   (`source`) und `quartz.lock.json` (`source`, `resolved`) enthalten den **absoluten Pfad**
   `<projekt>/.quartz-gui/authored-frames/<id>` (siehe `projectPaths.ts:10-30`, Reparatur durch
   `repointProjectPaths`/`repointAuthoredFrames`, Marker `/.quartz-gui/authored-frames/`
   in `framePaths.ts:6`).

   `frame.json` = `GridFrameDefinition` (`shared/ipc-contract.ts:200-205`, Teiltypen `:139-198`):
   ```ts
   type FrameBreakpoint = 'desktop' | 'tablet' | 'mobile'
   type LayoutPosition = 'header' | 'left' | 'right' | 'beforeBody' | 'afterBody' | 'footer' // ipc-contract.ts:20
   type FrameSlot = LayoutPosition | 'pageBody'
   type FrameAlign = 'left' | 'center' | 'right'
   interface GridAreaPlacement { row: number; col: number; rowSpan: number; colSpan: number; hidden?: boolean } // 1-basiert
   interface GridFrameArea { id: string; name: string; slot?: FrameSlot; group?: string }
   interface GridBreakpointLayout {
     rows: number; cols: number
     columnSizes?: string[]; rowSizes?: string[]        // fehlend/kürzer → '1fr' bzw. 'auto'
     rowGap: string; columnGap: string
     maxWidth?: string; align?: FrameAlign; paddingBlock?: string; paddingInline?: string
     columnLineNames?: Record<number, string[]>; rowLineNames?: Record<number, string[]>
     placements: Record<string, GridAreaPlacement>      // Schlüssel = GridFrameArea.id
   }
   interface GridFrameDefinition {
     id: string; frameName: string; areas: GridFrameArea[]
     breakpoints: Record<FrameBreakpoint, GridBreakpointLayout>
   }
   ```
   Geschrieben wird das Objekt, wie es aus `migrateGridFrameDefinition` kommt (Renderer bzw. `.qtpl`),
   geprüft vorher durch `frameDefinitionProblem()` (`:629-651`: zod `gridFrameDefinition` aus
   `ipc/schemas.ts`, eindeutige Bereichsnamen, keine Doppelbelegung slot+group).

   `package.json` (`generatePackageJson`, `:393-405`), exakt:
   ```json
   {
     "name": "<id>",
     "version": "1.0.0",
     "private": true,
     "type": "module",
     "quartz": {
       "frames": {
         "Frame": {
           "exportName": "Frame"
         }
       }
     }
   }
   ```
   `dist/frames.js`: generiertes ES-Modul (`generateFrameJs`, `:98-390`) mit eingebackenen Konstanten
   `FRAME_NAME`, `AREAS`, `GROUP_LAYOUTS` (aus `groupLayoutCandidates(config, frameName)`), dazu dem
   CSS aus `buildFrameCss` mit den Breakpoint-Breiten. Hängt von `quartz.config.yaml` und
   `layout-breakpoints.json` ab und wird deshalb vor jedem Build neu erzeugt. Für Byte-Gleichheit
   müsste QuartzHub den Generator 1:1 nachbauen (Template-String, nicht Teil dieser Erhebung).
3. **Schreiben**: alle drei atomar — `frame.json` per `writeJsonFile` (2 Leerzeichen, kein `\n`),
   `package.json` und `dist/frames.js` per `writeFileAtomic` (package.json ebenfalls ohne `\n`).
   Verzeichnisse per `mkdirSync(join(dir,'dist'), recursive)`. **Defekte `frame.json`**: wird *nicht*
   quarantäniert; `listFrames` loggt per `console.error` und lässt den Frame aus der Liste
   (`:536-545`). Nicht-Verzeichnisse in `authored-frames/` werden ignoriert.
4. **Migration**: `LegacyGridFrameDefinition` (`ipc-contract.ts:210-217`):
   ```ts
   interface LegacyGridFrameDefinition {
     id: string; frameName: string; rows: number; cols: number; gap: string
     areas: Array<{ id: string; name: string; slot: FrameSlot; row: number; col: number; rowSpan: number; colSpan: number }>
   }
   ```
   Erkannt an `typeof def.rows === 'number'` (`gridFrameCss.ts:555-557`). `migrateGridFrameDefinition`
   (`gridFrameCss.ts:563-588`): areas → `{id,name,slot}`; desktop = `{rows, cols, rowGap: gap,
   columnGap: gap, placements}`, tablet/mobile = Kopien. Beim Lesen in-memory migriert; auf Platte erst
   beim nächsten Schreiben (also spätestens beim nächsten Build durch `writeAllFrames`).
   Optional nachgerüstete Felder (`slot?`, `group?`, `maxWidth`/`align`/`padding*`) — fehlend = alt.
5. **Snapshot**: ja (inkl. `dist/`). **Kopie**: ja; danach `repointProjectPaths`. Beim Restore eines
   Snapshots, der Config/Lockfile berührt: `repointAuthoredFrames` (`snapshotService.ts:562-564`).

Geprüft: `gui-test/.quartz-gui/authored-frames/` (5 Frames, je `frame.json`, `package.json`,
`dist/frames.js`); `frame.json` und `package.json` enden auf `}` ohne `\n`.

---

### `content-backups/<timestampId>/` (beiseitegelegter Content-Ordner)

1. **Pfad** `.quartz-gui/content-backups/<id>/`. Schreiber: `snapshotContent()` (`backupService.ts:35-50`),
   aufgerufen von `contentService.changeContentSource()` (`contentService.ts:392-394`, nach einem
   Snapshot `contentChange`) und von `restoreContentBackup()` (`backupService.ts:124-139`) vor dem
   Zurückholen. Leser: `listContentBackups()` (`:83-112`), `restoreContentBackup()`; Löschen
   `deleteContentBackup()` (`:118-122`).
2. **Name**: `timestampId() = new Date().toISOString().replace(/[:.]/g, '-')`, z. B.
   `2026-09-04T16-56-37-340Z`; gelistet wird nur, was `TIMESTAMP_ID_RE =
   /^(\d{4}-\d{2}-\d{2}T\d{2})-(\d{2})-(\d{2})-(\d{3})Z$/` erfüllt und ein Verzeichnis ist.
   `createdAt` = Rückübersetzung (`idToIso`), nicht mtime. Inhalt **eins** von beiden:
   - `content/` — der alte echte Content-Ordner, per `rename` verschoben (kein Kopieren).
   - `symlink.json` — war `content` ein Symlink: `JSON.stringify({ target }, null, 2)` mit
     `target = readlink(content)` (roh, kann relativ sein), danach wird nur der Link entfernt.
   ```ts
   // nicht persistiert, nur Antwort an den Renderer (ipc-contract.ts:600-614)
   interface BackupEntry { id: string; createdAt: string; kind: 'folder' | 'link'; sizeBytes: number; fileCount: number; target?: string }
   ```
   `sizeBytes`/`fileCount` werden bei jedem Listen gemessen (Symlinks nicht gefolgt).
3. **Schreiben**: `symlink.json` per plain `writeFile` (2 Leerzeichen, kein `\n`). Unlesbares
   `symlink.json` beim Listen → `kind:'link'` ohne `target`; beim Restore wirft `JSON.parse`.
   Restore: Link per `symlink(target, contentDir, 'dir')` oder `cp(<id>/content, contentDir, recursive)`
   (kopiert, damit das Backup wiederverwendbar bleibt).
4. **Legacy**: früher als „Backups → Inhalte“ präsentiert; Format unverändert.
5. **Snapshot**: nein. **Kopie**: nein.

Geprüft: `Example/.quartz-gui/content-backups/2026-09-04T16-56-37-340Z/content/` (Ordner-Variante);
`gui-test/.quartz-gui/content-backups/` leer. Ein `symlink.json` lag nirgends vor (nicht am Beispiel
geprüft).

---

### `backups/` (Legacy, Config-Kopien) → `backups.migrated/`

1. **Pfad** `.quartz-gui/backups/` (vor dem Snapshot-Store, abgelöst in Commit `56fbfb5f` „Replace three
   backup mechanisms with one snapshot store“). Heute schreibt **niemand** mehr dorthin. Leser/Migrator:
   `migrateConfigBackupsUnlocked()` (`snapshotService.ts:354-414`), ausgelöst bei **jedem**
   `snapshot:list` (`ipc/handlers.ts:599-602`).
2. **Inhalt**: `<timestampId>.yaml` = wörtliche Kopie von `quartz.config.yaml`; nur Namen nach
   `/^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z\.yaml$/` werden importiert (sortiert, älteste zuerst).
3. **Migration**: zuerst `rename('backups', 'backups.migrated')` (gewinnt genau einer; scheitert → 0).
   Dann `ensureStore`. Je Datei: `git hash-object -w` → `git mktree` mit
   `100644 blob <sha>\tquartz.config.yaml\n` → `git commit-tree <tree> -m 'imported -'` mit
   `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` = Zeitstempel aus dem Namen → Ref
   `refs/snapshots/<timestampId>-0000`. Danach `pruneAutomaticUnlocked`. `backups.migrated/` bleibt
   liegen und wird nie gelöscht.
4. Kind `imported` gilt als **partiell**: Diff/Restore nur auf die enthaltenen Pfade (`isPartial`).
5. **Snapshot**: `backups` nein; **`backups.migrated` ja** (nicht in `isSnapshotWorthy` ausgeschlossen —
   gemessen, 39 Dateien im neuesten gui-test-Snapshot). **Kopie**: beide ja (nicht in `SKIP`).

Geprüft: `gui-test/.quartz-gui/backups.migrated/` (Dateien wie `2026-08-23T01-58-03-022Z.yaml`); im Store
`refs/snapshots/2026-08-26T18-27-43-683Z-0000` mit Subject `imported -`.

---

### `snapshots.git/` (Snapshot-Store, eigenes Git-Repo)

1. **Pfad** `.quartz-gui/snapshots.git/`. Alles in `electron/main/services/snapshotService.ts`.
   Git-Aufruf immer `git --git-dir <projekt>/.quartz-gui/snapshots.git --work-tree <projekt> …`
   (`:83-89`), cwd = Projekt. Alle Index-Operationen pro Projekt serialisiert (`serialize`, `:61-73`).
   `listSnapshots`/`getSettings` laufen ohne Warteschlange.
2. **Anlegen** `ensureStore()` (`:135-149`), wenn `<store>/HEAD` fehlt:
   ```
   quartzGuiDir(projectPath)                         # legt .quartz-gui/ + .gitignore-Regel an
   git init --bare --quiet <store>
   git --git-dir <store> config core.bare false
   git --git-dir <store> config user.name QuartzControl
   git --git-dir <store> config user.email snapshots@quartzcontrol.local
   ```
   Bei **jedem** `ensureStore` wird `<store>/info/exclude` neu geschrieben (`writeExcludes`, `:127-133`,
   plain `writeFile`, Zeilen mit `\n` getrennt **und** abschließendem `\n`):
   ```
   /node_modules/
   /public/
   /prof/
   /.quartz/
   /.quartz-cache/
   /.turbo/
   /.git/
   /.quartz-gui/
   /tsconfig.tsbuildinfo
   .DS_Store
   /content/            # nur wenn includeContent === false
   ```
   **Staging** `stage()` (`:151-165`): `git add -A` (Fehler → Exception), dann `git add -f -- <je
   isSnapshotWorthy-Eintrag aus readdir(.quartz-gui)>`, und bei `includeContent:false`
   `git rm -r --cached --quiet --ignore-unmatch -- content`.
3. **Refs/Commits**: keine Branches (HEAD des Bare-Repos bleibt ungenutzt), jeder Snapshot ist ein
   **Root-Commit ohne Parent**, gehalten von `refs/snapshots/<id>`.
   ```ts
   // id (newSnapshotId, :223-228): ISO-Zeit mit ':'/'.' → '-', plus '-' + 2 Zufallsbytes hex
   `${new Date().toISOString().replace(/[:.]/g, '-')}-${randomBytes(2).toString('hex')}` // 2026-11-04T19-57-54-592Z-cc90
   // IPC-Schema (ipc/schemas.ts:60-62): /^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z-[0-9a-f]{4}$/
   // importierte: <timestampId>-0000
   ```
   Commit-Erzeugung (`createSnapshotUnlocked`, `:233-284`): `write-tree` → `commit-tree <tree> -m
   <subject>` → `update-ref refs/snapshots/<id> <commit>` → `gc --auto --quiet` → (nicht-KEPT)
   `pruneAutomaticUnlocked`. Autor/Committer = `QuartzControl <snapshots@quartzcontrol.local>`,
   Datum = jetzt (git-Standard).
   **Subject** (eine Zeile): `"<kind> <projectHead|'-'>[ <label>]"`; `projectHead` = `git rev-parse HEAD`
   des Projekt-Repos, `-` wenn keins; `label` = `rawLabel.replace(/\s+/g,' ').trim().slice(0,120)`.
   Beispiele (gui-test): `configChange c60a2c5a…`, `pluginChange 559ec1c5… quartz-multilanguage`,
   `styleChange 7b35fd2d… Basis-Template`, `imported -`.
   ```ts
   type SnapshotKind = 'manual' | 'configChange' | 'coreUpdate' | 'pluginChange' | 'contentChange'
     | 'restore' | 'styleChange' | 'styleMigration' | 'imported'          // ipc-contract.ts:1142-1153
   interface Snapshot { id: string; commit: string; createdAt: string; kind: SnapshotKind; label: string; projectHead?: string } // :1155-1164
   ```
   Lesen (`listSnapshots`, `:286-313`): `for-each-ref --format='%(refname) %(objectname)
   %(creatordate:iso-strict) %(subject)' refs/snapshots/`, Split an Leerzeichen: `[refname, commit,
   createdAt, kind, projectHead, ...label]`; `kind` leer → `'manual'`, `projectHead '-'` → undefined;
   Sortierung absteigend nach id (String).
   Labels der Aufrufer: `pluginChange` = Plugin-Quelle/-Name (`pluginService.ts:25,30`,
   `updateService.ts:2012`), `styleChange` = Vorlagenname (`templatePackage/index.ts:282`), sonst `''`;
   `manual` = vom Nutzer (`handlers.ts:604`, max. 200 Zeichen im Schema, gekürzt auf 120).
   **Regeln**: nicht-KEPT (`manual`, `styleMigration` sind KEPT) wird übersprungen, wenn der Tree dem
   neuesten Snapshot gleicht; `configChange` zusätzlich, wenn innerhalb 15 min schon einer existiert.
   **Ausdünnen** (`:608-631`): nicht-KEPT, < 24 h alle; < 7 Tage einer je `day-YYYY-MM-DD`; < 56 Tage
   je `week-<floor(ms/7d)>`; älter je `month-YYYY-MM` (UTC); der neueste je Eimer bleibt; danach
   `update-ref -d` und `gc --prune=now --quiet`. Löschen: `update-ref -d` + `gc --prune=now --quiet`.
   Export: `git archive --format=zip --prefix=<id>/ -o <datei> <commit>`.
   Restore: vorher Snapshot `restore`; ganz = `read-tree -u --reset <commit>`, Auswahl =
   `checkout <commit> -- <≤1000 Pfade je Batch>` + Löschen fehlender; Content-Symlink wird dabei
   geparkt (`contentSymlink.ts`, nur im Speicher); optional `git reset --hard <projectHead>` im Projekt;
   danach ggf. `repointAuthoredFrames`, `npm install`.
4. **Versionen**: ersetzt drei ältere Mechanismen (Config-Backups `backups/`, Content-„Backups“, Update-
   Tags `git stash create`). Store selbst unversioniert; Format = obige Konventionen.
5. **Snapshot**: nie in sich selbst. **Kopie**: nein (`SKIP`).

Geprüft: `gui-test/.quartz-gui/snapshots.git/` (`config` mit `bare = false`, `[user]` wie oben,
`info/exclude` wie oben ohne `/content/`, `packed-refs`, nur `refs/snapshots/*`).

---

### `snapshot-settings.json`

1. Schreiber `saveSettingsUnlocked()` (`snapshotService.ts:206-218`); Leser `getSettings()` (`:189-204`),
   auch `ensureStore`.
2. ```ts
   // auf Platte
   { includeContent: boolean }
   // abgeleitet (ipc-contract.ts:1186-1190)
   interface SnapshotSettings { includeContent: boolean; contentExists: boolean; contentIsSymlink: boolean }
   // includeContent = contentIsSymlink ? false : (stored.includeContent ?? contentExists)
   ```
   Beim Schreiben ebenfalls normalisiert: Symlink → immer `false`.
3. plain `writeFile`, `JSON.stringify({includeContent}, null, 2)`, kein `\n`. Lesen per `JSON.parse` in
   `try/catch` → bei Fehler/fehlend `{}` (**keine Quarantäne**). Nach dem Schreiben `writeExcludes`.
4. —
5. **Snapshot**: nein. **Kopie**: ja.

Geprüft: `gui-test/.quartz-gui/snapshot-settings.json` = `{\n  "includeContent": true\n}` (ohne `\n`).
In Example nicht vorhanden (dann abgeleitet).

---

### `staging/<targetId>/`

1. Schreiber `stageWithDocuments()` (`deploy/staging.ts:54-89`), nur wenn `target.withDocuments`
   nicht leer. Angelegt per `quartzGuiDir(projectPath, 'staging', target.id)`, vorher `rm -rf`.
2. Inhalt: Spiegel des Build-Ordners (Dateien als Hardlinks, Fallback Kopie; Symlinks nicht übernommen)
   plus `downloads/<bookId>.<pdf|epub|html>` (Kopien der Dateien der genannten Dokument-Ziele). Wird
   für jede Vorschau/jeden Lauf neu erzeugt und über `remove()` danach gelöscht.
3. Kein JSON. Nach Absturz kann es liegen bleiben (wird beim nächsten Mal ersetzt).
4. Neu in 1.3.
5. **Snapshot**: nein. **Kopie**: nein.

Nicht an echten Dateien geprüft (kein Vorkommen).

---

### `branch-worktree-<targetId>/`

1. `worktreePath()` (`deploy/gitBranch.ts:42-44`) = `join(quartzGuiDir(projectPath), 'branch-worktree-' + target.id)`.
   Im Projekt-Repo registrierter **git worktree** (`git worktree add --detach <dir>`, `:74`), Inhalt =
   Build-Kopie (`cp`), `git add -A --force`, `write-tree`, Commit `commit-tree <tree> -m "Deploy <ISO>"`
   ohne Parent, Push auf `refs/heads/<branch>` mit Lease. Vorher `git worktree prune`,
   `worktree remove --force`, `rm -rf` (`:60-62`); danach `worktree remove --force` (`:171`, `:221`).
2. Inhalt: Build-Dateien + `.git`-Datei, die in `<projekt>/.git/worktrees/…` zeigt.
3. Nur Überbleibsel eines abgebrochenen Deploys.
4. **Legacy**: früher ein gemeinsamer Pfad für alle Ziele (Name im Code nicht mehr genannt; `worktree
   prune` räumt dessen Registrierung).
5. **Snapshot**: würde mitgenommen (Präfix nicht ausgeschlossen) — `git add -f` auf ein Verzeichnis mit
   `.git`-Datei ergibt vermutlich einen Gitlink; nicht gemessen. **Kopie**: nein (`SKIP_PREFIX`).

---

### `deploy-manifest.json` (Legacy, ein Manifest pro Projekt)

1. Nur noch gelesen: `readManifest()` (`deploy/manifest.ts:27-45`). Kann die Ziel-eigene Datei nicht
   gelesen werden (fehlt **oder** kaputt) und existiert `deploy-manifest.json`, wird sie per `rename`
   zu `deploy-manifest-<targetId>.json` des **ersten fragenden Ziels** gemacht (überschreibt dabei eine
   kaputte Zieldatei). Danach erneut gelesen; Fehler → `{}`.
2. Form wie unten (`Record<string,string>`).
3. —
4. Vor der Aufteilung pro Ziel. Ein Relay-Lauf legt vorher seine eigene Datei an, damit er das Legacy-
   Manifest nicht adoptiert (`deploy/index.ts:190-197`).
5. **Snapshot**: nicht ausgeschlossen (Name beginnt nicht mit `deploy-manifest-`) — vermutlich Lücke.
   **Kopie**: nein (`SKIP`).

---

### `deploy-manifest-<targetId>.json` (Site-Ziele) und `deploy-manifest-relay-<targetId>.json`

1. Schreiber: `writeManifest()` (`deploy/manifest.ts:47-49`) über `commitManifest()` (`:153-181`, nach
   erfolgreichem Lauf in `sftp.ts:346`, `ftp.ts:323`, `folder.ts:184`) und `reanchorTildeManifest()`
   (`:116-122`). Löschen: `forgetManifest()` (`:83-85`) — bei „Alles neu hochladen“, bei Umzug eines
   Ziels (`publishTargetsService.saveTarget`, `:101-102`, wenn sich `connectionId|type|remotePath/path/
   provider:branch` ändert) und vor jedem Relay-Lauf. Leser: `readManifest()`, `diffAgainstManifest()`.
   **rsync** und **git-branch** nutzen kein Manifest. `webhook`/`document`: keins.
   Relay: `formsService.ts:729`, `:817` ruft `runDirectoryUpload(…, manifestKey = 'relay-' + target.id)`;
   die Datei heißt also `deploy-manifest-relay-<targetId>.json`. `runDirectoryUpload`
   (`deploy/index.ts:160-230`): `forgetManifest`, dann
   - Upload: falls nicht vorhanden `writeFile(file, '{}\n')` (**mit** `\n`, einzige Ausnahme),
   - Entfernen: `writeFile(file, JSON.stringify(Object.fromEntries(remove.map(p => [p, 'remove'])), null, 2))`,
   danach schreibt der Adapter per `commitManifest` die echte Form.
2. ```ts
   type Manifest = Record<string, string>  // manifest.ts:15
   // Schlüssel: Pfad relativ zum Build-Ordner (bzw. Relay-Ordner), '/' als Trenner
   // Wert: sha256 hex (64 Zeichen) des Dateiinhalts
   //       '' nach reanchorTildeManifest (alle Hashes geleert → alles wird neu hochgeladen)
   //       'remove' im Entfernen-Vorlauf des Relays
   ```
   `commitManifest`: neue Hashes aller Dateien; ausgeschlossene Pfade behalten ihren alten Eintrag oder
   fehlen; entfernte+ausgeschlossene bleiben. Schlüsselreihenfolge: Einfügereihenfolge von
   `buildCurrentManifest` mit 32 parallelen Hash-Workern, d. h. grob `readdir`-Reihenfolge (APFS:
   sortiert), aber **nicht garantiert**; danach die übernommenen Einträge.
3. plain `writeFile` (nicht atomar), 2 Leerzeichen, kein `\n` (außer `'{}\n'`). Lesen per `JSON.parse`
   in `try/catch`; kaputt/fehlt → Legacy-Adoption oder `{}` (= „alles hochladen“), **keine Quarantäne**;
   der nächste erfolgreiche Lauf überschreibt.
4. Legacy siehe oben; Tilde-Re-Anchoring siehe `.tilde.json`.
5. **Snapshot**: nein (Präfix). **Kopie**: nein (`SKIP_PREFIX`).

Geprüft: `gui-test/.quartz-gui/deploy-manifest-35bfe4aa-….json` (54 KB, Schlüssel alphabetisch,
Werte sha256, Ende `"\n}`), `deploy-manifest-relay-35bfe4aa-….json` (Schlüssel `config.generated.php`,
`config.php`, `counters/.htaccess`, `counters/qf-probe.count`, `send.php`; Werte sha256; Ende `"\n}`).

---

### `deploy-manifest-<targetId>.modes.json`

1. Schreiber `settleModes()` (`deploy/manifest.ts:98-100`), nur SFTP-Adapter (nicht rsync), nur ohne
   `keepLocalModes` (also nie für das Relay), erst wenn der Server zu jeder Datei geantwortet hat
   (`sftp.ts:223`, `:343`). Leser `modesSettled()` (`:94-96`) — **nur `existsSync`**, Inhalt wird nie
   gelesen.
2. ```ts
   { mode: '0644', at: string /* new Date().toISOString() */ }
   ```
3. plain `writeFile`, 2 Leerzeichen, kein `\n`. Inhalt egal.
4. Marker der einmaligen 0666→0644-Korrektur für Uploads von 1.0.0–1.1.0 (ab 1.1.1).
5. **Snapshot**: nein. **Kopie**: nein.

Geprüft: `gui-test/.quartz-gui/deploy-manifest-35bfe4aa-….modes.json` =
`{\n  "mode": "0644",\n  "at": "2026-10-25T13:02:02.208Z"\n}` (ohne `\n`).

---

### `deploy-manifest-<targetId>.tilde.json`

1. Schreiber/Leser `reanchorTildeManifest()` (`deploy/manifest.ts:116-122`), aufgerufen in
   `makeContext()` (`deploy/index.ts:55-60`) für `ftp` oder `sftp` mit `transfer !== 'rsync'`, deren
   `remotePath` mit `~` beginnt. Ist der Marker da → nichts. Sonst: alle Manifest-Werte auf `''`, dann
   Marker schreiben. Nur `existsSync` wird geprüft.
2. ```ts
   { at: string /* ISO */ }
   ```
3. plain `writeFile`, 2 Leerzeichen, kein `\n`.
4. Seit 1.1.1 („~“ = Login-Verzeichnis); einmal je Ziel.
5. **Snapshot**: nein. **Kopie**: nein.

Nicht an echten Dateien geprüft (kein Vorkommen).

---

### `core-update.json` (offene Arbeit eines Core-Updates)

1. Schreiber `markInstallPending()` (`updateService.ts:762-783`; Aufrufe `:1404`, `:1465`, `:1517`,
   `noteInstallSucceeded` `:794-798`) und `clearInstallPending()` (`:800-808`, Aufruf `:1636`).
   Leser `readPendingInstall()` (`:721-760`), genutzt von `outstandingCoreInstall` (Badge) und dem
   Update-Lauf. Schreibfehler werden gemeldet, der Lauf geht weiter.
2. Auf Platte (Schlüsselreihenfolge fest):
   ```ts
   {
     installPendingFor: string      // voller SHA (40 oder 64 hex) des Merge-Commits, '' = nichts offen
     reinstall: PackageAddition[]   // eigene Pakete, die das Update aus package.json genommen hat
     filesAtHead: boolean           // package.json/Lockfile waren bei Laufbeginn exakt HEAD
     installFailed: boolean         // npm install dieses Laufs scheiterte
     putBack: string[]              // Namen aus reinstall, die npm schon zurückgeschrieben hat (dedupliziert, ⊆ reinstall)
   }
   interface PackageAddition { name: string; section: DependencySection; range: string } // shared/packageJsonDeps.ts:30-35
   type DependencySection = 'dependencies' | 'devDependencies' | 'optionalDependencies' | 'peerDependencies' // :21
   ```
   In-memory (`interface PendingInstall`, `:607-613`): `{ head, reinstall, filesAtHead, installFailed, putBack }`.
   Normalisierung beim Lesen: `head` nur bei `/^[0-9a-f]{40}([0-9a-f]{24})?$/`, sonst `''`;
   `filesAtHead`/`installFailed` nur `=== true`; `reinstall`-Einträge nur mit `name`/`range` nicht leer
   und nicht mit `-` beginnend, `section` aus der Liste; `putBack` nur solche Strings.
   Leerzustand (von `clearInstallPending`):
   `{"installPendingFor":"","reinstall":[],"filesAtHead":false,"installFailed":false,"putBack":[]}`.
3. `writeJsonFile` (atomar, 2 Leerzeichen, kein `\n`); Lesen `readJsonFileOr(…, {})` → kaputt wird
   quarantäniert, Array wird quarantäniert, Ergebnis „nichts offen“.
4. Felder kamen nacheinander dazu (`filesAtHead`, `installFailed`, `putBack`); fehlend = `false`/`[]`.
5. **Snapshot**: ja. **Kopie**: ja, bewusst; nach dem `npm install` der Kopie wird nur `installFailed`
   auf `false` gesetzt.

Geprüft: `gui-test` und `Example` (je 115 Byte, Leerzustand, Ende `[]\n}`).

---

### `project-prefs.json`

1. Schreiber `savePrefs()` (`projectPrefsService.ts:20-22`), Leser `getPrefs()` (`:14-18`).
2. ```ts
   interface ProjectPrefs { outputDir: string } // ipc-contract.ts:558-561; '' = Quartz-Standard public/
   // Lesen: outputDir nur als string übernommen, sonst ''
   ```
   `outputDir` kann absolut sein (`resolveBuildDir`, `projectDirs.ts:59-62`).
3. `writeJsonFile` (atomar, kein `\n`); `readJsonFileOr(…, {outputDir:''})` → Quarantäne bei Defekt
   oder Array. Geschrieben wird das Renderer-Objekt (ggf. weitere Schlüssel, wenn das Schema sie
   durchlässt — nicht geprüft).
4. —
5. **Snapshot**: ja. **Kopie**: nein (absoluter Pfad des Originals; `duplicateService.ts:41-47`).

Geprüft: `gui-test` = `{\n  "outputDir": "…"\n}` (21 Byte, Wert leer).

---

### `publish-targets.json`

1. Schreiber `write()` (`publishTargetsService.ts:26-28`) aus `listTargets()` (Migration),
   `saveTarget()` (`:78-104`), `deleteTarget()` (`:106-112`). Leser `read()`/`listTargets()`/`getTarget()`.
2. ```ts
   interface PublishTarget {                 // ipc-contract.ts:1324-1333
     id: string                              // randomUUID()
     name: string
     connectionId?: string                   // fehlt bei folder, git-branch (und document)
     destination: PublishDestination
     excludes: string[]
     withDocuments?: string[]                // nur wenn nicht leer und type ∉ {document, webhook}
   }
   type PublishDestination =                 // :1300-1318
     | { type: 'sftp'; remotePath: string; transfer: 'sftp' | 'rsync'; deleteRemoved: boolean }
     | { type: 'ftp'; remotePath: string; deleteRemoved: boolean }
     | { type: 'folder'; path: string; deleteRemoved: boolean }
     | { type: 'webhook' }
     | { type: 'git-branch'; branch: string; provider: 'github' | 'gitlab' | 'codeberg' }
     | { type: 'document'; path: string; bookId: string; formats: DocumentFormat[] } // 'pdf'|'epub'|'html'
   ```
   `saveTarget` baut das Objekt in der Reihenfolge `...unbekannteSchlüssel, id, name, connectionId,
   destination, excludes, [withDocuments]` (`:84-96`) — **unbekannte Schlüssel eines bestehenden
   Eintrags bleiben erhalten** (KNOWN = id, name, connectionId, destination, excludes, withDocuments).
   `connectionId: undefined` fällt bei `JSON.stringify` weg. `excludes` bleibt beim Bearbeiten, wenn nicht
   mitgegeben.
3. `writeJsonFile` (atomar, kein `\n`); `readJsonFileOr(…, [])` → Quarantäne bei Defekt oder Objekt.
4. **Migration** in `listTargets()` (`:30-55`): Alt-Profile mit `remotePath` aus `connectionsService.
   claimLegacyTargets()` (userData) werden einmalig zu Zielen `{id: randomUUID(), name, connectionId,
   destination: sftp → {type:'sftp', remotePath, transfer:'sftp', deleteRemoved:true} | ftp → {type:'ftp',
   remotePath, deleteRemoved:true}, excludes:[]}` und angehängt.
5. **Snapshot**: ja. **Kopie**: nein (Zugänge sind app-weit; Kopie könnte die Live-Site überschreiben).

Geprüft: `gui-test` (7 Ziele: sftp mit transfer, webhook, ftp, git-branch ohne connectionId, folder
ohne connectionId), `Example` (219 Byte). Ende `}\n]`.

---

### `layout-breakpoints.json`

1. Schreiber `saveBreakpointWidths()` (`layoutFrameService.ts:68-76`, schreibt danach alle Frames neu),
   auch Vorlagen-Import (`templatePackage/parts.ts:794`). Leser `getBreakpointWidths()` (`:53-61`).
2. ```ts
   interface FrameBreakpointWidths { tablet: number; mobile: number } // ipc-contract.ts:101-104
   const DEFAULT_FRAME_BREAKPOINT_WIDTHS = { tablet: 1200, mobile: 800 } // shared/gridFrameCss.ts:25-28
   // IPC-Schema (ipc/schemas.ts:134-137): z.object, ganze Zahlen 240..3840, mobile < tablet
   // Lesen: Number(raw.tablet/mobile); nicht endlich oder mobile >= tablet → Default
   ```
   Werte = max-width-Schwellen in px der generierten Media-Queries.
3. `writeJsonFile` (atomar, kein `\n`); Reihenfolge `tablet`, `mobile` (z.object streicht Rest);
   `readJsonFileOr` mit Default-Objekt → Quarantäne bei Defekt/Array.
4. —
5. **Snapshot**: ja. **Kopie**: ja.

Geprüft: `gui-test` = `{\n  "tablet": 1200,\n  "mobile": 900\n}` (ohne `\n`); `Example` 37 Byte.

---

### `theme-presets.json`

1. Schreiber `writeAll()` (`themePresetsService.ts:20-22`) via `savePreset()` (ersetzt per `id` oder
   hängt an) und `deletePreset()`. Leser `listPresets()`. Weitere Schreiber über `savePreset`: Vorlagen-
   Import (`templatePackage/parts.ts:1206-1212`, nur ids, die es noch nicht gibt).
2. ```ts
   interface ThemePreset {                    // ipc-contract.ts:345-358
     id: string                               // Renderer: `preset-${Date.now()}`; Vorlagen: feste ids (z. B. 'tpl-…')
     name: string
     createdAt: string                        // ISO
     baseThemeId: string
     options: {
       theme: string; mode: string
       variation?: string; calloutStyle?: string
       fonts?: Record<string, string>
       styleSettings?: Record<string, string | number | boolean>
       // + beliebige weitere Schlüssel: Schema ist z.looseObject (ipc/schemas.ts:425-431)
     }
   }
   ```
   Renderer baut (`src/routes/Styles/Theme.tsx:207-220`): `{id, name, createdAt, baseThemeId, options:
   {theme, mode, variation?, calloutStyle?, styleSettings}}` — `undefined` fällt weg. Vorlagen bringen
   z. B. `options.themeFonts: false` und `options.fonts: {header, body, code}`
   (`scripts/example-template/presets.mjs`).
3. `writeJsonFile` (atomar, kein `\n`); `readJsonFileOr(…, [])`.
4. —
5. **Snapshot**: ja. **Kopie**: ja.

Geprüft: `gui-test` (2 Presets, mit `themeFonts` und `fonts`, Ende `}\n]`), `Example` (745 Byte).

---

### `forms-relay.json` (quartz-forms-Relay, nicht geheim)

1. Schreiber `writeRelayFile()` (`formsService.ts:210-212`) aus `saveRelaySettings()` (`:214-217`),
   nach erfolgreichem Upload (`:735`) und nach Entfernen (`:820-821`). Leser `readRelayFile()`
   (`:205-208`), Aufrufe `:322`, `:714`, `:765`, `:791`. Geheimnisse liegen **nicht** hier, sondern
   verschlüsselt in userData (`relay-secrets.json`, `connectionsService.ts:447`), je Projekt-id.
2. ```ts
   interface RelayFile {                      // formsService.ts:199-203
     settings?: Partial<RelaySettings>
     lastUpload?: RelayLastUpload
     removedAt?: string                       // ISO; nur gesetzt nach Entfernen (lastUpload dann weg)
   }
   interface RelaySettings {                  // ipc-contract.ts:640-657
     targetId?: string                        // Ziel vom Typ sftp/ftp/folder
     subdir: string; from: string; allowedOrigins: string[]; subjectPrefix: string
     mailer: 'mail' | 'sendmail'; sendmailPath: string; counterDir: string
     configReadable: boolean; envelopeSender: boolean
   }
   const DEFAULT_RELAY: RelaySettings = {     // formsService.ts:187-197 – beim Lesen: { ...DEFAULT_RELAY, ...file.settings }
     subdir: 'forms', from: '', allowedOrigins: [], subjectPrefix: '', mailer: 'mail',
     sendmailPath: '/usr/sbin/sendmail -t -i', counterDir: '', configReadable: false, envelopeSender: true
   }
   interface RelayLastUpload {                // ipc-contract.ts:659-680
     at: string; hash: string; targetId: string
     location: string                         // `${type}|${connectionId ?? ''}|${path|remotePath}|${subdir}` (locationOf, :233-237)
     configReadable?: boolean                 // seit 2026-10-21
     operator?: string                        // operatorStamp(), seit 2026-10-21
     counterDir?: string                      // nur wenn gesetzt
     server?: string                          // `${username}@${host.trim().toLowerCase()}`, seit 2026-10-25, nicht bei folder
     generation?: string                      // seit 2026-10-25
   }
   ```
   Schreibreihenfolge nach Upload: `{...file, removedAt: undefined, lastUpload: {at, hash, targetId,
   location, configReadable, operator, [counterDir], [server], [generation]}}` — `removedAt` fällt weg.
   Nach Entfernen: `{...rest ohne lastUpload, removedAt}`. `settings` = Objekt aus dem Renderer
   (`relaySettings`-Schema `ipc/schemas.ts:709-720`, `looseObject` → unbekannte Schlüssel bleiben).
3. `writeJsonFile` (atomar, kein `\n`). Lesen `readJsonFile`: `unreadable` → quarantäniert, `{}`;
   fehlt → `{}`. (Ein JSON-Array würde als `ok` durchgehen — Randfall.)
4. `envelopeSender` seit quartz-forms 0.6.0 / 2026-10-25; fehlt → Default `true`.
5. **Snapshot**: ja (gemessen). **Kopie**: nein (verweist auf Ziel des Originals).

Geprüft: `gui-test/.quartz-gui/forms-relay.json` (Struktur maskiert: `settings` ohne `envelopeSender`,
`lastUpload` mit `at, hash, targetId, location, configReadable, operator`; Ende `}\n}`).

---

### `project-icon.json` und `icon-original.png` (Projektbild)

1. `projectIconService.ts`. Marker: Schreiber `writeMarker()` (`:73-80`) aus `setProjectIcon()`
   (`:227-250`), `clearProjectIcon()` (`:255-271`), `setProjectIconDark()` (`:198-202`),
   `clearProjectIconDark()` (`:204-208`). Leser `readMarker()` (`:59-70`). Original: `copyFile(icon.png,
   .quartz-gui/icon-original.png)` beim **ersten** Setzen (`:236-240`), zurückkopiert und gelöscht in
   `clearProjectIcon`. Das Bild selbst liegt in `quartz/static/icon.png` (+ `icon-dark.png`), nicht hier.
2. ```ts
   interface IconMarker {                     // projectIconService.ts:39-45
     custom: boolean        // icon.png wurde in der App gewählt
     hasOriginal: boolean   // icon-original.png hält das verdrängte icon.png
     customDark: boolean    // icon-dark.png wurde in der App gewählt
   }
   const NO_MARKER = { custom: false, hasOriginal: false, customDark: false }
   // Lesen: custom/hasOriginal nur === true; customDark fehlt (alte Marker) → custom && existsSync(icon-dark.png)
   ```
   Sind `custom` und `customDark` beide `false`, wird die Datei **gelöscht** statt geschrieben.
   `icon-original.png`: Byte-Kopie der vorherigen `quartz/static/icon.png`.
3. `writeJsonFile` (atomar, kein `\n`), Reihenfolge `custom, hasOriginal, customDark`; Lesen
   `readJsonFileOr(…, NO_MARKER)` → Quarantäne bei Defekt.
4. `customDark` später ergänzt (Fallback siehe oben).
5. **Snapshot**: ja (beide; nicht ausgeschlossen). **Kopie**: ja (beide).

Geprüft: `Example/.quartz-gui/project-icon.json` = `{\n  "custom": true,\n  "hasOriginal": true,\n
"customDark": true\n}` (ohne `\n`), `Example/.quartz-gui/icon-original.png` (17 KB). In gui-test nicht vorhanden.

---

### `locale-baseline/<code>.ts` (Übersetzungs-Baseline)

1. Schreiber `captureBaseline()` (`localizationService.ts:173-177`), aufgerufen von `saveLocaleEntry()`
   (`:110-120`) **vor** der ersten Änderung einer Sprache: `copyFileSync(quartz/i18n/locales/<code>.ts,
   join(quartzGuiDir(p, 'locale-baseline'), <code>.ts))`, nur wenn die Quelle existiert und noch keine
   Baseline da ist. Leser `getTranslationCustomizations()` (`:217-…`) über `baselinePath()` (`:169-171`).
2. Byte-Kopie der Quartz-Sprachdatei, Name = Locale-Code (z. B. `de-DE.ts`). Wird nie aktualisiert oder
   gelöscht. Fehlt sie, Fallback `git show HEAD:quartz/i18n/locales/<code>.ts` (nur wenn Datei von HEAD
   abweicht), sonst `source: 'none'`.
3. `copyFileSync` (nicht atomar).
4. —
5. **Snapshot**: ja. **Kopie**: ja.

Geprüft: `gui-test/.quartz-gui/locale-baseline/de-DE.ts`, `Example/.quartz-gui/locale-baseline/de-DE.ts`.

---

### Temporäre und beiseitegelegte Dateien (`*.tmp-*`, `*.corrupt-*`)

- `<name>.tmp-<pid>-<8hex>`: Zwischenstand jedes atomaren Schreibens; bleibt nur nach Absturz liegen,
  wird von niemandem aufgeräumt.
- `<name>.corrupt-<ISO mit '-'>`: von `readJsonFile` beiseitegelegte unlesbare JSON-Stores; bleiben liegen.
- **Snapshot**: ja (nicht ausgeschlossen, `-f`). **Kopie**: ja.

---

### `running-servers.json` — NICHT in `.quartz-gui/`

Liegt app-weit in `app.getPath('userData')/running-servers.json` (`runningServersStore.ts:17-21`),
`Record<projectId, { pid: number; port: number; startedAt: string }>` über `jsonStore`. Gehört nicht in
diesen Abschnitt; ebenso `projects.json`, `connections.json`, `settings.json`, `relay-secrets.json`.

### Geparkter Content-Symlink — kein Dateizustand

`withContentSymlinkParked()` (`contentSymlink.ts:19-38`) merkt sich das Link-Ziel nur im Speicher,
nichts in `.quartz-gui/`.

---

## Unklar / nicht gefunden

- **`deploy-manifest.json` (Legacy) im Snapshot**: `isSnapshotWorthy` schließt nur `deploy-manifest-*`
  aus; der Legacy-Name würde per `git add -f` gesichert. Wahrscheinlich unbeabsichtigt; nicht gemessen
  (kein Vorkommen).
- **`backups.migrated/`, `.DS_Store`, `*.corrupt-*`, `*.tmp-*`, `branch-worktree-*` im Snapshot**: im
  Code nicht ausgeschlossen; `backups.migrated` und `.DS_Store` am echten Store gemessen, die anderen
  nicht. Ob ein `branch-worktree-*`-Rest als Gitlink oder als Dateien landet: nicht gemessen.
- **Kommentar in `publishTargetsService.ts:40-41`** („the deploy manifest is re-keyed onto this one by
  deployService's own migration“): Ein solcher Re-Key-Code wurde nicht gefunden; einzige Migration ist
  die Adoption von `deploy-manifest.json` durch das erste fragende Ziel.
- **Schlüsselreihenfolge der Deploy-Manifeste** ist nicht deterministisch garantiert (parallele
  Hash-Worker); am Beispiel alphabetisch. Für byte-identische Round-Trips nicht verlässlich.
- **`dist/frames.js`**: generierter Code (~300 Zeilen Template in `layoutFrameService.ts:98-390`) nicht
  im Detail erfasst; für Gleichheit muss der Generator übernommen werden.
- **`project-prefs.json`**: ob das IPC-Schema zusätzliche Schlüssel durchlässt, die dann mitgeschrieben
  würden, nicht geprüft.
- **`forms-relay.json` als JSON-Array**: `readRelayFile` akzeptiert jedes Objekt inkl. Array (Randfall).
- **Relay über rsync**: rsync nutzt kein Manifest; `deploy-manifest-relay-<id>.json` bliebe dann beim
  Initialwert `{}\n` bzw. der `remove`-Liste stehen. Aus dem Code abgeleitet, nicht gemessen.
- **HEAD/Default-Branch des Bare-Stores**: `git init --bare` setzt HEAD auf den Standard-Branch des
  Systems; ungenutzt, Inhalt nicht festgelegt.
- **`symlink.json` in `content-backups`**, **`staging/`**, **`*.tilde.json`**, **`branch-worktree-*`**:
  kein echtes Exemplar vorhanden, nur aus dem Code beschrieben.
