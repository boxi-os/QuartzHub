> Bestandsaufnahme vom 2026-11-06 aus dem Code von QuartzControl `fix/1.3.x` (`0bbdb8cd`), Zeilenangaben
> relativ zu `../QuartzControl`. Erstellt von einem Lese-Agenten, Stichproben gegen den Code geprüft
> (Verschlüsselung, Relay-Fingerprint, `connections.json` lesen, Relay-Manifest `{}\n`, Marker-Namen).
> Überblick und was QuartzHub damit tut: [`../formats.md`](../formats.md).

# Formate im Projekt (außerhalb von `.quartz-gui/`)

Stand: QuartzControl `fix/1.3.x` (= 1.3.0, `0bbdb8cd`). Alle Pfade relativ zum Repo
`../QuartzControl`, Projektpfade relativ zum Projektordner. Gegengelesen an echten
Dateien (nur lesend) in `~/Documents/QuartzProjekte/gui-test` und `~/Documents/QuartzProjekte/Example`;
wo das geschah, steht es dabei. Ältere Fassungen gegen `git show v1.0.0:…` geprüft, wo genannt.

Gemeinsame Bausteine, auf die unten verwiesen wird:

- **`writeFileAtomic(path, text)`** (`electron/main/services/jsonStore.ts:121`): Temp-Datei
  `${path}.tmp-${pid}-${uuid8}` im selben Ordner, `handle.sync()` (fsync), `rename`; bei Fehler Temp
  löschen.
- **`whileHoldingStyles`** (`styleLock.ts`) und **`whileHoldingConfig`** (`configService.ts:164`): je ein
  `projectLock()` (`projectLock.ts`): pro `realpath` des Projekts eine Warteschlange, wartend statt
  ablehnend, wiedereintrittsfähig über `AsyncLocalStorage`. Kein Halter des einen nimmt das andere.
  Reihenfolge mit der Snapshot-Warteschlange: erst Queue, dann Config-Lock (Restore nimmt den
  Config-Lock am Ende).
- **`writableTarget(dir, name)`** (`templatePackage/shared.ts`): `containedPath` (resolve + relative, kein
  `..`, nicht absolut) plus `lstat` auf **jedem** Segment; ein Symlink auf dem Weg → `null` (kein
  Schreiben). Ein noch nicht existierendes Segment ist erlaubt.

---

### 1. Stylesheet-Blöcke: `quartz/styles/custom.scss` und `quartz/styles/_quartzcontrol.scss`

**Pfade.** `quartz/styles/custom.scss` (`customScssPath`, `styleService.ts:34`; die einzige Datei, die
Quartz lädt) und seit 1.1 `quartz/styles/_quartzcontrol.scss` (`MANAGED_SCSS_FILE`, `styleService.ts:669`).

**Marker-Syntax** (`managedBlockMarkers`, `styleService.ts:148`):

```scss
/* --- QuartzControl:managed:<id>:start --- */
<body>
/* --- QuartzControl:managed:<id>:end --- */
```

- `MARKER_NAMES = ['QuartzControl', 'Quartz-GUI']` (`styleService.ts:146`). Gelesen werden beide,
  geschrieben nur `QuartzControl`. `Quartz-GUI` war der Name bis 2026-09-18 (beta.2 und älter).
- Ein Block wird als `start\nbody\nend` geschrieben (`upsertManagedBlock`, `:375`); `body` ist der
  Inhalt zwischen den Markern (beim Lesen getrimmt).
- Ein Start-Marker ohne passenden End-Marker ist kein Block (`findManagedBlock`, `:163`).
- `<id>` matcht beim Umbenennen `[\w-]+` (`renameLegacyMarkers`, `:235`).

**Block-IDs**

| id | Inhalt | Schreiber | Ort seit 1.1 |
|---|---|---|---|
| `imports` | Ladereihenfolge: je Zeile `@use "./custom/<name>";` oder `@use "./imported/<name>";`, ggf. `as <ns>` | `setImportOrderNow` (`styleService.ts:1079`), `useLineFor` (`:1059`) | `_quartzcontrol.scss` (umgezogen) |
| `fonts` | importierte `@font-face`-Regeln (Schriftimport, Vorlagen) | `importFontFileNow` (`fontService.ts:53`), `removeImportedFontNow`, Vorlage `writeFontFaceBlock` (`parts.ts`) | `_quartzcontrol.scss` |
| `google-fonts` | von Google geholte `@font-face`, Dateien lokal | `fetchGoogleFontsNow` (`fontService.ts:402`), `dropGoogleFontsNow`, Vorlage `applyGoogleFontsCss` | `_quartzcontrol.scss` |
| `css-vars` | Variablen-Überschreibungen (`:root`, dunkel, nur hell) | `saveVariableOverridesNow` (`styleService.ts:510`) | `_quartzcontrol.scss` |
| `imported-styles` | freier Body einer Vorlage, unter `projectWins` angehängt | `projectWinsCustomScss` (`parts.ts:328`) | bleibt **immer** in `custom.scss` |

`MOVED_MARKERS = ['imports', 'fonts', 'google-fonts', 'css-vars']` (`styleService.ts:670`) – nur diese vier
wandern nach `_quartzcontrol.scss`.

**Inhalt je Block (Syntax aus dem Code, Beispiel gegengelesen in gui-test und Example):**

`imports` (`useSpecifierFor` `:544`: Endung `.scss`/`.css` fällt weg; `useLineFor` `:1059`):

```scss
/* --- QuartzControl:managed:imports:start --- */
@use "./custom/foundation";
@use "./custom/layout";
@use "./custom/01-typo" as ns-01-typo;
/* --- QuartzControl:managed:imports:end --- */
```

- `as <ns>` nur, wenn der Sass-Standard-Namespace (letzte Komponente ohne Endung, ohne führendes `_`,
  bis zum ersten Punkt, `defaultNamespaceFor` `:1037`) kein gültiger Bezeichner
  `/^[A-Za-z_][A-Za-z0-9_-]*$/` oder schon vergeben ist: dann `ns-<name>`, bei Kollision `-2`, `-3` …
- Lesen (`parseImportOrder`, `:564`): Regex `/@use\s+["']([^"']+)["']/g`; nur `custom/` und `imported/`,
  genau eine Ebene; aufgelöst gegen die Platte in der Reihenfolge `<name>.scss`, `_<name>.scss`,
  `<name>.css`. Nicht auflösbare Einträge fallen still weg, Duplikate auch.
