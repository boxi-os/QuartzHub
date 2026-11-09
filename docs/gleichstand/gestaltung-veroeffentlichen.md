# Gleichstand: Gestaltung und Veröffentlichen

Rohfassung vom 2026-11-09. Quellen: QuartzControls Routen (`src/routes/…`), das Handbuch
(`QuartzControl-Handbuch/…`, Kapitel 4 und 6), QuartzHubs `App/Pages/…` und der Katalog,
`docs/decisions/phase-4-oberflaeche.md` (kurz „P4“) und `docs/decisions/phase-3-dienste.md`
(kurz „P3“, nur Kern-Beleg, nicht „an der App gemessen“).

Vorgehen beim Abgleich: Für jede Route wurden alle Textschlüssel aus `t('…')` gegen die
Schlüssel in QuartzHubs Swift-Code (`App/`, `Packages/QuartzHubCore/Sources/`) gelegt. Fast alle
sind in Gebrauch; ungenutzt sind nur Beschriftungen ohne eigene Funktion
(`themeEditor.fontMatches`/`fontNoGoogleMatch`/`fontNoLocalMatch`/`fontListFor` — QuartzHub nimmt
`textInputSuggestions` ohne Trefferzahl; `themes.allDisabled`, `themes.catalog.github`,
`layoutEditor.componentPill.dragHandle`, `…paletteDragName`, `…inspector.title`,
`…frameBuilder.areaPanelEmpty`, Seitentitel/-beschreibungen). `layoutEditor.frameBuilder.placeArea`/`moveArea`
sind seit 2026-11-09 die Knöpfe im Inspektor (Layout: Frames).

Pfad-Kürzel: `Packages/…` = `Packages/QuartzHubCore/Sources/QuartzHubCore`; QC = `~/Development/QuartzControl/src/routes/`, HB = Handbuch
`~/Obsidian/QuartzProjekte/QuartzControl-Handbuch/`, QH = `~/Development/QuartzHub/`.

### Stile: Seite

| Funktion | QuartzControl | Handbuch | QuartzHub | Stand | Beleg |
|---|---|---|---|---|---|
| Vier Reiter (Basis, Community-Themes, Variablen, Eigenes CSS), bei schmalem Fenster als Menü | Styles/index.tsx | 4-gestaltung/01-die-vier-ebenen.md | App/Pages/Styles/StylesPage.swift | gemessen | P4 „Stile: der Rahmen und Basis“: „Bei 1000×700 werden die Reiter zum Menü … (gesehen)“ |
| Ein „Speichern“ (⌘S) schreibt alle Reiter (custom.scss, Stylesheets, Config, Variablen) | Styles/index.tsx | 4-gestaltung/02-basis-farben-und-schriften.md | App/Pages/Styles/StylesModel.swift | gemessen | P4 „Stile: der Rahmen und Basis“: „Eine Farbe ändern und mit ⌘S speichern: In der Config ändert sich nur diese Farbe“ |
| Entwurf überlebt den Wechsel des Reiters | Styles/index.tsx | – | App/Pages/Styles/StylesModel.swift | gebaut | P4 „Stile: der Rahmen und Basis“ beschreibt es („ein Entwurf überlebt den Wechsel des Reiters“), keine Messung genannt |
| Verlassen mit ungespeicherten Änderungen fragt | Styles/index.tsx | – | App/Pages/Styles/StylesPage.swift (`.unsavedChanges`) | gebaut | In P4 für Stile nicht unter „Gemessen“ |
| Zeile zur Kaskade: welches Theme gilt, wie viele Variablen überschrieben | Styles/index.tsx (`styles.cascade.*`) | 4-gestaltung/01-die-vier-ebenen.md | App/Pages/Styles/StylesPage.swift (`cascadeLine`) | gebaut | keine Messung in P4 |
| Hinweis „Projekt in der Form von 1.0“ mit „Jetzt umstellen“ (Snapshot vorher, gesperrt bei Ungespeichertem) | Styles/MoveStylesNote.tsx | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/StylesPage.swift | gemessen | P4 „Stile: der Rahmen und Basis“: „„Jetzt umstellen“ legt zuerst einen Snapshot `styleMigration` an, danach ist `_quartzcontrol.scss` byte-gleich“ |
| Fehlende `@use "./quartzcontrol"`-Zeile beim Speichern wieder einsetzen, mit Satz | Styles/index.tsx (`styles.managedUseRestored`) | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/StylesModel.swift | gebaut | keine Messung in P4 |
| Meldungen nach dem Speichern zu Google-Schriften (geholt, entfernt, n Dateien gelöscht, fehlend) | Styles/index.tsx (`styles.googleFonts*`) | 4-gestaltung/02-basis-farben-und-schriften.md | App/Pages/Styles/StylesModel.swift | Netz | P4 „Stile: der Rahmen und Basis“: „Nicht gemessen: eine neue Google-Schrift speichern (holt bei Google, braucht Netz)“ |
| Variable nicht schreibbar / Ladefehler der Seite | Styles/index.tsx (`styles.variableNotWritable`, `styles.loadFailed`) | – | App/Pages/Styles/StylesModel.swift | gebaut | P4: „Nicht gemessen: … ein Speicherfehler mitten im Ablauf“ |

### Stile: Basis

| Funktion | QuartzControl | Handbuch | QuartzHub | Stand | Beleg |
|---|---|---|---|---|---|
| Neun Farben je Modus bearbeiten (Farbwähler mit Alpha) | Styles/Basics.tsx, ColorPicker.tsx | 4-gestaltung/02-basis-farben-und-schriften.md | App/Pages/Styles/BasicsTab.swift | gemessen | P4 „Stile: der Rahmen und Basis“: „Eine Farbe ändern und mit ⌘S speichern“; Farbwähler „schreibt `#rrggbb` oder `rgba()`“ |
| Vom Theme/einer Variablen überschriebene Farben und Schriften abgeblendet, mit Zahl, weiter bearbeitbar | Styles/Basics.tsx (`themeEditor.overridden*`, `overrideCounted`) | 4-gestaltung/02-basis-farben-und-schriften.md | App/Pages/Styles/BasicsTab.swift | gemessen | P4: „Theme minimal …: Das Band zählt 9 von 9 Farben und 3 von 3 Schriften, die Felder sind abgeblendet, „THEME“ steht an den Farben“ |
| Font-Quelle wählen (Google / lokal) | Styles/Basics.tsx (`themeEditor.fontSource`) | 4-gestaltung/02-basis-farben-und-schriften.md | App/Pages/Styles/BasicsTab.swift | gebaut | keine Messung in P4 |
| Drei Schriftfelder mit Vorschlägen (1959 Google-Familien bzw. Familien des Projekts) | Styles/Basics.tsx | 4-gestaltung/02-basis-farben-und-schriften.md | App/Pages/Styles/BasicsTab.swift | gebaut | P4 beschreibt „Vorschlägen … über `textInputSuggestions`“; QC-Trefferzahl/„keine Treffer“ ungenutzt; keine Messung |
| Hinweise am Schriftfeld: andere Schreibweise, Google unbekannt, vom Theme, von eigener Variable | Styles/Basics.tsx | 4-gestaltung/02-basis-farben-und-schriften.md | App/Pages/Styles/BasicsTab.swift | gebaut | keine Messung in P4 |
| Schalter „Schriften lokal ausliefern“ (Google-Dateien ins Projekt) und „Jetzt holen“ | Styles/Basics.tsx (`themeEditor.delivery.selfHost`, `fetchNow`) | 4-gestaltung/02-basis-farben-und-schriften.md | App/Pages/Styles/BasicsTab.swift | Netz | P4: „Nicht gemessen: … die Schalter für die Auslieferung speichern (holt oder entfernt die Google-Dateien)“ |
| Schalter „Theme-Schriften“ (unpkg) | Styles/Basics.tsx (`themeEditor.delivery.themeFonts`) | 4-gestaltung/02-basis-farben-und-schriften.md | App/Pages/Styles/BasicsTab.swift | gebaut | P4: „Nicht gemessen: … die Schalter für die Auslieferung speichern“ |
| Zeile „was gerade gilt“: Lader (Quartz, Plugin Fonts, Theme), verlinkt/lokal, Stand der Schriftdateien | Styles/Basics.tsx (`themeEditor.delivery.state.*`, `styleEditor.current.fonts*`) | 4-gestaltung/02-basis-farben-und-schriften.md | App/Pages/Styles/BasicsTab.swift | gemessen | P4: „… die Lader sagen Quartz und Plugin“ |
| Warnung: Plugin Fonts ohne Basis-URL bricht den Build | Styles/Basics.tsx (`themeEditor.delivery.baseUrlMissing`) | 4-gestaltung/02-basis-farben-und-schriften.md | App/Pages/Styles/BasicsTab.swift | gebaut | keine Messung in P4 |
| Bekannte Konflikte: „Fix anlegen“ legt Stylesheet an und springt zu „Eigenes CSS“ | Styles/Basics.tsx (`styles.fixes.*`) | 4-gestaltung/01-die-vier-ebenen.md | App/Pages/Styles/BasicsTab.swift | gemessen | P4: „„Fix anlegen“ legt `custom/fix-heading-fonts.scss` an, nimmt sie in die Ladereihenfolge und wechselt zu „Eigenes CSS““ |
| Eigene Schriftdatei importieren (ttf/otf/woff/woff2), Gewicht/kursiv aus der Datei, Rolle zuweisen | Styles/Basics.tsx (`themeEditor.localFont*`, `fontImportDetected*`) | 4-gestaltung/02-basis-farben-und-schriften.md | App/Pages/Styles/BasicsTab.swift | gemessen | P4: „Import einer WOFF2: Familie aus dem Dateinamen, Gewicht 100 900 und kursiv aus der Datei“ |
| Satz „Die Datei nennt kein ‚weight‘“ bei Datei ohne Gewicht | Styles/Basics.tsx (`themeEditor.fontImportUndetected`) | 4-gestaltung/02-basis-farben-und-schriften.md | App/Pages/Styles/BasicsTab.swift | gebaut | keine Messung in P4 (Kern: P3 „Schriftdateien lesen“) |
| Ungenutzte Schriften entfernen (fragt, nimmt Datei und Regel weg) | Styles/Basics.tsx (`themeEditor.unusedFonts.*`) | – | App/Pages/Styles/BasicsTab.swift | gemessen | P4: „danach unter „Ungenutzte Schriften“; Entfernen fragt und nimmt Datei und Regel weg“ |

