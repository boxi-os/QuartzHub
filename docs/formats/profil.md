> Bestandsaufnahme vom 2026-11-06 aus dem Code von QuartzControl `fix/1.3.x` (`0bbdb8cd`), Zeilenangaben
> relativ zu `../QuartzControl`. Erstellt von einem Lese-Agenten, Stichproben gegen den Code geprüft
> (Verschlüsselung, Relay-Fingerprint, `connections.json` lesen, Relay-Manifest `{}\n`, Marker-Namen).
> Überblick und was QuartzHub damit tut: [`../formats.md`](../formats.md).

# Profilverzeichnis von QuartzControl 1.3

Stand: Code auf `fix/1.3.x` (HEAD `0bbdb8cd`, = 1.3.0 plus Doku-Commits). Nur Code gelesen, kein echtes
Profil geöffnet. Alle Zeilenangaben relativ zu `../QuartzControl`.

## Ort des Profils

- `app.getPath('userData')`. Der Name kommt aus `app.setName(APP_NAME)` mit `APP_NAME = 'QuartzControl'`
  (`electron/main/index.ts:48`, `electron/main/menu.ts:8`), gesetzt vor `whenReady`. Dev-Modus
  (`npm run dev`) und gepackte App teilen sich damit **dasselbe** Profil.
- macOS: `~/Library/Application Support/QuartzControl`; Linux: `$XDG_CONFIG_HOME/QuartzControl` bzw.
  `~/.config/QuartzControl`; Windows: `%APPDATA%/QuartzControl` (so leiten es die Prüfskripte her,
  `scripts/smoke.mjs:44-48`, `scripts/screenshots.mjs:82-86`).
- `--user-data-dir=<dir>` auf der Kommandozeile verlegt das ganze Profil (smoke/screenshots nutzen das,
  `scripts/smoke.mjs:140`).
- Wer das Verzeichnis anlegt: `projectStore`, `settingsService`, `connectionsService` (beide Stores),
  `runningServersStore` legen es mit `mkdirSync(dir, { recursive: true })` an, falls es fehlt.
  `windowState.ts` und `dialogDirectory.ts` legen es **nicht** an (verlassen sich darauf, dass es da ist).

Vollständige Liste dessen, was QuartzControl 1.3 selbst dort ablegt (grep über `getPath('userData')` in
`electron/`, `shared/`; es gibt keine weiteren Stellen):

| Datei / Ordner | Modul |
|---|---|
| `projects.json` | `projectStore.ts` |
| `settings.json` | `settingsService.ts` (+ Migration in `connectionsService.ts`) |
| `connections.json` | `connectionsService.ts` |
| `relay-secrets.json` | `connectionsService.ts` |
| `deploy-secrets.json` (nur gelesen, Altbestand) → `deploy-secrets.json.migrated` | `connectionsService.ts` |
| `legacy-publish-targets.json` | `connectionsService.ts` / `publishTargetsService.ts` |
| `running-servers.json` | `runningServersStore.ts` |
| `window-state.json` | `windowState.ts` |
| `dialog-state.json` | `dialogDirectory.ts` |
| `templates/qc-basic.qtpl` | `builtinTemplateService.ts` |
| `theme-docs/*.json` | `styleSettingsSchemaService.ts` |
| `runtime/bin/{node,npm,npx}` | `nodeRuntime.ts` |
| `<name>.corrupt-<zeit>`, `<name>.tmp-<pid>-<hex>` | `jsonStore.ts` (Nebenprodukte) |

Dazu kommen die Dateien, die Chromium/Electron selbst ins Profil legt (siehe letzter Abschnitt).

**Nicht** im Profil (oft vermutet, aber projektlokal unter `<projekt>/.quartz-gui/`):
`publish-targets.json`, `theme-presets.json`, `project-prefs.json`, `layout-breakpoints.json`,
`forms-relay.json`, `deploy-manifest-<targetId>.json`, `core-update.json`, `snapshot-settings.json`,
Logs (`publishTargetsService.ts:9-13`, `themePresetsService.ts:7-13`, `projectPrefsService.ts:10-21`,
`deploy/manifest.ts:17-24`). Temp-Ordner (`qc-git-*`, `qc-relay-*`, `qc-rsync-*`, `quartzcontrol-merge-*`,
Export) liegen in `os.tmpdir()`.

---

## Gemeinsame Schreib- und Leseregeln (`jsonStore.ts`)

`electron/main/services/jsonStore.ts`. Gilt für alle JSON-Stores außer `theme-docs/` und dem
Lesen von `deploy-secrets.json`.

### Schreiben

```ts
// jsonStore.ts:110-112
export async function writeJsonFile(path: string, value: unknown): Promise<void> {
  await writeFileAtomic(path, JSON.stringify(value, null, 2))
}
```

- `JSON.stringify(value, null, 2)`: **2 Leerzeichen Einrückung, kein abschließender Zeilenumbruch**,
  UTF-8 (`handle.writeFile(text, 'utf-8')`, `:127`). Kein BOM.
- Atomar (`writeFileAtomic`, `:121-139`): Temp-Datei **im selben Verzeichnis**
  `${path}.tmp-${process.pid}-${randomUUID().slice(0, 8)}` (`:123`), öffnen mit `'w'`, schreiben,
  `handle.sync()` (fsync), schließen, `rename(tmp, path)`. Bei Fehler wird die Temp-Datei gelöscht und
  der Fehler weitergeworfen. Kein fsync des Verzeichnisses. Dateimodus: Standard von `open(...,'w')`
  (0o666 & ~umask, also typisch 0644); es wird kein Modus gesetzt.
- Synchrone Variante `writeJsonFileSync` (`:147-162`) mit identischem Ergebnis (gleiche Einrückung,
  gleiche Temp-Benennung, `fsyncSync`, `renameSync`) — nur `window-state.json` beim Schließen.
