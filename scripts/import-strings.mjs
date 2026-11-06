// Einmaliger Import der Texte aus QuartzControl in den String Catalog von QuartzHub.
//
//   node scripts/import-strings.mjs <pfad-zu-QuartzControl> [--check]
//
// Quellen: src/i18n/locales/{de,en}.ts (Renderer, i18next) und electron/main/i18n.ts (mainT).
// Gelesen wird mit dem TypeScript-Parser aus QuartzControls node_modules, nicht per import(): Nur so
// kommen die Kommentare über den Schlüsseln mit, und die sind oft die einzige Stelle, die sagt,
// warum ein Satz so lautet. Sie landen als `comment` im Katalog.
//
// Abbildung:
//   * Renderer-Schlüssel behalten ihren Punkt-Pfad (`dashboard.attention.title`), Main-Schlüssel
//     bekommen `main.` davor (`main.menuFile`). Ein Schlüssel heißt in beiden Welten gleich, damit
//     die Langfassungen in QuartzControls docs/ auffindbar bleiben.
//   * `{{name}}` bleibt wörtlich stehen; L10n.t ersetzt es (benannte Platzhalter kennt der Katalog
//     nicht, Positionsformate würden die Reihenfolge der Übersetzung festlegen).
//   * `x` + `x_other` (+ optional `x_one`) wird zu einem Eintrag `x` mit Pluralvarianten one/other.
//     Die Falle aus dem Spike steht als Regel hier: i18next nimmt **ohne `_one` den
//     Grundschlüssel** als Singular, nicht `_other`.
//   * `_zero` wird die Variante `zero`: i18next nimmt sie bei `count === 0` in jeder Sprache, der
//     Katalog kennt sie ebenso als Sonderfall. Jede andere Endung (`_few` …) bricht den Import ab,
//     statt sie still zu verlieren.
//
// Mit --check wird nichts geschrieben; der Lauf sagt nur, ob der Katalog dem Import entspricht.
import { readFileSync, writeFileSync, existsSync } from 'fs'
import { createRequire } from 'module'
import { dirname, join, resolve } from 'path'
import { fileURLToPath } from 'url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const target = join(root, 'Packages/QuartzHubCore/Sources/QuartzHubCore/Resources/Localizable.xcstrings')
const args = process.argv.slice(2)
const check = args.includes('--check')
const qc = args.find((a) => !a.startsWith('--'))
if (!qc) {
  console.error('Aufruf: node scripts/import-strings.mjs <pfad-zu-QuartzControl> [--check]')
  process.exit(2)
}
const tsPath = join(resolve(qc), 'node_modules/typescript')
if (!existsSync(tsPath)) {
  console.error(`TypeScript fehlt unter ${tsPath} (in QuartzControl einmal npm install)`)
  process.exit(2)
}
const ts = createRequire(import.meta.url)(tsPath)

function source(file) {
  const text = readFileSync(join(resolve(qc), file), 'utf-8')
  return ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS)
}

function leadingComment(node, sf) {
  const ranges = ts.getLeadingCommentRanges(sf.text, node.getFullStart()) ?? []
  const lines = ranges.map((r) =>
    sf.text
      .slice(r.pos, r.end)
      .replace(/^\/\*+|\*+\/$/g, '')
      .split('\n')
      .map((l) => l.replace(/^\s*(\/\/|\*)\s?/, '').trim())
      .join(' ')
      .trim()
  )
  return lines.filter(Boolean).join(' ') || undefined
}

function propName(p) {
  if (ts.isIdentifier(p.name) || ts.isStringLiteral(p.name)) return p.name.text
  throw new Error(`unlesbarer Schlüssel: ${p.name.getText()}`)
}

function stringValue(init, where) {
  if (ts.isStringLiteral(init) || ts.isNoSubstitutionTemplateLiteral(init)) return init.text
  throw new Error(`${where}: kein einfacher String (${ts.SyntaxKind[init.kind]})`)
}

// Flacht ein Objektliteral zu { key: { value, comment } }.
function flatten(obj, sf, prefix, out) {
  for (const p of obj.properties) {
    if (!ts.isPropertyAssignment(p)) throw new Error(`${prefix}: unerwartetes ${ts.SyntaxKind[p.kind]}`)
    const key = prefix ? `${prefix}.${propName(p)}` : propName(p)
    let init = p.initializer
    while (ts.isAsExpression(init) || ts.isSatisfiesExpression?.(init)) init = init.expression
    if (ts.isObjectLiteralExpression(init)) flatten(init, sf, key, out)
    else out[key] = { value: stringValue(init, key), comment: leadingComment(p, sf) }
  }
  return out
}

