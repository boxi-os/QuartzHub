// Neue Texte in den String Catalog, ohne Xcode, in derselben Form, die Xcode schreibt.
//
//   node scripts/strings.mjs add <schlüssel> --de "…" --en "…" [--comment "…"]
//   node scripts/strings.mjs add <schlüssel> --de-one "…" --de-other "…" --en-one "…" --en-other "…"
//   node scripts/strings.mjs show <schlüssel>
//
// Ein Schlüssel, den es schon gibt, wird nicht überschrieben (Abbruch); geändert wird in Xcode
// oder von Hand. Regeln für den Wortlaut: docs/conventions.md, „Ein Wort, ein Name“.
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
if (!command || !key) fail('Aufruf: node scripts/strings.mjs add|show <schlüssel> …')

const catalog = JSON.parse(readFileSync(file, 'utf-8'))
if (command === 'show') {
  console.log(JSON.stringify(catalog.strings[key] ?? null, null, 2))
  process.exit(0)
}
if (command !== 'add') fail(`unbekannter Befehl ${command}`)
if (catalog.strings[key]) fail(`${key} gibt es schon`)

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
const comment = opt('comment')
catalog.strings[key] = { ...(comment ? { comment } : {}), localizations }
catalog.strings = Object.fromEntries(Object.keys(catalog.strings).sort().map((k) => [k, catalog.strings[k]]))
writeFileSync(file, JSON.stringify(catalog, null, 2).replace(/^(\s*"(?:[^"\\]|\\.)*"):/gm, '$1 :') + '\n')
console.log(`${key} eingetragen`)