- Folgen für ein byte-identisches Round-Trip aus Swift:
  - Schlüsselreihenfolge = Einfügereihenfolge des JS-Objekts (unten je Datei angegeben). `undefined`-Werte
    lässt `JSON.stringify` weg (Feld fehlt, kein `null`).
  - `JSON.stringify` schreibt `"key": value` (ein Leerzeichen **nach** dem Doppelpunkt, keins davor),
    leere Arrays/Objekte als `[]`/`{}` (auch eingerückt), `/` **nicht** escaped, Nicht-ASCII roh (kein
    `\uXXXX`), Steuerzeichen als `\n`, `\t`, … bzw. `\u00xx` (Kleinbuchstaben-Hex).
  - Hinweis (Allgemeinwissen, hier nicht gemessen): Foundations `JSONSerialization`/`JSONEncoder` mit
    `.prettyPrinted` schreibt auf Apple-Plattformen `"key" : value` und escaped `/` ohne
    `.withoutEscapingSlashes`; für Byte-Gleichheit braucht QuartzHub also einen eigenen Serialisierer.

### Lesen

```ts
// jsonStore.ts:29-36
export type JsonReadResult<T> =
  | { kind: 'ok'; value: T }
  | { kind: 'missing' }
  | { kind: 'unreadable'; quarantinedAs: string | null }
```

- `readJsonFile` (`:69-90`): ENOENT → `missing`. Jeder andere Lesefehler, ungültiges JSON (auch eine
  leere Datei) oder ein Wert, der weder Objekt noch Array ist (`null`, Zahl, String) → Datei wird
  beiseitegelegt → `unreadable`.
- `readJsonFileOr(path, fallback)` (`:97-108`): `missing`/`unreadable` → `fallback`. Zusätzlich: Ist
  `Array.isArray(fallback) !== Array.isArray(value)` (Array statt Objekt oder umgekehrt), wird die Datei
  ebenfalls beiseitegelegt und `fallback` geliefert (`:102-106`).
- Beiseitelegen (`quarantine`, `:55-67`): `rename(path, \`${path}.corrupt-${new Date().toISOString().replace(/[:.]/g, '-')}\`)`,
  also z. B. `settings.json.corrupt-2026-11-06T10-15-30-123Z`. Klappt das Umbenennen nicht, wird
  trotzdem notiert (`quarantinedAs: null`). Die Liste lebt nur im Speicher dieser Sitzung und wird über
  `getAppInfo().unreadableStores` auf der Einstellungsseite gezeigt (`settingsService.ts:53`,
  Typ `AppInfo` in `shared/ipc-contract.ts:1757-1771`).
- Es gibt **keine Schemaprüfung** der Felder beim Lesen; die Typen werden per Cast übernommen. Nur wo
  unten angegeben, werden Felder einzeln geprüft (window-state, dialog-state).

---

### `projects.json`

- **Pfad:** `<userData>/projects.json` (`projectStore.ts:9-13`).
- **Schreiber:** `projectStore.writeAll` (`:19-21`) aus `addProject` (`:27-40`), `touchProject`
  (`:42-48`), `relocateProject` (`:53-66`), `removeProject` (`:68-71`). Aufgerufen über IPC
  `project:add` (`ipc/handlers.ts:135-141`), `project:relocate` (`:142-151`), `project:open` → touch
  (`:152-155`), `project:remove` (`:156-166`), sowie nach erfolgreichem Anlegen/Duplizieren
  (`handlers.ts:201`, `:207`).
- **Leser:** `listProjects`/`getProject` (`projectStore.ts:23-25`, `:73-76`); u. a.
  `dialogDirectory.inPublishedContent` (`dialogDirectory.ts:56`), Orphan-Dialog beim Start
  (`index.ts:188`), Quit-Dialog, `connection:usage` (`handlers.ts:414-416`), Projektübersicht.
  Außerhalb der App lesen `scripts/smoke.mjs:50-55` und `scripts/screenshots.mjs:115` `list[0].path`.

```ts
// shared/ipc-contract.ts:4-10
export interface Project {
  id: string
  name: string
  path: string
  addedAt: string
  lastOpenedAt?: string
}
```

- Datei = `Project[]` (Array auf oberster Ebene). Fallback beim Lesen `[]` (`projectStore.ts:16`);
  ein Objekt statt Array wird beiseitegelegt.
- `id`: `randomUUID()` (UUID v4, klein geschrieben, `:32`). Das IPC-Schema verlangt für Projekt-IDs
  `z.uuid()` (`ipc/schemas.ts:169`), eine Nicht-UUID wäre also über IPC nicht ansprechbar.
- `name`: immer `basename(path)` (`:33`, `:63`); es gibt keinen Umbenennen-Weg.
- `path`: absoluter Pfad, so wie er aus dem Dialog/Wizard kam (Schema `absolutePath`: nur
  `isAbsolute`, keine Normalisierung, `ipc/schemas.ts:23-27`). Duplikatprüfung per String-Gleichheit
  (`:29`, `:59`). Kein `realpath`.
- `addedAt`, `lastOpenedAt`: `new Date().toISOString()` (UTC, Millisekunden, `Z`).
- Schlüsselreihenfolge beim Anlegen: `id, name, path, addedAt`; `lastOpenedAt` wird beim ersten
  `touchProject` hinten angehängt und behält danach seine Position; `relocateProject` ändert `path` und
  `name` an Ort und Stelle.
- Keine Version, keine Migration.
- **Pfade/Bezüge:** `path` zeigt ins Projekt. Die `id` ist Schlüssel in `running-servers.json` und
  `relay-secrets.json` (und im Renderer-Speicher für Sticky-State). Beim Entfernen werden Server
  gestoppt und `relay-secrets.json[id]` gelöscht (`handlers.ts:161-165`).

### `settings.json`

- **Pfad:** `<userData>/settings.json` (`settingsService.ts:18-22`).
- **Schreiber:** `saveSettings` (`settingsService.ts:33-41`) aus IPC `settings:save`
  (`handlers.ts:659-676`) und beim Beenden mit Häkchen „Nicht mehr fragen“
  (`index.ts:363-366`: `saveSettings({ ...current, serversOnQuit: decision })`). Außerdem einmalig die
  Token-Migration in `connectionsService.migrate` (`connectionsService.ts:214-228`, siehe unten).
- **Leser:** `getSettings` (`settingsService.ts:28-31`): `prepareBeforeWindow` (`index.ts:222-223`),
  `applyStoredTheme` (`theme.ts:36-38`), `refreshMainLanguage` (`i18n.ts:1177-1181`), Quit-Entscheidung
  (`index.ts:328`), IPC `settings:get` (`handlers.ts:658`). Direkt per `JSON.parse` liest nur die
  Migration (`connectionsService.ts:216`).