- Position: **vor der ersten Regel**, direkt nach führenden `@charset`/`@use`/`@forward`-Zeilen
  (z. B. Quartz' `@use "./variables.scss" as *;`), sonst nach führenden Kommentaren
  (`insertBeforeRules`, `:610`). Danach werden 3+ Zeilenumbrüche auf 2 reduziert.

`fonts` (`importFontFileNow`, `fontService.ts:53`):

```scss
@font-face {
  font-family: "<Family>";
  src: url("static/fonts/<datei>") format("<woff2|woff|truetype|opentype>");
  font-weight: <aus der Datei, z. B. 400 oder "100 900">;   /* nur wenn lesbar */
  font-style: italic;                                       /* nur wenn kursiv */
  font-display: swap;
}
```

- Regeln werden mit `joinUniqueRules` (`styleService.ts:261`) vereinigt: Regel = Text bis zur
  schließenden Klammer auf Tiefe 0 (Kommentare davor gehören dazu), gleich = gleicher Text bis auf
  Whitespace; Trenner `\n\n`.
- URLs **relativ** `static/fonts/…`. Bis 2026-09-19 schrieb die App `/static/fonts/…`;
  `relativeFontUrls` (`:301`) schreibt das um – nur in `fonts`-Blöcken, bei jedem Schreiben
  (`migrateOnWrite`, `:348`) und an der Build-Tür (`migrateFontUrls`, `:322`, beide Dateien).

`google-fonts` (`fetchGoogleFontsNow`, `fontService.ts:402`; gegengelesen gui-test):

```scss
/* --- QuartzControl:managed:google-fonts:start --- */
/* https://fonts.googleapis.com/css2?family=Noto+Sans:wght@400;700&…&display=swap */
/* QuartzControl: left out what the project's own rules cover 68d366fe410c */
/* cyrillic-ext */
@font-face {
  font-family: 'Noto Sans';
  …
  src: url(static/fonts/o-0ZIp….woff2) format('woff2');
  unicode-range: U+0460-052F, …;
}
…
/* --- QuartzControl:managed:google-fonts:end --- */
```

- **Erste Zeile = die Anfrage-URL** als Kommentar; gelesen mit
  `/^\s*\/\*\s*(https:\/\/fonts\.googleapis\.com\/\S+)\s*\*\//` (`requestOf`, `:337`). Daran erkennt ein
  späterer Aufruf „unverändert“.
- Optionale zweite Zeile `/* QuartzControl: left out what the project's own rules cover <sha1-12> */`
  (`OWN_RULES_NOTE`, `:573`; Fingerabdruck über eigene Regeln `family|style|weight|unicode-range`,
  sortiert, sha1, 12 Hex), gelesen mit `/left out what the project's own rules cover ([0-9a-f]+)/`.
- Danach Googles Antwort mit ersetzten URLs `static/fonts/<name>` (unquoted, wie Google es liefert).
- Sonderkörper, wenn alle Familien eigene Regeln haben (`NOTHING_FROM_GOOGLE`, `:569`):
  `/* QuartzControl: every family is declared by the project itself, nothing is fetched from Google */`.
  Der Block bleibt dann stehen: **sein Vorhandensein ist das Zeichen „dieses Projekt hält seine
  Google-Schriften selbst“** (`hasGoogleFontsBlock`), das die Build-Tür abfragt
  (`refreshGoogleFonts`, nur wenn außerdem `theme.fontOrigin === 'local'`).
- Grenzen: 800 Dateien, 128 MiB gesamt, `MAX_FONT_FILE_BYTES` je Datei; Dateiname muss
  `/^[\w-]+(?:\.[\w-]+)*\.(?:woff2|woff|ttf|otf)$/` sein, sonst Fehler.

`css-vars` (`renderVariableOverrides`, `styleService.ts:438`; Lesen `parseVariableOverrides`, `:416`):

```scss
:root {
  --<key>: <hell>;          /* beide Modi */
}

:root[saved-theme="dark"] {
  --<key>: <dunkel>;
}

:root:not([saved-theme="dark"]) {
  --<key>: <hell>;          /* "nur hell", Form C, seit 1.1 */
}
```

- Leere Werte werden nicht geschrieben (`--x: ;` wäre eine leere Custom Property).
- Leerer Gesamtkörper ⇒ Block wird entfernt.
- Lesen: Deklarationen `/--([\w-]+)\s*:\s*([^;]+);/g`; je Regelart gewinnt die spätere. Das
  Attribut wird mit oder ohne Anführungszeichen gelesen (`DARK_RULE`, `:412`) – v1.0.0 las nur die
  gequotete Form (`["']dark["']`).
- Form C (die dritte Regel) schreibt der Renderer nur in einem **umgezogenen** Projekt
  (`src/routes/Styles/VariableRow.tsx` ~`:181`); im nicht umgezogenen wird stattdessen die dunkle
  Hälfte ausdrücklich mitgeschrieben (Form von 1.0.1). Dasselbe beim Vorlagen-Import:
  `inFormOfTarget` (`parts.ts:212`).

`imported-styles`: freier Text des Vorlagen-Bodys (ohne dessen `@use`-Zeilen, die vorne in
`custom.scss` eingefügt werden, sofern nicht schon vorhanden).

**`_quartzcontrol.scss`** (gegengelesen gui-test, Example):

```scss
// Maintained by QuartzControl and loaded by custom.scss with `@use "./quartzcontrol";`.
// The blocks between QuartzControl markers are rewritten by the app (Styles page: load order,
// fonts, variables). Text outside them is kept.

/* --- QuartzControl:managed:imports:start --- */
…
/* --- QuartzControl:managed:imports:end --- */

/* --- QuartzControl:managed:fonts:start --- */
…
/* --- QuartzControl:managed:google-fonts:start --- */
…
/* --- QuartzControl:managed:css-vars:start --- */
…
```

- Kopf: `MANAGED_FILE_HEADER` (`styleService.ts:676`), wörtlich wie oben (drei Zeilen + Leerzeile).
- **Feste Reihenfolge** beim Schreiben (`writeManagedBlocks`, `:795`): erst alle vier Blöcke heraus,
  dann `imports` vor der ersten Regel (`upsertImportBlock`), dann `fonts`, `google-fonts`, `css-vars`
  jeweils ans Ende angehängt mit `\n\n` davor und `\n` danach. Variablen also zuletzt (nach den
  Stylesheets, die sie überschreiben). Text außerhalb der Marker bleibt.
- `custom.scss` eines umgezogenen Projekts trägt **eine Zeile** vor der ersten Regel
  (`MANAGED_USE_LINE`, `:672`), gegengelesen gui-test/Example:

```scss
@use "./variables.scss" as *;

@use "./quartzcontrol";
```

  Erkannt wird jede Schreibweise, die Sass als dasselbe Modul liest (`MANAGED_USE_RE`, `:675`):
  `/^[ \t]*@use\s+(["'])\.\/_?quartzcontrol(?:\.scss)?\1(?:\s+as\s+[\w*-]+)?\s*;/m`.

**„Umgezogen“ (Form 1.1) vs. „Form von 1.0“**

- `isMoved(sources) = _quartzcontrol.scss existiert || custom.scss hat die @use-Zeile` (`:778`).
- Nicht umgezogen: jeder Schreiber ersetzt den Block dort, wo er in `custom.scss` steht, oder hängt
  ihn ans Dateiende (Ladereihenfolge: vor die erste Regel); sonst wird nichts angefasst (`:806`).
- Umgezogen (oder `move: true`): alle vier Blöcke werden aus **beiden** Dateien gelesen, die Datei
  `_quartzcontrol.scss` zuerst geschrieben, dann `custom.scss` ohne die Blöcke und mit der @use-Zeile.
  Bricht es dazwischen ab, steht ein Block in beiden Dateien (wird doppelt gelesen und beim nächsten
  Schreiben dedupliziert), nie in keiner.
- **Kein Schreiber zieht um.** Umgezogen wird nur durch `migrateManagedStyles` (`:866`):
  Stile-Seite „Jetzt umstellen“ mit Snapshot der Art `styleMigration` (die Ausdünnung behält ihn)
  oder beim Anlegen eines Projekts in der App ohne Snapshot (`src/routes/Home.tsx:314`). Ist das
  Projekt schon umgezogen: no-op.
- „Die Form von 1.0“ = nur, was 1.0.x lesen **und zurückschreiben** kann
  (`docs/decisions/conventions-full.md:1375ff`): keine dritte `:not()`-Regel in einem nicht
  umgezogenen Projekt.

**Lesen, Duplikate, fehlende Blöcke**

- Body eines Blocks über beide Dateien: `managedBody` (`:746`) – erst `_quartzcontrol.scss`, dann
  `custom.scss`, in jeder Datei alle Kopien unter beiden Namen in Dateireihenfolge, getrimmt,
  mit `\n\n` verbunden. „Später gewinnt“ wie im Browser (die Kopie in `custom.scss` steht im CSS
  später).
- Mehrere Kopien gleichen Namens (Merge zweier Rechner) werden alle gelesen (`managedCopies`, `:188`).
- Eine Kopie **innerhalb** einer anderen (beta.2 schrieb seinen imports-Block in unseren) gehört zum
  Körper der äußeren (`findManagedBlocks`, `:202`); `checkStyles` meldet das als
  `nestedImportBlock`.
- Schreiben eines Blocks: die Vereinigung kommt an die Stelle der **ersten** Kopie, die übrigen
  werden herausgeschnitten (`replaceManagedBlocks`, `:224`; `cutSpan` `:211` schließt die Lücke nur
  dort).
- `imports` wird beim Mitnehmen nicht als Rohtext verkettet (zwei `@use` desselben Moduls brechen
  Sass), sondern aus der gelesenen, deduplizierten Reihenfolge neu gebildet, außer bei genau einer
  Kopie ohne Duplikat (dann byte-gleich) (`carriedImports`, `:762`).
- Bei jedem Schreiben (`migrateOnWrite`): alle Blöcke, die nur unter `Quartz-GUI` stehen, werden auf
  `QuartzControl` umbenannt (beide Marker, alle Kopien); ein Block mit Kopien unter beiden Namen
  bleibt dem Schreiben dieses Blocks überlassen. Plus relative Font-URLs.
- `stripManagedBlock` (`:517`) entfernt rekursiv alle Kopien unter beiden Namen.
- Build-Tür `repairManagedUse` (`:713`): Datei da, Zeile fehlt → Zeile wieder einsetzen; Zeile da,
  Datei fehlt → Datei nur mit Kopf anlegen. Beides fehlt → nicht umgezogen, nichts tun.
- `saveCustomScss` (`:62`, ganzer CSS-Reiter) setzt die @use-Zeile zurück, wenn
  `_quartzcontrol.scss` existiert und der Inhalt sie nicht hat.

**Wie geschrieben.** Beide Dateien über `writeFileAtomic`, nur wenn sich der Inhalt ändert; immer
unter `whileHoldingStyles` (Schreiber in `styleService`, `fontService`, Vorlagen-Teile `styles`,
`fonts`, `cssVariables`). Außerhalb des Schlosses: Snapshot-Restore, `quartz sync --pull`,
Core-Update-Merge, Editor des Nutzers.

**Was ältere Fassungen lesen**

- beta.2 und älter: nur `Quartz-GUI`-Marker → sieht nach einem Schreiben von ≥ 2026-09-18 **keinen**
  Block (0 von 50 Variablen gemessen), hängt eigene Blöcke an bzw. schachtelt den imports-Block.
- 1.0.x (1.0.0 = 2026-09-25, `v1.0.0` geprüft: `MARKER_NAMES` beide, `google-fonts` vorhanden):
  liest die vier Blöcke **nur in `custom.scss`**; kennt `_quartzcontrol.scss` nicht → ein umgezogenes
  Projekt hat dort 0 Variablen und 0 Stylesheets, und was 1.0.x einschaltet, steht als zweite Kopie in
  `custom.scss`. Kennt die dritte `:not()`-Regel nicht und löscht sie beim nächsten Speichern einer
  Variablen. Liest `saved-theme` nur gequotet.
- `_quartzcontrol.scss`, die @use-Zeile und dass die vier Blöcke dort stehen, sind seit 1.1 ein Format.

**Kantenfälle aus den Kommentaren.** Seit 1.1 kommen die verwalteten Blöcke im CSS **vor** dem Body von
`custom.scss` (Sass setzt Modul-CSS vor das ladende), eine eigene Regel gleicher Spezifität schlägt also
eine Variable der Stile-Seite (`variableCollisions`, `:469`). Ein Ende-Marker zu viel (Kopie in Kopie)
bleibt als Kommentar stehen. Zwei `google-fonts`-Kopien werden als ein Body gelesen, dessen erste Zeile
die Anfrage der ersten Kopie ist.

**Zusammenlegen (31 → 12 Stylesheets, `consolidateStylesheets`, `:887`).** Kein Formatbruch (ältere
Fassung liest zwölf normale Stylesheets). Snapshot `styleMigration` vorher. Ziel-Namen
`CONSOLIDATED_ORDER` (`shared/stylesheetConsolidation.ts:34`): `foundation, layout, components-header,
plugin-multilanguage, components-navigation, plugin-navigations, components-note, content, callouts,
pages, plugin-layout-box, a11y`. Dateiformat:

```scss
// <target> - put together by QuartzControl; each section is named after its former stylesheet.

// ====…==== <alter-name>      (sectionMarker: "=" x max(3, 96 - name.length), shared/…:165)

<Inhalt>
```

Erkannt als „schon zusammengelegt“ an dieser Kopfzeile, an der früheren
`// <target> - put together by QuartzControl from the stylesheets named in the sections below.` oder an
der ersten Zeile der 1.1-Vorlage (`TEMPLATE_FIRST_LINES`).

**Weitere Stylesheet-Dateien.** `quartz/styles/custom/*.scss|css` (eigene, `createStyleFileNow` `:984`
schreibt `// <fileName>\n` per `writeFile`, nicht atomar, und hängt an die Reihenfolge an),
`quartz/styles/imported/<datei>` (`importStyleFileNow` `:113`, `copyFile`). `writeStyleFileNow` ist
atomar. Umbenennen/Löschen schreiben die Reihenfolge vor bzw. nach der Dateioperation passend.

---

### 2. `quartz.config.yaml`

**Pfad.** `quartz.config.yaml` im Projektwurzel (`configService.ts:23`). Gegengelesen gui-test (erste
Zeile `# yaml-language-server: $schema=…` bleibt erhalten).

**Leser** `readConfig` (`configService.ts:38`), Bibliothek `yaml` (`parseDocument`):

- Fehler: `ENOENT` → `configMissing`; `doc.errors.length > 0` → `configNotParseable` (parseDocument
  wirft nicht!); Inhalt weder `null` noch Mapping → `configNotAMapping`; `plugins` vorhanden, aber
  keine Liste → `configPluginsNotAList`.
- Leere Datei (`toJS() === null`) = gültig, wie ein Dokument ohne Schlüssel.
- In-Memory-Form (`QuartzConfig`, `shared/ipc-contract.ts:386`): `configuration` = `configuration:` ohne
  `theme`; `theme` = `configuration.theme`; `plugins`; `layout` (top-level, `undefined` wenn fehlt).
- Je Plugin: `name = deriveName(source)` (nur im Speicher, nie geschrieben) und
  **`enabled: Boolean(p.enabled)`** – fehlender Schlüssel = aus, wie Quartz' Build
  (`filter((e) => e.enabled)`), nicht wie `quartz plugin list`.

**Schlüssel, die QuartzControl liest/schreibt**

```yaml
configuration:
  pageTitle, pageTitleSuffix, enableSPA, enablePopovers, locale, baseUrl,
  ignorePatterns: [..], analytics: {..}|null, …   # alle Schlüssel, Roundtrip
  theme:
    fontOrigin: local|googleFonts|…   # "local" + google-fonts-Block = App hält die Schriften
    cdnCaching: bool
    typography: { header, body, code, title }  # string oder {name: …}
    colors: { lightMode: {…}, darkMode: {…} }
    …                                  # weitere Theme-Schlüssel, Roundtrip
plugins:
  - source: "@quartz-community/x" | "github:owner/repo[#ref]" | /abs/path | {repo, subdir?, ref?, name?}
    enabled: bool                     # immer geschrieben
    order: number                     # Verarbeitungs-Plugins
    options: {…}
    layout: { position, priority, display?, condition?, group?, groupOptions?{grow,shrink,basis,order,align,justify} }
    …                                  # unbekannte Schlüssel bleiben
layout:
  groups: { <name>: { priority?, direction?, wrap?, gap? } }
  byPageType: { <pageType>: { …, template?, positions? } }
```

**Schreiber** `writeConfig(projectPath, config, {snapshot?})` (`:166`) → `writeConfigNow` (`:196`):

1. Snapshot `configChange` **vor** dem Lock, außer `snapshot: false` oder Datei leer/fehlt.
2. Unter `whileHoldingConfig`: Datei neu lesen, `parseDocument`; leer → `new Document({})`. Gleiche
   drei Prüfungen wie beim Lesen (Syntaxfehler, kein Mapping) → Fehler, Datei unverändert.
3. `syncMapping(doc, ['configuration'], config.configuration, keep=['theme'])` (`:139`): Schlüssel, die
   im neuen Objekt fehlen, werden gelöscht (`deleteIn`), die übrigen **je Schlüssel** mit `setIn`
   gesetzt. Kommentare zwischen den Schlüsseln bleiben; der **Teilbaum eines objektwertigen
   Schlüssels** (z. B. `analytics`, `ignorePatterns`) wird als Ganzes ersetzt.
4. `configuration.theme` genauso – aber nur, wenn es schon ein Mapping ist oder `config.theme`
   Schlüssel hat (sonst kein leeres `theme:`). `colors`/`typography` werden je als Ganzes ersetzt.
5. **`doc.set('plugins', …)` ersetzt die ganze Liste** (Kommentare darin gehen verloren). `name`
   wird entfernt; jeder String-`source` geht durch `ownFramePath` (siehe unten).
6. `layout` nur, wenn `config.layout !== undefined`: `setIn(['layout','groups'], …)` und
   `setIn(['layout','byPageType'], …)` (je `?? {}`), also nur diese zwei Unterschlüssel.
7. `doc.toString({ lineWidth: 120 })` (`:248`; wie die Quartz-CLI `writeDataToFile`, sonst falten beide
   lange Strings gegeneinander).
8. `atomicWrite` (`:120`): Ergebnis nochmals `parseDocument` – bei Fehlern Abbruch
   („Refusing to write invalid YAML …“); Temp `${path}.tmp-${Date.now()}`, `writeFile`, `rename`.
   **Kein fsync** (anders als `writeFileAtomic`).

**Die zwei Schreibwege** (`docs/decisions/plugins-and-config.md:~60`): (a) direkt über `config.save` →
`writeConfig` für Ein/Aus, Optionen, Reihenfolge, Layout, Basis; die CLI-Befehle
`quartz plugin enable/disable/config --set` sind für Built-ins No-ops (Exit 0, keine Änderung) und
werden nicht benutzt. (b) Die Quartz-CLI im Kindprozess nur für `plugins.add`/`.remove`/
`.installFromLock`/`.prune` (schreibt `quartz.config.yaml` und `quartz.lock.json` selbst, nicht unter
`whileHoldingConfig`). Direkte Änderungen adressieren Einträge per **Array-Index**, nicht per
abgeleitetem Namen (zwei Quellen können denselben Namen ergeben).

**Weitere Schreiber über `writeConfig`.** IPC `config.save` (`ipc/handlers.ts:223`), Vorlagen-Teile
(`parts.ts:100` `writeConfigPatch`, immer `snapshot: false`, ein Snapshot für den ganzen Import),
`rewriteRecordedPaths` (`projectPaths.ts`, `snapshot: false`).

**`repointProjectPaths(from, to)`** (`projectPaths.ts:36`, nach Duplizieren/Verschieben): schreibt jeden
absoluten Pfad, der **innerhalb** des alten Projektordners liegt, auf den neuen um – an drei Stellen:
`plugins[].source` (unter `whileHoldingConfig`, `writeConfig` ohne Snapshot), `quartz.lock.json`
`plugins.<id>.source` und `.resolved` (`writeFileAtomic`, `JSON.stringify(lock, null, 2) + '\n'`, Form
der CLI) und Symlinks `.quartz/plugins/<id>` (`rm` + `symlink(next, link, 'dir')`). Ohne
`quartz.config.yaml` im Ziel: nichts.

**`repointAuthoredFrames(projectPath)`** (`:74`): gleiche drei Stellen, aber per Muster
`ownFramePath` (`framePaths.ts`): ein absoluter Pfad, der `/.quartz-gui/authored-frames/` enthält und
**nicht** schon in dieses Projekt zeigt, wird auf `<projekt>/.quartz-gui/authored-frames/<id>` gesetzt –
nur wenn dieser Frame hier existiert. Läuft beim Hinzufügen eines Ordners (`handlers.ts:139`), an der
Build-Tür (`buildService.ts:472`), nach Restore; `writeConfig` wendet `ownFramePath` auf jeden Schreiber
an.

**Ältere Fassungen.** Gleiches Dateiformat (Quartz' Format). Unterschied in der Semantik: frühere Fassungen
lasen fehlendes `enabled` wie die CLI als „an“; `writeConfig` schreibt `enabled` seither für jeden
Eintrag. Frame-Einträge enthalten **absolute, maschinenspezifische Pfade** (gegengelesen gui-test:
`source: ~/Documents/QuartzProjekte/gui-test/.quartz-gui/authored-frames/frame-drawing`).

---

### 3. `.gitignore`

**Schreiber** `ensureIgnored` (`projectDirs.ts:18`), aufgerufen von `quartzGuiDir()` (jedem
**schreibenden** Zugriff auf `.quartz-gui/`; Lesepfade nehmen `quartzGuiPath()` und schreiben nichts).

- Nur wenn `<projekt>/.git` existiert.
- Schon vorhanden, wenn eine getrimmte Zeile genau `.quartz-gui/` oder `.quartz-gui` ist.
- Sonst angehängt (Präfix `\n`, falls die Datei nicht auf `\n` endet):

```gitignore

# Arbeitsverzeichnis von QuartzControl (Backups, Presets, Deploy-Manifest)
.quartz-gui/
```

- Der Kommentar kommt aus `mainT('gitignoreComment')` in der App-Sprache (de: oben; en: `QuartzControl
  working directory (backups, presets, deploy manifest)`, `electron/main/i18n.ts:190/771`). Er ist frei
  änderbar; entscheidend ist nur die Regelzeile. Gegengelesen gui-test, Example (Zeilen 16–17).
- `writeFileSync`, nicht atomar, kein Lock. Seit v1.0.0 unverändert (geprüft).

---

### 4. `.gitattributes` und `merge.ours.driver`

**Schreiber** `ensureGitAttributes` (`localizationService.ts:285`), automatisch nach jedem erfolgreichen
`saveLocaleEntry` und per IPC `localization.ensureGitAttributes`.

- Zeile (`MERGE_OURS_LINE`, `:251`): `quartz/i18n/locales/*.ts merge=ours`
- Vorhanden-Test: `existing.includes(MERGE_OURS_LINE)` (Teilstring). Sonst angehängt, mit `\n` davor,
  falls die Datei nicht auf `\n` endet, und `\n` danach. `writeFileSync`, nicht atomar.
- **Zweite Hälfte, ohne die die Zeile wirkungslos ist:** `git config merge.ours.driver true` im Repo
  (`.git/config`, nie versioniert), nur wenn `git config --get merge.ours.driver` leer ist. Kein Repo →
  still ignoriert.
- Status (`getGitAttributesStatus`, `:276`) = Datei hat die Zeile **und** Driver gesetzt.
- Gegengelesen gui-test und Example: `.gitattributes` = `* text=auto eol=lf` (von Quartz) +
  `quartz/i18n/locales/*.ts merge=ours`; `merge.ours.driver` = `true`.

---

### 5. Übersetzungsdateien `quartz/i18n/locales/<code>.ts`

**Leser** `getLocaleEntries` (`localizationService.ts`): TypeScript-AST, `export default { … }` (durch
`as`/`satisfies`/Klammern), rekursiv; Blatt = String/NoSubstitutionTemplate (`kind: 'string'`) oder
anderer Ausdruck (`kind: 'template'`, Quelltext). Liste ohne `definition.ts`, nur Codes, die
`isLocaleCode` besteht.

**Schreiber** `saveLocaleEntry` (`:110`): AST neu parsen, genau den Initializer am Pfad ersetzen
(`JSON.stringify(value)` bei `string`, roh bei `template`), sonst byte-gleich; ganzen Text mit
`ts.transpileModule` syntaktisch prüfen; `writeFileSync` (nicht atomar, kein Lock); danach
`ensureGitAttributes`. Vor der **ersten** Änderung Kopie nach `.quartz-gui/locale-baseline/<code>.ts`
(anderer Bereich). Vorlagen-Teil `translations` schreibt über denselben Weg.

---

### 6. `quartz-books/<id>.json` (seit 1.3)

**Pfad.** `quartz-books/<id>.json` im Projektwurzel (`BOOK_DIR`, `shared/bookDefinition.ts`); bewusst
versioniert, außerhalb `content/` und `static/`. `id` = Dateiname, `BOOK_ID = /^[a-z0-9][a-z0-9-]{0,62}$/`;
andere `.json` im Ordner werden übergangen.

**Form** (`serializeBook`; `id` steht nicht in der Datei, `version` immer zuletzt gesetzt):

```json
{
  "title": "", "subtitle": "", "author": "",
  "language": "",            // Sprachcode quartz-multilanguage, "" = Sprache der Website
  "root": "",                // Ordner-Slug ohne führende/abschließende "/", "" = ganze Website
  "order": null,             // null = Navigation der Website; sonst [{ "slug": "…" } | { "heading": "…" }]
  "excluded": [],            // Slugs
  "coverImage": "",          // projektrelativ, "" = Projektbild
  "toc": true, "tagIndex": false, "backlinks": false,
  "outsideLinks": "site",    // "site" | "text"
  "pdf": { "pageSize": "A4", "landscape": false },   // "A4" | "A5" | "Letter"
  "version": 1
}
```

Geschrieben mit `JSON.stringify(…, null, 2) + '\n'` über `writeFileAtomic` (`bookService.ts:84`), nach
`writableTarget` (kein Symlink auf dem Weg, auch nicht `quartz-books/` selbst). Neue id aus dem Titel
(`bookIdFromTitle`: Kleinbuchstaben, ä→ae ö→oe ü→ue ß→ss, NFKD ohne Diakritika, `[^a-z0-9]+`→`-`, max.
48 Zeichen, Fallback `dokument`, bei Kollision `-2`, `-3` …).

**Lesen** `normalizeBook`: jeder Schlüssel einzeln mit Default, Texte auf 500 Zeichen, Slugs 1–1024,
max. 10 000 Einträge, doppelte Slugs in `order` behalten die erste Position; **unbekannte Schlüssel
bleiben erhalten** (auch in `pdf`); fehlendes `version` = 1. Nur ein Nicht-Objekt ist „unlesbar“.

**Unlesbar** (JSON-Fehler, kein Objekt, Lesefehler außer ENOENT): Datei **bleibt liegen**, wird mit
Grund gelistet (`listBooks().unreadable`), und `saveBook` weigert sich, sie zu überschreiben – anders
als `jsonStore`, das Unlesbares als `.corrupt-…` beiseitelegt (wäre sonst im nächsten Commit des
Nutzers). Lesen legt den Ordner nie an. Löschen: `rm` nach `writableTarget`.

Ältere Fassungen (≤ 1.2) kennen den Ordner nicht (`shared/bookDefinition.ts` fehlt in `v1.0.0`).

---

### 7. `content/`: Wechsel Ordner/Symlink, Parken, `index.md`

- **Wechsel** `changeContentSource` (`contentService.ts:367`): Quelle darf weder in `content/` liegen
  noch es enthalten (`relative()`-Test). Snapshot `contentChange`, dann das bisherige `content/` nach
  `.quartz-gui/content-backups/` **verschieben** (`snapshotContent`, anderer Bereich). Danach
  `symlink(sourcePath, content, 'dir')` mit **absolutem** Ziel (Dialog liefert absolut) oder rekursives
  `cp`.
- **Lesen** `getContentStatus` (`:56`): `lstat` (nicht `existsSync`); bei Symlink `readlink`, ein
  relatives Ziel relativ zum Ordner des Links aufgelöst; hängender Link = Link mit `targetExists:
  false`.
- **Parken** `withContentSymlinkParked` (`contentSymlink.ts`): für git-Operationen, die nicht durch einen
  Symlink schreiben können (Core-Update `merge`/`merge --abort`, Snapshot-Reset). Ist `content` ein
  Symlink: `readlink` merken, Link löschen, Operation ausführen, im `finally` das von git angelegte
  `content/` rekursiv löschen und `symlink(target, content, 'dir')` mit dem **gemerkten Rohziel** wieder
  anlegen. Der Vault wird nie berührt. Kein Zustand auf Platte, der den Absturz mitten drin überlebt
  (dann fehlt der Link bzw. steht ein echtes `content/` da).
- **`content/index.md`** (`createIndexPage`, `:260`): nur auf Klick, öffnet mit Flag `wx` (überschreibt
  nie), schreibt in einen verlinkten Vault durch:

```markdown
---
title: <Titel>
---

- [<Ordner>](<./<Ordner>/>)
- [<Notiz>](<./<Notiz>.md>)
```

  Ordner zuerst, dann Notizen der obersten Ebene, `localeCompare(numeric, base)`; `[`, `]`, `\` im
  Text escaped; Ziel in `<…>`, außer es enthält `<`, `>` oder Zeilenumbruch → percent-encodiert.
- Gegengelesen gui-test: `content/` ist dort ein echter Ordner (kein Symlink-Fall verfügbar).

---

### 8. Layout-Frames: was im Projekt (außerhalb `.quartz-gui/`) entsteht

Die Frame-Dateien selbst (`frame.json`, `package.json`, `dist/frames.js`) liegen unter
`.quartz-gui/authored-frames/<id>/` (anderer Bereich; `writeFrameFiles` `layoutFrameService.ts:459`,
alle drei atomar, je Projekt serialisiert; `writeAllFrames` vor jedem Build/Server-Start). Im übrigen
Projekt hinterlässt ein Frame:

- `quartz.config.yaml`: Plugin-Eintrag mit **absolutem** `source` auf das Frame-Verzeichnis (gegengelesen
  gui-test, `enabled: true`, `options: {}`, `order: 50`). Angelegt durch `quartz plugin add <dir>` bzw.
  `installPluginSource` (`saveFrame`, `:653`) nur für neue Frames; beim Vorlagen-Import wird der Eintrag
  selbst nachgetragen, wenn die CLI mit Exit 0 keinen schrieb.
- `quartz.lock.json`: `source`/`resolved` mit demselben absoluten Pfad (von der CLI).
- `.quartz/plugins/<id>` → Symlink auf das Frame-Verzeichnis (gegengelesen gui-test).
- Frame-id `/^[a-z0-9][a-z0-9-]{0,63}$/i`, Form `frame-<timestamp>` oder `frame-<name>`.
- Löschen (`deleteFrame`, `:680`): `quartz plugin remove <id>`, dann Verzeichnis `rmSync`.
- `generatePackageJson` (`:393`): `{ name: id, version: "1.0.0", private: true, type: "module", quartz:
  { frames: { Frame: { exportName: "Frame" } } } }`.
- Unter `quartz/` schreibt QuartzControl **keine** generierten Frame-Dateien (gesucht nach
  `join(projectPath,'quartz',…)`; nur Styles, Static, Locales).

---

### 9. Projektbild / Favicon: `quartz/static/icon.png`, `quartz/static/icon-dark.png`

- `icon.png` ist zugleich Favicon-Quelle (`@quartz-community/favicon` liest den Pfad fest, keine Option).
  `icon-dark.png` nur für das Kopfbild (Quartz liefert keins; jede Vorlage seit 2026-09-24 schon).
- **Schreiben** (`prepareImage`, `projectIconService.ts:182`): nur `.png`, `.jpg`, `.jpeg`; über
  `nativeImage`; längste Kante ≤ 512 px. Ein PNG, das schon passt, wird **byteweise kopiert**
  (`copyFile`), sonst `writeFile(scaled.toPNG())`. Nicht atomar, kein Lock. SVG/leeres Bild → Fehler, alte
  Datei bleibt.
- `setProjectIcon` (`:227`): beim **ersten** Zuweisen wird das vorhandene `icon.png` nach
  `.quartz-gui/icon-original.png` kopiert; Marker `.quartz-gui/project-icon.json`
  `{ custom, hasOriginal, customDark }` (anderer Bereich).
- `clearProjectIcon` (`:255`): Original zurückkopieren, sonst `icon.png` löschen (dann hat die Website
  kein Favicon). `clearProjectIconDark`: `icon-dark.png` löschen.
- Quartz' eigenes `icon.png` = Git-Blob `b6656a7a819cf41ba6502b9eddf4e580617bbaba` (`:138`); ein anderes
  ohne Marker gilt als „nicht erfasst“ (`hasUnrecordedIcon`, z. B. nach Git-Sync-Klon). Der Vorlagen-Teil
  `static` ersetzt nur Dateien, die laut Marker nicht vom Nutzer gewählt sind.

---

### 10. Snippets und Bilder (quartz-layout-box)

- **Snippets**: Ordner = Option `dir` des layout-box-Eintrags (projektrelativ), Datei = `file`. Endungen
  `.html`, `.htm`, `.md`, max. 2 MiB. Ordner darf nicht absolut, außerhalb, in `.git`, `node_modules`,
  `.quartz`, `.quartz-gui` (ohne Groß/Klein) oder im Build-Ausgabeordner liegen (`checkDir`,
  `snippetService.ts`). Name: ein Segment, nicht versteckt, ≤ 200 Zeichen, ohne `/\:\0`.
- `writeSnippet` (`:138`): `writeFileAtomic`, ohne `overwrite` bei existierender Datei
  `{status:'exists'}`; Schreiben nie durch einen Symlink (`writablePath` → `writableTarget`), Lesen schon.
- **Bilder**: `quartz/static/images/<name>` (`IMAGES_DIR`), Endungen `.png .jpg .jpeg .gif .webp .svg
  .avif`, max. 20 MiB; `importStaticImage` (`:212`) → `copyAtomic` (Temp-Kopie, fsync, rename). Auf der
  Website `{{root}}/static/images/<name>`. Rückgabe `relativePath: "images/<name>"`.
- Umbenennen `rename`, Löschen über den Papierkorb (`trashStaticFile`, `:280`).

---

### 11. Schriftdateien `quartz/static/fonts/`

- Ordner `projectFontsDir` (`styleService.ts:1357`), flach.
- Import (`importFontFileNow`): `copyFile` unter Original-Basisnamen, Regel in Block `fonts` (siehe 1).
- Google (`downloadFontFile`, `fontService.ts:361`): je Datei `.<name>.download` im Ordner, dann
  `rename`; Namen sind Content-Hashes von Google, eine lesbare Datei gleichen Namens (Größe > 0) wird
  nicht neu geladen; bricht der Lauf ab, werden die in diesem Lauf geschriebenen Dateien gelöscht.
  Nach dem Schreiben des Blocks werden Dateien der Vorgänger-Regeln gelöscht, die keine Regel in
  irgendeinem Stylesheet mehr nennt (`deleteUnreferencedFontFiles`; gesucht in `quartz/styles`,
  `quartz/components/styles`, `quartz/static`, rekursiv).
- Alles unter `whileHoldingStyles`. Vorlagen-Teil `fonts` schreibt `files/fonts/<name>` per `writeFile`
  (nicht atomar), gleiche SHA-256 = übersprungen.

---

### 12. `quartz-forms/keys/<name>.asc`

`importKeyFile` (`formsService.ts:156`): Name `/^[A-Za-z0-9_-]{1,64}$/`, Datei ≤ 256 KiB, muss
`-----BEGIN PGP PUBLIC KEY BLOCK-----` enthalten und darf **kein** `-----BEGIN PGP PRIVATE KEY BLOCK-----`
enthalten (dann nichts geschrieben). Ziel per `writableTarget`, ohne `overwrite` bei Existenz
`{exists: rel}`. Schreiben: `${target}.tmp-${pid}`, `writeFile`, `rename` (kein fsync). Im Projekt
versioniert, von der Build gelesen (`keys.<name>.file`), nicht veröffentlicht. Relay-Einstellungen liegen in
`.quartz-gui/forms-relay.json` (anderer Bereich).

---

### 13. `package.json` / `package-lock.json` beim Core-Update

Langfassung vor Änderungen lesen (`docs/decisions/conventions-full.md`, Abschnitt Core-Update). Kurz:

- `NPM_OWNED_FILES = ['package.json', 'package-lock.json']` (`updateService.ts:289`) werden **nicht
  gemergt**, sondern von upstream genommen und von npm neu geschrieben.
- Plan (`localPackageChanges(base, ours, theirs)`, `shared/packageJsonDeps.ts:78`, rein): base =
  `package.json` am Merge-Base, ours = Arbeitsbaum, theirs = `FETCH_HEAD`. Ergebnis
  `reinstall: [{name, section, range}]`, `upstreamWins: string[]`, `unreproducible: string[]`
  (nicht leer ⇒ Plan gilt nicht, git entscheidet). Sektionen `dependencies`, `devDependencies`,
  `optionalDependencies`, `peerDependencies`.
- Ablauf: Merge läuft → Snapshot `coreUpdate`; Remote `quartz-upstream` =
  `https://github.com/jackyzha0/quartz.git` anlegen, falls fehlt (in `.git/config`; gegengelesen
  gui-test/Example); `git fetch quartz-upstream HEAD` mit Frist; die verfolgten npm-Dateien (`git
  ls-files`) per `git stash push -m <stashMessage(mergeCommit)> -- …` beiseite; `git merge FETCH_HEAD
  -m 'Merge quartz-upstream (via QuartzControl)'` (`:472`), Content-Symlink geparkt. Konflikte nur in den
  npm-Dateien → `git checkout --theirs`, nicht verfolgte → `git rm --cached --force`, `git add`, `git
  commit --no-edit`.
- Danach `npm install --save-<sektion> name@range …` je Sektion (`reinstallCommands`, `:122`) für das, was
  im gemergten `package.json` fehlt, sonst `npm install`. npm schreibt beide Dateien.
- Was npm geschrieben hat, kommt per `git commit --amend --only -- <npm-dateien>` in den eigenen
  Merge-Commit (nur wenn HEAD ein Commit dieses Laufs bzw. der notierte ist und nicht gepusht).
- Offener Stand zwischen zwei Läufen in `.quartz-gui/core-update.json`
  `{ head, reinstall, filesAtHead, installFailed, putBack }` (anderer Bereich).
- Projektlock je `realpath` für Update und Abbruch.

---

### 14. Vorlagen-Paket `.qtpl`

**Container** (`zipArchive.ts`): ZIP, eigene Implementierung. Pro Eintrag Methode 8 (raw deflate) oder 0
(store, wenn deflate nicht kleiner ist oder `store: true`), Flag Bit 11 (UTF-8-Namen), CRC32, DOS-Zeit,
„version needed“ 20, keine Verzeichniseinträge, kein ZIP64 (Eintrag > 0xFFFFFFFF → Fehler), keine
Verschlüsselung. Lesen: Namen mit absolutem Pfad, `..`, Laufwerksbuchstabe oder NUL → ganzes Archiv
abgelehnt; CRC geprüft; Summe entpackt ≤ 256 MiB, **vor** dem ersten entpackten Byte geprüft
(`maxOutputLength`). Endung `TEMPLATE_PACKAGE_EXTENSION = '.qtpl'`.

**Layout**

```
manifest.json                 # erster Eintrag
parts/<partId>.json           # je Baustein, JSON.stringify(payload, null, 2)
files/styles/<custom|imported>/<datei>
files/fonts/<datei>
files/static/<pfad>           # alles unter quartz/static außer fonts/
files/content/<pfad>
```

**Manifest** (`exportPackage`, `templatePackage/index.ts:65`; Typ `TemplatePackageManifest`):

```json
{
  "formatVersion": 1,
  "name": "…",
  "description": "…",                         // optional
  "createdAt": "<ISO>",
  "createdBy": { "app": "QuartzControl", "appVersion": "1.3.0" },
  "source": { "projectName": "<ordnername>", "quartzHead": "<git rev-parse --short HEAD>" },
  "parts": [ { "id": "<partId>", "stats": { "<zahl>": 0 }, "requires": [ { "name": "<npm>", "version": "…" } ] } ]
}
```

`FORMAT_VERSION = 1` (`shared.ts`, seit v1.0.0 unverändert). `requires[].version` nur informativ,
installiert wird nach Namen.

**Bausteine** in Registrier- = Anwendungsreihenfolge (`TEMPLATE_PART_IDS`, `ipc-contract.ts:1473`;
identisch in v1.0.0): `frames, theme, plugins, appearance, layout, presets, translations, styles, fonts,
static, cssVariables, content`. Payloads (`parts.ts`):

| id | Payload |
|---|---|
| `frames` | `{ frames: GridFrameDefinition[] }` |
| `theme` | `{ entry: PluginEntry, themeId: string\|null }` (der `@quartz-themes/*`-Eintrag) |
| `plugins` | `{ entries: PluginEntry[] }` (ohne Frame-Einträge; eigene Plugins ohne `#ref`) |
| `appearance` | `{ colors, typography, fontOrigin?, cdnCaching? }` |
| `layout` | `{ layout: LayoutConfig\|null, breakpoints: FrameBreakpointWidths }` |
| `presets` | `{ presets: ThemePreset[] }` |
| `translations` | `{ scope: 'changed'\|'all', locales: [{ code, entries: LocaleEntry[] }] }` |
| `styles` | `{ customScss: <custom.scss ohne alle 5 Blöcke und ohne @use-Zeile, getrimmt>, order: string[], files: string[] }` |
| `fonts` | `{ fontFaceCss: string\|null, googleFontsCss?: string\|null, files: string[] }` |
| `static` | `{ files: string[] }` (≤ 25 MiB) |
| `cssVariables` | `{ overrides: CssVariableOverride[] }` (`{key, light, dark?, lightOnly?}`) |
| `content` | `{ files: string[] }` (≤ 100 MiB) |

- `customScss` ist bewusst ohne `@use "./quartzcontrol";` (`stripAllManaged`, `parts.ts:49`), damit 1.0.x
  das Paket bauen kann.
- Import: ein Snapshot `styleChange` (Name des Pakets) vorher; `styles`, `fonts`, `cssVariables` je unter
  `whileHoldingStyles`; jeder Dateiname über `writableTarget` in `plan` **und** `apply`. Strategie
  `packageWins` (Standard) ersetzt, `projectWins` behält und warnt. Unbekannte Part-ids →
  `unknownParts`. quartz-forms-Optionen werden zusammengeführt (`mergeFormsOptions`).
- Altes Ordnerformat (vor dem Einzeldatei-Format: `layout.json`, `colors.json`, `frames.json`,
  `plugins.json`, `custom.scss`, `imported/`, `fonts/`) wird nur gelesen und in Bausteine umgewandelt.

---

### Unklar / nicht gefunden

- **`quartz create`/Setup-Assistent** (`createService.ts`): was Quartz selbst beim Anlegen schreibt, habe
  ich nicht im Detail gelesen; QuartzControl prüft danach nur, dass `quartz.config.yaml` existiert, und
  zieht die Stile um (`Home.tsx:314`).
- **`quartz sync`** (Git-Sync) erzeugt Commits, aber kein eigenes Dateiformat; nicht weiter untersucht.
- **Nicht-atomare Schreiber** (laut Code so, nicht als Absicht kommentiert): `.gitignore`,
  `.gitattributes`, Locale-Dateien (`writeFileSync`), `createStyleFileNow`, Vorlagen-Teile
  `styles`/`fonts`/`static` (`writeFile`), Projektbild (`copyFile`/`writeFile`), `atomicWrite` der Config
  ohne fsync. Ob QuartzHub das angleichen darf, ist eine Entscheidung, keine Formatfrage.
- **YAML-Kommentare**: erhalten bleiben sie zwischen Schlüsseln von `configuration`/`theme` und
  außerhalb; innerhalb der `plugins`-Liste und innerhalb objektwertiger Schlüssel (`colors`,
  `typography`, `layout.groups`, `layout.byPageType`) gehen sie verloren. Aus dem Code abgeleitet, nicht
  gemessen.
- **Exakte Zeichen der `sectionMarker`-Linie**: `"=".repeat(max(3, 100 - 4 - name.length))` laut Code;
  an einer zusammengelegten Datei nicht gegengelesen.
- **Form C an echter Datei**: in gui-test und Example steht keine `:root:not([saved-theme="dark"])`-Regel;
  die Syntax ist nur aus dem Code belegt.
- **`imported-styles`** an echter Datei nicht gesehen.
- **Bücher**: in gui-test und Example gibt es kein `quartz-books/`; Form nur aus dem Code.
- **Content-Symlink**: in den beiden Projekten nicht als Symlink vorhanden (gui-test hat zusätzlich einen
  Link `gui-test-content -> content`, der nicht von QuartzControl stammt); Parken nur aus dem Code.
- **Frame-Dateien** (`frame.json`, `dist/frames.js`), `content-backups/`, `locale-baseline/`,
  `project-icon.json`, `core-update.json`, `forms-relay.json`: liegen in `.quartz-gui/`, gehören dem
  anderen Bereich.
- **`quartz.lock.json`** wird außer bei `rewriteRecordedPaths` nur von der Quartz-CLI geschrieben; deren
  Format (`writeLockfile` in `quartz/cli/plugin-data.js`) habe ich nicht im Quartz-Quelltext gelesen.
