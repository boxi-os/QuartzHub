#!/usr/bin/env node
// Golden file for FormsOptions, made by QuartzControl's own code (`routes/Plugins/formsOptions.ts`):
// the plugin's templates word for word, how a form is laid over its template, ids and field names,
// writing forms, fields and their conditions, where a message of the plugin's check belongs, which
// captcha secrets the relay needs, and which entry of `texts` a language writes to.
//
// The schema is quartz-forms' own configSchema from gui-test (read only, copied into the fixture).
//
//   Runtime/node/bin/node scripts/forms-options-golden.mjs [../QuartzControl] [gui-test]
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const guiTest = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte', 'gui-test'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'forms-options')

const f = await loadQuartzControl(control, 'src/routes/Plugins/formsOptions.ts', {})
const schemaLib = await loadQuartzControl(control, 'shared/pluginOptionSchema.ts', {})

const pkgFile = join(guiTest, '.quartz', 'plugins', 'quartz-forms', 'package.json')
if (!existsSync(pkgFile)) throw new Error(`${pkgFile} fehlt`)
const configSchema = JSON.parse(readFileSync(pkgFile, 'utf8')).quartz.configSchema
const schema = schemaLib.normalizeJsonSchema(configSchema, 'configSchema')
const u = (v) => (v === undefined ? '__undefined' : v)

// ── forms ───────────────────────────────────────────────────────────────────────────────────────
const optionSets = [
  null, {}, { forms: 'x' }, { forms: [] },
  { forms: { kontakt: { template: 'contact', recipient: 'a', encryption: { mode: 'required' } }, 'umfrage': { template: 'survey' } },
    transport: { kind: 'relay', url: 'https://x' }, layoutForm: 'kontakt' },
  { forms: { 2: { fields: [{ type: 'text', name: 'a' }] }, b: null, 1: 7, c: { template: 'rsvp', fields: [{ type: 'email', name: 'e' }, 'junk', null], title: null },
    d: { template: 'nope', anonymous: true, transport: { kind: 'mailto' }, spam: { captcha: 'hcaptcha' } } }, transport: { kind: 'formspree' }, layoutForm: 'd' },
  { forms: { a: { template: 'feedback', spam: { captcha: 'turnstile', captchaSiteKey: 'k2' } }, b: { template: 'contact' },
    c: { template: 'survey' }, d: { template: 'contact', spam: { captcha: 'none' } }, e: { transport: { kind: 'endpoint' }, template: 'contact' } },
    spam: { captcha: 'turnstile', captchaSiteKey: 'k1' }, codeBlockLang: '  ', frontmatterKey: 'formular' },
  { forms: { x: { template: 'contact', anonymous: false, pageContext: true } }, codeBlockLang: 'qf', frontmatterKey: '' }
]
const lift = (v) => (v === null ? undefined : v)
const forms = optionSets.map((options) => {
  const o = lift(options)
  const list = f.formsOf(o)
  const ids = list.map(([id]) => id)
  return {
    options,
    forms: list,
    perForm: list.map(([id, def]) => ({ id, effective: f.effectiveForm(def), usesTemplate: f.usesTemplateFields(def),
      transport: f.transportKindOf(def, o), encryption: f.encryptionModeOf(def), anonymous: f.isAnonymous(def), embed: f.embedSnippets(id, o) })),
    renamed: ids.map((id) => ({ id, to: `${id}-neu`, options: f.renameForm(o ?? {}, id, `${id}-neu`) }))
      .concat(ids.length > 1 ? [{ id: ids[0], to: ids[1], options: f.renameForm(o ?? {}, ids[0], ids[1]) }] : []),
    removed: ids.map((id) => ({ id, options: f.removeForm(o ?? {}, id) })),
    duplicated: ids.map((id) => ({ from: id, ...f.duplicateForm(o ?? {}, id) })).concat([{ from: 'none', ...f.duplicateForm(o ?? {}, 'none') }]),
    withForm: [f.withForm(o ?? {}, ids[0] ?? 'neu', { title: 'T' }), f.withForm(o ?? {}, '0', { title: 'Null' })],
    captcha: f.captchaNeeds(o, f.resolvedGlobal(schema, o, 'spam')),
    globals: { spam: f.resolvedGlobal(schema, o, 'spam'), transport: f.resolvedGlobal(schema, o, 'transport') }
  }
})

const texts = [['x', 'de'], [{ en: 'E', de: 'D' }, 'de'], [{ en: 'E', de: 'D' }, 'de-AT'], [{ en: 'E', 'de-AT': 'A', de: 'D' }, 'DE-at'],
  [{ en: 'E', 'de_CH': 'C' }, 'de'], [{ fr: 'F', en: 7 }, 'de'], [{}, 'de'], [7, 'de'], [null, 'de'], [{ EN: 'X' }, 'en-us']]
  .map(([text, lang]) => ({ text, lang, result: f.textIn(text, lang) }))
