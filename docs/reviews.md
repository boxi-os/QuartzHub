# Reviews

Chronik der Review-Runden an QuartzHub: welcher Bericht, was daraus wurde, mit Commit. Abgearbeitet
mit dem Skill `review-befund`, ein Befund pro Commit; die Messungen stehen im Commit und in
`decisions/phase-5-gleichstand.md` unter „Review <datum>: die Befunde“.

## 2026-11-11: Daten, Geheimnisse, Server, Paket

Auftrag `REVIEW-2026-11-11-auftrag.md`, Bericht `REVIEW-2026-11-11.md` (Stand `ddcb802`): 1 Hoch,
2 Mittel, 6 Niedrig, 11 nebenbei. Der Nutzer wählte alle Befunde aus; die Nebenbei-Punkte sind
nicht abgearbeitet.

| Befund | Was jetzt stimmt | Commit |
| --- | --- | --- |
| H1 | Ein Restore lässt `content/` in Ruhe, solange der Store es heute ausnimmt; der Vergleich zeigt es nicht als „seitdem entfernt“ | `36f01de` |
| M2 | Ein Ziel aus der Datei wird vor Vorschau und Lauf geprüft (leerer Pfad, „..“, ganze Wurzel, Ordnerpfad) | `20beaf6` |
| N2 | Der Branch eines Ziels wird nie eine Option für git (`isBranchName` beim Lesen, `-- refs/heads/…`) | `c5aefb1` |
| M1 | Das Ziel eines geparkten Vault-Links steht in `.quartz-gui/content-link.json` und wird beim Öffnen zurückgelegt; Beenden fragt bei laufendem Update, Restore oder Deploy | `0a86f81` |
| N1 | Host und SSH-Benutzer, die mit „-“ beginnen oder Leerraum haben, erreichen weder ssh noch rsync; der Host steht hinter `--` | `6bb9111` |
| N3 | Eine unlesbare Datei lässt die Übernahme offen (zweiter Lauf führt zusammen); fehlende Geheimnisse lassen sich unter Einstellungen ▸ Zugänge nachholen | `b9c4f28` |
| N4 | Die vier Profil- und Fensterschalter kommen nur aus den Startargumenten; kein Rückfall auf das Repo des Bau-Rechners im Release | `9c6e890` |
| N5 | Verweigerte Löschungen stehen im Titel des Laufs | `28e2b61` |
| N6 | Der Ordner mit einem gespeicherten SSH-Schlüssel geht beim Beenden, Reste eines Absturzes beim nächsten Start | `7bac569` |

Nicht umgesetzt aus den Vorschlägen: `npm install` aus dem Parken des Kern-Updates herausziehen
(M1; Umbau von `CoreUpdate.merge` mit 64 Golden-Schritten) und ein eigener ssh-agent statt einer
Schlüsseldatei (N6; ändert jeden Login-Weg). H1, M1 und M2 stecken auch in QuartzControl 1.3; ob sie
dort auf `fix/1.3.x` kommen, entscheidet der Nutzer.
