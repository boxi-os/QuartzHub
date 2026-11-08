#!/usr/bin/env node
// Golden file for OptionFormText, made by QuartzControl's own form code: the texts of an option
// (`PluginOptionsForm/text.ts`), the value a hand-typed option becomes (`parseOptionValue`,
// AddOptionRow.tsx), the empty item of a list, the sentence under a field whose condition does not
// hold and the order of the groups (`emptyOf`, `conditionText`, `groupsOf`, editors.tsx, exposed at
// bundle time), the site's languages (`siteLanguages.ts`) and the repository of a plugin source
// (`routes/Plugins/pluginSource.ts`).
//
// The fields come from QuartzControl's normalizer over hand-made JSON Schemas; the Swift test
// normalizes the same schemas with OptionSchema, whose own golden is option-schema-golden.mjs.
// `t` answers key and arguments as JSON, so a sentence is compared by what it is made of.
//
//   Runtime/node/bin/node scripts/option-form-golden.mjs [../QuartzControl]
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'option-form')

const react = `export const useId = () => ''; export const useRef = () => ({}); export const useState = (v) => [v, () => {}];
  export const useMemo = (f) => f(); export default {}`
const ui = `const C = () => null; export const Badge = C, Button = C, FoldBox = C, IconButton = C, Select = C, TextInput = C, Toggle = C;
  export const DIVIDED_ROWS = ''`
const stubs = {
  react,
  'react-i18next': 'export const useTranslation = () => ({ t: (k) => k })',
  'lucide-react': 'export const ArrowDown = null, ArrowUp = null, RotateCcw = null, Trash2 = null',
  '../ui': ui,
  './snippets': 'export const ImageButton = null, PlaceholderList = null, SnippetFileField = null; export function siblingValue() {}'
}
const schema = await loadQuartzControl(control, 'shared/pluginOptionSchema.ts', {})
const text = await loadQuartzControl(control, 'src/components/PluginOptionsForm/text.ts', {})
const editors = await loadQuartzControl(control, 'src/components/PluginOptionsForm/editors.tsx', stubs, {
  expose: ['emptyOf', 'conditionText', 'groupsOf']
})
const addRow = await loadQuartzControl(control, 'src/components/PluginOptionsForm/AddOptionRow.tsx', stubs)
const languages = await loadQuartzControl(control, 'src/components/PluginOptionsForm/siteLanguages.ts', {})
const source = await loadQuartzControl(control, 'src/routes/Plugins/pluginSource.ts', {})

const t = (key, args) => JSON.stringify(args === undefined ? { key } : { key, args })

// ── fields ──────────────────────────────────────────────────────────────────────────────────────