### Stile: Community-Themes

| Funktion | QuartzControl | Handbuch | QuartzHub | Stand | Beleg |
|---|---|---|---|---|---|
| Katalog laden und durchsuchen (n weitere Treffer) | Styles/Theme.tsx (`themes.catalog.*`) | 4-gestaltung/03-community-themes.md | App/Pages/Styles/ThemeTab.swift | gemessen | P4 „Stile: Community-Themes“: „Der Katalog kam über `npm search` (177 Themes, 30 sichtbar, „147 weitere Treffer“)“ |
| Details eines Katalog-Themes (Modi, Varianten, Farben, Schriften) | Styles/Theme.tsx | 4-gestaltung/03-community-themes.md | App/Pages/Styles/ThemeTab.swift (Inspektor) | gemessen | P4: „die Details von cupertino aus seinem `theme.json` im Inspektor“ |
| Katalog nicht ladbar: Platzhalter-Themes mit Hinweis, „Neu laden“ | Styles/Theme.tsx (`themes.catalog.unavailable`, `refresh`) | 4-gestaltung/03-community-themes.md | App/Pages/Styles/ThemeTab.swift | gebaut | keine Messung in P4 |
| „Installieren & aktivieren“ | Styles/Theme.tsx (`themes.catalog.install`) | 4-gestaltung/03-community-themes.md | App/Pages/Styles/ThemeTab.swift | Netz | P4: „Nicht gemessen: „Installieren & aktivieren“ und „Anwenden“ eines Presets (beide `npm install`, Netz)“ |
| Aktives Theme deaktivieren (Einstellungen bleiben) | Styles/Theme.tsx (`themes.disableAll`) | 4-gestaltung/03-community-themes.md | App/Pages/Styles/ThemeTab.swift | gemessen | P4: „Deaktivieren und ⌘S: In der Config steht `enabled: false`, Theme und Modus bleiben“ |
| „Wieder aktivieren“ | Styles/Theme.tsx (`themes.active.reactivate`) | 4-gestaltung/03-community-themes.md | App/Pages/Styles/ThemeTab.swift | gebaut | in P4 beschrieben, nicht unter „Gemessen“ |
| Style Settings des Themes, gruppiert nach Überschriften, je Art ein Bedienelement | Styles/StyleSettingsForm.tsx | 4-gestaltung/03-community-themes.md | App/Pages/Styles/ThemeTab.swift | gemessen | P4: „Ultra Lobster …: „139 Optionen“ …, die Gruppen wie im Original auf- und zugeklappt“ |
| Suche in den Style Settings, „Zurücksetzen“ je Feld | Styles/StyleSettingsForm.tsx (`styles.styleSettings.searchPlaceholder`, `reset`) | 4-gestaltung/03-community-themes.md | App/Pages/Styles/ThemeTab.swift | gebaut | keine Messung in P4 (Kern: P4 „Style Settings schreiben und lesen“, Golden) |
| Theme ohne Style Settings: Hinweis mit Sprung zu Variablen | Styles/Theme.tsx (`themes.active.noStyleSettingsNote`, `goToVariables`) | 4-gestaltung/03-community-themes.md | App/Pages/Styles/ThemeTab.swift | gebaut | keine Messung in P4 |
| Beschreibungen der Optionen („Doku“) neu laden | Styles/Theme.tsx (`styles.styleSettings.refresh`) | 4-gestaltung/03-community-themes.md | App/Pages/Styles/ThemeTab.swift | Netz | P4: „Nicht gemessen: … „Doku neu laden“ gegen GitHub“ |
| Als Preset speichern | Styles/Theme.tsx (`themes.active.saveAsPreset`) | 4-gestaltung/03-community-themes.md | App/Pages/Styles/ThemeTab.swift | gemessen | P4: „Preset speichern schreibt `.quartz-gui/theme-presets.json` …, „Aktiv“ steht daneben“ |
| Preset anwenden | Styles/Theme.tsx (`themes.presets.apply`) | 4-gestaltung/03-community-themes.md | App/Pages/Styles/ThemeTab.swift | Netz | P4: „Nicht gemessen: … „Anwenden“ eines Presets (… `npm install`, Netz)“ |
| Preset löschen (fragt) | Styles/Theme.tsx (`themes.presets.confirmDelete`) | 4-gestaltung/03-community-themes.md | App/Pages/Styles/ThemeTab.swift | gemessen | P4: „Löschen fragt, danach ist die Datei inhaltlich wieder die vom Anfang“ |

### Stile: Variablen

| Funktion | QuartzControl | Handbuch | QuartzHub | Stand | Beleg |
|---|---|---|---|---|---|
| Hauptvariablen nach Gruppen des Katalogs, mit Anzahl und „n geändert“ | Styles/Variables.tsx, VariableGroup.tsx | 4-gestaltung/04-variablen.md | App/Pages/Styles/VariablesTab.swift | gemessen | P4 „Stile: Variablen“: „Ohne Theme: 64 Hauptvariablen, 151 weitere, 67 geänderte“ |
| Alle Theme- und Build-Variablen nach Namensanfang gruppiert, „Einzelne Variablen“ | Styles/Variables.tsx | 4-gestaltung/04-variablen.md | App/Pages/Styles/VariablesTab.swift | gemessen | P4: „Mit Theme minimal: 1143 weitere Variablen, … die Präfixgruppen zugeklappt“ |
| Suche (bis 150 Treffer) | Styles/Variables.tsx | 4-gestaltung/04-variablen.md | App/Pages/Styles/VariablesTab.swift | gebaut | P4: „Nicht gemessen: die Suche mit ihrer Grenze von 150“ |
| Filter „Nur geänderte“ und Farben/Andere Werte | Styles/Variables.tsx | 4-gestaltung/04-variablen.md | App/Pages/Styles/VariablesTab.swift | gebaut | in P4 beschrieben, nicht unter „Gemessen“ |
| Zeile mit zwei Farbflecken, Wert, „n abhängig“, Herkunft | Styles/VariableRow.tsx | 4-gestaltung/04-variablen.md | App/Pages/Styles/VariablesTab.swift | gemessen | P4: „`--secondary` im Inspektor mit „Von dir geändert. Ursprung: Letzter Build“, der Kette und sieben Abhängigen“ |
| Gewählte Variable: aktueller Wert, Herkunft und Kette, „Verwendet“/„Wird verwendet von“ | Styles/VariableRow.tsx | 4-gestaltung/04-variablen.md | App/Pages/Styles/VariablesTab.swift (Inspektor) | gemessen | wie oben |
| Sprung zu einer verwendeten/abhängigen Variablen | Styles/VariableRow.tsx | 4-gestaltung/04-variablen.md | App/Pages/Styles/VariablesTab.swift | gemessen | P4: „Der Sprung zu `--link-color` landet dort“ |
| Eigenen Wert setzen (hell/dunkel; „nur hell“ im umgestellten Projekt) und speichern | Styles/VariableRow.tsx | 4-gestaltung/04-variablen.md | App/Pages/Styles/VariablesTab.swift | gemessen | P4: „`--dark` hell auf `#222222` geändert und mit ⌘S gespeichert: … genau eine Regel“ |
| „Im Dunkelmodus abweichend“ / „In beiden Modi gleich“ | Styles/VariableRow.tsx (`splitDark`, `unsplitDark`) | 4-gestaltung/04-variablen.md | App/Pages/Styles/VariablesTab.swift | gebaut | keine Messung in P4 (Kern: P4 „eine Variable bearbeiten (`VariableEditing`)“) |
| Auf Originalwert zurücksetzen | Styles/VariableRow.tsx (`resetToOriginal`) | 4-gestaltung/04-variablen.md | App/Pages/Styles/VariablesTab.swift | gebaut | keine Messung in P4 |
| Eigene Variable ohne Original entfernen (fragt) | Styles/VariableRow.tsx (`removeOwn`) | 4-gestaltung/04-variablen.md | App/Pages/Styles/VariablesTab.swift | gebaut | P4: „Nicht gemessen: … das Entfernen einer eigenen Variablen in der laufenden App“ |
| Ohne Auswahl: Zahlen und eigene Änderungen zum Anspringen | Styles/Variables.tsx (`panelEmpty*`) | 4-gestaltung/04-variablen.md | App/Pages/Styles/VariablesTab.swift | gebaut | in P4 beschrieben, nicht unter „Gemessen“ |
| Hinweis: custom.scss setzt dieselbe Variable und gewinnt | Styles/Variables.tsx (`collisionNote`) | 4-gestaltung/04-variablen.md | App/Pages/Styles/VariablesTab.swift | gebaut | keine Messung in P4 |
| „Es gibt noch keinen Build-Output“ und „Neu einlesen“ | Styles/Variables.tsx (`noBuild`, `reload`) | 4-gestaltung/04-variablen.md | App/Pages/Styles/VariablesTab.swift | gebaut | keine Messung in P4 |
| „nicht auflösbar“ (nur in einem Selektor / Variable darin ohne Wert) | Styles/VariableRow.tsx (`unresolved`) | 4-gestaltung/04-variablen.md | App/Pages/Styles/VariablesTab.swift | gebaut | keine Messung in P4 (Kern: P4 „Variablen auflösen“, Golden) |