```ts
// shared/ipc-contract.ts:2047-2076 (Kommentare gekürzt)
export interface Settings {
  /** Pre-fills the folder pickers on the start screen and the create wizard. */
  defaultProjectDirectory?: string
  language?: 'system' | 'de' | 'en'
  theme?: 'system' | 'light' | 'dark'
  nodeRuntime?: 'embedded' | 'system'
  serversOnQuit?: 'ask' | 'stop' | 'keep'
}

// settingsService.ts:12-16 — was auf der Platte stehen kann
interface StoredSettings extends Settings {
  // Only ever read, by connectionsService's migration; never written by this service again.
  githubToken?: string
  githubTokenEncrypted?: string
}
```

- Datei = Objekt. Fallback `{}` (`settingsService.ts:25`); ein Array wird beiseitegelegt.
- Alle Felder optional; die Datei existiert erst nach dem ersten Speichern. **Defaults beim Lesen**
  (nicht in die Datei geschrieben):
  - `language`: fehlt/`'system'` → `app.getLocale().startsWith('de') ? 'de' : 'en'` (`i18n.ts:1179`).
  - `theme`: alles außer `'light'`/`'dark'` → `'system'` (`theme.ts:27-28`).
  - `nodeRuntime`: `?? 'embedded'` (`index.ts:223`, `handlers.ts:675`).
  - `serversOnQuit`: `?? 'ask'` (`index.ts:328`).
  - `defaultProjectDirectory`: kein Default; wird im Renderer nur genutzt, wenn er existiert.
- IPC-Schema `settings` ist `z.looseObject` (`ipc/schemas.ts:664-670`): **unbekannte Schlüssel
  werden durchgereicht und gespeichert.** Der Renderer schickt immer das ganze Objekt
  (`{ ...useAppStore.getState().settings, ...patch }`, `src/routes/Settings.tsx:56`), das er vorher von
  `getSettings` bekam. Fremde Schlüssel überleben also ein Speichern; Reihenfolge = vorhandene Schlüssel
  in Lesereihenfolge, neue hinten.
- `saveSettings` ist Read-Modify-Write nur für die zwei Legacy-Token-Felder: Steht noch
  `githubToken`/`githubTokenEncrypted` in der Datei, werden sie hinten wieder angehängt
  (`settingsService.ts:36-40`). `getSettings` filtert sie heraus (`:29-30`), der Renderer sieht sie nie.
- Seit 1.0.0 unverändert (Typ in `v1.0.0:shared/ipc-contract.ts` identisch).
- **Legacy/Migration:** `githubToken` (Klartext) und `githubTokenEncrypted` (base64 safeStorage) stammen
  aus der Zeit vor dem 2026-08-27 (`1cd7ec15`), also **vor jedem Release** (erste Beta 2026-09-10). Sie
  werden beim ersten Lesen von `connections.json`, das „missing“ ergibt, in eine GitHub-Verbindung
  überführt und aus `settings.json` entfernt.
- **Pfade:** `defaultProjectDirectory` (absoluter Pfad, beliebiger Ort).

### `connections.json`

- **Pfad:** `<userData>/connections.json` (`connectionsService.ts:43-47`).
- **Schreiber:** `writeAll` (`:253-255`) aus `readAll` (Erstanlage nach Migration, `:248-249`),
  `saveConnection` (`:301-363`), `deleteConnection` (`:365-368`), `rememberHostKey` (`:385-391`),
  `forgetHostKey` (`:394-400`). IPC: `connection:save`, `connection:delete`,
  `connection:forgetHostKey` (`handlers.ts:406-411`); `rememberHostKey` aus
  `deploy/hostVerifier.ts:46-50` und `:82-86`.
- **Leser:** `readAll` (`:239-251`) → `listConnections`, `getConnection`, `getSecret`
  (Deploy, `deploy/index.ts:64`, `:199`), `getGithubToken` (Marketplace, Theme-Marketplace,
  `gitAuth.ts:34`, `githubService.ts:27`).

```ts
// connectionsService.ts:26-41 — Form auf der Platte
interface StoredConnection {
  id: string
  kind: 'ssh' | 'ftp' | 'github' | 'webhook'
  name: string
  host?: string
  port?: number
  username?: string
  authMethod?: SshAuthMethod
  keyPath?: string
  secure?: boolean
  login?: string
  encryptedSecret?: string // base64 of safeStorage.encryptString() output
  hostKey?: PinnedHostKey
}

// shared/ipc-contract.ts:1238
export type SshAuthMethod = 'password' | 'privateKey' | 'agent'

// shared/ipc-contract.ts:1245-1249
export interface PinnedHostKey {
  fingerprint: string   // "SHA256:<base64 ohne Padding>" (hostVerifier.ts:10-12)
  blob: string          // roher Public Key, base64 (mit Padding)
  type: string          // Algorithmusname aus dem Blob, z. B. "ssh-ed25519" (hostVerifier.ts:18-23)
}
```

- Datei = `StoredConnection[]`. Pro `kind` belegte Felder (`saveConnection`, `:323-357`):
  - `ssh`: `host` (getrimmt seit 1.3, `:336`), `port`, `username`, `authMethod`, `keyPath?`,
    `encryptedSecret?`, `hostKey?`.
  - `ftp`: `host` (getrimmt), `port`, `username`, `secure` (FTPS), `encryptedSecret?`. `hostKey` nur
    theoretisch (wird übernommen, falls vorhanden).
  - `github`: `login?`, `encryptedSecret` (Token).
  - `webhook`: `login` = **Origin der Hook-URL zur Anzeige** (`new URL(secret).origin`, `:351-356`),
    `encryptedSecret` = die ganze URL.
- **Defaults beim Lesen** (`toPublic`, `:269-290`): ssh `host ?? ''`, `port ?? 22`, `username ?? ''`,
  `authMethod ?? 'password'`; ftp `host ?? ''`, `port ?? 21`, `username ?? ''`, `secure: !!secure`;
  `hasSecret = !!encryptedSecret`; webhook `displayOrigin = login`. Öffentlicher Typ:
  `Connection = SshConnection | FtpConnection | GithubConnection | WebhookConnection`
  (`shared/ipc-contract.ts:1251-1291`).
