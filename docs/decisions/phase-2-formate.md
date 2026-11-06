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