### Stile: Eigenes CSS

| Funktion | QuartzControl | Handbuch | QuartzHub | Stand | Beleg |
|---|---|---|---|---|---|
| Editor mit Reitern je Datei (custom.scss fest, Punkt für ungespeichert, Reiter schließen) | Styles/CustomCss.tsx | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/CssTab.swift | gemessen | P4 „Stile: Eigenes CSS, Editor und Dateien“: „`foundation.scss` aus der Ladereihenfolge geöffnet, eine Zeile getippt, ⌘S: genau diese Zeile in der Datei“ |
| Ladereihenfolge anzeigen (Inspektor) | Styles/CustomCss.tsx (`styleEditor.files.*`) | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/CssTab.swift | gemessen | wie oben (Datei aus der Ladereihenfolge geöffnet) |
| Neue Datei anlegen | Styles/CustomCss.tsx (`files.create`) | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/CssTab.swift | gemessen | P4: „„Neue Datei“ `probe` legt `custom/probe.scss` an und nimmt sie in die Ladereihenfolge“ |
| Datei löschen (fragt) | Styles/CustomCss.tsx (`files.confirmDelete`) | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/CssTab.swift | gemessen | P4: „Löschen fragt und nimmt beides wieder weg“ |
| Datei umbenennen | Styles/CustomCss.tsx (`files.rename`) | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/CssTab.swift | gebaut | P4: „Nicht gemessen: … Umbenennen, Verschieben“ |
| Nach oben / Nach unten in der Ladereihenfolge | Styles/CustomCss.tsx (`files.moveUp`/`moveDown`) | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/CssTab.swift | gebaut | P4: „Nicht gemessen: … Verschieben“ |
| „Vorhanden, aber nicht eingebunden“ mit „Einbinden“ | Styles/CustomCss.tsx (`files.orphansHeading`, `include`) | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/CssTab.swift | gebaut | keine Messung in P4 |
| Verwaltete Datei `_quartzcontrol.scss` ansehen, mit Warnung | Styles/CustomCss.tsx (`managedFile.warning`) | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/CssTab.swift | gebaut | in P4 beschrieben, nicht unter „Gemessen“ |
| „Datei importieren…“ | Styles/CustomCss.tsx (`importFile`) | – | App/Pages/Styles/CssTab.swift | gebaut | P4: „Nicht gemessen: … Importieren über den Dateidialog“ |
| „Extern öffnen“ | Styles/CustomCss.tsx (`openExternally`) | – | App/Pages/Styles/CssTab.swift | gebaut | keine Messung in P4 |
| „Code prüfen“: fehlerfrei | Styles/CustomCss.tsx (`check.ok`) | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/CssTab.swift | gemessen | P4: „Die Prüfung beim Ankommen sagt „fehlerfrei““ |
| „Code prüfen“: Fehler mit Datei, Zeile und Sprung | Styles/CustomCss.tsx (`check.failed`, `location`) | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/CssTab.swift | gemessen | P4: „„Undefined mixin“ mit „In custom/foundation.scss, Zeile 290 öffnen“, der Sprung landet dort“ |
| Prüfung: verschachtelte Ladereihenfolge mit „Ladereihenfolge neu schreiben“ | Styles/CustomCss.tsx (`check.nestedImportsRepair`) | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/CssTab.swift | gebaut | keine Messung in P4 |
| Zusammenlegen der Vorlagen-Stylesheets von 1.0 (Snapshot, Umbenennen) | Styles/ConsolidateStylesNote.tsx | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/CssTab.swift | gebaut | P4: „Nicht gemessen: Zusammenlegen (die Kopien sind schon zusammengelegt)“ |
| Veralteter Entwurf: „Speichern würde diese Änderung überschreiben“, neu laden | Styles/CustomCss.tsx (`styles.scssStaleBy.*`, `scssStaleReload`) | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/CssTab.swift | gebaut | P4: „Nicht gemessen: … der Hinweis eines veralteten Entwurfs in der App“ |
| „Komponente wählen“ fügt Selektor ein, „(Klasse ungeprüft)“ | Styles/CustomCss.tsx (`componentOption*`) | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/CssTab.swift | gebaut | keine Messung in P4 (Kern: P4 „„Komponente wählen“ (`ComponentSelectors.list`)“, Golden) |
| Aktuell geltende Farben und Schriften (Zusammenfassung, Tabelle, Probe, Lader) | Styles/CustomCss.tsx (`styleEditor.current.*`) | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/CssReference.swift | gemessen | P4 „Nachschlagen und geltende Stile“: „mit minimal die Zusammenfassung „ui-sans-serif · ui-monospace“ und die Lader; ohne Theme Noto … und echter Probe“ |
| Klick auf Farbfeld/Schriftnamen kopiert | Styles/CustomCss.tsx (`cssVars.copyHint`) | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/CssReference.swift | gebaut | keine Messung in P4 |
| „Ersatzschrift“ bei fehlender Schriftdatei | Styles/CustomCss.tsx (`current.notInstalled*`) | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/CssReference.swift | anders | P4: „Bewusst anders als QuartzControl: Die generischen Familien von CSS … gelten als vorhanden und zeigen die passende Systemschrift“ |
| Verfügbare CSS-Variablen nachschlagen, Suche, Klick fügt `var(--name)` ein | Styles/CssVariableReference.tsx | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/CssReference.swift | gebaut | P4: „Nicht gemessen: … ⌥-Klick“; Einfügen des Namens nicht genannt |
| Farbfeld der Referenz fügt den Wert ein | Styles/CssVariableReference.tsx (`insertValue`) | – | App/Pages/Styles/CssReference.swift | gemessen | P4: „das Farbfeld von `--secondary` fügt `#399617` ans Ende des Editors“ |
| Callout-Grundgerüste einfügen | Styles/CssVariableReference.tsx (`calloutsInsertHint`) | – | App/Pages/Styles/CssReference.swift | gebaut | P4: „Nicht gemessen: … das Callout-Grundgerüst in der App“ |
| Original-Styles einer Komponente (nur lesend) | Styles/CustomCss.tsx (`referenceHeading`) | 4-gestaltung/05-eigenes-css.md | App/Pages/Styles/StylesPage.swift (`PluginReferences`) | gebaut | P4: „Nicht gemessen: die Original-Styles einer Komponente“ |

### Layout: Seite

| Funktion | QuartzControl | Handbuch | QuartzHub | Stand | Beleg |
|---|---|---|---|---|---|
| Drei Reiter Übersicht, Komponenten, Frames; „Wo war ich“ (Reiter, Seitentyp, Auswahl) | LayoutEditor/index.tsx | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/LayoutPage.swift | gebaut | P4 „Layout: der Rahmen und die Bühne“ beschreibt `@SceneStorage`, keine Messung des Wiederkehrens |
| Speichern (⌘S): Config auf Übersicht/Komponenten, Frame auf Frames | LayoutEditor/index.tsx, FrameBuilder.tsx | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/LayoutPage.swift | gemessen | P4 „Layout: Frames“: „⌘S ändert in `frame.json` genau `colSpan`“; „Layout: der Rahmen“: „`search` „Später“ und ⌘S tauschen genau zwei Prioritäten“ |
| Verlassen mit ungespeicherten Änderungen fragt (Config und Frame) | LayoutEditor/index.tsx | – | App/Pages/Layout/LayoutPage.swift | gemessen | P4 „Layout: Frames“: „Verlassen fragt, „Änderungen verwerfen“ lässt die Datei, wie sie war“ |
| Frame-Entwurf über das Verlassen hinweg halten | LayoutEditor/index.tsx (`stage.otherDraftOpen`) | – | App/Pages/Layout/LayoutPage.swift | anders | P4: „Das ist bewusst anders als dort: QuartzControl hielt einen Frame-Entwurf über das Verlassen hinweg fest, hier fragt es wie jede Seite“ |
| Übergabe von der Plugins-Seite („Auf der Bühne zeigen“, „Im Layout-Editor“) | LayoutEditor/index.tsx | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/LayoutPage.swift (`LayoutHandOver`) | gemessen | P4 „Layout: Frames“: „„Im Layout-Editor“ für `focus` und „Auf der Bühne zeigen“ für `darkmode` auf der Plugins-Seite landen richtig“ |

### Layout: Übersicht

| Funktion | QuartzControl | Handbuch | QuartzHub | Stand | Beleg |
|---|---|---|---|---|---|
| Fünf Kennzahlen (platziert, Bedingung, ausgeschaltet, abweichende Seitentypen, eigene Frames) | LayoutEditor/LayoutOverview.tsx | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/OverviewTab.swift | gemessen | P4 „Layout: Übersicht“: „21 platziert …, 1 mit Bedingung, 8 ausgeschaltet, 7 Seitentypen …, 5 eigene Frames“ |
| Kennzahl aufklappen zur Liste | LayoutEditor/LayoutOverview.tsx | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/OverviewTab.swift | gemessen | P4: „„Ausgeschaltet“ klappt die acht auf“ |
| Matrix Komponente × Seitentyp mit Zeichen, Satz als Tooltip, Legende | LayoutEditor/LayoutOverview.tsx | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/OverviewTab.swift | gemessen | P4: „Canvas- und Excalidraw-Seiten zeigen die geleerten Seitenleisten“ |
| Sprung vom Spaltenkopf auf die Bühne des Seitentyps | LayoutEditor/LayoutOverview.tsx | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/OverviewTab.swift | gemessen | P4 „Layout: Übersicht“: „„Tag-Seiten“ öffnet die Bühne auf Tag-Seiten mit Frame `index`“ |
| Sprung von Komponente auf die Bühne, von Frame in den Frame-Editor | LayoutEditor/LayoutOverview.tsx | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/OverviewTab.swift | gebaut | P4 beschreibt die Wege, gemessen ist nur der Spaltenkopf |
| Frame eines Plugins „unbekannt“ | LayoutEditor/LayoutOverview.tsx | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/OverviewTab.swift | gebaut | keine Messung in P4 |

