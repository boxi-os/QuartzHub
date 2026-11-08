#!/usr/bin/env node
// Golden file for MultilanguageOptions, made by QuartzControl's own code
// (`routes/Plugins/multilanguageOptions.ts`): the languages as quartz-multilanguage reads them,
// renaming, removing, publishing and reordering them with the written form kept where nobody
// changed it, and the groups of settings below the list.
//
// An entry remembers the item it was read from (a WeakMap there, a field in Swift), so the
// operations are described here as steps on the entries `languagesOf` hands out: the Swift test
// takes the same steps on its own entries. The schema is quartz-multilanguage's own configSchema
// from gui-test (read only, copied into the fixture).
//
//   Runtime/node/bin/node scripts/multilanguage-golden.mjs [../QuartzControl] [gui-test]
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const guiTest = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte', 'gui-test'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'multilanguage')

const ml = await loadQuartzControl(control, 'src/routes/Plugins/multilanguageOptions.ts', {})
const schemaLib = await loadQuartzControl(control, 'shared/pluginOptionSchema.ts', {})

const pkgFile = join(guiTest, '.quartz', 'plugins', 'quartz-multilanguage', 'package.json')
if (!existsSync(pkgFile)) throw new Error(`${pkgFile} fehlt`)
const configSchema = JSON.parse(readFileSync(pkgFile, 'utf8')).quartz.configSchema
const schema = schemaLib.normalizeJsonSchema(configSchema, 'configSchema')

// `null` stands for "no options".
const optionSets = [
  null, {}, { languages: [] }, { languages: 'de' }, { languages: ['de', 'en'] },
  { languages: [{ code: 'de', label: 'German', native: 'Deutsch', locale: 'de-DE' }, { code: 'en', label: 'English' }], defaultLanguage: 'de' },
  { languages: [' DE ', { code: 'En', native: 'English' }, 'de', { label: 'no code' }, 7, null, { code: '' }, { code: 'fr' }, 'FR'],
    defaultLanguage: 'EN', publishLanguages: ['DE', 'xx', 3, 'fr'], seo: { xDefault: 'De', hreflang: true } },
  { languages: ['de', 'en', 'fr'], defaultLanguage: 'it', publishLanguages: ['en'] },
  { languages: ['de', 'en', 'fr'], defaultLanguage: '', publishLanguages: ['de', 'en', 'fr'], seo: { xDefault: 'en' } },
  { languages: [{ code: 'ΣΟΦΟΣ' }, { code: 'İstanbul' }, { code: 'ﬁ' }], publishLanguages: 'de' },
  { languages: ['de'], detection: ['folder'], switcher: { style: 'dropdown' }, extra: 1, rememberChoice: true },
  { languages: [{ code: 'de', home: 'start', flag: '🇩🇪' }, 'en'], publishLanguages: ['de'], seo: 'nope' },
  // A second entry before its language's place: a reorder must not keep it under the old code.
  { languages: ['de', 'DE', 'en'] }
]
const lift = (v) => (v === null ? undefined : v)

// The steps, applied to the entries languagesOf hands out (index into them).
function stepsFor(options) {
  const langs = ml.languagesOf(options)
  const steps = []
  langs.forEach((l, i) => {
    steps.push({ op: 'rename', from: l.code, to: `${l.code}-x` })
    steps.push({ op: 'rename', from: l.code, to: langs[(i + 1) % langs.length].code })
    steps.push({ op: 'remove', code: l.code })
    steps.push({ op: 'publish', code: l.code, on: true })
    steps.push({ op: 'publish', code: l.code, on: false })
    if (i + 1 < langs.length) steps.push({ op: 'swap', i, j: i + 1 })
    steps.push({ op: 'edit', i, key: 'label', value: 'Neu' })
  })
  steps.push({ op: 'add', code: 'xx' })
  steps.push({ op: 'same' })
  return steps
}