const l10n = (de, en) => ({ 'x-quartz-l10n': { ...(de ? { de } : {}), ...(en ? { en } : {}) } })
const schemas = [
  {
    id: 'texts',
    schema: {
      type: 'object',
      properties: {
        sort: { type: 'string', enum: ['alpha', 'date', 'none'], default: 'alpha', title: 'Sort', description: 'How folders are sorted',
          ...l10n({ title: 'Sortierung', description: 'Wie Ordner sortiert werden', group: 'Ordnung', enum: { alpha: 'Alphabetisch', date: 'Datum' } }) },
        order: { type: 'array', items: { type: 'string', enum: ['frontmatter', 'git', 'filesystem'] }, default: ['frontmatter', 'git'],
          'x-quartz-group': 'Ordering', ...l10n({ group: 'Ordnung' }, { group: 'Ordering' }) },
        newest: { type: 'boolean', default: true, title: 'Newest first', 'x-quartz-when': { sort: 'date' }, 'x-quartz-group': 'Ordering' },
        limit: { type: 'integer', minimum: 1, maximum: 50, 'x-quartz-when': { sort: ['alpha', 'date'], newest: false } },
        folded: { type: 'boolean', 'x-quartz-when': { collapsible: true } },
        open: { type: 'boolean', 'x-quartz-when': { collapsible: false, 'deep.mode': ['a', 2, true] } },
        collapsible: { type: 'boolean', title: 'Collapsible', ...l10n({ title: 'Einklappbar' }) },
        deep: { type: 'object', properties: { mode: { enum: ['a', 'b', 2, true], ...l10n({ enum: { a: 'Erstens', 2: 'Zwei', true: 'Ja' } }) } } },
        size: { type: 'number', 'x-quartz-when': { level: 3 }, 'x-quartz-advanced': true },
        level: { type: 'integer', enum: [1, 2, 3], title: 'Level', ...l10n({ enum: { 3: 'Drei' } }) },
        mode: { anyOf: [{ type: 'string', enum: ['both', 'none'] }, { type: 'boolean' }], ...l10n({ enum: { both: 'Beide', true: 'An' } }) },
        shape: { anyOf: [{ type: 'object', properties: { x: { type: 'string' } } }, { type: 'string' }] },
        byLang: { type: 'object', additionalProperties: { type: 'object', properties: { label: { type: 'string', title: 'Label' } } },
          'x-quartz-keys': 'languages', 'x-quartz-group': 'Sprachen' },
        tags: { type: 'array', items: { type: 'object', properties: { name: { type: 'string', description: 'tag name with Umlaut ÄÖÜ' } } } },
        anything: { not: { type: 'string' } },
        nothing: { type: 'array', items: { anyOf: [{ type: 'number' }, { type: 'string' }] } },
        free: { type: 'object', additionalProperties: { type: 'number' } }
      }
    }
  },
  {
    id: 'ordered',
    schema: {
      type: 'object',
      properties: {
        z: { type: 'string', 'x-quartz-group': 'B', 'x-quartz-order': 3 },
        y: { type: 'string', 'x-quartz-order': 1 },
        x: { type: 'string', 'x-quartz-group': 'A' },
        w: { type: 'string', 'x-quartz-group': 'B', 'x-quartz-order': 1 },
        v: { type: 'string', ...l10n({ group: 'B' }, { group: 'Bee' }) },
        u: { type: 'string', 'x-quartz-group': 'A', 'x-quartz-order': -2 }
      }
    }
  }
]
const queries = ['', 'sort', 'ordnung', 'ordering', 'umlaut äöü', 'label', 'tag name', 'x', 'nichts', 'name', 'ein', 'DATUM'.toLowerCase()]

function walk(fields, path, visit) {
  for (const f of fields) {
    visit(f, [...path, f.key], fields)
    const nested = (node) => {
      if (node.kind === 'object') walk(node.fields, [...path, f.key], visit)
      else if (node.kind === 'record') nested(node.value)
      else if (node.kind === 'array') nested(node.items)
      else if (node.kind === 'union') node.variants.forEach(nested)
    }
    nested(f.node)
  }
}

const fieldCases = schemas.map(({ id, schema: s }) => {
  const normalized = schema.normalizeJsonSchema(s, 'configSchema')
  const fields = []
  walk(normalized.fields, [], (f, path, siblings) => {
    const enums = f.node.kind === 'enum' ? f.node.values : f.node.kind === 'union' ? f.node.variants.flatMap((v) => (v.kind === 'enum' ? v.values : v.kind === 'boolean' ? [true, false] : [])) : []
    fields.push({
      path,
      text: { de: text.fieldText(f, 'de'), en: text.fieldText(f, 'en') },
      enumLabels: { de: enums.map((v) => text.enumLabel(f, v, 'de')), en: enums.map((v) => text.enumLabel(f, v, 'en')) },
      empty: editors.emptyOf(f.node) ?? null,
      condition: f.when
        ? { de: editors.conditionText(f, siblings, 'de', t), en: editors.conditionText(f, siblings, 'en', t), prefixed: editors.conditionText(f, siblings, 'de', t, 'switcher.') }
        : null,
      match: Object.fromEntries(queries.map((q) => [q, { de: text.fieldMatch(f, q, 'de'), en: text.fieldMatch(f, q, 'en') }]))
    })
  })
  const groups = (lang) => editors.groupsOf(normalized.fields, lang).map(([g, list]) => [g ?? null, list.map((f) => f.key)])
  return { id, schema: s, fields, groups: { de: groups('de'), en: groups('en') } }
})

