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
- **Mit dem Release 0.5.0** (2026-11-16) liest QuartzHub gegen 0.5.0 (`readAgainst`). Ein Projekt
  mit 0.4.x bekommt im Inspektor den Hinweis, dass QuartzHub gegen eine andere Fassung gelesen hat;
  die Regeln seiner zehn Varianten sind dieselben, die Rail-Kachel fehlt dort (Schema).
- **0.5.1** (2026-11-16, nach dem Ausprobieren): Trennlinien (`navDivider`, `dividers`), `rail.startPinned`
  und das Einklappen nach dem Lösen der Pinnadel. QuartzHub liest gegen 0.5.1; `dividers` steht im Schritt
  „Beschriftung und Icons“ und wirkt bei `select` und `pager` nicht.
- **0.6.0** (2026-11-17): eigene SVG-Icons, `svg:<pfad>` und `svg-mono:<pfad>` als Wert von `navIcon` und
  `nodeIcons` (Plan und Messung in quartz-navigations `docs/plan-svg-icons.md`). Keine Option und keine
  Regel einer Variante hat sich geändert, nur drei Beschreibungen im Schema; QuartzHub liest gegen 0.6.0,
  der Wert bleibt ein freies Textfeld.
- **0.6.1** (2026-11-17): Lucide 1.74.0, die früheren Namen umbenannter Icons zeichnen weiter. Was QuartzHub
  liest (`render.tsx`, `options.ts`, Schema), ist gleich: 0.6.1 steht in `sameCode`, gelesen wird weiter gegen 0.6.0.
- **0.6.2** (2026-11-21): Mit `rest: icons` und `content: push` rückte ein per Hover (`hoverContent: overlay`)
  oder angeheftet (`pinContent: overlay`) übergelegtes Menü die Seite um die Breite der Leiste zurück; jetzt
  bleibt sie neben der Leiste. Neu ist `--quartz-nav-rail-gap`, ein Abstand zwischen schiebender Rail und Seite,
  der in `--quartz-nav-rail-offset-*` mitzählt (die volle Kopfzeile reicht damit weiter bis an den Rand).
  Geändert sind nur die Client-Skripte und das Stylesheet: 0.6.2 steht in `sameCode`.
- **0.6.3** (2026-11-21): Mit `content: push` glitt die Seite bei jedem Seitenwechsel vom Fensterrand herein
  (gui-test, Chrome: 88 px → 0 → 88 px in 200 ms je Klick). Das Aufräumen der Rail nahm den Abstand sofort weg,
  Quartz liest das Layout vor dem Aufbau der nächsten Seite, die Transition startete bei 0. Jetzt gleicht das
  Aufräumen `<html>` erst nach dem Aufbau ab. Geändert ist nur das Client-Skript: 0.6.3 steht in `sameCode`.
- **0.7.0** (2026-11-21): `quartz.cssVariables` im Manifest, die 64 Variablen mit Vorgabe, Gruppe und
  Beschreibung auf Englisch und Deutsch (`docs/plan-plugin-variablen.md`, A1). `src` ist unverändert, das
  Manifest sonst gleich: 0.7.0 steht in `sameCode`. quartz-forms 0.7.0 ebenso (10 Variablen).

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
seinem Rand zurück, und das Fenster schneidet den Rest ab (`html:has(<Frame>) { overflow-x: clip }`;
an der Wurzel wird daraus das `hidden` des Viewports, das Quartz' `base.scss` ohnehin setzt, eine
Sticky-Kopfzeile bleibt sticky). Zuerst stand der Clip an `#quartz-body`: Dann schnitt er die
Kopfzeile ab, sobald eine Rail `<body>` einrückte und die Kopfzeile über `--qgframe-bleed-left`
wieder bis an den Rand reichte (an der Website gemessen: Kopfzeile 0–1600, sichtbar erst ab 320). `#quartz-body` verliert dabei Quartz' eigenen
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

**Innenabstand des Inhalts** (2026-11-16, nach dem ersten Ausprobieren in gui-test): Ein voller
Bereich hatte keinen Innenabstand; ohne eine Regel der Site (das Basis-Template hat
`--tpl-header-inline-pad`) standen die Bedienelemente der Kopfzeile direkt an den Fensterrändern.
Seitdem bekommt sein Inhalt den Innenabstand des Frames, wo er ganze Zeilen füllt, sonst `0`:
`:where(.qgframe-area-<name>) { padding-inline: … }`. `:where()` hat keine Spezifität, denn das
`<style>` des Frames steht später im Dokument und schlüge sonst jede gleich starke Regel der Site.
Gemessen mit dem Testframe oben in WebKit: Inhalt bei 1600/1300/1000 px 20 px vom Rand; eine Regel
`.qgframe-area-header { padding-inline: 50px }` *vor* dem Frame-CSS gewinnt (50 px), ohne `:where()`
verlor sie (20 px).

## Rail und volle Kopfzeile

