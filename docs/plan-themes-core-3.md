# Plan: Community-Themes mit @quartz-themes/core 3 (2026-11-22)

Anlass: Quartz 5.2.1 pinnt `@quartz-themes/core` ^3.1.0 (erschienen 2026-11-22, 19:51). Core 3 lädt
jedes Obsidian-Community-Theme beim Build selbst und wandelt es um; die Pakete `@quartz-themes/<id>`,
auf denen QuartzHubs Katalog, Installation, Style-Settings-Erkennung, Theme-Schriften und der
Variablen-Graph stehen, gibt es dafür nicht mehr. Gelesen: das Paket 3.1.0 (`dist/index.d.ts`,
`dist/index.js`), README und `docs/plugins/ThemesCore.md` aus Quartz v5.2.1.

Entschieden (Nutzer, 2026-11-22):
- **Nur noch core 3.** Der Weg über `@quartz-themes/<id>` fällt ganz weg. Ein Projekt mit core 2.x
  (Quartz 5.1, 5.2.0) zeigt unter Stile ▸ Community-Themes nur einen Hinweis aufs Update.
- **Aufräumen anbieten.** Alte Theme-Pakete und die Optionen, die core 3 übergeht, entfernt QuartzHub
  auf Wunsch, mit Snapshot. Eine alte ID wie `catppuccin.frappe` bleibt stehen.
- **Dazu:** Screenshots im Katalog, Theme vorab laden, andere Quellen (GitHub-Repo, URL, lokale
  Datei), dazu `version` und `snippets`.

## Was core 3 tut

- `theme` ist ein Name aus Obsidians Liste (`community-css-themes.json` aus `obsidianmd/obsidian-releases`,
  heute 1057 Einträge, jeder mit `name`, `author`, `repo`, `screenshot`, `modes`; 15 mit `legacy`),
  ein Repo `owner/repo`, eine URL auf ein `theme.css`, ein lokaler Pfad (`./…`, `/…`, `~`, endet auf
  `.css`), seit 3.1.1 `default`/`obsidian`/`Obsidian default` für Obsidians eingebautes Theme oder eine ID aus 2.x. Für die alten IDs trägt core eine Tabelle (`LEGACY_THEMES`, rund 860
  Einträge: Name, Modi, Style-Settings-Preset der Variante).
- Geladen wird beim Build: Liste und `manifest.json` 24 h gecacht (`cacheHours`), das `theme.css` der
  Release-Version oder von `HEAD`, alles unter `.quartz-cache/quartz-themes/` im Projekt. Ohne Netz baut
  es aus dem Cache, ohne Cache bricht der Build ab („offline and no cached copy“).
- Optionen: `theme`, `mode`, `styleSettings` (Objekt oder Pfad zu einer JSON-Datei), `snippets`
  (Pfade oder URLs), `version`, `themeFonts`, `cacheDir`, `cacheHours`; `variation` geht für alte
  Varianten weiter. `aspects`, `include`, `calloutStyle`, `fonts` werden übergangen, mit einer Zeile im
  Log.
- Style Settings: dieselben Schlüssel wie bisher (`<block>@@<setting>`, `@@light`/`@@dark`).
- Ein Theme mit nur einem Modus setzt diesen Modus durch und blendet den Umschalter aus.
- Schriften: Was das Theme einbettet, legt core als Datei unter `static/plugins/quartz-themes/fonts/`
  ab (kein unpkg mehr). Die Schriftvariablen meldet es Quartz' Schriften-Teil (`globalThis.__quartzFonts`);
  dann gilt in Quartz 5.2.1 das Theme, außer wo eine Schrift ausdrücklich gesetzt ist.
- Das CSS kommt als `inline: true` in die Seite, nicht mehr aus einem Paket in `node_modules`.

## Heute in QuartzHub (was wegfällt oder sich ändert)

- `ThemeMarketplace`: Katalog aus `npm search @quartz-themes`, Sterne aus der GitHub-Organisation,
  Details aus `theme.json` (installiert oder jsDelivr), Installation per `npm install`. **Fällt weg.**
- `PluginSchemaReader.themeJSON`/`localThemeDetail`/`themeStyleSettings`: lesen
  `node_modules/@quartz-themes/<id>/theme.json`. **Fallen weg.** Die Style-Settings-Seite hängt heute
  an `styleSettingsId` aus dieser Datei und verschwände sonst still.
- `StyleSettingsSchema`: liest schon Obsidians Liste und den `@settings`-Block aus dem `theme.css` auf
  GitHub, sucht das Theme aber über den Slug der alten ID. **Bleibt im Kern, bekommt seine Quelle neu.**
- `SiteFonts.faces(themeId:)`, `VariableGraph.graph(themeId:)`: Theme-Schriften und -Variablen aus
  `theme.json`. **Bekommen ihre Quelle neu.**