- **Was das Secret je Methode ist:**
  - ssh `password`: das Passwort.
  - ssh `privateKey` **ohne** `keyPath`: der Inhalt des privaten Schlüssels (eingefügt oder aus dem
    Altformat). **Mit** `keyPath`: es wird nichts gespeichert, die Datei wird beim Verbinden gelesen
    (`deploy/sftp.ts:36-45`).
  - ssh `agent`: kein Secret (`SSH_AUTH_SOCK`, `deploy/sftp.ts:31-35`).
  - Zeile `:342`: Für `agent` oder mit `keyPath` wird `encryptedSecret` auf `encrypt(input.secret)` bzw.
    `undefined` gesetzt; das Formular schickt dort `secret: ''` (`ConnectionForm.tsx:142`), also faktisch
    `undefined`.
  - **Key-Passphrasen gibt es nicht.** Kein Feld, kein `passphrase` im Code (grep leer); ein
    verschlüsselter Schlüssel kann nicht benutzt werden.
  - ftp: Passwort. github: Token. webhook: URL.
- **Secret leer lassen beim Bearbeiten = behalten** (`keepStoredSecret`, `:321`): `secret === undefined`
  oder (`''` und Eintrag existiert und `authMethod` unverändert). Ein Wechsel der ssh-`authMethod`
  verwirft das alte Secret.
- `id`: `randomUUID()` bzw. bei Migration die alte Profil-ID (`:187`). IPC verlangt `z.uuid()`
  (`connection:delete`, `connectionId` in Zielen `ipc/schemas.ts:564`).
- `hostKey`: TOFU. Beim ersten Bestätigen geschrieben (`hostVerifier.ts:82-86`), bei Migration nur mit
  Fingerprint `{ fingerprint, blob: '', type: '' }` (`:201-203`), Blob wird beim nächsten passenden
  Verbinden nachgetragen (`hostVerifier.ts:43-50`). Bei `saveConnection` wird `existing?.hostKey`
  übernommen (`:329`). `forgetHostKey` löscht das Feld per `delete`.
- **Schlüsselreihenfolge:** `saveConnection` baut `{ id, kind, name, encryptedSecret, hostKey }` und
  hängt dann an: ssh `host, port, username, authMethod, keyPath`; ftp `host, port, username, secure`;
  github `login`; webhook `login`. Undefinierte fallen weg. `rememberHostKey` auf einem Eintrag ohne
  `hostKey` hängt es **hinten** an. Migrierte Einträge: `id, kind, name, host, port, username,
  authMethod, secure, encryptedSecret, hostKey` (`:186-204`). Innerhalb `hostKey`:
  `fingerprint, blob, type`.
- **Unbekannte Felder** gehen bei `saveConnection` verloren (Eintrag wird feldweise neu gebaut),
  bei `rememberHostKey`/`forgetHostKey`/`deleteConnection` bleiben sie erhalten (Objekt wird mutiert).
- **Lesen/Fehler:** `readJsonFile` direkt (`:240`).
  - `ok` + Array → Wert.
  - `missing` → Migration läuft (`migrate()`), Ergebnis wird geschrieben — **auch wenn es leer ist**,
    also entsteht beim ersten Lesen eine Datei mit Inhalt `[]` (`:248-250`).
  - `unreadable` → Datei liegt schon als `.corrupt-…` daneben, diese Sitzung arbeitet mit `[]`, es
    wird nichts migriert (`:242-247`); das nächste Speichern legt eine neue Datei an.
  - `ok`, aber Objekt statt Array → `[]` **ohne** Beiseitelegen (`:241`, `:247`); das nächste Speichern
    überschreibt die Datei. (Abweichung vom sonstigen Muster, siehe „Unklar“.)
- **Verschlüsselung:** siehe Abschnitt „safeStorage“ unten. Nur `encryptedSecret` ist verschlüsselt,
  alles andere (Host, Benutzer, Port, Key-Pfad, Host-Key, Webhook-Origin, GitHub-Login) steht im Klartext.
- **Pfade:** `keyPath` (absoluter Pfad zu einer Schlüsseldatei, Schema `absolutePath`,
  `ipc/schemas.ts:488`). Die Verbindungs-`id` wird von `<projekt>/.quartz-gui/publish-targets.json`
  (`connectionId`) referenziert; die Verbindung selbst kennt kein Projekt.
- **Hinweis zu `login` bei GitHub:** In 1.3 setzt kein Code `login` aus der API in die Datei;
  `Settings.tsx:428` speichert den Token ohne `login` (Feld fällt dadurch weg), das allgemeine Formular
  reicht nur einen vorhandenen Wert durch (`ConnectionForm.tsx:36`).

### `relay-secrets.json`

- **Pfad:** `<userData>/relay-secrets.json` (`connectionsService.ts:444-448`). Seit 1.2 (2026-10-19,
  `57a2fe67`); `fingerprint` seit 2026-10-21 (`e3184875`).
- **Schreiber:** `saveRelaySecrets` (`:498-549`), IPC `forms:relaySaveSecrets`
  (`handlers.ts:238`) und `formsService.ts:381` (`saveRelaySecrets(projectId, {})`, legt beim ersten
  Upload das Signier-Secret an); `deleteRelaySecrets` (`:552-557`) beim Entfernen eines Projekts
  (`handlers.ts:165`).
- **Leser:** `readRelayStore` (`:450-453`) → `getRelaySecretInfo` (`formsService.ts:324`, `:731`),
  `projectsWithRelaySecrets` (`projectOverviewService.ts:22`), `getRelaySecrets` (`formsService.ts:379-382`,
  entschlüsselt, nur Main).

```ts
// connectionsService.ts:421-432 — Form auf der Platte, je Projekt-ID
interface StoredRelaySecrets {
  encrypted: string
  recipients: string[]        // Namen der Empfänger mit Adresse (ohne Adresse!)
  captchaSecret: boolean
  captchaSecrets: string[]    // Formular-IDs mit eigenem Captcha-Secret
  updatedAt: string           // new Date().toISOString()
  fingerprint?: string        // fehlt in Einträgen vor 2026-10-21
}
// Datei: Record<projectId, StoredRelaySecrets>

// connectionsService.ts:414-419 — der verschlüsselte Klartext
export interface RelaySecrets {
  secret: string                         // Signier-Secret, randomBytes(32).toString('base64url')
  recipients: Record<string, string>     // Name -> Adresse (getrimmt)
  captchaSecret?: string
  captchaSecrets?: Record<string, string> // Formular-ID -> Secret
}
```