### Layout: Komponenten

| Funktion | QuartzControl | Handbuch | QuartzHub | Stand | Beleg |
|---|---|---|---|---|---|
| Bühne zeigt die Bereiche nach dem Frame (Standard, eigene, Plugin-Frame als Satz) | LayoutEditor/GlobalBoard.tsx, stageGeometry.ts | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/StageTab.swift, StageLayouts.swift | gemessen | P4 „Layout: Übersicht“: „öffnet die Bühne auf Tag-Seiten mit Frame `index`“; Geometrie im Kern: P4 „Bühne nach Proportionen“, Golden |
| Ansicht Desktop/Tablet/Mobil | LayoutEditor/GlobalBoard.tsx (`stage.viewLabel`) | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/StageTab.swift | gebaut | keine Messung der Bühne in den drei Ansichten in P4 |
| Komponente mit der Maus in einen Bereich ziehen | LayoutEditor/GlobalBoard.tsx | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/StageTab.swift | gemessen | P4: „`reader-mode` mit der Maus auf `breadcrumbs` gezogen landet vor dem Inhalt an erster Stelle“ |
| Aus dem Vorrat ziehen: weitere Instanz (Duplikat) | LayoutEditor/Palette.tsx | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/StageTab.swift | gebaut | keine Messung in P4 |
| In den Vorrat ziehen: ausschalten bzw. Duplikat entfernen; wieder auf Bereich: einschalten | LayoutEditor/Palette.tsx, GlobalBoard.tsx | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/StageTab.swift | gebaut | keine Messung in P4 |
| Ziehen mit der Tastatur (Leertaste, Pfeile, Escape) | LayoutEditor/GlobalBoard.tsx (dnd-kit) | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/ComponentInspector.swift | anders | P4 4b: „Die Tastatur verschiebt über den Inspektor, so wie QuartzControls Seitenleiste seit 1.1. macOS hat keine native Geste …“ |
| Ansage jeder Ablage | LayoutEditor/GlobalBoard.tsx (`dnd.*`) | – | App/Pages/Layout/StageTab.swift | gebaut | P4 „Layout: der Rahmen“: „Jede Ablage wird mit den übernommenen `dnd.*`-Sätzen angesagt“, ohne Messung |
| Leerer Bereich „Leer: hierher ziehen“ | LayoutEditor/GlobalBoard.tsx (`emptySlot`) | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/StageTab.swift | gebaut | keine Messung in P4 |
| Ohne Auswahl: Zusammenfassung (Frame, was in welchem Bereich) | LayoutEditor/LayoutSummary.tsx | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/ComponentInspector.swift | gebaut | keine Messung in P4 |
| Position, Früher/Später (⌥⌘↑/↓) | LayoutEditor/Inspector.tsx | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/ComponentInspector.swift | gemessen | P4: „`search` „Später“ und ⌘S tauschen genau zwei Prioritäten“ |
| Sichtbarkeit (Immer, Nur Desktop, Nur Mobil) | LayoutEditor/Inspector.tsx | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/ComponentInspector.swift | gebaut | keine Messung in P4 |
| Bedingung (vorgegeben oder eigene) | LayoutEditor/Inspector.tsx | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/ComponentInspector.swift | gebaut | keine Messung in P4 |
| Gruppe und Gruppen-Optionen (Grundbreite, wachsen, schrumpfen, Reihenfolge, Ausrichtung) | LayoutEditor/Inspector.tsx | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/ComponentInspector.swift | gebaut | keine Messung in P4 |
| Duplizieren / In den Vorrat legen (Hinweis, wenn das ganze Plugin ausgeht) | LayoutEditor/Inspector.tsx | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/ComponentInspector.swift | gebaut | keine Messung in P4 |
| Optionen des Plugins im Inspektor | LayoutEditor/ComponentOptions.tsx | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/ComponentInspector.swift | gebaut | P4 beschreibt „dasselbe `OptionsForm` wie auf der Plugins-Seite“, keine Messung |
| Flex-Gruppen anlegen und einstellen (Richtung, Umbruch, Abstand, Priorität) | LayoutEditor/GroupsPanel.tsx | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/StageTab.swift | gebaut | keine Messung in P4 |
| Seitentyp wählen, „(angepasst)“ | LayoutEditor/GlobalBoard.tsx (`pageType.*`) | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/StageTab.swift | gemessen | P4 „Layout: der Rahmen“: „auf Tag-Seiten `search` ausgeblendet …“ |
| Frame je Seitentyp wählen | LayoutEditor/GlobalBoard.tsx (`template*`) | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/StageTab.swift | gebaut | keine Messung des Wechsels in P4 |
| Komponente auf einem Seitentyp ausblenden (alle Duplikate, mit Zahl) | LayoutEditor/Inspector.tsx (`pageType.hideOnType`, `excludeDuplicateHint`) | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/ComponentInspector.swift | gemessen | P4: „auf Tag-Seiten `search` ausgeblendet … schreibt `exclude: ["@quartz-community/search"]`“ |
| Bereich auf einem Seitentyp leeren | LayoutEditor/GlobalBoard.tsx (`pageType.areaCleared`) | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/StageTab.swift | gemessen | P4: „… die rechte Seitenleiste geleert schreibt … `right: []`“ |
| „Anpassung entfernen“ | LayoutEditor/GlobalBoard.tsx (`pageType.removeOverride`) | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/StageTab.swift | gebaut | P4 nennt „beides zurück“, nicht den Knopf |
| Tote Ausschlüsse (Hinweis) | LayoutEditor/GlobalBoard.tsx (`excludeDeadHint`) | – | App/Pages/Layout/StageTab.swift | gebaut | keine Messung in P4 |
| „Frame bearbeiten“ springt in den Frames-Reiter | LayoutEditor/GlobalBoard.tsx (`stage.editFrame`) | 4-gestaltung/07-layout-komponenten-anordnen.md | App/Pages/Layout/StageTab.swift | gemessen | P4 „Layout: Frames“: „`editorial` geöffnet über „Frame bearbeiten““ |

### Layout: Frames

| Funktion | QuartzControl | Handbuch | QuartzHub | Stand | Beleg |
|---|---|---|---|---|---|
| Frame wählen, Quartz-Standard ansehen (Maße aus der Sass des Projekts) | LayoutEditor/FrameBuilder.tsx, FramePreview.tsx | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | gemessen | P4 „Layout: Frames“: „Quartz' Standard in Desktop und Tablet“ |
| „Als eigenen Frame anpassen“ | LayoutEditor/FrameBuilder.tsx (`customizeStandard`) | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | gebaut | keine Messung in P4 |
| Neuer Frame (leer) speichern | LayoutEditor/FrameBuilder.tsx (`newFrame`) | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | gebaut | P4: „Nicht gemessen, weil es `quartz plugin add`/`remove` aufruft: ein neues Frame speichern“ |
| Frame duplizieren | LayoutEditor/FrameBuilder.tsx (`duplicate`) | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | gebaut | keine Messung in P4 |
| Frame löschen (fragt; Seitentypen fallen auf Standard) | LayoutEditor/FrameBuilder.tsx (`deleteConfirm`) | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | gebaut | P4: „Nicht gemessen …: … ein Frame löschen“ |
| Breakpoint wählen (Desktop/Tablet/Mobil, mit Pixelgrenze) | LayoutEditor/FrameBuilder.tsx | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | gemessen | P4: „Quartz' Standard in Desktop und Tablet“ |
| Maße je Breakpoint: Zeilen, Spalten, Größen, Abstände, Maximalbreite, Ausrichtung, Innenabstände, zurücksetzen | LayoutEditor/FrameBuilder.tsx | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | gebaut | keine Messung in P4 |
| „Auf Tablet/Mobil kopieren“ | LayoutEditor/FrameBuilder.tsx (`copyLayoutTo`) | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | gebaut | P4: „Ebenso nicht: … „Auf Tablet kopieren““ |
| Bereich mit der Maus aus dem Raster zurück in den Vorrat ziehen | LayoutEditor/FrameBuilder.tsx | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | gemessen | P4 „Layout: Frames“: „In den Vorrat gezogen, erscheint die Warnung „Auf Desktop ausgeblendet““ |
| Bereich mit der Maus aus dem Vorrat auf eine Zelle ziehen (Spanne gekürzt, angesagt) | LayoutEditor/FrameBuilder.tsx (`dropNarrowed`) | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | gebaut | P4 beschreibt es („Bereiche werden auf Zellen gezogen“), nicht unter „Gemessen“ |
| Spanne an der Kante ziehen, hält vor anderem Bereich | LayoutEditor/FrameBuilder.tsx | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | gemessen | P4: „`custom-8` an der rechten Kante von 6 auf 4 Spalten gezogen …; zurückgezogen bis in die rechte Seitenleiste hält er bei 6 an“ |
| Escape bricht ein laufendes Ziehen ab | LayoutEditor/FrameBuilder.tsx | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | anders | P4: „Anders als dort: Escape bricht ein laufendes Ziehen nicht ab (die Geste von SwiftUI lässt sich nicht von außen beenden)“ |
| Bereich mit der Tastatur platzieren oder verschieben | LayoutEditor/FrameBuilder.tsx (`placeArea`, `moveArea`, dnd-kit) | 4-gestaltung/06-layout-frames.md („Das geht auch mit der Tastatur“) | App/Pages/Layout/FramesTab.swift (`FrameAreaInspector`, `FramePlacing`) | gemessen | P5 „Frames mit der Tastatur“: im Inspektor „Verschieben nach“/„Platzieren auf“ mit Zeile, Spalte und Knopf (Entscheidung 4b statt dnd-kits Pfeilen); „right“ auf 2/3 abgelehnt, „right“ und „after-body“ getauscht, ein ausgeblendeter Bereich an seinem Platz wieder gezeigt (Dunkel 1400×860, Hell 1000×700) |
| Bereich im Inspektor: Name, Belegung, Eigener Bereich | LayoutEditor/FrameBuilder.tsx | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | gebaut | keine Messung in P4 |
| Zeilen-/Spalten-Spanne als Zahl, „Sichtbar auf“ | LayoutEditor/FrameBuilder.tsx | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | gebaut | keine Messung in P4 |
| „Aus Raster lösen“, „Bereich löschen“ (fragt), „+ Bereich hinzufügen“ | LayoutEditor/FrameBuilder.tsx | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | gebaut | keine Messung in P4 |
| Ablegen auf einen belegten Platz wird abgewiesen, mit Satz | LayoutEditor/FrameBuilder.tsx (`overlapError`, `dropRefused`) | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | gebaut | P4 misst nur das Anhalten der Kante („hält er bei 6 an“), nicht das Abweisen beim Ablegen |
| Warnungen unter dem Raster (Position ohne Bereich, nie sichtbar, Überlappung, außerhalb, doppelt) | LayoutEditor/FrameBuilder.tsx | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | gemessen | P4: „erscheint die Warnung „Auf Desktop ausgeblendet““ (eine Warnung gesehen) |
| Breakpoints (Tablet/Mobil) einstellen und speichern | LayoutEditor/FrameBreakpoints.tsx | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | gebaut | P4: „Ebenso nicht: die Breakpoint-Breiten speichern (schreibt jedes Frame neu)“ |
| Benannte Grid-Lines | LayoutEditor/FrameBuilder.tsx (`lineNames*`) | 4-gestaltung/06-layout-frames.md | App/Pages/Layout/FramesTab.swift | gebaut | P4: „Ebenso nicht: … benannte Grid-Lines“ |
| Hinweis „Dev-Server neu starten“ nach Speichern eines Frames | LayoutEditor/FrameBuilder.tsx | – | App/Pages/Layout/LayoutPage.swift (`devServer.staleHint`) | anders | P4: „Den Neustart-Hinweis … sagt `devServer.staleHint` nach jedem Speichern eines bestehenden Frames, ohne zu prüfen, ob einer läuft“ |