Schiebt eine Rail die Seite (`content: push`), rückt das Plugin `<body>` um
`--quartz-nav-rail-offset-left|right` ein; eine volle Kopfzeile würde mitrücken, obwohl das Panel
unter ihr beginnt. Der Rand eines vollen Bereichs ist deshalb
`calc(<Lücke> - var(--qgframe-bleed-left, 0px))` (rechts entsprechend, physische Seiten wie bei der
Rail): Eine Site zieht ihn über diese zwei Variablen weiter hinaus, ohne die Lücke des Frames zu
kennen. Das Frame-CSS kennt das Plugin nicht; das Basis-Template verbindet beides
(`--qgframe-bleed-left: var(--quartz-nav-rail-offset-left)` an der Kopfzeile, nicht am Fuß, den das
Panel bis zum Fensterboden überdeckt). Das README des Plugins zeigt dasselbe für Sites ohne Frame.

## Das Basis-Template

- `parts/frames.json`: in allen vier Frames `header` und `footer` mit `fullWidth: true`.
- Fünf neue Tokens in `parts/cssVariables.json` (Reiter „Variablen“): `tpl-header-inline-pad`,
  `tpl-footer-inline-pad` (Abstand des Inhalts zu den Fensterrändern), `tpl-rail-width`,
  `tpl-rail-open-width`, `tpl-rail-bg`. Eine Inhaltsbreite für Kopf und Fuß gibt es nicht: In einem
  Rasterbereich bezieht sich `%` auf den Bereich, der hier um zwei Spaltenlücken breiter ist als die
  Seite, eine zentrierte Breite wäre um die Lücke verschoben.
- Die 100vmax-Hintergründe von Kopf und Fuß bleiben: Sie decken den oberen bzw. unteren Innenabstand
  des Frames und halten den Hintergrund randlos, wenn jemand „Volle Fensterbreite“ wieder ausschaltet.
  Ebenso bleibt der mobile Rand `-20px` der Kopfzeile; als voller Bereich gewinnt der Rand des Frames
  (sein `<style>` steht später im Dokument).
- Die Marke bekommt `margin-inline-end: auto`: Mit einem Rail-Button davor hat die Kopfzeile drei
  Teile, und `space-between` setzte Logo und Titel sonst in die Mitte (in der Aufnahme gesehen).
- `plugin-navigations.scss` gestaltet die Rail (Tokens, Button in Zielgröße, Monogramme, Scrim);
  das Akkordeon bleibt das Menü des Templates.

**Die Gruppe „brand“ ist eine Flex-Reihe** (2026-11-16): Sie war ein Raster mit drei benannten
Zellen (Marke, Name, Kapitel), damit das Kapitel zuerst kürzt. Ein Menü-Button in der Gruppe bekam
keine Zelle und stand deshalb immer hinter dem Titel, gleich mit welcher Priorität; den Kapitel-Eintrag
hatte keine Vorlage mehr. Jetzt ordnet die Priorität wie in jeder Gruppe, und nur die Namen dürfen
schmaler werden (`min-width: 0` nur an ihnen), Marke und Menü-Button behalten ihre Breite. Unter
900 px hält die App-Leiste vorn nur noch Platz für einen Auslöser frei, der über ihr liegt (Burger
mit `mobile: offcanvas`, Explorer), sonst stand er leer vor dem Rail-Button. An gui-test gemessen
(WebKit, Dev-Server): Burger, Marke, Titel bei 1600 px auf 24/66/106, bei 700 px auf 12/54/94
(vorher 56); mit einem eingefügten Burger kommen die 56 px zurück. Das Template selbst ist nicht an
einer gebauten Website angesehen, seine Regeln sind dieselben.

Nachgeholt am 2026-11-17 (Review 2026-11-17, N6): Example trägt alle 13 Stylesheets der Grundvorlage
byte-gleich. Eine Kopie mit QuartzHub gebaut (die Frames neu geschrieben, mit dem Innenabstand voller
Bereiche aus `f17fcd2`) und in WebKit gemessen: bei 1600 px Marke, Titel, Abschnitt auf 24/62/173 px, die
Bedienelemente enden 24 px vor dem Rand, der Innenabstand ist der der Vorlage (`--tpl-header-inline-pad`,
24 px), die `:where()`-Regel des Frames tritt also zurück; bei 700 px Burger, Marke, Titel auf 8/56/94 px.
Das Raster ragt um die Spaltenlücke über das Fenster (1664 bei 1600 px), das ist der Rand der vollen Breite;
`html` hat `overflow-x: clip`, seitlich verschieben lässt sich nichts (`scrollX` bleibt 0).

**An der Website angesehen** (Kopie der Website-Vorlage mit dem Plugin aus dem Branch, WebKit, Dev-Server):
1600 px Rail `rest: icons`, `content: push` offen: Kopfzeile 0–1600, Seite um 320 px eingerückt, Panel
darunter; 1100 px hell mit offenem Menü über der Seite; 700 px Kopf und Fuß 0–700, kein seitliches
Scrollen. Mein Messfenster spielt keine CSS-Übergänge ab, das offene Panel blieb dort ohne
`transition: none` auf Leistenbreite stehen; im Browser nicht nachgeprüft.