const ids = ['', 'a', 'A', '-a', 'a-', 'kontakt', 'ä', '1', 'a b', 'a_b', 'abc\n'].flatMap((id) =>
  [undefined, 'kontakt'].map((own) => ({ id, own: own ?? null, problem: f.formIdProblem(id, ['kontakt', 'umfrage'], own) })))
const names = ['', 'a', '1a', 'a-b_c', 'a b', 'form', 'pageTitle', 'name', 'Ä', 'x\n'].map((name) => ({ name, problem: f.fieldNameProblem(name, ['name', 'email']) }))
const freeIds = ['Kontakt', 'kontakt', 'Über uns!', '---', '', 'a--b', '😀x', 'umfrage', 'a  !b', 'ä😀b'].map((base) => ({ base, id: f.freeId(base, ['kontakt', 'kontakt-2', 'umfrage', 'form']) }))
const freeNames = ['name', 'email', 'Über', '1abc', '___', '', 'form', 'a-b', 'x y'].map((base) => ({ base, name: f.freeFieldName(base, ['name', 'name2', 'email']) }))
const newForms = ['contact', 'empty', 'survey'].map((start) => ({ start, def: f.newForm(start, 'Nachricht') }))

// ── fields and conditions ───────────────────────────────────────────────────────────────────────
const fieldList = [
  { type: 'text', name: 'n', autocomplete: 'name', label: { de: 'Name' } }, { type: 'text', name: 't', autocomplete: 'off' },
  { type: 'email', name: 'e' }, { type: 'tel', name: 'p' }, { type: 'pgpKey', name: 'k' }, { type: 'textarea', name: 'm', autocomplete: 'street-address' },
  { type: 'select', name: 's', options: [{ value: 'a', label: { en: 'A', de: 'Ah' } }, { value: '', label: 'x' }, 'junk', { value: 'b' }] },
  { type: 'radio', name: 'r', options: 'nope' }, { type: 'checkboxes', name: 'c', options: [{ value: 'x', label: 'X' }] },
  { type: 'checkbox', name: 'cb', text: { de: 'Ja' } }, { type: 'scale', name: 'sc', min: 1, max: 5 }, { type: 'scale', name: 'sc2', min: 1.5, max: 3 },
  { type: 'scale', name: 'sc3', min: 0, max: 25 }, { type: 'scale', name: 'sc4', min: 3, max: 1 }, { type: 'consent', name: 'ok', text: 'Einverstanden' },
  { type: 'pageBreak', title: { de: 'Schritt 2' }, showIf: { field: 's', equals: 'a' } }, { type: 'hidden', name: 'h' },
  { type: 'text', name: 'cond', showIf: { field: 'r', equals: ['x', '', 3, 'y'] } }, { type: 'text', name: 'bad', showIf: { field: '', equals: 'a' } },
  { type: 'text', name: 'bad2', showIf: { field: 's', equals: [] } }, { type: 'text', name: 'bad3', showIf: 'x' }, { type: 'select', label: 'no name' }
]
const fields = fieldList.map((field) => ({ field, personal: f.isPersonalField(field), showIf: u(f.showIfOf(field)), controller: f.isController(field),
  values: f.controllerValues(field, 'de'), label: u(f.fieldLabel(field, 'de')), pageBreak: f.isPageBreak(field) }))
const renamedConditions = f.renameInConditions(fieldList, 's', 'auswahl')
const showIfValues = [['s', ['a']], ['s', ['a', 'b']], ['s', []]].map(([field, equals]) => f.showIfValue(field, equals))

// ── the plugin's check, placed ──────────────────────────────────────────────────────────────────
const messages = [
  'forms.kontakt.fields[2].pattern: kein gültiger Ausdruck', 'forms.kontakt: no fields given', 'forms.kontakt: keine Felder angegeben',
  'forms.kontakt.recipient: unknown key', 'forms.kontakt.transport.kind: x', 'forms.kontakt.encryption: mode', 'forms.kontakt.spam.pow: 3',
  'forms.kontakt.colour: unknown', 'forms.kontakt.title: missing', 'forms.kontakt: needs a title', 'forms.kontakt.fields: no fields',
  'forms.kontakt.fieldsX: what', 'forms.my-form.anonymous: yes', 'forms.Kontakt.title: upper', 'forms.kontakt.fields[x].a: b',
  'keys.boxi: expired', 'keys: none', 'transport.url: missing', 'spam.pow: too low', 'layoutForm: unknown form', 'language: de',
  'texts.de.submit: x', 'frontmatterKey: empty', 'codeBlockLang: x', 'something else', 'forms.kontakt.fields[12]', 'forms.kontakt.subject:x',
  'forms.kontakt.pageContext\tmeh', 'forms.kontakt.$weird.x: y', 'forms.kontakt: no fieldsets'
].map((text) => {
  const placed = f.placeMessage(text)
  return { text, placed, part: f.partOf(placed) }
})

