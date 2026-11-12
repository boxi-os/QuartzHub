# Gleichstand mit QuartzControl 1.3

Was QuartzControl 1.3 einem Nutzer bietet, Zeile für Zeile, und ob QuartzHub es hat. Grundlage
sind QuartzControls Routen (`src/routes/`), seine 180 IPC-Kanäle (`shared/ipc-contract.ts`) und das
Handbuch (`QuartzControl-Handbuch`, Kapitel 1–8). Das erste Release kommt erst, wenn keine Zeile mehr
auf `gebaut` oder `fehlt` steht (docs/plan.md, Phase 5).

Die Teile:

- [Einrichtung](gleichstand/einrichtung.md): Fenster „Projekte“, Einstellungen, Hülle und Menü,
  Übersicht, Vorschau & Build, Konfiguration
- [Plugins und Wartung](gleichstand/plugins-wartung.md): Plugins (alle Reiter), Updates, Snapshots,
  Git-Sync
- [Gestaltung und Veröffentlichen](gleichstand/gestaltung-veroeffentlichen.md): Stile, Layout,
  Vorlagen, Veröffentlichen, Dokumente, Export
- [Kanäle](gleichstand/kanaele.md): jeder IPC-Kanal mit seinem Gegenstück in Kern und App

## Was die Wörter heißen

- `gemessen`: an der gebauten App ausprobiert, von Hand oder im UI-Test, und eine Doku sagt es.
  Der Beleg nennt den Abschnitt und zitiert ihn. Nur das gilt als abgehakt.
- `gebaut`: im Code der App vorhanden, aber ohne Beleg einer Messung an der App. Ein Golden-Test
  des Kerns ist ein Beleg für den Kern, nicht für die App.
- `anders`: bewusst anders gelöst; der Beleg nennt die Entscheidung.
- `Netz`: braucht einen Lauf gegen GitHub, npm, einen Server oder Google Fonts und ist nicht
  gemessen. Jeder Lauf wird einzeln erfragt (Nutzer, 2026-11-09), nie gegen die echten Ziele der
  gui-test-Kopie.
- `fehlt`: in QuartzHub nicht vorhanden.

Eine Zeile, die nur ein UI-Test prüft, ohne dass eine Doku es als Messung nennt, steht vorerst auf
`gebaut` mit dem Vermerk „UI-Test …“. Prüft der Test die Funktion selbst, wird sie beim Durchgang
zu `gemessen` mit dem Testnamen als Beleg.

## Stand am 2026-11-09 (Rohfassung)

Die Teile wurden aus den Quellen zusammengestellt (nur lesend), die Stände aus den
Entscheidungs-Dokus übernommen; gemessen wurde dafür nichts Neues. Die Zahlen sind aus den Teilen
gezählt, zuletzt am 2026-11-11 nach den letzten gebaut-Zeilen (decisions/phase-5-gleichstand.md, „Die letzten gebaut-Zeilen“). Die letzte `gebaut`-Zeile, die abgelehnte Schlüsselbund-Abfrage bei der Übernahme, ist beim echten ersten Start des Nutzers gemessen (2026-11-11); keine Zeile steht mehr auf `gebaut`.

| Teil | gemessen | gebaut | anders | Netz | fehlt | Zeilen |
|---|---|---|---|---|---|---|
| Einrichtung | 194 | 0 | 18 | 0 | 4 | 216 |
| Plugins und Wartung | 254 | 0 | 7 | 0 | 0 | 261 |
| Gestaltung und Veröffentlichen | 234 | 0 | 9 | 0 | 0 | 243 |
| **Summe** | **682** | **0** | **34** | **0** | **4** | **720** |

Die Kanäle: 159 mit Gegenstück in Kern und App, 18 bewusst anders (Fortschritt und Protokoll über
Rückrufe und Streams, Dialoge über AppKit, Menü über SwiftUI), einer nur im Kern (`books:read`, den
auch QuartzControls Oberfläche nie aufruft), zwei fehlen (`appUpdate:check`, `dialog:openHandbook`;
beide stehen unten).

## Was fehlt

Die `fehlt`-Zeilen der Teile, zusammengefasst. Die ersten zwei sind seit Phase 4 für Phase 5
vorgesehen; die übrigen sind beim Zusammenstellen aufgefallen.

1. **Handbuch-Links:** „Im Handbuch nachlesen“ im Kopf jeder Seite, auf der Startseite und
   Hilfe ▸ Handbuch. Kommt mit dem Handbuch (Phase 5).
2. **Hinweis auf eine neuere Fassung** der App (`appUpdate:check`). Braucht einen Release-Kanal.
3. ~~Das Hilfe-Menü~~: gebaut am 2026-11-09 wie in QuartzControl (Nutzer: alles); Datenordner und
   Lizenzen gemessen, die drei Web-Links nur im Menü gelesen. Rückmeldung kommt erst an, wenn das
   Repo öffentlich ist.
4. ~~Darstellung ▸ Zoom, Neu laden, Entwicklerwerkzeuge~~: entfallen (Nutzer, 2026-11-09).
5. ~~Band „Zugangsdaten nicht sicher speicherbar“~~: kein Fall auf macOS, QuartzControl zeigt es nur
   unter Linux (gelesen am 2026-11-09; die Zeile steht jetzt auf `anders`).
6. ~~Der Fehler beim Leeren des Theme-Doku-Caches~~: kein Fall, QuartzControls Dienst scheitert nie
   (gelesen am 2026-11-09; die Zeile steht jetzt auf `anders`).
