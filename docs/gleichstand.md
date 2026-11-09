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
Entscheidungs-Dokus übernommen; gemessen wurde dafür nichts Neues.

| Teil | gemessen | gebaut | anders | Netz | fehlt | Zeilen |
|---|---|---|---|---|---|---|
| Einrichtung | 56 | 122 | 14 | 8 | 16 | 216 |
| Plugins und Wartung | 106 | 133 | 4 | 15 | 3 | 261 |
| Gestaltung und Veröffentlichen | 91 | 118 | 10 | 20 | 2 | 241 |
| **Summe** | **253** | **373** | **28** | **43** | **21** | **718** |

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
3. **Das Hilfe-Menü:** Rückmeldung senden, Quartz-Dokumentation, Plugin-Katalog, Datenordner
   öffnen, Lizenzen. Die Lizenztexte reisen im Paket mit, die App zeigt aber keinen Weg dorthin.
4. **Darstellung ▸ Zoom, Neu laden, Entwicklerwerkzeuge:** Die letzten zwei gehören zu Electron;
   eine Entscheidung dagegen steht noch nirgends.
5. **Band „Zugangsdaten nicht sicher speicherbar“** im Fenster „Projekte“. Eine Ablehnung des
   Schlüsselbunds meldet erst der Zugriff.
6. **Der Fehler beim Leeren des Theme-Doku-Caches** wird verworfen (`SettingsWindow.swift`).
7. **Projektbild und Pfad im Kopf der Seitenleiste.**
8. **Die Rollposition je Seite** (QuartzControls `useRestoreScroll`).
9. **Ein Eintrag unter „Handlungsbedarf“ führt auf den richtigen Reiter:** `ProjectAttention.Issue.tab`
   liest die App nicht, obwohl Konfiguration und Stile inzwischen Reiter haben. Die Phase-4-Doku
   hatte das für später vorgesehen.
10. **Rückweg-Links** (`markReturn`): von den Plugin-Editoren zurück nach „Alle Optionen“ bzw. zur
    Bühne, von Snapshots zurück zu Updates. Für die Übersicht ist der Verzicht entschieden, für
    diese nicht.
11. **Formulare: „Keine passende Seite“** in den Vorschlägen der Zielseite.
12. **Frames: einen Bereich mit der Tastatur setzen oder verschieben.** Die Entscheidung 4b
    („die Tastatur verschiebt über den Inspektor“) ist auf der Bühne umgesetzt, im Frame-Editor
    nicht.
13. **Aufräumen beim Start und Abbrechen beim Beenden:** `SiteCopy.sweep`,
    `FormsRelay.sweepTempDirs` und `ExportBook.cancelAll()` gibt es im Kern, die App ruft keinen
    davon auf. Daher die liegengebliebenen `quartzhub-export-…`-Kopien im Temp-Ordner.

## Wie weiter

1. Die Lücken schließen, je eine mit eigenem Commit; für 3 und 4 entscheidet der Nutzer, was
   davon QuartzHub braucht.
2. Die `gebaut`-Zeilen Seite für Seite an einer Kopie von gui-test messen und mit Beleg auf
   `gemessen` stellen; was dabei scheitert, wird ein Befund.
3. Die `Netz`-Zeilen gesammelt, je Lauf mit Freigabe.
