# Phase 2: Formate und Übernahme

Gebaut und gemessen ab dem 2026-11-06. Was hier steht, war eine Entscheidung oder anders als
erwartet. Die Formate selbst stehen in [`../formats.md`](../formats.md).

### JSON wie Node, nicht wie Foundation

QuartzControl schreibt jede JSON-Datei mit `JSON.stringify(wert, null, 2)` aus dem Objekt, das es
gelesen hat. Damit bleiben drei Dinge erhalten, die Foundation nicht kann:

- **Die Form:** `"key": value` (Foundations `.prettyPrinted` schreibt `"key" : value`), `/` nicht
  maskiert, kein Zeilenende, Zahlen nach ECMAScripts `Number::toString` (`100`, nicht `100.0`;
  `1e-7`, nicht `1e-07`).
- **Die Reihenfolge der Schlüssel:** Einfügereihenfolge, nur Array-Indizes (`"0"`, `"42"`) kommen
  zuerst und aufsteigend, wie in jedem JavaScript-Objekt. `JSONEncoder` kennt nur zufällig oder
  alphabetisch.
- **Unbekannte Schlüssel:** Ein `Codable`-Struct verliert, was es nicht deklariert.

Deshalb gibt es `JSONValue` mit `JSONObject` (Reihenfolge wie JavaScript), `JSJSON.parse` und
`JSJSON.stringify`, und die Modelle sind Sichten auf einen `JSONValue` statt `Codable`-Structs: Sie
lesen ihre Felder daraus und schreiben Änderungen dorthin zurück.

- **Gemessen gegen Node 24.22.2** (`JSJSONTests`, Node aus `Runtime/`): ein Korpus mit
  Schlüsselreihenfolge, doppelten Schlüsseln, Maskierungen, Zahlen am Rand und Leerraum, dazu 7.000
  Zahlen (5.000 zufällige Bitmuster, 2.000 Dezimalzahlen). Alle gleich.
- **Gegenprobe:** Ein falscher Bereich für die Exponentenschreibweise (`-7 < n` statt `-6 < n`)
  lässt `numbersMatchNode` scheitern, `\u0008` statt `\b` lässt `roundTripMatchesNode` scheitern.
- **Absichtlich anders:** Ein einzelnes UTF-16-Surrogat (`"\udc00"`) wird zu U+FFFD, weil ein
  Swift-String es nicht halten kann; Node schriebe es zurück. QuartzControl schreibt keine solchen
  Zeichen.
- **Echte Dateien:** Alle 23 JSON-Dateien in `.quartz-gui/` von `gui-test`, `Example`,
  `QuartzControl-Web` und `werkstatt` sind byte-gleich mit `JSON.stringify(JSON.parse(datei), null, 2)`
  (geprüft mit Node, nur gelesen).

`JSONStore` portiert `jsonStore.ts` mit denselben Namen für Temp- und Quarantäne-Dateien, weil beide
Apps in denselben Ordnern schreiben.

### Modelle als Sichten, Golden Files maskiert

- Jede JSON-Datei aus Profil und `.quartz-gui/` hat eine Sicht (`Formats/`), die mit den Regeln von
  QuartzControl liest: Defaults beim Lesen, Schalter nur bei `=== true`, `Number(…)` für die
  Breakpoints, die Filter von `readPendingInstall`. Eine Sicht, die nichts ändert, schreibt dieselben
  Bytes zurück.
- **Golden Files** (`Tests/QuartzHubCoreTests/Fixtures/quartz-gui/`, 13 Dateien) erzeugt
  `scripts/golden-fixtures.mjs` aus `gui-test` und `Example`. Es maskiert Adressen, Pfade, Hashes und
  Zielnamen (ein Zielname war eine Domain) und schreibt mit `JSON.stringify(…, null, 2)`, also in
  QuartzControls Form und mit den Original-Schlüsseln in Original-Reihenfolge. Eine Quelldatei, die
  nicht schon in dieser Form ist, lässt das Skript abbrechen. Gegenprobe: Ein Zeilenende am Schluss
  lässt alle 13 scheitern.
- Die Profil-Sichten sind an Objekten in der Schlüsselreihenfolge der Schreiber getestet, nicht an
  einem echten Profil. Das echte Profil misst die Übernahme.

### Übernahme

`ProfileMigration` in zwei Schritten: `plan` liest QuartzControls Profil (mit `JSONStore.peek`, das
nichts beiseitelegt: die Dateien gehören einer anderen App), `run` schreibt QuartzHubs Profil.
`projects.json` kommt zuletzt und ist die Marke „übernommen“; ein abgebrochener Lauf bietet die
Übernahme beim nächsten Start wieder an, ein zweiter Lauf wird abgewiesen.

- Geheimnisse: je Verbindung ein Schlüsselbund-Eintrag `QuartzHub` / `connection:<id>`, je Relay
  `relay:<projektId>` (der entschlüsselte JSON-Text). In QuartzHubs Dateien fehlt dann
  `encryptedSecret` bzw. `encrypted`, dafür steht `secretInKeychain: true`. Was sich nicht
  entschlüsseln lässt, nennt der Bericht mit Kennung; es muss neu eingegeben werden.
- Nicht übernommen: Fenster- und Dialogzustand, Caches, Shims, der Altbestand von vor dem ersten
  Release (`deploy-secrets.json`, `legacy-publish-targets.json`, `githubToken` in `settings.json`);
  der Plan nennt ihn.
- **CommonCrypto prüft das PKCS#7-Padding nicht vollständig.** Gemessen: „x“ mit einem Schlüssel
  verschlüsselt, mit einem anderen entschlüsselt, ergab Bytes statt eines Fehlers. Entschlüsselt wird
  deshalb ohne Padding, und `ChromiumSafeStorage` prüft das Padding selbst. Auch eine volle Prüfung
  lässt etwa jeden 256. falschen Schlüssel durch; dahinter steht die UTF-8-Prüfung.
- **`Process` übergibt Argumente zerlegt (NFD).** Der Test gegen Node bekam mit „pass wört“ in argv
  einen anderen Schlüssel als Swift; über stdin stimmen beide. Gilt für jeden Kindprozess, dem
  QuartzHub Nicht-ASCII mitgibt (Prozessstarter, Phase 3).
- Gemessen ist die Formel bisher gegen Nodes `crypto`, eine unabhängige Umsetzung derselben
  Bausteine, **nicht gegen Electron**.

### Nebeneinander-Betrieb

`Coexistence.foreignServers` liest QuartzControls `running-servers.json` und zählt einen Eintrag nur,
wenn die PID lebt (`kill(pid, 0) == 0`, wie QuartzControl: EPERM zählt nicht) und `ps -p … -o
command=` noch `quartz` und `--serve` enthält. QuartzHub meldet solche Server, beendet sie nie.
