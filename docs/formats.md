# Formate: was QuartzControl liest und schreibt

Jede Datei, die QuartzControl 1.3 anfasst, mit dem, was QuartzHub damit tut. Die Einzelheiten (Typen,
Schreiber und Leser mit Datei:Zeile, Schlüsselreihenfolge, Ränder) stehen in drei Teilen:

- [`formats/profil.md`](formats/profil.md): das Profil (`~/Library/Application Support/QuartzControl`)
  und die Verschlüsselung der Geheimnisse
- [`formats/quartz-gui.md`](formats/quartz-gui.md): `<projekt>/.quartz-gui/`, Snapshot- und Kopierregeln
- [`formats/projekt.md`](formats/projekt.md): alles im Projekt außerhalb davon (Stylesheet-Marker,
  `quartz.config.yaml`, `.gitignore`, `.gitattributes`, Bücher, Frames, Projektbild, `.qtpl`)

Grundsatz (`conventions.md`): **Was im Projekt liegt, teilen sich beide Apps**, also schreibt
QuartzHub es in der Form von 1.3. **Das Profil gehört je einer App**: QuartzHub hat sein eigenes
(`~/Library/Application Support/QuartzHub`) und übernimmt beim ersten Start, was dort weiterlebt.

## JSON-Dateien

Fast alle JSON-Dateien schreibt QuartzControl über `jsonStore.ts`: `JSON.stringify(wert, null, 2)`,
**ohne Zeilenende**, atomar über `<name>.tmp-<pid>-<8 hex>`, `fsync`, `rename`. Was sich nicht lesen
lässt, wird zu `<name>.corrupt-<ISO-Zeit mit '-'>`. QuartzHub tut dasselbe mit `JSONStore`
(`Packages/QuartzHubCore/Sources/QuartzHubCore/Storage/`), gemessen gegen Node 24 (`JSJSONTests`).

- **Gemessen am 2026-11-06:** Alle 23 JSON-Dateien in `.quartz-gui/` von `gui-test`, `Example`,
  `QuartzControl-Web` und `werkstatt` sind byte-gleich mit `JSON.stringify(JSON.parse(datei), null, 2)`.
  Ein Lesen und unverändertes Zurückschreiben muss sie also byte-gleich lassen.
- **Schlüsselreihenfolge und unbekannte Schlüssel** überleben in QuartzControl, weil es das gelesene
  Objekt weiterreicht. Deshalb sind QuartzHubs Modelle keine `Codable`-Structs, sondern Sichten auf
  einen `JSONValue`, der Reihenfolge und Unbekanntes behält (`decisions/phase-2-formate.md`).
- **Ausnahmen** vom Muster, jede mit Abschnitt in den Teilen: Deploy-Manifeste, `.modes.json`,
  `.tilde.json`, `snapshot-settings.json` und `content-backups/<id>/symlink.json` gehen per
  einfachem `writeFile` (gleiche Form, nicht atomar, keine Quarantäne); das erste Relay-Manifest ist
  `{}\n` **mit** Zeilenende; `theme-docs/` ist kompakt; `quartz-books/<id>.json` bleibt unlesbar liegen.

## Im Profil

| Datei | Form | QuartzHub |
|---|---|---|
| `projects.json` | `Project[]` (`id`, `name`, `path`, `addedAt`, `lastOpenedAt?`) | **übernehmen**, Phase 2 |
| `settings.json` | Objekt, alle Felder optional (`language`, `theme`, `nodeRuntime`, `serversOnQuit`, `defaultProjectDirectory`); unbekannte Schlüssel bleiben | **übernehmen**, Phase 2 |
| `connections.json` | `StoredConnection[]`, Geheimnis in `encryptedSecret` (base64 von `safeStorage`) | **übernehmen**, Geheimnis je Eintrag in QuartzHubs Schlüsselbund, Phase 2 |
| `relay-secrets.json` | `Record<projektId, …>`, `encrypted` = verschlüsseltes kompaktes JSON, `fingerprint` = HMAC | **übernehmen** wie oben; Fingerprint exakt nachbilden (`localeCompare`), Phase 2 |
| `running-servers.json` | `Record<projektId, {pid, port, startedAt}>` | **nur lesen**: fremde Server von QuartzControl erkennen (Nebeneinander-Betrieb), nie als eigene Waisen |
| `window-state.json`, `dialog-state.json` | Fenster bzw. letzter Ordner | nicht übernehmen (eigene Fenster, macOS merkt sich Ordner selbst) |
| `templates/`, `theme-docs/` | Caches (Vorlage `qc-basic.qtpl`, Theme-Schemas) | nicht übernehmen, QuartzHub füllt eigene |
| `runtime/bin/` | Shims mit Pfaden ins Electron-Bundle | nicht übernehmen (QuartzHub braucht keine Shims) |
| `deploy-secrets.json`, `legacy-publish-targets.json`, `githubToken*` in `settings.json` | Altbestand von vor dem ersten Release (vor 2026-08-27) | nicht übernehmen; QuartzHub nennt es, wenn es sie findet |

## In `.quartz-gui/`

Alles hier teilen sich beide Apps. QuartzHub liest und schreibt es ab dem Dienst, der es braucht
(Phase 3); die Modelle und Golden-File-Tests für die JSON-Dateien kommen in Phase 2.