- Datei = Objekt, Schlüssel = Projekt-`id` aus `projects.json`. Fallback `{}`: bei `missing`,
  `unreadable` (dann beiseitegelegt) und bei einem Array (dann **ohne** Beiseitelegen, `:452`).
- `encrypted` = `encrypt(JSON.stringify(next))` (`:538`): kompaktes JSON (ohne Einrückung) eines
  `RelaySecrets` in Reihenfolge `secret, recipients, captchaSecret?, captchaSecrets?` (`:532-537`;
  `captchaSecret`/`captchaSecrets` nur, wenn gesetzt bzw. nicht leer), dann safeStorage, dann base64.
- Schlüsselreihenfolge pro Eintrag: `encrypted, recipients, captchaSecret, captchaSecrets, updatedAt,
  fingerprint` (`:540-547`).
- `fingerprint` (`secretsFingerprint`, `:438-442`): `HMAC-SHA256(key = secret als UTF-8-String)` über
  `JSON.stringify([sortierte Entries von recipients, captchaSecret ?? null, sortierte Entries von
  captchaSecrets])`, Hex, **erste 32 Zeichen**. Sortierung mit `localeCompare` (ICU-Locale-Vergleich,
  nicht Codepoint!). QuartzHub muss das exakt nachbilden, sonst meldet der Relay-Status „geändert“.
- Schreiben verweigert, wenn `safeStorage` nicht verfügbar (`:513`, `:539`); kein Klartext-Fallback.
- Das Signier-Secret wird beim ersten Speichern erzeugt und behalten; nur `renewSecret: true` erzeugt
  ein neues (`:533`).
- Keine Pfade. Bezug: Projekt-ID.

### `deploy-secrets.json` (Altbestand, nur gelesen) und `deploy-secrets.json.migrated`

- **Pfad:** `<userData>/deploy-secrets.json` (`connectionsService.ts:49-51`). Geschrieben hat sie der
  gelöschte `secretsService.ts` (letzte Fassung `1cd7ec15^`, 2026-08-27) mit
  `writeFile(path, JSON.stringify(profiles, null, 2), 'utf-8')` — **vor jedem Release**.
- **Leser:** nur `migrate()` (`:176-181`), per `readFile` + `JSON.parse` (nicht jsonStore; Fehler → `[]`).
  `migrate()` läuft nur, wenn `connections.json` **fehlt**.

```ts
// connectionsService.ts:149-162
interface LegacyProfile {
  id: string
  projectPath: string
  name: string
  protocol: 'sftp' | 'ftp'
  host: string
  port: number
  username: string
  remotePath: string
  authMethod: 'password' | 'privateKey'
  secure?: boolean
  encryptedSecret?: string
  hostKeyFingerprint?: string
}
```

- Migration (`:183-212`): je Profil eine Verbindung (ID bleibt; `sftp`→`ssh`, `ftp`→`ftp`;
  `authMethod` nur für ssh, `secure` nur für ftp; `encryptedSecret` 1:1 übernommen, nicht neu
  verschlüsselt; `hostKeyFingerprint` → `hostKey: { fingerprint, blob: '', type: '' }`) und ein
  `LegacyProfileTarget` für `legacy-publish-targets.json`.
- Danach `rename(deploy-secrets.json, deploy-secrets.json.migrated)` — nur wenn mindestens ein Profil da
  war (`:232`). Die `.migrated`-Datei wird nie wieder gelesen.
- **Pfade:** `projectPath` (Projektordner).

### `legacy-publish-targets.json`

- **Pfad:** `<userData>/legacy-publish-targets.json` (`connectionsService.ts:168-170`).
- **Schreiber:** `migrate()` (`:234`, nur wenn es Ziele gab) und `claimLegacyTargets` (`:259-267`), das
  die Einträge eines Projekts entfernt und den Rest zurückschreibt (bleiben keine, steht `[]` darin;
  die Datei wird nicht gelöscht).
- **Leser:** `claimLegacyTargets` per `readJsonFileOr(..., [])`, aufgerufen von
  `publishTargetsService.listTargets` (`publishTargetsService.ts:36`) bei **jedem** Auflisten der Ziele
  eines Projekts; gefundene Einträge werden als neue Ziele (neue UUID, `deleteRemoved: true`,
  `transfer: 'sftp'`, `excludes: []`) in `<projekt>/.quartz-gui/publish-targets.json` geschrieben
  (`publishTargetsService.ts:39-53`).

```ts
// connectionsService.ts:141-147
export interface LegacyProfileTarget {
  projectPath: string
  connectionId: string
  name: string
  protocol: 'sftp' | 'ftp'
  remotePath: string
}
```

- Zuordnung per String-Gleichheit `t.projectPath === projectPath` (`:263`).
- Nur aus Vor-Release-Profilen; in einem Profil, das mit 1.0+ begonnen wurde, existiert die Datei nicht.
- **Pfade:** `projectPath`.

### `running-servers.json`

- **Pfad:** `<userData>/running-servers.json` (`runningServersStore.ts:17-21`) — liegt im Profil,
  nicht im Projekt.
- **Schreiber:** `record` (`:31-35`) beim Spawn eines Dev-Servers (`buildService.ts:674`,
  fire-and-forget), `remove` (`:37-42`) wenn das Kind endet/vergessen wird (`buildService.ts:514-516`),
  `takeAll` (`:44-48`) beim Start: liest alles und schreibt `{}`.
- **Leser:** `takeAll` aus `detectOrphanedServers` (`buildService.ts:1160-1165`), aufgerufen aus
  `promptForOrphanedServers` (`index.ts:183-184`) direkt nach dem ersten Fenster.

```ts
// runningServersStore.ts:11-15
export interface TrackedServer {
  pid: number
  port: number
  startedAt: string   // new Date().toISOString() beim Spawn (buildService.ts:671)
}
// Datei: Record<projectId, TrackedServer>
```