### Vorlagen

| Funktion | QuartzControl | Handbuch | QuartzHub | Stand | Beleg |
|---|---|---|---|---|---|
| Zwölf Bausteine mit Zahlen (Dateien, Größe), nur vorhandene | Templates.tsx (`templates.parts.*`) | 4-gestaltung/09-vorlagenpakete.md | App/Pages/Templates/TemplatesPage.swift, TemplateWords.swift | gemessen | P4 „Vorlagen“: „Die Bausteine zeigen dieselben Zahlen wie das Projekt (58 Plugins, 41 aktiv; 5 Frames; 67 Variablen)“ |
| Name und Beschreibung der Vorlage | Templates.tsx (`nameLabel`, `descriptionLabel`) | 4-gestaltung/09-vorlagenpakete.md | App/Pages/Templates/TemplatesPage.swift | gebaut | Export gemessen, Felder nicht einzeln genannt |
| Exportieren als `.qtpl` (Speicherfenster, genau eine Endung) | Templates.tsx (`exportButton`) | 4-gestaltung/09-vorlagenpakete.md | App/Pages/Templates/TemplatesModel.swift | gemessen | P4: „Export in den Scratchpad: 1,8 MB, zwölf Teile, Manifest „QuartzHub““; „Ohne Endung vorgeschlagen … entsteht genau eine“ |
| Übersetzungen: „Alle Texte“ / „Nur deine Änderungen“, Hinweis bei fehlender Basis | Templates.tsx (`scopeAll`, `scopeChanged`, `scopeNoChanges`) | 4-gestaltung/09-vorlagenpakete.md | App/Pages/Templates/TemplatesPage.swift | gebaut | keine Messung in P4 |
| Obergrenzen für Statische Dateien und Inhalt („keine Mediathek“) | Templates.tsx (Fehler aus `templatePackage`) | 4-gestaltung/09-vorlagenpakete.md | Packages/QuartzHubCore/…/Templates/TemplatePackage.swift (`main.templateStaticTooLarge`, `…ContentTooLarge`) | gebaut | keine Messung in P4; Kern: P3 „Vorlagen-Paket“ |
| „Vorlage wählen…“ (Datei öffnen) | Templates.tsx (`pickPackage`) | 4-gestaltung/09-vorlagenpakete.md | App/Pages/Templates/TemplatesModel.swift | gebaut | P4 nennt nur das Basis-Template als geladenes Paket |
| „Basis-Template“ laden, nur Gestaltungs-Bausteine vorgewählt | Templates.tsx (`pickBuiltin`, `baselineHint`) | 4-gestaltung/09-vorlagenpakete.md | App/Pages/Templates/TemplatesModel.swift | gemessen | P4: „Basis-Template geladen: angehakt sind nur die Gestaltungs-Bausteine, die Hinweise stehen darunter“ |
| Basis-Template: neuere Fassung von GitHub (einmal am Tag), Zeile sagt welche | Templates.tsx (`packageOrigin`) | 4-gestaltung/09-vorlagenpakete.md | App/Pages/Templates/TemplatesModel.swift | Netz | P4: „Nicht gemessen, weil es ins Netz geht: … das Basis-Template von GitHub“ |
| Bausteine beim Import an-/abwählen | Templates.tsx | 4-gestaltung/09-vorlagenpakete.md | App/Pages/Templates/TemplatesPage.swift | gemessen | P4: „Angewendet ohne Theme und Frames“ |
| „Vorlage gewinnt“ / „Projekt gewinnt“ | Templates.tsx (`strategy*`) | 4-gestaltung/09-vorlagenpakete.md | App/Pages/Templates/TemplatesPage.swift | gemessen | P4: „„Projekt gewinnt“ stellt Zusammenfassungen und Hinweis um“ |
| Vorschau (Plan) je Baustein: neu, ersetzt, übersprungen, „ändert nichts“ | Templates.tsx (`plan*`) | 4-gestaltung/09-vorlagenpakete.md | App/Pages/Templates/TemplateWords.swift | gemessen | P4: „neu geplant zeigt CSS-Variablen „ändert nichts““ |
| Plan-Hinweise: Plugins an/aus, Schriftdateien gehen, fehlende CSS-Variablen, Formulare | Templates.tsx (`planPluginsOn/Off`, `planFontsRemoved`, `planMissingVariables`, `planForms*`) | 4-gestaltung/09-vorlagenpakete.md | App/Pages/Templates/TemplateWords.swift, Packages/…/Templates/ImportWarnings.swift | gebaut | P4: „Gegen QuartzControls Funktionen gemessen sind sie nicht, nur am Bildschirm gegen den Plan gelesen“ |
| Alte und neue Aufteilung der Stylesheets beim Import | Templates.tsx (`planByPosition`, `planCustomScssMerged`) | 4-gestaltung/09-vorlagenpakete.md | App/Pages/Templates/TemplateWords.swift | gemessen | P4: „Angewendet …: ein Snapshot, ersetzte Stylesheets“; P4: „Auch nicht: ein Ordner im alten Format“ |
| Verknüpfter Content-Ordner: Inhalt wird übersprungen, mit Grund | Templates.tsx (`planContentIsSymlink`) | 4-gestaltung/09-vorlagenpakete.md | App/Pages/Templates/TemplateWords.swift | gebaut | keine Messung in P4 |
| Kein Baustein schreibt aus dem Projekt hinaus (Plan nennt Pfade) | Templates.tsx (`planOutside*`) | 4-gestaltung/09-vorlagenpakete.md | App/Pages/Templates/TemplateWords.swift | gebaut | keine Messung in P4; Kern: P3 „Vorlagen-Paket“ |
| Ungültige Frames im Paket, unbekannte Bausteine, altes Format | Templates.tsx (`planInvalidFrames`, `unknownParts`, `legacyBadge`) | 4-gestaltung/09-vorlagenpakete.md | App/Pages/Templates/TemplatesPage.swift | gebaut | keine Messung in P4 |
| Frage vor dem Anwenden, Snapshot vorher; „Abbrechen“ ändert nichts | Templates.tsx (`confirmImportAction`) | 4-gestaltung/09-vorlagenpakete.md | App/Pages/Templates/TemplatesModel.swift | gemessen | P4: „„Abbrechen“ in der Frage: kein Snapshot, Config und custom.scss byte-gleich“ |
| Anwenden ohne Netz-Bausteine (Farben, CSS, Variablen …), Ergebnis „Fertig: alles übernommen“ | Templates.tsx (`importing`) | 4-gestaltung/09-vorlagenpakete.md | App/Pages/Templates/TemplatesModel.swift | gemessen | P4: „Content unberührt, „Fertig: alles übernommen““ |
| Theme, Plugins, Frames anwenden (installiert, klont) | Templates.tsx (`willInstall`, `willClone`) | 4-gestaltung/09-vorlagenpakete.md | App/Pages/Templates/TemplatesModel.swift | Netz | P4: „Nicht gemessen, weil es ins Netz geht: Theme, Plugins und Frames anwenden (npm und `quartz plugin add`)“ |
| Laufender Import überlebt den Seitenwechsel | Templates.tsx (`useStickyState`) | – | App/Pages/Templates/TemplatesModel.swift (`shared`) | gebaut | P4: „Auch nicht: … ein Seitenwechsel mitten im Import“ |

### Veröffentlichen

