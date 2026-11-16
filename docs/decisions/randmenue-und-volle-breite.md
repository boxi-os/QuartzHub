# Randmenü und Bereiche über die volle Fensterbreite (2026-11-16)

Anlass: quartz-navigations bekommt die Variante `rail` (Branch `feat/rail-variant`, noch nicht
veröffentlicht), ein Menü am Fensterrand. Der Nutzer wollte sie in QuartzHub und im Basis-Template,
dazu Kopf- und Fußzeile, die wie das Menü über die ganze Fensterbreite laufen. Entscheidungen des
Nutzers vom 2026-11-16: volle Breite als Frame-Einstellung, im Template bleibt das Akkordeon das
Menü und die Rail bekommt nur Styles.

## Die Rail in QuartzHub

- **Name**: „Randmenü“ / „Edge menu“, im Plugin-Schema derselbe deutsche Name (vorher
  „Nexus-Leiste“, ein Produktname). Standardplatz `header`, wie das README des Plugins rät: eine
  Stelle, die nicht scrollt; das Panel beginnt unter der Sticky-Leiste.
- **Regeln** aus `render.tsx` und `options.ts` des Branches gelesen, nicht aus QuartzControl (das die
  Rail nie kannte): Ordner klappen an Ort und Stelle wie beim Akkordeon (`variantCollapsible`), also
  wirken `chevrons`, `folderClick`, `exclusive`, `folderDefaultState`, `expandActive`,
  `persistState`; `align`, `trigger` und die Objekte der anderen Varianten nicht. `mobile:
  accordion` und `offcanvas` setzt das Plugin bei der Rail auf `same`; QuartzHub zeigt das am Feld
  `mobile` als „wirkt nicht bei der Variante „Randmenü““. Gegenprobe: `inPlace` ohne `.rail` ließ
  `railRulesFromThePluginCode` an fünf Stellen scheitern.
- **QuartzControls Golden Cases** decken weiter seine zehn Varianten ab: `noEffectReason` und
  `root` nehmen die Menge der Varianten als Parameter (`among`), der Test übergibt
  `Variant.quartzControl`.
- **Die Kacheln folgen dem installierten Plugin** (`NavigationVariants.offered`): die Rail nur, wenn
  das Schema des Projekts `rail` im Enum von `variant` hat. Ein Plugin vor 0.5 machte aus `rail`
  stillschweigend `tree`.
- **Offen bis zum Release des Plugins**: `readAgainst` bleibt `0.4.2`. Mit dem Release `readAgainst`
  auf die neue Fassung setzen; die Regeln der zehn alten Varianten sind dort unverändert.

## Bereiche über die volle Fensterbreite

**Format**: ein Bereich in `frame.json` bekommt `fullWidth: true` (`GridFrameArea`, neben `slot` und
`group`). Das ist QuartzHubs erste Erweiterung des Frame-Formats; QuartzControl 1.3 prüfte Bereiche
mit einem zod-Objekt, das unbekannte Schlüssel durchlässt, und schrieb das Objekt ganz zurück, die
Datei bleibt also für 1.3 lesbar (es ignoriert den Schlüssel). `FrameDefinitionCheck` verlangt
einen Wahrheitswert.

**Wirkung** (`GridFrameCss`): Füllt ein solcher Bereich in einem Breakpoint ganze Zeilen (ab der
ersten Spalte über alle), bekommt das Raster dort links und rechts eine Spur mehr. Ihre Breite ist
der Innenabstand des Frames plus der Raum, den `maxWidth` und `align` lassen; die inneren Spuren
behalten so genau ihre Breite. Der volle Bereich spannt über alle Spuren.

Die Spaltenlücke steht auch zwischen Randspur und erster innerer Spur. Wären die Randspuren um sie
kleiner, ginge das nur, solange die Lücke kleiner ist als der Innenabstand; im Basis-Template ist es
umgekehrt (Lücke 4rem/3rem, Abstand 20px), der Inhalt wäre auf dem Tablet um 28px je Seite
eingerückt worden. Deshalb reicht das Raster um eine Lücke je Seite über die Seite hinaus
(`width: calc(100% + 2 * gap)`, `margin-inline: calc(-1 * gap)`), der volle Bereich nimmt sie mit
`margin-inline: gap` zurück, und `#quartz-body` schneidet den Rest mit `overflow-x: clip` ab (kein
Scroll-Container, eine Sticky-Kopfzeile bleibt sticky). `#quartz-body` verliert dabei Quartz' eigenen
Innenabstand unterhalb der Desktop-Breite, sonst endeten die vollen Bereiche 1rem vor dem Rand; der
Innenabstand des Frames ist dann der einzige.

Ohne `fullWidth` bleibt die Ausgabe Byte für Byte die von QuartzControl (`LayoutFramesTests`
unverändert grün). Füllt der Bereich in einem Breakpoint keine ganze Zeile, gilt dort das alte Raster
und sein Rand ist `0`; jeder Wert wird in jedem Breakpoint geschrieben, weil die schmaleren
Breakpoints dieselben Selektoren überschreiben.

**Messung** in WebKit (WKWebView, Testframe 4 Spalten, Lücke 4rem/3rem/1rem, Abstand 20px, Desktop
1440px zentriert, Inhalt in Spalte 2–3):

| Fenster | Kopf | Inhalt | erwartet (altes Raster) | `scrollWidth` |
|---|---|---|---|---|
| 1600 | 0–1600 | 466–1134 | 466–1134 | 1600 |
| 1300 | 0–1300 | 351–949 | 351–949 | 1300 |
| 1000 (Tablet) | 0–1000 | 20–980 | 20–980 (ohne Quartz' 1rem) | 1000 |
| 600 (Mobil, Kopf halbe Zeile) | 20–148 | 20–580 | altes Raster | 600 |

## Rail und volle Kopfzeile

Schiebt eine Rail die Seite (`content: push`), rückt das Plugin `<body>` um
`--quartz-nav-rail-offset-left|right` ein; eine volle Kopfzeile würde mitrücken, obwohl das Panel
unter ihr beginnt. Das README des Plugins zeigt jetzt die zwei Regeln, mit denen sie stehen bleibt;
das Basis-Template bringt sie mit.