7. ~~Projektbild und Pfad im Kopf der Seitenleiste~~: gebaut und gemessen am 2026-11-09.
8. ~~Die Rollposition je Seite~~: gebaut und gemessen am 2026-11-09.
9. ~~Ein Eintrag unter „Handlungsbedarf“ führt auf den richtigen Reiter~~: geschlossen und gemessen
   am 2026-11-09, dazu „Konfiguration ›“ unter „Die Seite“.
10. ~~Rückweg-Links~~ (`markReturn`): gebaut und gemessen am 2026-11-09, für alle Verweise
    zwischen Seiten und Reitern wie in QuartzControl; von der Übersicht aus bleibt es beim Verzicht.
11. ~~Formulare: „Keine passende Seite“~~: geschlossen und gemessen am 2026-11-09.
12. ~~Frames: einen Bereich mit der Tastatur setzen oder verschieben~~: gebaut und gemessen am
    2026-11-09, im Inspektor nach der Entscheidung 4b („Verschieben nach“, „Platzieren auf“).
13. ~~Aufräumen beim Start und Abbrechen beim Beenden~~: angeschlossen am 2026-11-09
    (`App/Shell/ServerLifecycle.swift`); das Aufräumen beim Start ist gemessen.

## Wie weiter

1. Die Lücken schließen, je eine mit eigenem Commit; für 3 und 4 entscheidet der Nutzer, was
   davon QuartzHub braucht.
2. Die `gebaut`-Zeilen Seite für Seite an einer Kopie von gui-test messen und mit Beleg auf
   `gemessen` stellen; was dabei scheitert, wird ein Befund. Fertig: Fenster „Projekte“
   (2026-11-09, zwei Befunde behoben), Fenster „Einstellungen“ (2026-11-09, drei Befunde behoben),
   Hülle und Menü (2026-11-09, ohne Befund), Übersicht (2026-11-09, ein Befund behoben),
   Vorschau & Build (2026-11-09, zwei Befunde behoben), Konfiguration (2026-11-09, zwei Befunde
   behoben), Plugins ▸ Installiert (2026-11-09, sechs Befunde behoben), Plugins ▸ Navigationen mit
   der Vorschau (2026-11-09, vier Befunde behoben), Plugins ▸ Zusätzliche Inhalte (2026-11-09,
   sieben Befunde behoben), Plugins ▸ Mehrsprachigkeit (2026-11-09, ein Befund behoben),
   Plugins ▸ Formulare (2026-11-09, zehn Befunde behoben), Updates, Snapshots und Git-Sync
   (2026-11-09, ohne Befund), Layout (2026-11-10, fünf Befunde behoben),
   Stile (2026-11-10, vier Befunde behoben, einer davon ein Absturz), Vorlagen (2026-11-10, ohne Befund),
   Veröffentlichen ohne Netz (2026-11-10, zwei Befunde behoben), Dokumente und Export
   (2026-11-10, drei Befunde behoben, einer davon ein Absturz), Export ohne Netz
   (2026-11-10, zwei Befunde behoben), Frames anlegen und löschen mit `quartz plugin add`
   (2026-11-10, ohne Befund), Stile mit Google Fonts (2026-11-10, ohne Befund), Themes und Presets mit `npm install` (2026-11-10, ein Befund behoben: c45b5e8), SFTP, rsync und FTP gegen debian-vm (2026-11-10, ein Befund behoben: 06be3b7), Grenzfälle der Vorlagen mit gebauten Paketen (2026-11-10, ohne Befund), Grenzfälle der Stile (2026-11-10, ohne Befund), Dokumente mit Navigation und Sprache (2026-11-10, ohne Befund), git in den Einstellungen (2026-11-10, ohne Befund), Plugins mit leerer Liste und Schema-Bedingungen (2026-11-10, ohne Befund), der leere Unterschied der Snapshots (2026-11-10, ohne Befund), Relay mit erfundenen Zielen und das Entfernen mit Relay-Geheimnissen (2026-11-10, ein Befund behoben: 6afee3c), nicht gebaute Seiten der Formulare (2026-11-10, ohne Befund).
3. Die `Netz`-Zeilen gesammelt, je Lauf mit Freigabe. Freigegeben am 2026-11-10: erst die, die nur lesen oder holen, dann das Relay auf debian-vm; was bei GitHub schreibt, nur mit einem Test-Repo. Gemessen: Update-Prüfung (2026-11-10, ohne Befund), Marktplatz (2026-11-10, ohne Befund), Installieren und Wiederherstellen (2026-11-10, ohne Befund), Anlegen und Duplizieren (2026-11-10, ohne Befund), Vorlagen (2026-11-10, ein Befund behoben: 44cbfa3), Projektbild im Kopfbereich (2026-11-10, ohne Befund), Export mit KaTeX und Mermaid vom CDN (2026-11-10, ohne Befund), Relay auf debian-vm (2026-11-10, ohne Befund), Branch-Deploy und Webhook ohne Netz gegen ein lokales Bare-Repo und einen lokalen HTTPS-Server (2026-11-11, ein Befund behoben). GitHub mit Test-Repo: Token, Push, Branch-Deploy, Pages, Repository anlegen, eigene Domain und HTTPS (2026-11-11, ein Befund behoben: ein Deploy verwarf die eigene Domain). Echte Updates an einer Kopie von gui-test (2026-11-11, ohne Befund, ein geerbter Nebenbefund). Warnungen nach dem Anlegen (2026-11-11, ohne Befund, zwei geerbte Nebenbefunde). Band „QuartzControl läuft“ (2026-11-11, zwei Befunde behoben). Plugin von GitHub (2026-11-11, ohne Befund). Relay auf qh-test.borkel.net bei all-inkl (2026-11-11, fünf Befunde behoben).
