#!/usr/bin/env node
// Golden file for StyleSettingsValues, made by QuartzControl's own src/routes/Styles/styleSettings.ts
// and the grouping of StyleSettingsForm.tsx (buildGroups, with React and the UI stood in for): how a
// Style Settings value is written into quartz.config.yaml (keys, colour formats, hsl-split, modes),
// read back for the colour picker, and how the theme's headings group the fields.
//
// The schemas are Ultra Lobster's (176 fields, the cached copy in QuartzControl's profile,
// theme-docs/ultra-lobster.json, a published upstream theme's documentation), Tokyo Night's from
// Fixtures/themes and made-up fields for every kind and format.
//
//   Runtime/node/bin/node scripts/style-settings-golden.mjs [../QuartzControl] [QuartzControl's profile]
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { loadQuartzControl } from './lib/qc-bundle.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const profile = resolve(process.argv[3] ?? join(homedir(), 'Library', 'Application Support', 'QuartzControl'))
const fixtures = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures')
const out = join(fixtures, 'style-settings')

const settings = await loadQuartzControl(control, 'src/routes/Styles/styleSettings.ts', {})
const form = await loadQuartzControl(control, 'src/routes/Styles/StyleSettingsForm.tsx', {
  react: 'export const useMemo = (f) => f(); export const useState = (v) => [v, () => {}]',
  'react/jsx-runtime': 'export const jsx = () => null; export const jsxs = () => null; export const Fragment = null',
  'react-i18next': 'export const useTranslation = () => ({ t: (k) => k })',
  'lucide-react': 'export const ChevronDown = null; export const ChevronRight = null',
  '../../components/ui': 'export const Select = null; export const TextInput = null; export const Toggle = null',
  './ColorPicker': 'export default null'
}, { expose: ['buildGroups'] })

const lobster = JSON.parse(readFileSync(join(profile, 'theme-docs', 'ultra-lobster.json'), 'utf8'))
if (!lobster?.fields?.length) throw new Error('no Ultra Lobster schema in the profile')
const steps = JSON.parse(readFileSync(join(fixtures, 'themes', 'steps.json'), 'utf8'))
const tokyo = steps.find((s) => s.call === 'getStyleSettingsSchema' && s.result?.fields).result

const f = (id, kind, extra = {}) => ({ id, blockId: 'made', title: id, kind, ...extra })
const made = [
  f('h1', 'heading', { level: 1 }), f('c-hex', 'variable-color', { format: 'hex', default: '#abc' }),
  f('c-rgb', 'variable-color', { format: 'rgb', default: 'rgb(10, 20, 30)' }), f('c-rgb-split', 'variable-color', { format: 'rgb-split', default: '10, 20, 30' }),
  f('c-rgb-values', 'variable-color', { format: 'rgb-values' }), f('c-hsl', 'variable-color', { format: 'hsl', default: 'hsl(200, 50%, 50%)' }),
  f('c-hsl-values', 'variable-color', { format: 'hsl-values', default: '200, 50%, 50%' }), f('c-hsl-split', 'variable-color', { format: 'hsl-split', default: '#80D0FF' }),
  f('c-none', 'variable-color'), f('h2', 'heading', { level: 2, collapsed: true }),
  f('t-hex', 'variable-themed-color', { format: 'hex', defaultLight: '#ffffff', defaultDark: '#000' }),
  f('t-split', 'variable-themed-color', { format: 'hsl-split', defaultLight: '#80D0FF', defaultDark: 'hsl(10, 20%, 30%)' }),
  f('t-rgb', 'variable-themed-color', { format: 'rgb', default: 'rgba(1, 2, 3, 0.5)' }), f('h3', 'heading', { level: 3 }),
  f('n', 'variable-number', { default: 3 }), f('s', 'variable-number-slider', { min: 0, max: 10, step: 0.5, default: '4' }),
  f('txt', 'variable-text', { default: 'x' }), f('ct', 'class-toggle'), f('cs', 'class-select', { options: [{ label: 'A', value: 'a' }] }),
  f('i', 'info-text', { description: 'about' }), f('u', 'unsupported'), f('h1b', 'heading', { level: 1 }), f('after', 'variable-text'),
  f('h4', 'heading'), f('h2b', 'heading', { level: 2 })
]
const schemas = { lobster, tokyo, made: { ids: ['made'], themeName: 'made', author: 'x', repo: 'x/y', fields: made } }