// ── texts ───────────────────────────────────────────────────────────────────────────────────────
const entryKeys = [[{ de: {}, en: {} }, 'de'], [{ 'de-DE': {} }, 'de'], [{ DE: {} }, 'de'], [{ 'de-AT': {}, de: {} }, 'de'], [{}, 'fr'], [{ en_US: {} }, 'en-gb']]
  .map(([texts, code]) => ({ texts, code, key: f.entryKey(texts, code) }))

// ── keys (FormsKeys.tsx) ────────────────────────────────────────────────────────────────────────
const keysFile = join(control, 'src/routes/Plugins/FormsKeys.tsx')
const keysLib = await loadQuartzControl(control, 'src/routes/Plugins/FormsKeys.tsx', {
  react: 'export const useState = (v) => [v, () => {}]; export default {}',
  'react-i18next': 'export const useTranslation = () => ({ t: (k) => k })',
  'lucide-react': 'export const FileUp = null, KeyRound = null, Trash2 = null',
  '../../components/ui': 'const C = () => null; export const Button = C, Field = C, IconButton = C, SegmentedControl = C, TextInput = C',
  '../../components/ErrorSurface': 'export const formatIpcError = String',
  '../../utils/confirm': 'export const confirmDialog = async () => false',
  '../ProjectLayout': 'export const useProject = () => ({})'
}, { expose: ['withoutKey'] })
// The name rule stands inside the component; it is read from the file, not copied.
const nameRule = /const nameProblem = (.*)\n/.exec(readFileSync(keysFile, 'utf8'))?.[1]
if (!nameRule) throw new Error('FormsKeys.tsx: nameProblem not found')
const nameProblemOf = new Function('name', 'keys', `return ${nameRule}`)
const keyOptions = [
  {},
  { keys: { a: { file: 'k/a.asc' }, b: { armored: 'x' } }, forms: { f1: { encryption: { mode: 'required' } }, f2: { encryption: { mode: 'optional', keys: ['a'] } },
    f3: { encryption: { mode: 'off', keys: ['a'] } }, f4: {}, f5: { encryption: { mode: 'required', keys: ['b', 'a', 5] } }, f6: 'x' } },
  { keys: { a: {} }, forms: { g: { encryption: { mode: 'required', keys: ['a'], showFingerprint: false } } }, layoutForm: 'g' },
  { forms: { h: { encryption: { mode: 'required', keys: 'a' } } } },
  { keys: [1], forms: [] }
]
const keys = keyOptions.flatMap((options) => ['a', 'b', 'c'].map((name) => ({
  options, name, using: keysLib.formsUsingKey(options, name), without: keysLib.withoutKey(options, name)
})))
const keyNames = ['', 'owner', 'a-b_C9', 'a b', 'ä', 'x'.repeat(64), 'x'.repeat(65), 'taken', 'Taken', 'a.b']
  .map((name) => ({ name, problem: nameProblemOf(name, [['taken', {}]]) }))

// ── the schema's parts ──────────────────────────────────────────────────────────────────────────
const formSchema = f.formSchema(schema)
const schemaParts = {
  formKeys: formSchema?.fields.map((x) => x.key) ?? null,
  objectKeys: Object.fromEntries(['spam', 'transport', 'keys', 'forms', 'nothing'].map((k) => [k, f.objectSchema(schema, k)?.fields.map((x) => x.key) ?? null])),
  variants: Object.fromEntries([...Object.values(f.FIELD_GROUPS).flat(), 'nope'].map((t) => [t, f.fieldVariant(formSchema, t).map((x) => x.key)])),
  defaults: Object.fromEntries(['spam', 'transport', 'frontmatterKey', 'codeBlockLang', 'layoutForm', 'language', 'nothing'].map((k) => [k, u(f.defaultOf(schema, k))]))
}

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'schema.json'), JSON.stringify(configSchema, null, 1) + '\n')
writeFileSync(join(out, 'cases.json'), JSON.stringify({
  constants: {
    readAgainst: f.FORMS_READ_AGAINST, layoutSince: f.FORMS_LAYOUT_SINCE, textsSince: f.FORMS_TEXTS_SINCE, envelopeSenderSince: f.FORMS_ENVELOPE_SENDER_SINCE,
    reserved: f.RESERVED_NAMES, templateNames: f.TEMPLATE_NAMES, templates: f.TEMPLATES, transportKinds: f.TRANSPORT_KINDS, encryptionModes: f.ENCRYPTION_MODES,
    sections: f.SECTIONS, fieldGroups: f.FIELD_GROUPS, sameShape: f.SAME_SHAPE, inputKeys: f.INPUT_KEYS, personalAutocomplete: f.PERSONAL_AUTOCOMPLETE,
    controllerTypes: f.CONTROLLER_TYPES, formKeys: [...f.FORM_KEYS], relayOwnWords: [...f.RELAY_OWN_WORDS]
  },
  forms, texts, ids, names, freeIds, freeNames, newForms, fields, renamedConditions, showIfValues, messages, entryKeys, schemaParts, keys, keyNames
}, null, 1) + '\n')
console.log(`forms-options: ${forms.length} option sets, ${fields.length} fields, ${messages.length} messages`)