| Funktion | QuartzControl | Handbuch | QuartzHub | Stand | Beleg |
|---|---|---|---|---|---|
| Liste der Ziele, Auswahl, Details im Inspektor | Publish/index.tsx | 6-veroeffentlichen/01-zugaenge-und-ziele.md | App/Pages/Publish/PublishPage.swift | gemessen | P4 „Veröffentlichen“: Messungen an Ordner-, Dokument-, Branch-Ziel |
| „+ Neues Ziel“ im Formular (Sheet), Art wählen | Publish/index.tsx (`newTarget`, `targetForm.*`) | 6-veroeffentlichen/01-zugaenge-und-ziele.md | App/Pages/Publish/TargetSheet.swift | gemessen | P4: „Ordner-Ziel im Scratchpad angelegt (Ausschluss `static/icon.png`)“ |
| Neues Ziel bleibt nach dem Speichern gewählt | Publish/index.tsx | – | App/Pages/Publish/TargetSheet.swift | gemessen | P4: „Gemessen, behoben: Nach „Speichern“ eines neuen Ziels setzte die gemerkte Auswahl … das alte Ziel zurück“ |
| Ziel bearbeiten | Publish/index.tsx (`common.edit`) | 6-veroeffentlichen/01-zugaenge-und-ziele.md | App/Pages/Publish/TargetSheet.swift | gebaut | keine Messung in P4 |
| Abbrechen im Formular fragt nur bei Änderungen | Publish/index.tsx (`confirmDiscardTargetDraft`) | – | App/Pages/Publish/TargetSheet.swift | gebaut | P4 beschreibt es, keine Messung |
| Ziel löschen (fragt, Zugang bleibt) | Publish/index.tsx (`confirmDeleteTarget`) | 6-veroeffentlichen/01-zugaenge-und-ziele.md | App/Pages/Publish/PublishPage.swift | gebaut | keine Messung in P4 |
| Zugang passend zur Art wählen, neuen Zugang im Formular anlegen | Publish/index.tsx (`newConnectionOfKind`, `connectionKindFixed`) | 6-veroeffentlichen/01-zugaenge-und-ziele.md | App/Pages/Publish/TargetSheet.swift, App/Components/ConnectionForm.swift | gemessen | P4: „Neuer SFTP-Zugang aus dem Zielformular: danach gewählt“ |
| „Zugänge verwalten“ öffnet die Einstellungen | Publish/index.tsx (`manageConnections`) | 6-veroeffentlichen/01-zugaenge-und-ziele.md | App/Pages/Publish/PublishPage.swift | gemessen | P4: „„Zugänge verwalten“ öffnet die Einstellungen auf „Zugänge““ |
| Zugang ohne Geheimnis: Warnung | Publish/index.tsx (`noSecretWarning`) | – | App/Pages/Publish/PublishPage.swift | gebaut | keine Messung in P4 |
| Ziel „Ordner“: veröffentlichen | Publish/index.tsx (`typeFolder`) | 6-veroeffentlichen/05-in-einen-ordner.md | App/Pages/Publish/PublishModel.swift | gemessen | P4: „im Ordner 473 Dateien ohne die beiden; Diff danach „Neu: 1““ |
| Ordner nicht da (Laufwerk getrennt): Lauf bricht ab | – (Kern `deploy/folder.ts`) | 6-veroeffentlichen/05-in-einen-ordner.md | Packages/…/Publishing/FolderAdapter.swift | gebaut | keine Messung in P4; Kern: P3 8a „`Deploy`, `DeployStaging`, `FolderAdapter` … 61 Schritte“ |
| Ziel SFTP | Publish/index.tsx (`transferSftp`, `sftpHint`) | 6-veroeffentlichen/04-auf-einen-webspace.md | App/Pages/Publish/TargetSheet.swift | Netz | P4: „Nicht gemessen, weil es ins Netz geht: SFTP, rsync, FTP …“; Kern: P3 8b (lokales sshd, debian-vm) |
| Ziel rsync | Publish/index.tsx (`transferRsync`, `rsyncHint`) | 6-veroeffentlichen/04-auf-einen-webspace.md | App/Pages/Publish/TargetSheet.swift | Netz | wie oben |
| rsync gesperrt mit Grund (kein Zugang, Passwort, Schlüsseltext, Host-Key, fehlt) | Publish/index.tsx (`rsyncBlocked.*`) | 6-veroeffentlichen/04-auf-einen-webspace.md | App/Pages/Publish/PublishWords.swift | gemessen | P4: „rsync gesperrt mit „braucht einen bestätigten Host-Key““ (ein Grund gesehen) |
| Ziel FTP/FTPS | Publish/index.tsx | 6-veroeffentlichen/04-auf-einen-webspace.md | App/Pages/Publish/TargetSheet.swift | Netz | P4: „Nicht gemessen …: … FTP“; Kern: P3 8c (vsftpd auf debian-vm) |
| Remote-Pfad prüfen (leer, ganzes Anmeldeverzeichnis mit Löschen, `..`, rsync-Zeichen/Leerraum) | Publish/index.tsx (`remotePathError.*`, `rsyncPathChar`, `rsyncPathSpace`) | 6-veroeffentlichen/04-auf-einen-webspace.md | App/Pages/Publish/TargetSheet.swift, PublishWords.swift | gebaut | keine Messung in P4; Kern: P3 8a „`RemotePath` … 437 Fälle“ |
| Host-Key beim ersten Verbinden bestätigen (Fingerprint-Dialog) | – (Hauptprozess) | 6-veroeffentlichen/01-zugaenge-und-ziele.md | App/Shell/AppDeploy.swift (`askHostKey`) | Netz | keine Messung in P4; Kern: P3 8b „Host-Keys: Vertrauen beim ersten Kontakt mit Fingerprint“ |
| Host-Key-Zustand am Zugang, „Host-Key vergessen“ (fragt) | Publish/index.tsx (`hostKeyPinned`, `forgetHostKey`) | 6-veroeffentlichen/01-zugaenge-und-ziele.md | App/Pages/Publish/PublishPage.swift | gebaut | keine Messung in P4 |
| Ziel „Git-Branch“ mit Anbieter (GitHub, Codeberg, GitLab) und Hinweis je Anbieter | Publish/index.tsx (`branchHint.*`) | 6-veroeffentlichen/02-github-pages.md | App/Pages/Publish/TargetSheet.swift, PublishWords.swift | gebaut | P4 misst nur das GitHub-Branch-Ziel ohne Token |
| Branch-Deploy: Frage „Branch wird ersetzt“, aktueller/Standard-Branch abgelehnt | Publish/index.tsx (`confirmDeployBranch`) | 6-veroeffentlichen/02-github-pages.md | App/Pages/Publish/PublishPage.swift | Netz | P4: „Nicht gemessen …: … Git-Branch-Push“; Kern: P3 8a „`GitBranchAdapter` gegen ein lokales Bare-Repo“ |
| Ziel „Webhook“ auslösen (Frage ohne Dateien, keine Dateiliste) | Publish/index.tsx (`webhookExplainer`, `confirmDeployWebhook`) | 6-veroeffentlichen/06-webhook.md | App/Pages/Publish/PublishPage.swift | Netz | P4: „Nicht gemessen …: … Webhook“ |
| Webhook: „keine URL hinterlegt“ | Publish/index.tsx (`webhookNoUrl`) | 6-veroeffentlichen/06-webhook.md | App/Pages/Publish/PublishWords.swift | gebaut | keine Messung in P4 |
| Ziel „Dokument“ (Zielordner, Buch, Formate; Buch fehlt, keine Bücher) | Publish/DocumentFields.tsx | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Publish/TargetSheet.swift | gemessen | P4: „Dokument-Ziel mit einem Buch über `animation/`“ |
| „Entfernte Dateien auch im Ziel löschen“ | Publish/index.tsx (`deleteRemoved`) | 6-veroeffentlichen/07-was-hochgeladen-wird.md | App/Pages/Publish/TargetSheet.swift | gebaut | keine Messung in P4 |
| „Nie veröffentlichen“ (Ausschlüsse je Ziel) | Publish/index.tsx (`excludes`) | 6-veroeffentlichen/07-was-hochgeladen-wird.md | App/Pages/Publish/TargetSheet.swift | gemessen | P4: „Ausschluss `static/icon.png` … im Ordner 473 Dateien ohne die beiden“ |
| Diff aktualisieren: Neu/Geändert/Entfernt, „Noch kein Diff“, „Keine Änderungen“ | Publish/index.tsx (`diffHeading`, `refreshDiff`, `noDiffYet`, `noChanges`) | 6-veroeffentlichen/07-was-hochgeladen-wird.md | App/Pages/Publish/PublishPage.swift | gemessen | P4: „Diff „Neu: 474““, „Diff danach „Neu: 1““ |
| Einzelne Dateien für einen Lauf abwählen | Publish/index.tsx (`toggleExclude`) | 6-veroeffentlichen/07-was-hochgeladen-wird.md | App/Pages/Publish/PublishPage.swift | gemessen | P4: „`404.html` für den Lauf abgewählt“ |
| „Alles neu hochladen“ (Manifest vergessen) | Publish/index.tsx (`uploadEverything`) | 6-veroeffentlichen/07-was-hochgeladen-wird.md | App/Pages/Publish/PublishPage.swift | gemessen | P4: „„Alles neu hochladen“ bietet wieder 474 an“ |
| „Jetzt bauen“ mit Ergebniszeile | Publish/index.tsx (`buildNow`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Publish/PublishPage.swift | gemessen | P4: „„Jetzt bauen“ sagt das Ergebnis mit Vorschau & Builds Zeile („Erfolgreich in 13,7s“)“ |
| Bestätigung mit Zahlen vor dem Hochladen | Publish/index.tsx (`confirmDeployConnection`) | 6-veroeffentlichen/07-was-hochgeladen-wird.md | App/Pages/Publish/PublishPage.swift | gemessen | P4: „Frage „473 Datei(en) werden hochgeladen““ |
| Fortschritt während des Laufs, Erfolg/Fehler danach | Publish/index.tsx (`progress`, `deploySuccess`, `deployFailed`) | 6-veroeffentlichen/07-was-hochgeladen-wird.md | App/Pages/Publish/PublishPage.swift, PublishModel.swift | gemessen | P4: „Gemessen, behoben: Bei 474 Dateien hing die Anzeige … Derselbe Lauf endet in der Anzeige nach 2 s“ |
| Nicht löschbare Datei auf dem Server mit Grund nennen | – (Kern) | 6-veroeffentlichen/07-was-hochgeladen-wird.md | Packages/…/Publishing/SSH | Netz | keine Messung in P4; Kern: P3 8b „die Fehler lauten „delete: Permission denied …““ |
| Warnung: Basis-URL steht auf localhost | Publish/index.tsx (`baseUrlWarning`) | 6-veroeffentlichen/01-zugaenge-und-ziele.md | App/Pages/Publish/PublishPage.swift | gebaut | keine Messung in P4 |
| Ausgabeordner (geteilt mit Vorschau & Build) | Publish/index.tsx (`outputDir`, `outputDirShared`) | 6-veroeffentlichen/07-was-hochgeladen-wird.md | App/Pages/Publish/PublishPage.swift | gebaut | keine Messung in P4 |
| GitHub Pages: Karte ohne Token | Publish/GithubPages.tsx | 6-veroeffentlichen/02-github-pages.md | App/Pages/Publish/GitHubPagesSection.swift | gemessen | P4: „GitHub-Branch-Ziel ohne Token: die Karte sagt es, ohne GitHub zu fragen“ |
| GitHub Pages: Zustand (veröffentlicht, wird gebaut, fehlgeschlagen, nie), neu laden | Publish/GithubPages.tsx (`pages.status.*`, `reload`) | 6-veroeffentlichen/02-github-pages.md | App/Pages/Publish/GitHubPagesSection.swift | Netz | P4: „Nicht gemessen …: … GitHub Pages mit Token“ |
| GitHub Pages einrichten (auf diesen Branch) | Publish/GithubPages.tsx (`pages.apply`, `notConfigured`) | 6-veroeffentlichen/02-github-pages.md | App/Pages/Publish/GitHubPagesSection.swift | Netz | wie oben |
| Eigene Domain (CNAME bei GitHub) | Publish/GithubPages.tsx (`pages.cname`) | 6-veroeffentlichen/02-github-pages.md | App/Pages/Publish/GitHubPagesSection.swift | Netz | wie oben |
| HTTPS erzwingen (gesperrt ohne Domain, „zu früh“-Satz) | Publish/GithubPages.tsx (`httpsEnforced`, `httpsOnlyWithDomain`) | 6-veroeffentlichen/02-github-pages.md | App/Pages/Publish/GitHubPagesSection.swift | Netz | wie oben |
| `origin` nicht auf github.com: Hinweis auf Git-Sync | Publish/GithubPages.tsx (`noGithubOrigin`) | 6-veroeffentlichen/02-github-pages.md | App/Pages/Publish/GitHubPagesSection.swift | gebaut | keine Messung in P4 |
| Repository auf GitHub anlegen (öffentlich/privat, als `origin`) | GitSync.tsx (liegt auf Git-Sync, nicht auf Veröffentlichen) | 6-veroeffentlichen/02-github-pages.md | App/Pages/GitSync/GitSyncPage.swift, GitSyncModel.swift (`createRepo`) | Netz | P4 „Git-Sync“: „Nicht gemessen: Push mit Token zu GitHub, „Repository anlegen“ (Netz)“ |

### Dokumente

| Funktion | QuartzControl | Handbuch | QuartzHub | Stand | Beleg |
|---|---|---|---|---|---|
| Liste der Bücher, erstes gewählt | Documents/index.tsx | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Documents/DocumentsPage.swift | gemessen | P4 „Dokumente“: „Testbuch über `animation/`“ |
| „Neues Buch“ | Documents/index.tsx (`newBook`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Documents/DocumentsModel.swift | gemessen | P4: „„Änderungen verwerfen“ legte `neues-buch.json` an“ |
| Neues Buch über die ganze Website, nach Ordnertiefe eingerückt | Documents/PageOrder.tsx | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Documents/DocumentsPage.swift | gemessen | P4: „Neues Buch über die ganze Website: 138 Seiten, eingerückt nach Ordnertiefe“ |
| Buch löschen (fragt) | Documents/index.tsx (`deleteBook`, `confirmDelete`) | – | App/Pages/Documents/DocumentsPage.swift | gebaut | keine Messung in P4 |
| Löschen eines anderen Buchs behält Änderungen am offenen | Documents/index.tsx (`reload(selectedId)`) | – | App/Pages/Documents/DocumentsModel.swift | anders | P4: „Abweichung: Löschen eines anderen Buchs behält die Änderungen am offenen. QuartzControl … verwarf sie still“ |
| Seiten der Navigation folgend (Quelle: Explorer, quartz-navigations …) | Documents/PageOrder.tsx (`followingHint`, `documents.source.*`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Documents/DocumentsPage.swift | gemessen | P4: „der Navigation folgend 6 Seiten“ |
| Seite abwählen (Haken) | Documents/PageOrder.tsx | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Documents/DocumentsPage.swift | gemessen | P4: „eine Seite abgewählt, ⌘S: … die Seite unter `excluded`“ |
| „Eigene Reihenfolge“ | Documents/PageOrder.tsx (`ownOrder`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Documents/DocumentsPage.swift | gemessen | P4: „„Eigene Reihenfolge“, Zwischenüberschrift „Anhang““ |
| Zwischenüberschrift hinzufügen | Documents/PageOrder.tsx (`addHeading`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Documents/DocumentsPage.swift | gemessen | P4: „die Datei hat `order` mit der Überschrift an fünfter Stelle“ |
| Umsortieren mit der Maus | Documents/PageOrder.tsx (dnd-kit) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Documents/DocumentsPage.swift | gemessen | P4: „Ziehen einer Zeile an die Spitze: nur von der freien Fläche der Zeile aus“ |
| Umsortieren mit Tastatur (Pfeilknöpfe je Zeile in QC) | Documents/PageOrder.tsx (`pluginsInstalled.moveUp`/`moveDown`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Documents/DocumentsPage.swift | anders | P4: „Umsortieren nach den drei Wegen (Ziehen, Anordnen ▸ ⌥⌘↑/⌥⌘↓, Kontextmenü und Bedienungshilfe-Aktion), statt QuartzControls Pfeilknöpfen je Zeile“; gemessen: „mit ⌥⌘↑ zwei Plätze hoch“ |
| „Wieder der Navigation folgen“ | Documents/PageOrder.tsx (`followNavigation`) | – | App/Pages/Documents/DocumentsPage.swift | gebaut | P4 nennt nur den abgeschnittenen Knopf („Follow the navigation again“), nicht die Wirkung |
| Neue Seiten der Website am Ende angefügt (Abzeichen, Abschnitt) | Documents/PageOrder.tsx (`appendedBadge`, `appendedHeading`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Documents/DocumentsPage.swift | gebaut | keine Messung in P4 |
| Seiten, die die Navigation nicht zeigt, aufnehmen | Documents/PageOrder.tsx (`hiddenHeading`, `takeIn`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Documents/DocumentsPage.swift | gebaut | P4: „Nicht gemessen: … „Aufnehmen“ einer Seite, die die Navigation nicht zeigt“ |
| Seite fehlt im Build: Abzeichen, gesperrt, entfernbar | Documents/PageOrder.tsx (`missingBadge`) | – | App/Pages/Documents/DocumentsPage.swift | gemessen | P4: „Eine Seite, die der Build nicht hat: „fehlt im Build“, Ankreuzfeld gesperrt, entfernbar“ |
| Titel, Untertitel, Autor | Documents/index.tsx (`fields.title`, `subtitle`, `author`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Documents/DocumentsPage.swift | gemessen | P4: „Untertitel geändert, „Neues Buch“: die Frage“ (Untertitel als Entwurf gesehen) |
| Ordner (Teil der Website), gelesen wenn das Tippen ruht | Documents/index.tsx (`fields.root`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Documents/DocumentsModel.swift | gemessen | P4: „„animation“ zügig getippt ergab eine Kopie; Gegenprobe, zwei Tasten mit 4 s Pause, ergab zwei“ |
| Sprache des Buchs (mehrsprachige Website) | Documents/index.tsx (`fields.language`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Documents/DocumentsPage.swift | gebaut | P4: „Nicht gemessen: die Sprachwahl (gui-test hat eine Sprache …)“ |
| Deckblatt-Bild | Documents/index.tsx (`fields.cover`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Documents/DocumentsPage.swift | gebaut | keine Messung in P4 |
| Papierformat, quer | Documents/index.tsx (`fields.pageSize`, `landscape`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Documents/DocumentsPage.swift | gebaut | keine Messung in P4; Kern: P3 9c „A5, A4 quer und Letter quer haben die richtige Seitengröße“ |
| Inhaltsverzeichnis, Rückverweise, Schlagwortregister an/aus | Documents/index.tsx (`fields.toc`, `backlinks`, `tagIndex`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Documents/DocumentsPage.swift | gebaut | keine Messung in P4 |
| Verweise nach außen (Link auf Website / Text) | Documents/index.tsx (`fields.outsideLinks`) | – | App/Pages/Documents/DocumentsPage.swift | gebaut | keine Messung in P4 |
| Speichern (⌘S) / Verwerfen in der Symbolleiste | Documents/index.tsx | – | App/Pages/Documents/DocumentsPage.swift | gemessen | P4: „⌘S: die Datei hat `order` …“ |
| Wechsel mit Änderungen fragt (anderes Buch, Neues Buch, andere Seite) | Documents/index.tsx | – | App/Pages/Documents/DocumentsPage.swift (`UnsavedGuard`) | gemessen | P4: „Wechsel zum anderen Buch mit Änderungen, „Abbrechen“: die Hervorhebung springt zurück, die Änderungen bleiben“ |
| Speicherfehler (z. B. schreibgeschützt) bleibt auf der Seite | Documents/index.tsx | – | App/Pages/Documents/DocumentsModel.swift | gemessen | P4: „`quartz-books/` schreibgeschützt (`chmod 555`), ⌘S: EACCES im Inspektor, die Seite bleibt ungespeichert“ |
| Feld über den Grenzen der Buchdatei | – (`bookSaveArgs`) | – | App/Pages/Documents/DocumentsModel.swift (`documents.saveInvalid`) | gebaut | P4: „Nicht gemessen: … `documents.saveInvalid` (die Felder müssten über 500 Zeichen lang sein)“ |
| Unlesbare Buchdatei: Warnung, Datei bleibt | Documents/index.tsx (`unreadable`) | – | App/Pages/Documents/DocumentsPage.swift | gemessen | P4: „Eine Datei mit Konfliktmarken (`kaputt.json`): die Warnung unter den Büchern, die Datei unverändert“ |
| Wege zu Vorschau & Build und zu Veröffentlichen, „So funktioniert's“ | Documents/index.tsx (`toBuild`, `toPublish`, `howItWorks`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Documents/DocumentsPage.swift | gebaut | keine Messung in P4 |

### Export

| Funktion | QuartzControl | Handbuch | QuartzHub | Stand | Beleg |
|---|---|---|---|---|---|
| Vorschau der Dateien, die der Export schreibt (Neu/Geändert) | Publish/index.tsx (Dokument-Ziel) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Publish/PublishPage.swift | gemessen | P4 „Veröffentlichen“: „Diff „Neu: 2“ … Diff danach „Geändert: 2““ |
| „Jetzt exportieren“: PDF | Publish/index.tsx (`exportButton`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Publish/PublishModel.swift | gemessen | P4: „Export ohne Netz in 3 s (PDF 34 Seiten, ePub 6 Kapitel)“ |
| „Jetzt exportieren“: ePub | Publish/index.tsx | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Publish/PublishModel.swift | gemessen | wie oben |
| „Jetzt exportieren“: eine HTML-Datei ohne Netz (Bilder als `data:`, Grenze 200 MiB) | Publish/index.tsx (`format.html`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Publish/PublishWords.swift | gebaut | App: P4 nennt nur PDF und ePub; Kern: P3 9c „HTML ohne Netz und ohne kaputte Bilder“, 9a „die Grenze an sieben Kanten“ |
| Bericht nach dem Export (Seiten, Herkunft der Reihenfolge, Ersetztes) | Publish/index.tsx (`exportSuccess`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Publish/PublishModel.swift | gebaut | App: kein wörtlicher Beleg; Kern: P3 9c „der Bericht in QuartzControls Sätzen“ |
| Export abbrechen | Publish/index.tsx (`cancelExport`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Publish/PublishPage.swift | gebaut | P4: „Auch nicht: „Export abbrechen“ (der Export dauerte 3 s)“; Kern: P3 9c „abgebrochen, nichts geschrieben“ |
| Ablehnungen vor dem Export (Zielordner im Build/Projekt, Buch fehlt, Ordner darüber fehlt) | – (`deploy/document.ts`) | 6-veroeffentlichen/08-als-dokument.md | Packages/…/Publishing/DocumentAdapter.swift | gebaut | keine Messung in P4; Kern: P3 9c „Der Zieltyp „Dokument“ … die Ablehnungen vor dem Export“ |
| PDF: Inhaltsverzeichnis mit Seitenzahlen | – (Hauptprozess `writePdf.ts`) | 6-veroeffentlichen/08-als-dokument.md | Packages/…/Export/PDFWrite.swift | gebaut | Kern: P3 9c „Seitenzahlen in Inhaltsverzeichnis und Register in zwei Durchgängen“ |
| PDF: Lesezeichen aus den Überschriften | – | 6-veroeffentlichen/08-als-dokument.md | Packages/…/Export/PDFWrite.swift | gebaut | Kern: P3 9c „Lesezeichen je Ebene gleich, Example 9/46/252/260/16/7“ |
| PDF: Fußzeile mit Titel und Seitenzahl | – | – | Packages/…/Export/PDFWrite.swift | gebaut | Kern: P3 9c „Eine eigene `PDFPage`-Klasse zeichnet Titel links und „Seite / Seiten“ rechts“ |
| PDF: Sprache und „Titel im Fenster“ | – | – | Packages/…/Export/PDFWrite.swift | gebaut | Kern: P3 9c „`/Lang` und „Titel im Fenster“ … Gelesen mit Core Graphics, pdf-lib und `pdfinfo`“ |
| PDF getaggt (Tagged PDF) | – | – | – | anders | P3 9c: „Nicht getaggt. Entschieden mit dem Plan (Tagged PDF verzichtbar).“ |
| Seitenumbruch des PDFs (WebKit statt Chromium) | – | – | Packages/…/Export/PDFWrite.swift | anders | P3 9c: „Seiten: Example 298 statt 279, gui-test 348 statt 323 (WebKit bricht früher um, wie im Spike)“ |
| ePub 3 mit Navigation, Fußnoten im Reader, epubcheck sauber | – (`writeEpub.ts`) | 6-veroeffentlichen/08-als-dokument.md | Packages/…/Export/BookPack.swift (`EpubPack`) | gebaut | Kern: P3 9c „epubcheck 0 Fehler und 0 Warnungen“, 9a „8 Bücher als ePub Byte für Byte“ |
| Formeln (KaTeX) und Diagramme (Mermaid) im PDF wie auf der Website, in ePub/HTML als Bild | – (`pageScripts.ts`, `drawPictures`) | 6-veroeffentlichen/08-als-dokument.md | Packages/…/Export/BookContentPrep.swift, ExportWindow.swift | Netz | App ohne Netz exportiert „ohne das, was die Seiten von außen laden (`outside: false`)“ (P4); Kern: P3 9b über `cdn-build.mjs` ohne Netz, 9c „mit Netz für Mermaid und KaTeX“ gegen QuartzControl |
| Diagramme hell, auch wenn macOS dunkel ist | – | – | Packages/…/Export/ExportWindow.swift | anders | P3 9c: „QuartzHubs Fenster ist immer hell (`NSAppearance.aqua`)“ — Befund in QuartzControl: „9 der 16 Diagramme dunkel“ |
| Rückverweise am Seitenende, Schlagwortregister (im PDF mit Seitenzahlen) | – (`exportService.ts`) | 6-veroeffentlichen/08-als-dokument.md | Packages/…/Export/DocumentHTML.swift (`ExportExtras`), ExportBook.swift | gebaut | Kern: P3 9a „13 Läufe mit Rückverweisen und Register in drei Sprachen“ |
| Deckblatt mit Titelbild und Datum | – (`documentHtml.ts`) | 6-veroeffentlichen/08-als-dokument.md | Packages/…/Export/DocumentHTML.swift | gebaut | Kern: P3 9a „16 Titelbilder aus Dateien“, 9c „Das Datum auf dem Deckblatt ist ICUs Muster für `yMMMMd` … gegen Node für neun Sprachen“ |
| Ersatzsatz mit Adresse für Formular, Video, Leinwand | – (`collect.ts`) | 6-veroeffentlichen/08-als-dokument.md | Packages/…/Export/ExportCollect.swift | gebaut | Kern: P3 9b „Einsammeln … die Ersatztexte in der Sprache des Dokuments“ |
| Keine fremden Ressourcen beim Export (gesperrt außer CDN) | – (`exportWindow.ts`) | – | Packages/…/Export/ExportWindow.swift | gebaut | Kern: P3 9b „QuartzControls Regel als `WKContentRuleList` … Gemessen gegen einen zweiten Server“ |
| „Dokumente mit hochladen“ (Website-Ziel nimmt Dokument-Ziele nach `downloads/` mit) | Publish/DocumentFields.tsx (`withDocuments`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Publish/TargetSheet.swift | gebaut | keine Messung in P4 |
| Link zum Kopieren je Dokumentdatei | Publish/DocumentFields.tsx (`copyLink`) | 6-veroeffentlichen/08-als-dokument.md | App/Pages/Publish/TargetSheet.swift | gebaut | keine Messung in P4 |
| Hinweis: Dokument älter als der Build | – (`staging.ts`) | 6-veroeffentlichen/08-als-dokument.md | Packages/…/Publishing/DeployStaging.swift (`main.stagingDocumentOlder`) | gebaut | keine Messung in P4; Kern: P3 8a `DeployStaging` |
| Alte Export-Kopien beim Start aufräumen | – (Hauptprozess, `sweepExportTempDirs`) | – | App/Shell/ServerLifecycle.swift (`SiteCopy.sweep`) | gemessen | 2026-11-09, gestartet an einem Wegwerf-Profil: vorher lagen `quartzhub-export-…` und vier `…-rules-…` vom 2026-11-08 nach Dutzenden Starts noch da; nach dem Start waren alle sechs weg, zwei jüngere als eine Stunde (eine davon angelegt als Gegenprobe) blieben |
| Alte Relay-Ordner beim Start aufräumen, offene beim Beenden löschen | – (Hauptprozess, `sweepRelayTempDirs`, `will-quit`) | – | App/Shell/ServerLifecycle.swift (`FormsRelay.sweepTempDirs`, `removeOpenTempDirs`) | gemessen | Start: 2026-11-09, ein `qh-relay-…` mit Datum vom Vortag war danach weg. Löschen der offenen beim Beenden nicht gemessen (braucht einen laufenden Relay-Lauf, Netz) |
| Laufende Exporte beim Beenden abbrechen | – | – | App/Shell/ServerLifecycle.swift (`ExportBook.cancelAll`) | gebaut | Beenden über das Menü ohne laufenden Export geprüft (beendet sauber); mit laufendem Export nicht gemessen |