- `FontDelivery`: Lader „theme“ mit Modus `cdn` (unpkg). **Wird lokal.**
- `TemplatePackage`: Teil „Theme“ installiert `@quartz-themes/<id>`. **Nur noch core.**
- `ThemeTab`, `StylesPage.activateTheme`, `OverviewPage` (Name des aktiven Themes).
- `scripts/themes-golden.mjs` und seine Golden Files (gegen QuartzControls Dienst). **Fallen weg**;
  damit weicht QuartzHub hier bewusst von QuartzControl 1.3 ab (Eintrag in `decisions/`).

## Schritt 0: gemessen (2026-11-22)

Die Einzelheiten stehen in `decisions/phase-5-gleichstand.md` unter „themes-core 3: Messung vor dem
Bau“. Was daraus für die Schritte folgt:

- **Das Kern-Update läuft ohne npm-Konflikt.** Die alten Pakete haben keine Peer-Abhängigkeit, sie
  bleiben nur liegen. Das Aufräumen gehört also auf die Theme-Seite (Schritt 5), nicht ins Update.
- **`default` ist seit core 3.1.1 (Quartz 5.2.2) Obsidians eingebautes Theme** (Nachtrag
  2026-11-23); mit 3.0.0 bis 3.1.0 bricht es ab, und `npm install` allein holt 3.1.1 nicht, erst das
  Kern-Update. `default` bleibt deshalb eine gültige Wahl: im Katalog als eigener Eintrag „Obsidian
  (eingebaut)“ vor den Community-Themes, anders als der ausgeschaltete Eintrag. Ob das core eines
  Projekts `default` kennt, liest QuartzHub nicht aus der Nummer: Vorab laden fragt core selbst
  (Schritt 1), und scheitert es, zeigt die Seite den Sprung zu Updates.
- **Ein gescheitertes Theme lässt den Build durchgehen** (Exit 0, das Plugin wird übersprungen).
  Vorab laden (Schritt 1) fängt das beim Wählen ab. Dazu meldet Vorschau & Build die Zeile
  „`@quartz-themes/core` … was skipped“ als Fehler mit Sprung zur Theme-Seite (in Schritt 6).
- **Eine Adresse auf `.css` liest core 3.1.0 als Pfad.** QuartzHub hängt beim Schreiben eine Abfrage
  an (`?quartzhub`); das ist dokumentiert, ein Issue wird nicht gestellt.
- **Das Theme steht in `static/resource-style-<hash>.css`** (die Datei mit `@layer obsidian`), seine
  Schriften unter `static/plugins/quartz-themes/fonts/`. Daraus lesen `SiteFonts` und `VariableGraph`
  in Schritt 4, statt aus `theme.json`.
- **Schriften:** Bei einem aktiven Theme mit `themeFonts` gelten Text-, Überschriften- und
  Code-Schrift aus Stile ▸ Basis nicht für den Inhalt, weil sie in `theme.typography` stehen. Nur was
  in `configuration.fonts` steht, also die Oberflächenschrift und die Schrift je Überschrift, schlägt
  das Theme. Stile ▸ Basis sagt das dann neben den drei Feldern (Schritt 4).
- **Style Settings:** Schlüssel und Wirkung wie bisher. Überschriftenfarben eines Themes kommen gegen
  die Vorlage qc-basic aber nicht an: Ihre Regeln stehen ohne Ebene und schlagen `@layer obsidian`.
  Das war mit core 2 schon so und gehört nicht in diesen Plan. Es steht unten bei „Offen“.

## Was kommt

Ein Schritt je Commit, jeweils mit Bau, `qh-check i18n` und Tests.

1. **Erkennung und Helfer** (Kern). *Fertig 2026-11-23.*
   - `QuartzFeatures.themesCore3`: Das installierte core deklariert `resolveTheme`
     (`node_modules/@quartz-themes/core/dist/index.d.ts`), aus dem Projekt gelesen, nicht aus der Nummer.
   - Neuer Helfer `theme-fetch`: lädt das core des Projekts und ruft `resolveTheme` mit dessen
     Cache-Ordner. Er antwortet mit Name, Modi, Version, Quelle und Preset und legt das `theme.css`
     in den Cache, den der Build liest. Damit fragt QuartzHub core selbst, auch nach alten IDs und
     Tippfehlern (core schlägt drei Namen vor). Ist QuartzHub offline, bekommt der Helfer ein `fetch`,
     das scheitert: Er antwortet dann nur aus dem Cache.
   - Tests mit einem Stellvertreter-core unter `Fixtures/`.
2. **Katalog** (Kern, `ThemeCatalog` statt `ThemeMarketplace`): Obsidians Liste, 24 h im Profil
   gecacht. Die Liste teilt er mit `StyleSettingsSchema`, das heute schon dieselbe lädt. Je Theme Name,
   Autor, Repo, Modi und Screenshot-Adresse. Keine Installation mehr.