// ── values ──────────────────────────────────────────────────────────────────────────────────────

const inline = ['', 'text', 'with "quotes"', 0, -1.5, 1e21, 1e-7, true, null, [], ['a', 'b'], [1, 'x', 2.5], [true], [['a']], { a: 1 },
  { b: [1, { c: 'ü' }] }, [null], ['', ''], 'ä']
const typed = ['', ' ', 'true', 'false', ' true ', 'True', '3', '-0', '0x10', '0o17', '0b11', '1e3', '.5', '5.', '+7', '-0x10',
  'Infinity', '-Infinity', 'NaN', '1_000', '12px', '[1, 2]', '[1, 2', '{"a": 1}', '{a: 1}', '"quoted"', '"broken', '  [ ]  ',
  'null', 'text with spaces', ' padded ', '\t42\n', '١٢', '0.1e-2', '1,5', '00012', '9007199254740993']

const configs = [
  { id: 'none', config: null },
  { id: 'locale', config: { configuration: { locale: 'de-DE' }, plugins: [] } },
  { id: 'locale-upper', config: { configuration: { locale: 'EN' }, plugins: [] } },
  { id: 'locale-empty', config: { configuration: { locale: '' }, plugins: [] } },
  { id: 'locale-number', config: { configuration: { locale: 5 }, plugins: [] } },
  { id: 'multilanguage', config: { configuration: { locale: 'de-DE' }, plugins: [
    { name: 'quartz-multilanguage', source: 'github:quartz-community/quartz-multilanguage', options: { languages: ['DE', { code: ' en ' }, { code: 5 }, null, '', 'de', 'fr-CA'] } }] } },
  { id: 'multilanguage-empty', config: { configuration: { locale: 'it-IT' }, plugins: [
    { name: 'quartz-multilanguage', source: { repo: 'https://github.com/quartz-community/quartz-multilanguage.git' }, options: { languages: [] } }] } },
  { id: 'multilanguage-not-list', config: { configuration: {}, plugins: [
    { name: 'quartz-multilanguage', source: 'github:quartz-community/quartz-multilanguage', options: { languages: 'de' } }] } },
  { id: 'multilanguage-second', config: { configuration: { locale: 'de' }, plugins: [
    { name: 'x', source: 'github:someone/quartz-multilanguage', options: { languages: ['nl'] } },
    { name: 'quartz-multilanguage', source: 'github:quartz-community/quartz-multilanguage', options: { languages: ['sv'] } }] } }
]

const sources = ['github:quartz-community/explorer', 'github:Quartz-Community/Explorer#v2', '@quartz-community/explorer',
  'git+https://github.com/boxi-os/quartz-layout-box.git', 'https://github.com/a/b.git#main', 'http://github.com/a/b',
  '/Users/x/project/.quartz-gui/authored-frames/f1', './local/plugin', 'npm-package', 'github:a/b/c', 'github:a/', '',
  { repo: 'github:owner/repo', ref: 'main' }, { repo: 'https://github.com/Owner/Repo.git', subdir: 'x' }, { repo: 'gitlab.com/a/b' },
  'git+github:a/b', '@scope/pkg', 'github:ä/ü']

const golden = {
  fields: fieldCases,
  inline: inline.map((value) => ({ value, text: text.inlineValue(value) })),
  typed: typed.map((raw) => {
    const value = addRow.parseOptionValue(raw)
    // JSON has no NaN or infinity; the number says which it was.
    return { raw, value: typeof value === 'number' && !Number.isFinite(value) ? { nonFinite: String(value) } : value }
  }),
  languages: configs.map(({ id, config }) => ({ id, config, languages: languages.siteLanguages(config) })),
  sources: sources.map((s) => ({ source: s, id: source.normalizedRepoId(s), url: source.repoUrl(s) }))
}

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify(golden, null, 2) + '\n')
console.log(`option-form: ${fieldCases.reduce((n, c) => n + c.fields.length, 0)} fields, ${inline.length} values, ${typed.length} typed, ${configs.length} configs, ${sources.length} sources`)