- Datei = Objekt, Schlüssel = Projekt-ID. Fallback `{}`; Array wird beiseitegelegt.
- `pid` ist die PID des `npx`-Prozesses (`npm exec quartz build --serve …`), nicht die des lauschenden
  Kindes. Beim Start gilt ein Eintrag nur als verwaist, wenn `kill(pid, 0)` lebt **und**
  `ps -p <pid> -o command=` sowohl `quartz` als auch `--serve` enthält (`buildService.ts:1124-1142`).
- Wird ein Server mit „Weiterlaufen lassen“ beim Beenden zurückgelassen, bleibt sein Eintrag stehen und
  der nächste Start fragt (`index.ts:315-320`; `killAllServers` leert nur die In-Memory-Map,
  `buildService.ts:1091-1092`).
- Schlüsselreihenfolge: `pid, port, startedAt`.
- Keine Pfade. Bezug: Projekt-ID.

### `window-state.json`

- **Pfad:** `<userData>/window-state.json` (`windowState.ts:30-32`). Seit 2026-09-13 (vor 1.0).
- **Schreiber:** `trackWindowState` (`:95-121`): 400 ms nach dem letzten `resize`/`move`/`maximize`/
  `unmaximize`/`enter-full-screen`/`leave-full-screen` per `writeJsonFile` (`:106`), und beim `close`
  **synchron** per `writeJsonFileSync` (`:112-120`).
- **Leser:** `loadWindowState` (`:40-45`) einmal vor dem ersten Fenster (`index.ts:258`).

```ts
// windowState.ts:13-17
export interface WindowState {
  bounds: Rectangle      // Electron: { x: number; y: number; width: number; height: number }
  maximized: boolean
  fullScreen: boolean
}
```

- Inhalt: `{ bounds: win.getNormalBounds(), maximized: win.isMaximized(), fullScreen: win.isFullScreen() }`
  (`:99`). `bounds` sind die **normalen** Bounds (Größe, zu der ein maximiertes Fenster zurückkehrt),
  in DIP, ganzzahlig.
- Lesen mit Feldprüfung: gültig nur, wenn `bounds.x/y/width/height` alle endliche Zahlen sind
  (`isRectangle`, `:34-37`); `maximized`/`fullScreen` nur bei `=== true` wahr (`:43`). Sonst wie
  „keine Datei“: Default `1280×800` zentriert (`:19`, `:55`). Mindestgröße `960×600` (`:20`).
- Anwendung (`fitToDisplays`, `:54-79`): Position nur, wenn die oberen 40 px über mindestens 120 px
  Breite auf einer Arbeitsfläche liegen; Größe auf die Arbeitsfläche gekappt.
- Schlüsselreihenfolge: `bounds, maximized, fullScreen`; innerhalb `bounds` die Reihenfolge, die
  Electron liefert (vermutlich `x, y, width, height`, nicht verifiziert).
- Keine Pfade. Beschreibt die Monitore dieses Rechners.

### `dialog-state.json`

- **Pfad:** `<userData>/dialog-state.json` (`dialogDirectory.ts:20-22`). Seit 2026-10-11 (1.1).
- **Schreiber:** `rememberDialogResult` (`:68-73`) nach jedem Öffnen-/Speichern-Dialog
  (`handlers.ts:474`, `:488`, `:637`, `:702`, `:728`); fire-and-forget, nur wenn sich der Ordner ändert.
- **Leser:** `dialogStartDirectory` (`:33-39`), einmal je Sitzung (Wert danach im Speicher, `let last`).

```ts
// dialogDirectory.ts:35, :72 — implizite Form
{ lastDirectory: string }   // absoluter Ordner
```

- Geschrieben wird immer genau `{ lastDirectory: folder }` mit `folder = dirname(gewählter Pfad)` —
  für eine Datei ihr Ordner, für einen gewählten Ordner dessen **Elternordner**.
- Lesen: Fallback `{}`; nur ein String in `lastDirectory` zählt (`:36`). Existiert der Ordner nicht mehr
  → `app.getPath('documents')` (`:38`). Speichern-Dialoge weichen zusätzlich auf Documents aus, wenn der
  Ordner im (per realpath aufgelösten) `content/` eines registrierten Projekts liegt (`:48-62`).
- **Pfade:** `lastDirectory` (beliebiger Ort, oft in einem Projekt oder Vault).

### `templates/` (`qc-basic.qtpl`)

- **Pfad:** `<userData>/templates/qc-basic.qtpl` (`builtinTemplateService.ts:45`, `:58-60`).
- **Schreiber:** `refresh` (`:96-116`): Download von
  `https://raw.githubusercontent.com/boxi-os/quartzcontrol-templates/main/qc-basic.qtpl` (`:32-33`) über
  `net.fetch`, Timeout 15 s, 1 B…25 MiB, muss als ZIP mit gültigen CRCs lesbar sein und `manifest.json`
  enthalten (`:104-109`). Dann `mkdir templates` und atomar geschrieben (`writeAtomically`, `:74-89`):
  Temp-Name `qc-basic.qtpl.tmp-<pid>` (ohne UUID-Anteil), fsync, rename. Binär, unverändert wie geladen.
- **Leser:** `getBuiltinTemplate` (`:187-199`): lädt neu, wenn die Datei älter als 24 h ist
  (**mtime** der Datei, `:62-68`, `:189`); eine unlesbare Kopie wird gelöscht und sofort neu geladen
  (`:178-184`). Zwischen Cache und mitgelieferter Kopie (`Resources/templates/qc-basic.qtpl`) gewinnt
  das jüngere `createdAt` aus `manifest.json`; Gleichstand → mitgelieferte Kopie. **QuartzHub liefert
  keine Kopie mit** (Entscheidung 2026-11-11, `decisions/phase-5-gleichstand.md`): Es zählt nur der
  Cache; die Regel gilt nur noch in den Tests und im Debug-Bau ohne Netz.
- Format der `.qtpl` selbst: ZIP mit `manifest.json` und `parts/<id>.json`
  (`templatePackage/shared.ts:12-17`) — gehört in einen eigenen Abschnitt (Vorlagenpaket), nicht hierher.