3. **Style Settings** (Kern): Das Schema kommt aus dem `theme.css`, das der Helfer geholt hat (die
   Fassung, die auch der Build nimmt), auch für Repo, URL und lokale Datei. Die Seite zeigt Style
   Settings, wenn das Schema Felder hat, nicht mehr nach `theme.json`. Das Preset einer alten ID
   erscheint als Vorgabe. Der Cache `theme-docs/` im Profil wird nach Quelle und Version geführt.
4. **Schriften und Variablen** (Kern): `FontDelivery` (Theme-Schriften lokal), `SiteFonts`,
   `VariableGraph` lesen `static/resource-style-*.css` (Schritt 0). `theme.json`-Leser und `themes-golden.mjs` gehen.
5. **Aufräumen und Vorlagen** (Kern):
   - `ThemeLegacy` findet alte `@quartz-themes/<id>`-Pakete in `package.json` und die übergangenen
     Optionen am Eintrag. Es entfernt sie mit `SnapshotStore.Take` und `npm uninstall`. `theme: default` ist kein Fund mehr (Schritt 0).
   - `TemplatePackage`: Der Teil „Theme“ installiert nur noch core. In ein Projekt mit core 2.x wird
     er nicht angewandt, mit Grund in der Teile-Wahl.
6. **Seite Community-Themes** (App).
   - Der Katalog ist eine Liste mit Vorschaubild, Name, Autor und Modi, mit Suche. Die Bilder werden
     erst beim Erscheinen geladen, verkleinert und folgen `-QHOffline`.
   - Im Inspektor stehen das große Bild, das Repo und **Verwenden**. Das schreibt `theme` und schaltet
     den Eintrag ein, danach lädt der Helfer vorab: „Geladen, Version …“ oder der Fehler mit den
     Vorschlägen.
   - Beim aktiven Theme gibt es eine Quelle als Wahl: Katalog, GitHub-Repo, Adresse, Datei im Projekt
     (Dateiwahl, Pfad relativ). Dazu `version` (Katalog, Repo), `snippets` (Liste aus Dateien oder
     Adressen) und den Modus. Bei einem Theme mit einem einzigen Modus ist der Modus fest, mit einem
     Wort dazu.
   - Der Kasten „Aufräumen“ erscheint, wenn Schritt 5 etwas findet.
   - Ein Projekt mit core 2.x bekommt nur den Hinweis mit Sprung zu Updates.
   - Der alte Code fällt weg: Installieren, Varianten, `calloutStyle` und die Sterne.
7. **Texte, Doku**:
   - Neue Texte de/en über `strings.mjs`, alte Schlüssel weg, `qh-check i18n`.
   - `decisions/phase-5-gleichstand.md` mit den Messungen und der Abweichung von QuartzControl.
   - In `gleichstand.md` werden die Zeilen zu den Themes zu „anders“.
   - In `CLAUDE.md` gehen die Golden-Liste und der Stand.
8. **Handbuch** (de und en):
   - `5-gestaltung/06-community-themes` neu schreiben.
   - Prüfen, was in `05-stile-basis`, `09-vorlagen`, `01-die-ebenen`, `3-uebersicht/01-die-uebersicht`,
     `2-projekte/05-die-einstellungen` und `4-einrichtung/01-website` über Themes steht.
   - Die Aufnahmen für 5.6 kommen vom Demo-Projekt auf 5.2.2 (vorher `handbook-demo.sh` nachziehen).
   - Danach `qh-check handbook` und die Prüfung auf Persönliches.
9. **Abschluss**: Rauchtest, App in Hell und Dunkel angesehen. Prüfen, ob die Vorlagen qc-basic und
   qc-example ein Theme mitbringen.

## Offen und Risiken

- **Vorlage gegen Theme:** qc-basic setzt Überschriften- und Textfarben ohne Ebene, deshalb gelten
  die Farben eines Community-Themes dort nicht. Abhilfe wäre, die Vorlage in eine Ebene zwischen
  `quartz-base` und `obsidian` zu legen. Das ist eine eigene Entscheidung mit dem Nutzer und betrifft
  auch die Projekte, die die Vorlage schon haben.
- Der erste Build mit einem neuen Theme braucht Netz. Vorab laden mildert das, nimmt es nicht weg.
- Screenshots sind teils mehrere MB groß; ohne Verkleinern und ohne Laden erst beim Erscheinen wird die Liste träge.
- core 3 ist jung (3.0.0 bis 3.1.1 an einem Tag; 3.1.1 am 2026-11-23 nachgemessen). Vor jedem Schritt
  nachsehen, ob es eine neuere Fassung gibt; was QuartzHub von core liest, steht im Helfer an einer Stelle.
