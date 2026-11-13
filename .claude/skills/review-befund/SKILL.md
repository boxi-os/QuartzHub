---
name: review-befund
description: Arbeitet eine Review-Liste von QuartzHub ab (docs/REVIEW-<datum>.md): ein Befund pro Durchgang mit Vorher-Messung, Fix, Bau, qh-check, Tests, eigenem Commit, Nebenbei-Liste und Eintrag in docs/reviews.md. Verwenden, wenn der Nutzer sagt, ein Review oder einen Befund abzuarbeiten.
---

# Einen Review-Befund abarbeiten

Übernommen aus QuartzControl (`.claude/skills/review-befund`), angepasst an Swift. Die Regeln
stehen in `docs/conventions.md`; bei einer Regel mit **(QC)** die Begründung in
`../QuartzControl/docs/decisions/conventions-full.md` lesen, **bevor** an der Stelle geändert wird.

## Vor der Liste: einordnen

Betrifft die Liste das Veröffentlichen oder das Relay, bekommt jeder Befund seine Stufe aus der
Support-Matrix (bis QuartzHub eine eigene hat: `../QuartzControl/docs/support-matrix.md`):

- **Hoch und Mittel** werden abgearbeitet, wenn die Stufe es verlangt: unterstützt immer, geduldet
  nur bei Datenverlust, fremden Dateien oder einem offenen Geheimnis.
- **Niedrig und Nebenbei** werden mit Stufe und Einschätzung als Liste vorgelegt; der Nutzer wählt
  aus. Nicht ungefragt abarbeiten.
- Vor einem Fix fragen, zu welcher Klasse der Fall gehört, und die Nachbarfälle mitmessen.

## Je Befund, einer nach dem anderen

1. **Nachstellen.** Erst messen, wie er wirklich auftritt: an der gebauten App (Skill `run-app`),
   per Swift-Test oder am echten Projekt (nur Kopien von `gui-test`/`Example`, nie
   ein privates Projekt des Nutzers).
2. **Fix.** Minimal, im Stil der Datei. Neue Texte mit `node scripts/strings.mjs add` in beiden
   Sprachen. Berührt der Fix eine Funktion, die ein früherer Befund dieser Liste geändert hat:
   dessen Messung wiederholen.
3. **Gegenprobe.** Dieselbe Messung nach dem Fix, dazu der Fall, in dem der Weg *nicht* still werden
   darf. Möglichst als Test (Swift Testing im Kern, XCUITest in der App).
4. **Prüfen:** `scripts/xcodegen.sh`, Bau, `swift run --package-path Packages/QuartzHubCore qh-check i18n`,
   `xcodebuild … test` (Rauchtest und Kerntests), dazu die `qh-check`-Prüfung des Bereichs.
5. **Commit**, Nachricht englisch: erste Zeile sagt, was jetzt stimmt; Rumpf beginnt mit
   `Review <datum>, Befund <n>:` bzw. `…, nebenbei:`, sagt Ursache, Messung vorher/nachher und
   womit gemessen. Endet mit der Co-Authored-By-Zeile.
6. **Nebenbei** Aufgefallenes nur sammeln.

## Am Ende der Liste

- Neue dauerhafte Regel: kurz nach `docs/conventions.md`, Messung nach `docs/decisions/`.
- Chronik ans Ende von `docs/reviews.md` (anlegen, wenn es sie noch nicht gibt); Stand in
  `CLAUDE.md` nachziehen.
- Nebenbei-Liste dem Nutzer nennen. Nicht pushen, nicht taggen, ohne dass er es sagt.