- **Legacy:** 1.0.0-beta.1 und beta.2 cachten `templates/minimal-lesbar.qtpl`
  (`git show v1.0.0-beta.1:electron/main/services/builtinTemplateService.ts:32`). 1.3 liest und löscht
  diese Datei nicht; sie kann in alten Profilen liegen.
- Reiner Cache, kann beim Umzug weggelassen werden.

### `theme-docs/`

- **Pfad:** `<userData>/theme-docs/` (`styleSettingsSchemaService.ts:45-49`, legt den Ordner bei
  Bedarf an).
- Inhalt:
  - `community-css-themes.json`: Kopie der Obsidian-Theme-Registry
    (`https://raw.githubusercontent.com/obsidianmd/obsidian-releases/master/community-css-themes.json`),
    geschrieben bei jedem erfolgreichen Abruf (`:67-91`, Schreiben `:77`), höchstens einmal je 24 h pro
    Sitzung (Memo im Speicher). Gelesen nur als Offline-Fallback.
  - `<themeId>.json` je Community-Theme: das ermittelte `StyleSettingsSchema` **oder `null`**
    (`:278-285`, Schreiben `:283`). Dauerhaft, kein Ablauf. `themeId` passt auf
    `^[a-z0-9][a-z0-9._-]*$`, max. 128 (`ipc/schemas.ts:88-92`).
- **Schreibweise:** `writeFile(path, JSON.stringify(x), 'utf-8')` — **kompakt, nicht atomar, nicht über
  jsonStore**, Fehler werden verschluckt.
- **Lesen:** `readFile` + `JSON.parse`, jeder Fehler → „nicht im Cache“ (`:262-269`). Eine **leere
  Datei** ist der Löschmarker: „Neu laden“ im Theme-Tab schreibt `''` statt zu löschen (`:352-358`).
  „Cache leeren“ in den Einstellungen löscht alle `*.json` (`:333-350`). Die Statistik zählt nur
  nicht-leere Dateien (`:313-331`).

```ts
// shared/ipc-contract.ts:299-308 (Inhalt von <themeId>.json, oder null)
export interface StyleSettingsSchema {
  ids: string[]
  themeName: string
  author: string
  repo: string
  screenshotUrl?: string
  fields: StyleSettingField[]
}
// StyleSettingField: shared/ipc-contract.ts:275-297; StyleSettingKind: :262-273

// styleSettingsSchemaService.ts:33-39 (community-css-themes.json: Array davon, upstream unverändert
// durchgereicht, also auch weitere Felder)
interface RegistryEntry { name: string; author: string; repo: string; screenshot?: string; modes?: string[] }
```

- Reiner Cache, keine Pfade.

### `runtime/bin/` (`node`, `npm`, `npx`)

- **Pfad:** `<userData>/runtime/bin/` (`nodeRuntime.ts:132-133`).
- **Schreiber:** `applyRuntimeMode('embedded')` (`:118-158`) bei **jedem Start** (`index.ts:223`) und nach
  einem Wechsel der Einstellung (`handlers.ts:674-676`). `writeFileSync(path, shim, 'utf-8')` +
  `chmodSync(path, 0o755)` (`:142-146`), nicht atomar. Bei `'system'` wird nur PATH bereinigt, die
  Dateien bleiben liegen (`:119-129`).
- **Leser:** die Shell bzw. jeder Kindprozess über PATH (`binDir` vorn).
- Inhalt: Vorlage `resources/runtime/shim.sh` mit ersetzten Platzhaltern (`:105-114`):

```sh
#!/bin/sh
# … Kommentar aus der Vorlage …
ELECTRON_RUN_AS_NODE=1 exec '<Helper-Binary>' -r '<Resources>/runtime/defaultapp.cjs' '<Resources>/npm/bin/npm-cli.js' "$@"
```

  `node` ohne Skript-Argument, `npm` → `npm/bin/npm-cli.js`, `npx` → `npm/bin/npx-cli.js`. Auf macOS
  ist das Binary der Helper „QuartzControl Helper“ (`nodeBinary`, `:93-96`, `shared/macNodeBinary.ts`).
  Alle Werte in einfachen Anführungszeichen (`shellQuote`, `:55-57`).
- **Pfade:** absolute Pfade ins App-Bundle. Beim Kopieren eines Profils wertlos; wird ohnehin bei jedem
  Start neu geschrieben. QuartzHub sollte den Ordner nicht übernehmen.

---

## safeStorage (Verschlüsselung der Geheimnisse)

Einziges Modul, das verschlüsselt: `connectionsService.ts`. Betroffen: `connections.json`
(`encryptedSecret`), `relay-secrets.json` (`encrypted`), Altbestand `settings.json`
(`githubTokenEncrypted`) und `deploy-secrets.json` (`encryptedSecret`).

```ts
// connectionsService.ts:100-106
function encrypt(secret: string): string | undefined {
  if (!secret || !safeStorage.isEncryptionAvailable()) return undefined
  return safeStorage.encryptString(secret).toString('base64')
}
// connectionsService.ts:121-129
function decrypt(encrypted?: string): string | null {
  if (!encrypted) return null
  if (!safeStorage.isEncryptionAvailable()) throw new Error(storageUnavailableMessage('secretStorageUnreadable'))
  try {
    return safeStorage.decryptString(Buffer.from(encrypted, 'base64'))
  } catch {
    throw new Error(mainT('secretUndecryptable'))
  }
}
```

- Gespeichert wird **Standard-base64 (mit Padding) der rohen Ausgabe von `encryptString`**. QuartzControl
  setzt **kein eigenes Präfix**; das Präfix in den Bytes stammt von Chromium (auf Linux `v11` gemessen,
  `connectionsService.ts:65-69`).
- Nur die synchronen APIs (`encryptString`/`decryptString`), nicht die async-Varianten (`:22-25`).
  `setUsePlainTextEncryption` wird nie aufgerufen (`:61-63`).