const hexes = ['#80D0FF', '#000000', '#ffffff', '#123456', 'abcdef', '#ABC', 'nope', '#7f7f7f']
const modes = [undefined, 'light', 'dark']
const valueSets = [
  {},
  { 'made@@c-hex': '#abc', 'made@@c-rgb': 'rgb(300, -5, 7.6)', 'made@@c-rgb-split': '10, 20, 30', 'made@@c-hsl': 'hsla(200, 50%, 50%, 0.4)',
    'made@@c-hsl-values': '200, 50%, 50%', 'made@@c-hsl-split-h': '200', 'made@@c-hsl-split-s': '50%', 'made@@c-hsl-split-l': '50%',
    'made@@t-hex@@light': '#010203', 'made@@t-hex@@dark': 'garbage', 'made@@t-split-h@@dark': 10, 'made@@t-split-s@@dark': '20', 'made@@t-split-l@@dark': '30%',
    'made@@t-rgb@@light': ' rgb( 1 , 2 , 3 ) ', 'made@@c-none': 'hsl(400, 100%, 50%)' },
  { 'made@@c-hsl-split-h': '', 'made@@c-hsl-split-s': 'x', 'made@@c-hsl-split-l': '1', 'made@@c-hex': '', 'made@@c-rgb': 'rgb(1,2)', 'made@@t-split-h@@light': '-30',
    'made@@t-split-s@@light': '100%', 'made@@t-split-l@@light': '50%', 'made@@c-hsl': 'hsl(1e2, 1%, 99%)' }
]

const fieldCases = []
for (const [name, schema] of Object.entries(schemas)) {
  for (const field of schema.fields) {
    const isColor = field.kind === 'variable-color' || field.kind === 'variable-themed-color'
    fieldCases.push({
      schema: name,
      field,
      key: settings.optionKey(field),
      keys: settings.keysOf(field),
      entries: isColor ? hexes.flatMap((hex) => modes.map((mode) => ({ hex, mode: mode ?? null, entries: settings.colorEntries(field, hex, mode) }))) : [],
      read: isColor ? valueSets.flatMap((values, set) => modes.map((mode) => ({ set, mode: mode ?? null, ...settings.readColor(field, values, mode) }))) : []
    })
  }
}

// What the form shows: the usable fields (unsupported out, class toggles only when shipped), a
// search, and the groups.
const shippedSets = { lobster: [], tokyo: ['toggle', 'a'], made: ['ct', 'a'] }
const strip = (groups) => JSON.parse(JSON.stringify(groups, (k, v) => (v === undefined ? null : v)))
const groupCases = []
for (const [name, schema] of Object.entries(schemas)) {
  const shipped = new Set(shippedSets[name])
  const usable = schema.fields.filter((field) => field.kind !== 'unsupported' && (field.kind !== 'class-toggle' || shipped.has(field.id)))
  for (const query of ['', 'color', 'ACCENT', 'zzz', 'about']) {
    const q = query.trim().toLowerCase()
    const filtered = q ? usable.filter((field) => field.kind === 'heading' || field.title.toLowerCase().includes(q) || field.id.toLowerCase().includes(q) || (field.description?.toLowerCase().includes(q) ?? false)) : usable
    groupCases.push({ schema: name, shipped: [...shipped], query, groups: strip(form.buildGroups(filtered)) })
  }
}

const hsl = []
for (const h of [0, 59.9, 60, 120, 180, 240, 300, 359, 360, 400, -30, 202.5]) for (const s of [0, 50, 100, 120]) for (const l of [0, 25, 50, 75, 100]) hsl.push({ h, s, l, hex: settings.hslToHex(h, s, l) })

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify({ schemas: { tokyo, made: schemas.made }, valueSets, hexes, fieldCases, groupCases, hsl }) + '\n')
writeFileSync(join(out, 'ultra-lobster.json'), JSON.stringify(lobster) + '\n')
console.log(`${fieldCases.length} fields, ${groupCases.length} group cases, ${hsl.length} hsl cases`)