function defaultExportObject(sf) {
  for (const st of sf.statements) {
    if (ts.isExportAssignment(st)) {
      let e = st.expression
      while (ts.isAsExpression(e) || ts.isSatisfiesExpression?.(e)) e = e.expression
      if (ts.isObjectLiteralExpression(e)) return e
    }
  }
  throw new Error(`${sf.fileName}: kein export default { … }`)
}

function mainStrings(sf) {
  for (const st of sf.statements) {
    if (!ts.isVariableStatement(st)) continue
    for (const d of st.declarationList.declarations) {
      if (d.name.getText() !== 'STRINGS') continue
      let e = d.initializer
      while (ts.isAsExpression(e)) e = e.expression
      const result = {}
      for (const p of e.properties) result[propName(p)] = flatten(p.initializer, sf, '', {})
      return result
    }
  }
  throw new Error('electron/main/i18n.ts: const STRINGS fehlt')
}

const renderer = {
  de: flatten(defaultExportObject(source('src/i18n/locales/de.ts')), source('src/i18n/locales/de.ts'), '', {}),
  en: flatten(defaultExportObject(source('src/i18n/locales/en.ts')), source('src/i18n/locales/en.ts'), '', {})
}
const mainSf = source('electron/main/i18n.ts')
const main = mainStrings(mainSf)

const PLURAL = /_(zero|one|two|few|many|other)$/
const strings = {}
const problems = []

function add(lang, key, entry) {
  const m = key.match(PLURAL)
  if (m && !['zero', 'one', 'other'].includes(m[1])) problems.push(`${lang} ${key}: Pluralform ${m[1]} wird nicht unterstützt`)
  const base = m ? key.slice(0, -m[0].length) : key
  const form = m ? m[1] : 'base'
  const slot = (strings[base] ??= { comment: undefined, langs: {} })
  slot.comment ??= entry.comment
  ;(slot.langs[lang] ??= {})[form] = entry.value
}

for (const lang of ['de', 'en']) {
  for (const [k, v] of Object.entries(renderer[lang])) add(lang, k, v)
  for (const [k, v] of Object.entries(main[lang])) add(lang, `main.${k}`, v)
}

const unit = (value) => ({ stringUnit: { state: 'translated', value } })
const catalog = { sourceLanguage: 'de', strings: {}, version: '1.0' }
for (const key of Object.keys(strings).sort()) {
  const { comment, langs } = strings[key]
  const localizations = {}
  for (const lang of ['de', 'en']) {
    const forms = langs[lang]
    if (!forms) {
      problems.push(`${key}: fehlt in ${lang}`)
      continue
    }
    if (forms.other !== undefined) {
      const one = forms.one ?? forms.base
      if (one === undefined) problems.push(`${lang} ${key}: _other ohne Singular`)
      const plural = { one: unit(one), other: unit(forms.other) }
      if (forms.zero !== undefined) plural.zero = unit(forms.zero)
      localizations[lang] = { variations: { plural } }
    } else if (forms.one !== undefined || forms.zero !== undefined) {
      problems.push(`${lang} ${key}: _one/_zero ohne _other`)
    } else {
      localizations[lang] = unit(forms.base)
    }
  }
  catalog.strings[key] = { ...(comment ? { comment } : {}), localizations }
}

if (problems.length) {
  console.error(problems.join('\n'))
  console.error(`${problems.length} Probleme, nichts geschrieben`)
  process.exit(1)
}

// Xcode schreibt Kataloge mit " : " und zwei Leerzeichen; dieselbe Form, damit ein Speichern in
// Xcode keinen Diff über die ganze Datei erzeugt.
const text = JSON.stringify(catalog, null, 2).replace(/^(\s*"(?:[^"\\]|\\.)*"):/gm, '$1 :') + '\n'
const count = Object.keys(catalog.strings).length
const plurals = Object.values(catalog.strings).filter((s) => s.localizations.de?.variations).length
if (check) {
  const current = existsSync(target) ? readFileSync(target, 'utf-8') : ''
  if (current === text) {
    console.log(`Katalog entspricht dem Import (${count} Schlüssel)`)
    process.exit(0)
  }
  console.log('Katalog weicht vom Import ab (in Xcode bearbeitet oder QuartzControl geändert)')
  process.exit(1)
}
writeFileSync(target, text)
console.log(`${count} Schlüssel geschrieben (${plurals} mit Plural), ${Object.keys(main.de).length} davon aus main`)