| Eintrag | Form | Schreiber in QuartzControl |
|---|---|---|
| `publish-targets.json` | `PublishTarget[]` | `publishTargetsService` |
| `project-prefs.json` | Objekt | `projectPrefsService` |
| `layout-breakpoints.json` | Objekt | `layoutFrameService` |
| `theme-presets.json` | `ThemePreset[]` | `themePresetsService` |
| `forms-relay.json` | Relay-Einstellungen ohne Geheimnisse | `formsService` |
| `project-icon.json`, `icon-original.png` | Projektbild | `projectIconService` |
| `core-update.json` | offene Arbeit eines Core-Updates (`wanted`, `putBack`) | `updateService` |
| `snapshot-settings.json` | Ausdünnen der Snapshots | `snapshotService`, nicht atomar |
| `snapshots.git/` | eigenes Git-Repo, je Snapshot ein Root-Commit unter `refs/snapshots/<zeit>-<4 hex>` | `snapshotService` |
| `deploy-manifest-<ziel>.json`, `-relay-<ziel>.json` | `Record<pfad, sha256>` | `deploy/manifest.ts`, nicht atomar |
| `deploy-manifest-<ziel>.modes.json`, `.tilde.json` | einmalige Umstellungen aus 1.1 | `deploy/manifest.ts` |
| `deploy-manifest.json` | Altbestand (ein Manifest je Projekt) | wird übernommen, nie geschrieben |
| `authored-frames/<id>/` | eigene Frames als lokale Quartz-Plugins | `layoutFrameService` |
| `content-backups/<id>/` | beiseitegelegter Content-Ordner (mit `symlink.json`) | `backupService` |
| `backups/` → `backups.migrated/` | alte Config-Kopien, in Snapshots überführt | `snapshotService` |
| `locale-baseline/<code>.ts` | Übersetzungs-Baseline | `localizationService` |
| `logs/`, `staging/<ziel>/`, `branch-worktree-<ziel>/` | Server-Ausgabe, Upload-Vorrat, Pages-Worktree | `buildService`, `deploy/` |

**Ein Lesepfad legt nie `.quartz-gui/` an.** Das Anlegen schreibt nebenbei `.quartz-gui/` in die
`.gitignore`, wenn das Projekt ein git-Repo ist.

## Im Projekt außerhalb von `.quartz-gui/`

| Datei | Was QuartzControl dort tut |
|---|---|
| `quartz/styles/custom.scss`, `_quartzcontrol.scss` | verwaltete Blöcke zwischen `/* --- QuartzControl:managed:<id>:start --- */` und `…:end --- */` (gelesen auch `Quartz-GUI`); fünf IDs, vier davon ziehen beim „Jetzt umstellen“ nach `_quartzcontrol.scss` |
| `quartz.config.yaml` | yaml-Document-API (Kommentare bleiben außer in `plugins`), `lineWidth` 120 |
| `.gitignore`, `.gitattributes` | Zeile `.quartz-gui/`; `quartz/i18n/locales/*.ts merge=ours` mit `merge.ours.driver` |
| `quartz/i18n/locales/<code>.ts` | per AST-Spleiß geänderte Übersetzungen |
| `quartz-books/<id>.json` | Bücher für den Export, `version: 1`, versioniert im Projekt |
| `quartz/static/icon.png`, `icon-dark.png`, `fonts/`, `images/` | Projektbild, Schriften, Snippet-Bilder |
| `quartz-forms/keys/*.asc` | öffentliche Schlüssel der Formular-Empfänger |
| `package.json`, `package-lock.json` | Core-Update: Fassung von Quartz, eigene Pakete per npm zurück |
| `.qtpl` | Vorlagen-Paket: ZIP mit `manifest.json`, `parts/<id>.json`, `files/…` |

Dafür kommen die Leser und Schreiber mit dem jeweiligen Dienst in Phase 3. `quartz.config.yaml` geht
über den Helfer `yaml-edit` (Phase 1, byte-gleich gemessen).

## Geheimnisse

QuartzControl verschlüsselt mit Electrons `safeStorage`; auf macOS liegt der Schlüssel im
Schlüsselbund-Eintrag „QuartzControl Safe Storage“. Gespeichert wird base64 der rohen Ausgabe, ohne
eigenes Präfix. Das Format der Ausgabe ist Chromiums (`v10`, AES-128-CBC, Schlüssel per PBKDF2-SHA1
aus dem Passwort, Salz `saltysalt`, 1003 Runden, IV aus 16 Leerzeichen); Konto des Eintrags
„QuartzControl Key“. Gegen Electron 43.4.1 gemessen (`decisions/phase-2-formate.md`).

QuartzHub verschlüsselt nicht selbst, sondern legt je Geheimnis einen eigenen Schlüsselbund-Eintrag
an. Die Dateien von QuartzControl bleiben unberührt.

## Aufgefallen, nicht behoben (QuartzControl in Wartung)

- `isSnapshotWorthy` nimmt mit `git add -f` alles mit, was nicht ausdrücklich ausgeschlossen ist: Im
  neuesten Snapshot von `gui-test` liegen `.DS_Store` und `backups.migrated/` (39 Dateien).
- `connections.json` mit einem Objekt statt einer Liste und `relay-secrets.json` mit einer Liste statt
  eines Objekts werden nicht beiseitegelegt, sondern beim nächsten Speichern überschrieben.
- Die Stores sind Lesen-Ändern-Schreiben ohne Sperre, auch zwischen zwei Apps: Darum warnt QuartzHub,
  wenn QuartzControl läuft (Plan, „Nebeneinander-Betrieb“).
