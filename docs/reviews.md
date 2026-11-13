# Reviews

Chronik der Review-Runden an QuartzHub: welcher Bericht, was daraus wurde, mit Commit. Abgearbeitet
mit dem Skill `review-befund`, ein Befund pro Commit; die Messungen stehen im Commit und in
`decisions/phase-5-gleichstand.md` unter „Review <datum>: die Befunde“.

## 2026-11-11: Daten, Geheimnisse, Server, Paket

Auftrag `REVIEW-2026-11-11-auftrag.md`, Bericht `REVIEW-2026-11-11.md` (Stand `ddcb802`): 1 Hoch,
2 Mittel, 6 Niedrig, 11 nebenbei. Der Nutzer wählte alle Befunde aus, danach auch alle
Nebenbei-Punkte.

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

Die Nebenbei-Punkte (Messungen unter „Review 2026-11-11: die Nebenbei-Punkte“):

| Punkt | Was jetzt stimmt | Commit |
| --- | --- | --- |
| 1 | Manifeste, Marker und `snapshot-settings.json` werden ersetzt, nicht an Ort und Stelle überschrieben | `b0ac09f` |
| 2 | Scheitern `commit-tree` oder `update-ref`, scheitert der Snapshot, und der Schreiber hält an | `7f6bb0c` |
| 3 | Eine `relay-secrets.json`, die kein Objekt ist, verdeckt die Altlasten nicht mehr | `c4a2584` |
| 4 | Der Übernahme-Dialog verspricht nur noch unveränderte Dateien; „Erlauben“ genügt | `5259071` |
| 5 | Branch-Ziel und Snapshot-Store haben für jeden git-Aufruf eine Frist; `npm install` nach einem Restore auch | `af8b801` |
| 6 | Ein gescheiterter Helferbau sagt beim Paketbau, warum | `dccfab4` |
| 7 | Der Branch-Deploy lässt keine Hooks des Projekts laufen | `b803db1` |
| 8 | Die Webhook-Schwärzung findet den Token kodiert und dekodiert | `61a4f17` |
| 9 | Ein Link im Build ist mit und ohne Dokumente derselbe | `1bf6889` |
| 10 | Unverändert: das Umbiegen der Frame-Pfade ist eine Reparatur ohne Snapshot, wie in QuartzControl | — |
| 11 | Test- und Messstarts lassen die Fensterrahmen des Nutzers für seinen nächsten Start da | `5c1c4ce` |

Nicht umgesetzt: ein Abbrechen-Knopf für einen laufenden Deploy (Punkt 5; die Seite hat nur einen
für den Export).

## Zweite Runde: was seit der ersten dazukam (2026-11-11)

Auftrag `REVIEW-2026-11-11-2-auftrag.md`, Bericht `REVIEW-2026-11-11-2.md` (Code `c19628d..eed348b`,
Stand `301d5c1`): 0 Hoch, 2 Mittel, 6 Niedrig, 18 nebenbei. Der Nutzer wählte alle Befunde und alle
Nebenbei-Punkte; M1 entschied er statt eines Umbaus.

| Befund | Was jetzt stimmt | Commit |
| --- | --- | --- |
| M1 | Entschieden: Ein Projekt mit eigenen Frames baut QuartzControl nach QuartzHub nicht mehr; das Koexistenz-Band sagt es, solange QuartzControl läuft | `68b13c4` |
| M2 | Aus einer Vorschau gehen nur http(s)-Adressen an das System; eigene Ordner öffnen im Finder, ohne ein `*.app` zu starten | `d06c0e2` |
| N1 | Eine Vorlage nimmt `layout.sidebars` nicht weg; „docs“ mit dem Basis-Template bleibt „docs“ | `562546f` |
| N2 | Eine Prüfung, die nicht lief, und Befunde ohne Plugin stehen auf der Seite Plugins; nach einem Kern-Update kein „warnt nur“ über Fehlern | `de65b2b` |
| N3 | Eine alte `CNAME` bleibt beim Branch-Deploy nur, wenn GitHubs Pages-Einstellungen dieselbe Domain nennen | `afca86c` |
| N4 | Nur Zeilenumbruch und NUL im Passwort werden abgelehnt; Tab und Emoji-Folgen gehen | `626cf46` |
| N5 | Der Reiter Formulare fragt den Schlüsselbund nur, ob das Relay-Geheimnis da ist | `4239f5e` |
| N6 | „gewollt“ gilt nur, solange alle Einträge eines Plugins dieselbe Quelle haben | `50e4fcf` |

Die Nebenbei-Punkte:

| Punkt | Was jetzt stimmt | Commit |
| --- | --- | --- |
| 1 | Speichern lässt Kommentare, Flow-Stil und Anker in unveränderten Blöcken stehen (`links`, `drafts`, Seitentypen) | `e3dcb40` |
| 2 | Nur festgehalten: QuartzControl 1.3 kann die `sidebars` eines Seitentyps löschen (eingestellt, kein Fix) | — |
| 3 | Was `-QHOffline` nicht vom Netz nimmt, steht in `Offline.swift` und `decisions/` | `f353ad9` |
| 4 | Doctors Befunde zu eigenen Frames stehen auf der Seite Plugins, mit QuartzHubs Hinweis | `a76ab18` |
| 5 | Alle `QH…`-Schalter kommen aus den Startargumenten; `LaunchSwitchHygieneTests` hält es | `54f7027` |
| 6 | `order: null` eines alten Eintrags gilt wie in Quartz | `33c9582` |
| 7 | Ein kurzes FTP-Passwort schwärzt nur nach „PASS “, nicht jedes gleiche Wort | `d4fe7fc` |
| 8 | Übernommene Passwörter verlieren den Zeilenumbruch am Ende wie gespeicherte | `99bd6b8` |
| 9 | Umbenennen bei fehlenden Relay-Geheimnissen schreibt nichts | `93bfa75` |
| 10 | Der veraltete Kommentar in `GitBranchAdapter.swift` ist mit N3 neu geschrieben | `afca86c` |
| 11 | Eine `cname` in Kleinbuchstaben wird im Lauf genannt | `277165c` |
| 12 | Ein Token mit Zeilenumbruch heißt Token | `4f50884` |
| 13 | Eine https-Adresse, die auf http:// umleitet, bekommt ihren eigenen Satz | `4c557f4` |
| 14 | „Erstellen“ wartet auf das Basis-Template und sagt, dass es lädt | `fcd059d` |
| 15 | Der Download der Vorlage bricht beim Laden an 25 MiB ab | `9282a15` |
| 16 | Elf weitere Tests beenden nur noch, was ihnen gehört | `1b6b4f7` |
| 17 | Nur festgehalten: Nehmen beide Apps gleichzeitig Snapshots, kann QuartzControls Commit QuartzHubs älteren Index enthalten (nicht neu durch `c114f6c`, mit der alten Sperre genauso) | — |
| 18 | Nur festgehalten: `lsof -Fn` maskiert Zeilenumbruch, Tab und Backslash im Pfad; ein Server in so einem Ordner gehört keinem Projekt, nie einem falschen | — |

Nicht an der App gesehen, weil es einen echten Lauf gebraucht hätte: das Band zu M1 (QuartzControl
läuft), N3 (schreibt bei GitHub), N5 (Systemabfrage des echten Schlüsselbunds), der Satz auf der
Seite Updates zu N2 (echtes Kern-Update), der Ladezustand zu 14 (zu kurz ohne langsames Netz).
Unterwegs aufgefallen, nicht geändert: Eine Vorlage aus einem 5.1-Projekt bringt `sidebars` auch in
ein 5.0-Projekt; unter `Packages/QuartzHubCore/file:/…` liegen 128 versionierte Dateien, ein
Testrückstand vom 2026-11-06 (eine URL als Pfad).

## 2026-11-13: Befunde aus dem Handbuch

Bericht `REVIEW-2026-11-13-handbuch.md` (Stand `6bfb1fa`, kein Auftrag: gesammelt beim Schreiben des
Handbuchs): 2 Hoch, 4 Mittel, 13 Niedrig, rund 100 nebenbei; mit den Büchern kamen M5, N14 und N15 dazu. Der
Nutzer wählte zuerst H1 und H2, dann M5, N14, N15 und die übrigen.

| Befund | Was jetzt stimmt | Commit |
| --- | --- | --- |
| H1 | „Auch den Projekt-Commit zurücksetzen“ lässt einen Content-Ordner, den der Store ausnimmt, wie er ist (gemischter Reset, außerhalb von `content/` wie `--hard`) | `6094280` |
| H2 | Speichern oder Löschen eines Frames behält ungespeicherte Änderungen der Bühne (`PluginListMerge`, Dreiwege-Abgleich) | `f8dd175` |
| M5 | Im PDF bleibt „ff“ und „ffi“ als Text lesbar: Druck ohne gewöhnliche Ligaturen (`DocumentHTML.webKitPrintRules`); vorher 200 Wörter unlesbar, danach keins | `f64d2d9` |
| M1 | Ungespeicherte Übersetzungen fragen vor einer anderen Sprache, beim Schließen und Beenden; Verwerfen verwirft wirklich | `5cacfa8` |
| M2 | Beim ersten Einrichten von GitHub Pages geht die eingetragene Domain mit (PUT nach dem POST); nicht gegen GitHub selbst gemessen | `5f92c12` |
| N14 | ➕ Neues Buch fragt zuerst nach dem Titel und zeigt den Dateinamen, der daraus wird | `731bc55` |
| N15 | Die Format-Schalter des Ziels „Dokument“ sind drei Elemente mit eigener Kennung; ein Klick schaltet das richtige | `83e2271` |

Im Handbuch nachgezogen: 5.4 und 7.3 (Vault `d6c3234`). Zu N14: 6.6 (Vault, mit Schritt 7). Nicht gemessen zu N15: was VoiceOver
vorliest; System Events zeigt bei keiner SwiftUI-Checkbox der App einen Titel.