function apply(options, step) {
  const o = options ?? {}
  const langs = ml.languagesOf(o)
  switch (step.op) {
    case 'rename': return ml.renameLanguage(o, langs, step.from, step.to)
    case 'remove': return ml.removeLanguage(o, langs, step.code)
    case 'publish': return ml.withPublished(o, langs, step.code, step.on)
    case 'swap': {
      const next = [...langs]
      ;[next[step.i], next[step.j]] = [next[step.j], next[step.i]]
      return ml.withLanguages(o, next)
    }
    case 'edit': return ml.withLanguages(o, langs.map((l, i) => (i === step.i ? { ...l, [step.key]: step.value } : l)))
    case 'add': return ml.withLanguages(o, [...langs, { code: step.code }])
    case 'same': return ml.withLanguages(o, langs)
  }
}

const cases = optionSets.map((options) => {
  const o = lift(options)
  const langs = ml.languagesOf(o)
  return {
    options,
    languages: langs,
    defaultLanguage: ml.defaultLanguageOf(o, langs),
    published: ml.publishedOf(o, langs),
    byRemoving: Object.fromEntries(langs.map((l) => [l.code, ml.publishedByRemoving(o, langs, l.code).map((x) => x.code)])),
    steps: stepsFor(o).map((step) => ({ step, result: apply(o, step) })),
    groups: Object.fromEntries(['de', 'en'].map((lang) => [lang, ml.settingsGroups(schema, o ?? {}, lang)
      .map((g) => ({ ...g, sole: ml.soleObject(schema, g)?.key ?? null }))])),
    groupsWithoutSchema: ml.settingsGroups(null, o ?? {}, 'de')
  }
})

// The real schema groups every field; this one has fields without a group and without an order.
const syntheticSchema = { type: 'object', properties: {
  plain: { type: 'string' }, late: { type: 'string', 'x-quartz-group': 'Late', 'x-quartz-order': 9 },
  early: { type: 'boolean', 'x-quartz-group': 'Early', 'x-quartz-order': 1 }, loose: { type: 'string', 'x-quartz-order': 5 },
  same: { type: 'string', 'x-quartz-group': 'Late', 'x-quartz-order': 9 }, wrapped: { type: 'object', 'x-quartz-group': 'Box', properties: { x: { type: 'string' } } },
  languages: { type: 'array', items: { type: 'string' } } } }
const synthetic = schemaLib.normalizeJsonSchema(syntheticSchema, 'configSchema')
const syntheticGroups = ml.settingsGroups(synthetic, { plain: 'x', stray: 1 }, 'de').map((g) => ({ ...g, sole: ml.soleObject(synthetic, g)?.key ?? null }))

const codes = ['de', ' DE ', '', '   ', 'pt-br', 'a b', 'a/b', 'a\\b', 'EN', 'en', 'zh_Hant', 'x\ty']
const problems = codes.flatMap((code) => [undefined, 'en'].map((own) => ({ code, own: own ?? null,
  problem: ml.codeProblem(code, [{ code: 'de' }, { code: 'en' }], own) })))
const normalized = ['DE', ' En ', 'ΣΟΦΟΣ', 'İ', 'ﬁ', ' x ', 'Straße'].map((code) => ({ code, result: ml.normalizeCode(code) }))

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'schema.json'), JSON.stringify(configSchema, null, 1) + '\n')
writeFileSync(join(out, 'cases.json'), JSON.stringify({
  readAgainst: ml.MULTILANGUAGE_READ_AGAINST, sameCode: ml.MULTILANGUAGE_SAME_CODE, languageKeys: ml.LANGUAGE_KEYS,
  cases, problems, normalized, syntheticSchema, syntheticGroups
}, null, 1) + '\n')
console.log(`multilanguage: ${cases.length} option sets, ${cases.reduce((n, c) => n + c.steps.length, 0)} steps, ${problems.length} code checks`)
