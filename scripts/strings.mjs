// Neue Texte in den String Catalog, ohne Xcode, in derselben Form, die Xcode schreibt.
//
//   node scripts/strings.mjs add <schlüssel> --de "…" --en "…" [--comment "…"]
//   node scripts/strings.mjs add <schlüssel> --de-one "…" --de-other "…" --en-one "…" --en-other "…"
//   node scripts/strings.mjs set <schlüssel> --de "…" --en "…"   (ändert einen vorhandenen Text,
//     der Kommentar bleibt, wenn keiner angegeben ist; Muster beim Umstellen auf „QuartzHub“)
//   node scripts/strings.mjs show <schlüssel>
//   node scripts/strings.mjs normalize   (nur sortieren und jeden Eintrag „manual“ markieren)
//
// Jeder Eintrag trägt `"extractionState" : "manual"`: Die Texte kommen über `L10n.t`, das Xcodes
// Abgleich nicht kennt; ohne die Markierung setzte die Xcode-Oberfläche beim Bauen jeden Schlüssel
// auf „stale“. Und `"generatesSymbol" : false`: Für Einträge von Hand erzeugt `xcstringstool` sonst
// Swift-Symbole, und zwei Schlüssel ergäben dasselbe (decisions/ui-ueberarbeitung.md, Kataloge).
//
// `add` überschreibt keinen Schlüssel, den es schon gibt (Abbruch), `set` ändert nur einen
// vorhandenen; sonst wird in Xcode oder von Hand geändert. Regeln für den Wortlaut: docs/conventions.md, „Ein Wort, ein Name“.
import { readFileSync, writeFileSync } from 'fs'
import { dirname, join, resolve } from 'path'
import { fileURLToPath } from 'url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const file = join(root, 'Packages/QuartzHubCore/Sources/QuartzHubCore/Resources/Localizable.xcstrings')
const [command, key, ...rest] = process.argv.slice(2)
const opt = (name) => {
  const i = rest.indexOf(`--${name}`)
  return i >= 0 ? rest[i + 1] : undefined
}
const fail = (message) => {
  console.error(message)
  process.exit(2)
}
if (!command || (!key && command !== 'normalize')) fail('Aufruf: node scripts/strings.mjs add|set|show <schlüssel> … oder normalize')

const catalog = JSON.parse(readFileSync(file, 'utf-8'))
// Xcode's order of an entry's keys, alphabetical: comment, extractionState, generatesSymbol, localizations.
const manual = ({ comment, extractionState, generatesSymbol, localizations, ...more }) =>
  ({ ...(comment !== undefined ? { comment } : {}), extractionState: 'manual', generatesSymbol: false,
     ...(localizations ? { localizations } : {}), ...more })
const write = () => {
  catalog.strings = Object.fromEntries(Object.keys(catalog.strings).sort().map((k) => [k, manual(catalog.strings[k])]))
  writeFileSync(file, JSON.stringify(catalog, null, 2).replace(/^(\s*"(?:[^"\\]|\\.)*"):/gm, '$1 :') + '\n')
}
if (command === 'normalize') {
  write()
  console.log('normalisiert')
  process.exit(0)
}
if (command === 'show') {
  console.log(JSON.stringify(catalog.strings[key] ?? null, null, 2))
  process.exit(0)
}
if (command !== 'add' && command !== 'set') fail(`unbekannter Befehl ${command}`)
if (command === 'add' && catalog.strings[key]) fail(`${key} gibt es schon`)
if (command === 'set' && !catalog.strings[key]) fail(`${key} gibt es nicht`)

const unit = (value) => ({ stringUnit: { state: 'translated', value } })
const localizations = {}
for (const lang of ['de', 'en']) {
  const plain = opt(lang)
  const one = opt(`${lang}-one`)
  const other = opt(`${lang}-other`)
  if (plain !== undefined) localizations[lang] = unit(plain)
  else if (one !== undefined && other !== undefined) localizations[lang] = { variations: { plural: { one: unit(one), other: unit(other) } } }
  else fail(`${lang}: --${lang} oder --${lang}-one und --${lang}-other angeben`)
}
const comment = opt('comment') ?? (command === 'set' ? catalog.strings[key].comment : undefined)
catalog.strings[key] = { ...(comment ? { comment } : {}), localizations }
write()
console.log(`${key} ${command === 'set' ? 'geändert' : 'eingetragen'}`)
