# Plan: Zeilen im Frame-Editor (2026-11-22)

Anlass: In 00_test war auf Mobile im Frame „index“ der Bereich left herausgenommen, und die übrigen
Bereiche waren von Hand je eine Zeile hochgezogen. Die Höhe `0` der alten left-Zeile blieb an Zeile 2
stehen und traf before-body: Titel und Tags lagen unter dem Akkordeon der rechten Spalte. Dazu der
Wunsch des Nutzers: Bereiche umsortieren wie eine Liste, ohne dass erst ein Feld frei sein muss.
Entschieden (Nutzer, 2026-11-22): **Einfügen zwischen Zeilen** und **Tauschen**.

## Heute

- Der Editor kennt nur Bereiche: ablegen auf eine freie Zelle, zurück in die Ablage, Ränder ziehen,
  im Inspektor „Verschieben nach“. Eine besetzte Zelle lehnt ab („überlappt“).
- Zeilen gibt es nur als Zahl im Inspektor (Zeilen 8); weniger schneidet hinten ab. Ihre Höhen
  (`rowSizes`, eine Liste mit Lücken) und Linien-Namen (`rowLineNames`, ein Objekt Linie → Namen,
  `rows + 1` Linien) hängen am Index. Wer Bereiche hochzieht, nimmt die Höhen nicht mit.
- Eine leere Zeile kostet trotzdem einen Zeilenabstand, und ihre Höhe bleibt, wo sie war.

## Was kommt

Alles im Kern (`FrameEditing`), mit Tests; das Board und der Inspektor rufen es nur auf.

1. **Zeile einfügen** (`insertingRow(def, bp, before: r)`): `rows + 1`; Bereiche ab Zeile `r`
   rücken eins nach unten, ein Bereich, der über die Linie reicht, wird eine Zeile länger (rechts auf
   Desktop); in `rowSizes` kommt an Stelle `r` eine Lücke (= `auto`), die Linien-Namen ab Linie `r`
   rücken mit. Ausgeblendete Platzierungen (`hidden`) rücken mit wie sichtbare.
2. **Zeile entfernen** (`removingRow(def, bp, r)`), nur wenn kein sichtbarer Bereich allein in ihr
   liegt: Bereiche darunter rücken hoch, einer, der über sie reicht, wird eine Zeile kürzer; ihre Höhe
   und ihre untere Linie gehen mit. Eine ausgeblendete Platzierung nur in dieser Zeile bleibt an der
   Stelle stehen, auf `rows` begrenzt.
3. **In eine neue Zeile ziehen** (`movingToNewRow(def, bp, id, before: r)`): Zeile vor `r`
   einfügen, der Bereich kommt hinein (seine Spalte und Breite bleiben, die Höhe wird eine Zeile;
   gesagt, wenn er dabei kürzer wird, wie heute „Spanne gekürzt“). Wird seine alte Zeile dadurch leer,
   wird sie entfernt. Das ist das Umsortieren: before-body unter right ziehen, right rutscht hoch.
4. **Tauschen** (`swapping(def, bp, a, b)`): zwei Bereiche tauschen ihre Plätze, jeder behält seine
   Spannen; erlaubt, wenn danach beide im Raster liegen und nichts überlappt (gleich große tauschen
   immer).
5. **Leere Zeilen** als Hinweis unter dem Board, wie die anderen Warnungen: „Zeile 2 ist leer und
   hält trotzdem einen Zeilenabstand“, mit **Leere Zeilen entfernen** (Punkt 2 für jede). Nicht von
   selbst beim Zurücklegen in die Ablage: Eine leere Zeile mit fester Höhe kann ein Abstand sein.

## Bedienung

- **Ziehen auf dem Board**: Nahe der Linie zwischen zwei Zeilen (im Zeilenabstand oder im oberen
  bzw. unteren Viertel einer Zeile) zeigt eine Linie über die ganze Breite, wo die neue Zeile entsteht
  (Punkt 3). Über einem anderen Bereich: Tauschen, der Geist zeigt den Platz, Rot wenn es nicht geht.
  Über einer freien Zelle wie heute. Auch aus der Ablage heraus.
- **Tastatur und Bedienungshilfen** (der Inspektor übernimmt im Raster die Rolle von „Nach oben“/„Nach
  unten“, docs/conventions.md): beim gewählten Bereich **Eine Zeile höher** und **Eine Zeile tiefer**
  (Punkt 3 vor die Zeile darüber bzw. nach der darunter); „Verschieben nach“ auf einen besetzten Platz
  tauscht, statt abzulehnen. Jede Bewegung wird angesagt.

## Ränder (Testfälle)

- 00_test, index, Mobile: left in die Ablage, „Leere Zeilen entfernen“ → 7 Zeilen, die `0` ist weg,
  before-body hat `auto`. Gegenprobe im Browser bei 500 px: Titel frei.
- gui-test, index, Desktop: before-body unter page-body ziehen → right (Zeilen 2–5) bleibt lang
  genug, nichts überlappt, keine leere Zeile bleibt.
- `rowSizes` kürzer als `rows`, mit `null`-Lücken; `rowLineNames` mit Namen an der ersten und letzten
  Linie; ein Bereich mit `rowSpan` über die Einfügestelle; Einfügen vor Zeile 1 und nach der letzten.
- Tauschen verschieden großer Bereiche, die nicht passen → abgelehnt, nichts geändert.
- Das Format bleibt das von QuartzControl 1.3 (nur Zahlen und Listen ändern sich).

## Offen danach

- Das Basis-Template legt auf Mobile eine left-Zeile der Höhe `0` an und holt den Abstand mit
  `margin-block-start: -2rem` an before-body zurück (`custom/layout.scss`). Ohne left-Zeile rückt
  before-body damit zu dicht an den Kopf. Am Template prüfen, ob left dort auf Mobile etwas trägt.

## Umgesetzt (2026-11-22)

Kern in `Layout/FrameRows.swift` (`FrameRowsTests`), Oberfläche in `App/Pages/Layout/FramesTab.swift`.
An einer Kopie von 00_test angesehen:

- index, Mobile: left in die Ablage → „Zeile 2 ist leer …“ → **Leere Zeile entfernen** → before-body
  direkt unter dem Kopf; right in die Lücke unter header gezogen (blaue Linie) → right Zeile 2,
  before-body rückt nach; „Eine Zeile tiefer“ setzt es zurück; before-body auf left gezogen → getauscht.
- index, Desktop: before-body zwischen page-body und custom-8 gezogen → right bleibt über die Zeilen 2–5.
- before-body nach dem Tausch in left's Zeile der Höhe 0 → „before-body liegt in einer Zeile der Höhe 0“.
  left selbst in dieser Zeile sagt nichts: die Warnung gilt nur Bereichen, deren Position etwas trägt
  (die leere left-Zeile des Templates ist Absicht).
- Abweichend vom Plan: Was eine verlassene Zeile ist, entscheidet `removingRow` („liegt kein anderer
  Bereich allein darin“), nicht `emptyRows`: Sonst bliebe auf Desktop neben right eine leere Zeile stehen.
- Nebenbei gefunden: Ein Ablegen im Abstand zwischen zwei Spalten traf keine Zelle und tat nichts
  (schon vorher so; beim Tauschen über einem breiten Bereich fast immer). Jetzt zählt die nächste Zelle.