- Leerer String wird nicht verschlüsselt → Feld fehlt (`:101-104`).
- **safeStorage nicht verfügbar:**
  - Speichern einer Verbindung mit Secret wirft (`secretStorageUnavailable[Mac]`, `:308-310`); Relay-
    Secrets ebenso (`:513`, `:539`). **Kein Klartext-Fallback.** Eine Verbindung ohne neues Secret kann
    trotzdem gespeichert werden.
  - Lesen eines vorhandenen Secrets wirft `secretStorageUnreadable[Mac]`; ein Secret, das sich nicht
    entschlüsseln lässt (z. B. `connections.json` von einem anderen Rechner), wirft
    `secretUndecryptable`. `null` heißt ausschließlich „nichts gespeichert“.
  - `getSecretStorageInfo` (`:91-98`) fragt auf macOS bewusst nicht (würde den Schlüsselbund lesen) und
    meldet `{ available: true, backend: null, secure: true }`; auf Linux `available`, `backend`
    (`getSelectedStorageBackend()`, z. B. `gnome_libsecret`, `basic_text`), `secure = available &&
    backend !== 'basic_text'`. Typ `SecretStorageInfo`: `shared/ipc-contract.ts:1708-1725`.
- **macOS-Schlüssel:** Schlüsselbund-Eintrag „QuartzControl Safe Storage“ (bestätigt durch
  `docs/decisions/electron-runtime-and-packaging.md:132-135`). Die App ist ad hoc signiert; jeder neue
  Build fragt zweimal (ACL + Partitionsliste).
- **Für QuartzHub entscheidend, hier nicht verifiziert (Chromium-Quelle, nicht in diesem Repo):** Auf
  macOS erzeugt Chromiums OSCrypt das Format `"v10"` + AES-128-CBC, Schlüssel per PBKDF2-HMAC-SHA1 aus
  dem Passwort des Schlüsselbund-Eintrags (Salt `saltysalt`, 1003 Iterationen, 16 Byte), IV = 16 × `0x20`,
  PKCS#7. Account-Name des Eintrags vermutlich ebenfalls `QuartzControl`. Muss gegen die Chromium-/
  Electron-43-Quelle und ein Test-Profil geprüft werden, bevor QuartzHub Secrets liest oder schreibt;
  außerdem fragt der Schlüsselbund auch QuartzHub (andere Signatur) beim ersten Zugriff.

---

## Von Chromium/Electron selbst angelegte Dateien

Nicht von QuartzControl-Code geschrieben, aber im selben Verzeichnis (übliche Electron-Struktur, nicht
am Profil geprüft): `Preferences`, `Local State`, `Local Storage/`, `Session Storage/`, `IndexedDB/`,
`Cookies`, `Network Persistent State`, `TransportSecurity`, `Cache/`, `Code Cache/`, `GPUCache/`,
`DawnCache/`/`DawnGraphiteCache/`, `blob_storage/`, `Shared Dictionary/`, `Crashpad/` u. a.

- Der Renderer der App nutzt **kein** `localStorage`/`sessionStorage`/IndexedDB (grep über `src/` leer;
  Sticky-State ist nur im Speicher). Die in-App-Vorschau der Website (`http://localhost:<port>`) läuft
  aber in der Standard-Session; was die Quartz-Website selbst in `localStorage` legt (z. B. `theme`),
  landet in `Local Storage/`. Das Exportfenster nutzt eine In-Memory-Partition
  (`export/exportWindow.ts:62-63`), schreibt also nichts ins Profil.
- Für QuartzHub irrelevant; beim Kopieren des Profils weglassen.

---

## Bezüge zwischen den Dateien (für eine Migration)

- `projects.json[].id` ⇄ Schlüssel in `running-servers.json` und `relay-secrets.json`.
- `connections.json[].id` ⇄ `connectionId` in `<projekt>/.quartz-gui/publish-targets.json` (und in
  `legacy-publish-targets.json`).
- Pfade, die beim Umzug gültig bleiben müssen: `projects.json[].path`,
  `settings.json.defaultProjectDirectory`, `connections.json[].keyPath`, `dialog-state.json.lastDirectory`,
  `legacy-publish-targets.json[].projectPath`, `deploy-secrets.json[].projectPath`. Wertlos nach Umzug:
  `runtime/bin/*` (Pfade ins Bundle), `running-servers.json` (PIDs).
- Secrets lassen sich nicht als Datei mitnehmen, sondern nur, wenn QuartzHub denselben Schlüsselbund-
  Eintrag lesen darf (bzw. auf einem anderen Rechner gar nicht).

---

## Unklar / nicht gefunden

- **Byteformat der safeStorage-Ausgabe auf macOS** (`v10`, PBKDF2-Parameter, IV, Account-Name des
  Schlüsselbund-Eintrags): nicht in diesem Repo, nur aus Chromium bekannt; nicht verifiziert.
- **Reihenfolge der Schlüssel in `bounds`** (`getNormalBounds()`): kommt aus Electrons nativer Konvertierung,
  nicht im Code sichtbar; vermutlich `x, y, width, height`.
- **`connections.json` mit Objekt statt Array** wird nicht beiseitegelegt, sondern als `[]` gelesen und
  beim nächsten Speichern überschrieben (`connectionsService.ts:241`, `:247`); ebenso
  `relay-secrets.json` mit Array statt Objekt (`:452`). Abweichung von der jsonStore-Regel, kein
  Fix-Auftrag (Wartung), nur notiert.
- **Wettläufe ohne Sperre:** Alle Stores sind Read-Modify-Write ohne Schloss (z. B. zwei parallele
  `record`/`remove` in `running-servers.json`, fire-and-forget aus `buildService.ts:516`, `:674`). Ob das
  in der Praxis Einträge verliert, ist nicht gemessen.
- **Legacy-Token ohne safeStorage:** `migrate()` entfernt `githubToken` aus `settings.json` auch dann,
  wenn `encrypt()` mangels safeStorage `undefined` lieferte (`connectionsService.ts:220-225`) — der
  Klartext-Token ginge verloren. Betrifft nur Vor-Release-Profile.
- **GitHub-`login`:** Der Typkommentar sagt „resolved from the API once and cached“, in 1.3 schreibt aber
  kein Code ihn in die Datei (nur Durchreichen). Ob ältere Fassungen ihn gesetzt haben, nicht geprüft.
- **Dateimodi** der JSON-Stores: nicht explizit gesetzt (umask-abhängig, typisch 0644); auch
  `connections.json` mit verschlüsselten Secrets ist nicht auf 0600 gesetzt.
- Nicht geprüft: Windows-spezifische Pfade/Backends (DPAPI-Schlüssel in `Local State`), Flatpak-Sandbox-Pfad
  des Profils.
