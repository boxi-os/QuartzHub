#!/usr/bin/env node
// Golden files for the option schema, made by QuartzControl's own code: shared/quartzPluginName.ts,
// shared/pluginOptionSchema.ts (the normalizer) and electron/main/services/pluginSchemaService.ts
// (where a plugin's package is, what it says about its options, the default frame of a page-type
// plugin, a theme's theme.json). The Swift tests (OptionSchemaTests, PluginSchemaReaderTests) run
// the same inputs and compare.
//
//   Runtime/node/bin/node scripts/option-schema-golden.mjs [../QuartzControl] [gui-test]
//
// Written to Fixtures/option-schema/:
//   plugin-names.json   source → quartzPluginName, isNpm-independent
//   normalizer.json     hand-made JSON Schemas, optionSchemas, defaults, values and conditions
//   handmade/case.json  a project tree of hand-made packages (package.json, .d.ts, theme.json,
//                       page-type entries) and what each query answers
//   real/               package.json and dist/**/*.d.ts of every plugin gui-test uses, the entry
//                       files of four page-type plugins, and real/case.json with the answers
//
// The answers are canonical (scripts/lib/option-schema-canon.mjs): a field's keys in one fixed
// order. QuartzControl builds a field in an order that depends on the path it took (a schema field
// and an inferred one differ), and no reader of the object looks at that order; Swift has a struct.
// Values from the plugin (`default`, `when`) keep their own order.
//
// Stand-ins: mainT answers key and arguments as JSON (commonStubs). Nothing else: typescript and
// the rest are QuartzControl's.
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { canonResult, canonSchema } from './lib/option-schema-canon.mjs'
import { layOut } from './lib/tree.mjs'
import { parse as parseYaml } from '../Helpers/node_modules/yaml/dist/index.js'
import { cpSync, existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { spawnSync } from 'node:child_process'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const guiTest = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte', 'gui-test'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'option-schema')

const names = await loadQuartzControl(control, 'shared/quartzPluginName.ts', {})
const normalizer = await loadQuartzControl(control, 'shared/pluginOptionSchema.ts', {})
const service = await loadQuartzControl(control, 'electron/main/services/pluginSchemaService.ts', commonStubs)

rmSync(out, { recursive: true, force: true })
mkdirSync(out, { recursive: true })
const write = (path, value) => {
  mkdirSync(dirname(join(out, path)), { recursive: true })
  writeFileSync(join(out, path), JSON.stringify(value, null, 1) + '\n')
}

// ── plugin names ────────────────────────────────────────────────────────────────────────────────

const sources = [
  '@quartz-community/explorer', 'explorer', 'a/b', '@scope/x/', '', '-x',
  'github:boxi-os/quartz-forms', 'github:a/b#main', 'github:a/b/', 'github:', 'github:a/b/c#x#y',
  'git+https://github.com/a/b.git', 'git+https://github.com/a/b.git#v1', 'git+ssh://git@github.com:a/b',
  'https://github.com/a/b', 'https://github.com/a/b.git/', 'https://x', 'https://', 'https://h/a.b.git',
  'https://h/a/git+b', 'https://h/b\n', 'git+https://h/b.gitx',
  '/abs/path/frame-a', '/abs/path/frame-a/', '/abs/path/frame-a//', '/', './rel', '../up/x', '..', '.',
  'C:\\Users\\x\\plugins\\baz', 'c:/x/y', 'C:x', 'Ä/ü', 'name with space',
  { repo: 'github:a/b' }, { repo: 'github:a/b', name: 'own' }, { repo: '/abs/frame', name: '' }, { repo: 'https://h/r.git' },
  { repo: '@scope/pkg' }, { repo: '../x', name: '../../y' }
]
write('plugin-names.json', sources.map((source) => ({ source, name: names.quartzPluginName(source) })))

// ── the normalizer ──────────────────────────────────────────────────────────────────────────────

const N = normalizer
const enumField = { type: 'enum', values: ['a', 'b'] }
const everything = {
  type: 'object',
  $defs: {
    title: { type: 'string', title: 'Title from $defs', description: 'shared', 'x-quartz-widget': 'markdown' },
    'a b': { type: 'boolean' },
    loop: { type: 'object', properties: { child: { $ref: '#/$defs/loop' }, n: { type: 'number' } } },
    hop: { $ref: '#/$defs/title' },
    asEnum: { enum: [1, 2] }
  },
  definitions: { old: { type: 'integer', minimum: 0 } },
  properties: {
    b: { type: 'boolean', default: true, title: 'B', description: 'switch' },
    10: { type: 'string' },
    2: { type: 'string' },
    s: { type: 'string', title: 5, description: null, default: null },
    n: { type: 'number', minimum: 1, maximum: 9.5, default: 3 },
    int: { type: 'integer', minimum: '0' },
    e: { enum: ['x', 1, true] },
    eMixed: { enum: ['x', { no: 1 }] },
    eEmpty: { enum: [] },
    flat: enumField,
    flatNoValues: { type: 'enum' },
    c: { const: 'only' },
    cNull: { const: null, type: 'string' },
    one: { oneOf: [{ const: 'a' }, { const: 'b' }, { enum: ['b', 'c'] }] },
    any: { anyOf: [{ type: 'string' }, { type: 'number' }, { type: 'string' }] },
    anyOne: { anyOf: [{ type: 'string' }, { type: 'string' }] },
    anyNone: { anyOf: [] },
    both: { oneOf: [{ type: 'string' }], anyOf: [{ type: 'number' }] },
    nested: { anyOf: [{ anyOf: [{ type: 'string' }, { type: 'boolean' }] }, { type: 'number' }] },
    nullable: { type: ['string', 'null'] },
    multi: { type: ['string', 'number', 'null'], minimum: 2 },
    onlyNull: { type: ['null'] },
    twice: { type: ['string', 'string'] },
    odd: { type: ['string', 5] },
    weird: { type: 5 },
    weird2: { type: [['a', 'b']] },
    weird3: { type: {} },
    weird4: { type: [null] },
    weird5: { type: 1e21 },
    unknown: { type: 'color' },
    arr: { type: 'array', items: { type: 'string' } },
    tuple: { type: 'array', items: [{ type: 'string' }] },
    arrBare: { type: 'array' },
    arrNull: { type: 'array', items: null },
    arrDeep: { type: 'array', items: { type: 'array', items: { type: 'object', properties: { x: { type: 'string' } } } } },
    obj: { type: 'object', properties: { x: { type: 'string' }, y: { type: 'object', properties: { z: { type: 'boolean' } } } } },
    objEmpty: { type: 'object' },
    objPropsArray: { type: 'object', properties: ['x'] },
    rec: { type: 'object', additionalProperties: { type: 'string' } },
    recTrue: { type: 'object', additionalProperties: true },
    recFalse: { type: 'object', additionalProperties: false },
    recNum: { type: 'object', additionalProperties: 5 },
    recLang: { additionalProperties: { type: 'string' }, 'x-quartz-keys': 'languages' },
    recBadKeys: { type: 'object', additionalProperties: { type: 'string' }, 'x-quartz-keys': 'pages' },
    keysOnObject: { type: 'object', properties: { a: { type: 'string' } }, 'x-quartz-keys': 'pages' },
    objRest: { type: 'object', properties: { a: { type: 'string' } }, additionalProperties: { type: 'number' } },
    anything: {},
    yes: true,
    no: false,
    nothing: null,
    text: 'string',
    noted: { 'x-quartz-note': 'why not' },
    notedNum: { 'x-quartz-note': 5 },
    described: { description: 'only words', title: 't', default: 1 },
    allOf: { allOf: [{ type: 'string' }] },
    not: { not: { type: 'string' } },
    if: { if: { type: 'string' }, then: {} },
    pattern: { patternProperties: { '^x': { type: 'string' } } },
    noType: { minLength: 2 },
    ref: { $ref: '#/$defs/title' },
    refBeside: { $ref: '#/$defs/title', title: 'Beside wins', 'x-quartz-widget': 'html' },
    refOld: { $ref: '#/definitions/old' },
    refSpace: { $ref: '#/$defs/a%20b' },
    refMissing: { $ref: '#/$defs/none' },
    refOther: { $ref: '#/properties/b' },
    refRemote: { $ref: 'https://example.com/s.json' },
    refNum: { $ref: 5 },
    refHop: { $ref: '#/$defs/hop' },
    loop: { $ref: '#/$defs/loop' },
    refEnum: { $ref: '#/$defs/asEnum' },
    deep: [...Array(18)].reduce((inner) => ({ type: 'object', properties: { d: inner } }), { type: 'string' }),
    whenOk: { type: 'string', 'x-quartz-when': { b: true, 'obj.x': ['a', 1], n: 3 } },
    whenEmpty: { type: 'string', 'x-quartz-when': {} },
    whenBad: { type: 'string', 'x-quartz-when': { b: { x: 1 } } },
    whenBadList: { type: 'string', 'x-quartz-when': { b: [true, null] } },
    whenArray: { type: 'string', 'x-quartz-when': ['b'] },
    whenNull: { type: 'string', 'x-quartz-when': null },
    grouped: { type: 'string', 'x-quartz-group': 'G', 'x-quartz-order': 2, 'x-quartz-advanced': true },
    groupedBad: { type: 'string', 'x-quartz-group': 1, 'x-quartz-order': '2', 'x-quartz-advanced': 'yes' },
    snippet: { type: 'string', 'x-quartz-widget': 'snippetFile', 'x-quartz-dir-option': 'dir' },
    snippetBare: { type: 'string', 'x-quartz-widget': 'snippetFile', 'x-quartz-dir-option': 3 },
    glob: { type: 'string', 'x-quartz-widget': 'glob' },
    widgetUnknown: { type: 'string', 'x-quartz-widget': 'color' },
    widgetNum: { type: 'string', 'x-quartz-widget': 7 },
    unknownKeyword: { type: 'string', 'x-quartz-colour': 'red', 'x-quartz-hint': 1 },
    l10n: {
      enum: ['a', 'b'],
      'x-quartz-l10n': {
        de: { title: 'Titel', description: 'Text', group: 'Gruppe', enum: { a: 'A', b: 2, c: 'C' } },
        en: { title: 3, enum: [] },
        fr: 'non',
        it: {}
      }
    },
    l10nBad: { type: 'string', 'x-quartz-l10n': 'de' },
    defaultsObj: { type: 'object', properties: { a: { type: 'string', default: 'x' } }, default: { a: 'y', z: 1 } }
  }
}

const normalizerCases = [
  { name: 'json-not-object', op: 'json', schema: 'x' },
  { name: 'json-array', op: 'json', schema: [] },
  { name: 'json-empty', op: 'json', schema: {} },
  { name: 'json-object-without-properties', op: 'json', schema: { type: 'object' } },
  { name: 'json-root-array', op: 'json', schema: { type: 'array', items: { type: 'string' } } },
  { name: 'json-root-enum', op: 'json', schema: { enum: ['a'] } },
  { name: 'json-root-note', op: 'json', schema: { type: 'object', properties: 5, allOf: [] } },
  { name: 'json-root-record', op: 'json', schema: { additionalProperties: { type: 'string' } } },
  { name: 'json-root-ref', op: 'json', schema: { $ref: '#/$defs/o', $defs: { o: { type: 'object', properties: { a: { type: 'string' } } } } } },
  { name: 'json-everything', op: 'json', schema: everything },
  // QuartzControl throws on these two (URIError; RangeError from annotationsOf following the alias
  // forever): recorded as such, Swift answers with a note (OptionSchemaTests).
  { name: 'json-ref-bad-escape', op: 'json', schema: { type: 'object', $defs: { x: {} }, properties: { a: { $ref: '#/$defs/%E0%A4%A' } } } },
  { name: 'json-ref-alias-loop', op: 'json', schema: { type: 'object', $defs: { a: { $ref: '#/$defs/a' } }, properties: { a: { $ref: '#/$defs/a' } } } },
  { name: 'json-dts-source', op: 'json', schema: { type: 'object', properties: { a: { type: 'string' } } }, source: 'dts' },
  { name: 'flat-not-object', op: 'flat', schema: ['a'] },
  { name: 'flat-empty', op: 'flat', schema: {} },
  { name: 'flat-community', op: 'flat', schema: { mode: { type: 'enum', values: ['a', 'b'], default: 'a' }, size: { type: 'number' }, ref: { $ref: '#/$defs/x' } } },
  {
    name: 'defaults-merge', op: 'defaults',
    schema: {
      type: 'object',
      properties: {
        s: { type: 'string' },
        withDefault: { type: 'string', default: 'schema' },
        obj: { type: 'object', properties: { a: { type: 'string' }, b: { type: 'number' } } },
        e: { enum: ['a', 'b'] },
        u: { anyOf: [{ type: 'string' }, { type: 'number' }] },
        j: {}
      }
    },
    defaults: {
      s: 5, withDefault: 'defaults', obj: { a: 'x', c: true, d: { e: [1, 2] } }, e: 'c', u: true, j: { any: 1 },
      bool: false, num: 1.5, str: 'x', strs: ['a', 'b'], nums: [1, 2], mixed: [1, 'a'], none: [], emptyObj: {}, nul: null,
      deepObj: { a: { b: { c: 'd' } } }, 0: 'index key'
    }
  },
  { name: 'defaults-not-object', op: 'defaults', schema: { type: 'object', properties: { a: { type: 'string' } } }, defaults: ['x'] },
  { name: 'defaults-object-becomes-union', op: 'defaults', schema: { type: 'object', properties: { o: { type: 'object', properties: { a: { type: 'string' } } } } }, defaults: { o: 'flat' } },
  { name: 'from-defaults', op: 'fromDefaults', defaults: { a: 1, b: { c: 'x' } } },
  { name: 'from-defaults-empty', op: 'fromDefaults', defaults: {} },
  { name: 'from-defaults-not-object', op: 'fromDefaults', defaults: 'x' },
  {
    name: 'present-keys', op: 'present',
    schema: { type: 'object', properties: { a: { type: 'string' }, o: { type: 'object', properties: { x: { type: 'boolean' } } }, n: { type: 'number', default: 1 } } },
    defaults: { d: 'from defaults' },
    values: { a: ['not', 'a', 'string'], o: { x: true, y: { deep: 1 } }, n: 2, d: 3, set: 'by user', obj: { k: 'v' } }
  },
  { name: 'present-not-object', op: 'present', schema: { type: 'object', properties: { a: { type: 'string' } } }, values: 'x' },
  {
    name: 'conditions', op: 'conditions',
    schema: {
      type: 'object',
      properties: {
        variant: { enum: ['tree', 'tabs'], default: 'tree' },
        box: { type: 'object', properties: { mode: { type: 'string', default: 'inner' }, plain: { type: 'string' } }, default: { mode: 'outer', other: 'o' } },
        n: { type: 'number' },
        flag: { type: 'boolean', default: false }
      }
    },
    checks: [
      { when: null, values: {} },
      { when: { variant: 'tree' }, values: {} },
      { when: { variant: 'tabs' }, values: {} },
      { when: { variant: ['tabs', 'tree'] }, values: {} },
      { when: { variant: 'tabs' }, values: { variant: 'tabs' } },
      { when: { 'box.mode': 'inner' }, values: {} },
      { when: { 'box.mode': 'outer' }, values: {} },
      { when: { 'box.other': 'o' }, values: {} },
      { when: { 'box.mode': 'x' }, values: { box: { mode: 'x' } } },
      { when: { 'box.plain': 'p' }, values: {} },
      { when: { n: 1 }, values: { n: 1 } },
      { when: { n: 1 }, values: {} },
      { when: { flag: false }, values: {} },
      { when: { flag: false, variant: 'tabs' }, values: {} },
      { when: { missing: 'x' }, values: {} },
      { when: { variant: 'tree' }, values: 'not an object' },
      { when: { box: 'x' }, values: { box: { mode: 'x' } } },
      { when: { '': 'x' }, values: { '': 'x' } },
      { when: { 'a.b': 1 }, values: { a: { b: 1 } } },
      { when: { 'a.b': 1 }, values: { a: 5 } },
      { when: {}, values: {} }
    ]
  },
  {
    name: 'paths', op: 'paths',
    checks: [
      { obj: { a: 1, b: 2 }, path: ['a'], value: 3 },
      { obj: { a: 1, b: 2 }, path: ['c'], value: 3 },
      { obj: { a: 1, b: 2 }, path: ['a'] },
      { obj: { a: 1 }, path: [], value: 3 },
      { obj: { byLang: { en: { title: 'x' } }, z: 1 }, path: ['byLang', 'en', 'title'] },
      { obj: { byLang: { en: { title: 'x', d: 1 } } }, path: ['byLang', 'en', 'title'] },
      { obj: { a: 'flat' }, path: ['a', 'b'], value: 1 },
      { obj: { a: 'flat' }, path: ['a', 'b'] },
      { obj: { a: {}, b: 1 }, path: ['b'] },
      { obj: { 1: 'x', a: 1 }, path: ['0'], value: 'y' },
      { obj: { a: { b: 1 } }, path: ['a', 'c', 'd'], value: [1] }
    ],
    gets: [
      { obj: { a: { b: { c: 1 } } }, path: ['a', 'b', 'c'] },
      { obj: { a: { b: [1] } }, path: ['a', 'b', '0'] },
      { obj: { a: 1 }, path: [] },
      { obj: 'x', path: ['a'] },
      { obj: { a: null }, path: ['a'] }
    ],
    prunes: [
      { a: {}, b: { c: {}, d: 1 }, e: [{}], f: { g: { h: {} } }, i: null }
    ]
  }
]

const recordNormalizer = (c) => {
  const normalize = () => (c.op === 'flat' ? N.normalizeOptionSchema(c.schema) : N.normalizeJsonSchema(c.schema, c.source ?? 'configSchema'))
  switch (c.op) {
    case 'json':
    case 'flat':
      return canonSchema(normalize())
    case 'defaults':
      return canonSchema(N.applyDefaults(normalize(), c.defaults))
    case 'fromDefaults':
      return canonSchema(N.schemaFromDefaults(c.defaults))
    case 'present': {
      const base = c.defaults ? N.applyDefaults(normalize(), c.defaults) : normalize()
      return canonSchema(N.withPresentKeys(base, c.values))
    }
    case 'conditions': {
      const fields = normalize().fields
      return c.checks.map((k) => N.evaluateCondition(k.when ?? undefined, k.values, fields))
    }
    case 'paths':
      return {
        sets: c.checks.map((k) => N.setAtPath(k.obj, k.path, k.value)),
        // undefined is not JSON: an absent value is written as {"absent": true}.
        gets: c.gets.map((k) => { const v = N.getAtPath(k.obj, k.path); return v === undefined ? { absent: true } : { value: v } }),
        prunes: c.prunes.map((k) => N.pruneEmptyObjects(k))
      }
  }
}
const recordOrThrow = (c) => { try { return { expected: recordNormalizer(c) } } catch (e) { return { throws: e.name } } }
write('normalizer.json', normalizerCases.map((c) => ({ ...c, ...recordOrThrow(c) })))

// ── packages: hand-made ─────────────────────────────────────────────────────────────────────────

const pkg = (quartz, extra = {}) => JSON.stringify({ name: 'x', version: '1.0.0', ...extra, ...(quartz === undefined ? {} : { quartz }) })
const P = '.quartz/plugins'
const NM = 'node_modules'
const dts = {
  // Every branch of typeToSchema, rooted by the constructor's type argument.
  [`${P}/dts-all/package.json`]: pkg({}),
  [`${P}/dts-all/dist/index.d.ts`]: `
import type { X } from "./other"
export interface Base { inherited: string; overridden: number }
/** A shape */
export interface AllOptions extends Base, Missing {
  /** A switch. */
  bool: boolean
  str: string
  num: number
  anyValue: any
  unknownValue: unknown
  paren: (string)
  ro: readonly string[]
  litS: "a"
  litN: 1.5
  litT: true
  litF: false
  litNull: null
  opt?: string | undefined
  nullable: string | null
  en: "a" | "b" | 3 | true
  mixed: "a" | number
  arr: string[]
  gen: Array<number>
  roArr: ReadonlyArray<boolean>
  genBare: Array
  rec: Record<string, number>
  recBare: Record<string>
  part: Partial<Inner>
  req: Required<Inner>
  partBare: Partial
  omit: Omit<Inner, "b">
  pick: Pick<Inner, "a" | "c">
  pickBad: Pick<Inner, keyof Inner>
  lit: { x: string; y?: { z: boolean } }
  fn: (a: string) => void
  method(a: string): void
  both: Inner & { extra: string }
  bothBad: Inner & string
  undeclared: Undeclared
  imported: X
  self: AllOptions
  ns: ns.Inner
  tuple: [string, number]
  keys: keyof Inner
  index: { [key: string]: boolean }
  "quoted-name": string
  42: string
  [Symbol.iterator]: string
  noType
  deep: D1
  alias: InnerAlias
  layout: LayoutBoxOptions
}
interface Inner { a: string; b: number; c?: boolean }
type InnerAlias = Inner
interface LayoutBoxOptions { title: string; byLang: Record<string, Omit<LayoutBoxOptions, "byLang">> }
type D1 = { d: D2 }
type D2 = { d: D3 }
type D3 = { d: D4 }
type D4 = { d: D5 }
type D5 = { d: D6 }
type D6 = { d: D7 }
type D7 = { d: D8 }
type D8 = { d: string }
declare const Plugin: QuartzTransformerPlugin<Partial<AllOptions>>
export default Plugin
`,
  // Votes: the type most constructors name wins over an …Options interface.
  [`${P}/dts-votes/package.json`]: pkg({ version: '2.0.0-q' }),
  [`${P}/dts-votes/dist/a.d.ts`]: 'export interface BigOptions { a: string; b: string; c: string }\nexport interface Voted { v: boolean }\ndeclare const A: QuartzComponentConstructor<Voted>\ndeclare const B: QuartzEmitterPlugin<Readonly<Voted>>, C: QuartzFilterPlugin<Other>\n',
  [`${P}/dts-votes/dist/sub/b.d.ts`]: 'export interface Other { o: number }\ndeclare const D: QuartzFilterPlugin<Other>\ndeclare const E: NotQuartzPlugin<BigOptions>\n',
  // No votes: the outermost …Options, not Resolved…, most members.
  [`${P}/dts-outermost/package.json`]: pkg({}),
  [`${P}/dts-outermost/dist/index.d.ts`]: 'export interface SeoOptions { hreflang: boolean; ogLocale: boolean; xDefault: string }\nexport interface MultilanguageOptions { languages: string[]; seo: SeoOptions }\nexport interface ResolvedPluginOptions { a: string; b: string; c: string; d: string }\nexport interface EmptyOptions { method(): void }\n',
  [`${P}/dts-cycle/package.json`]: pkg({}),
  [`${P}/dts-cycle/dist/index.d.ts`]: 'export interface AOptions { b: BOptions }\nexport interface BOptions { a: AOptions; n: number }\n',
  [`${P}/dts-none/package.json`]: pkg({}),
  [`${P}/dts-none/dist/index.d.ts`]: 'export declare function f(): void\n',
  [`${P}/dts-alias-root/package.json`]: pkg({}),
  [`${P}/dts-alias-root/dist/index.d.ts`]: 'type Opts = { a: string } & { b: number }\ndeclare const P: QuartzPlugin<Opts>\n',
  [`${P}/dts-alias-scalar/package.json`]: pkg({}),
  [`${P}/dts-alias-scalar/dist/index.d.ts`]: 'type Opts = string\ndeclare const P: QuartzPlugin<Opts>\n',
  [`${P}/dts-skips-node-modules/package.json`]: pkg({}),
  [`${P}/dts-skips-node-modules/dist/node_modules/x/index.d.ts`]: 'export interface HiddenOptions { h: string }\n',
  [`${P}/dts-skips-node-modules/dist/index.d.ts`]: 'export interface ShownOptions { s: string }\n',
  [`${P}/dts-no-dist/package.json`]: pkg({ defaultOptions: { only: 'defaults' } })
}
const handmadeTree = {
  ...dts,
  [`${NM}/@scope/npm-plugin/package.json`]: pkg({ configSchema: { type: 'object', properties: { a: { type: 'string', default: 's' } } }, defaultOptions: { a: 'd', b: 2 }, category: ['emitter', 5, 'component'] }),
  [`${NM}/plain/package.json`]: pkg({ optionSchema: { x: { type: 'boolean' } }, category: 'transformer' }, { version: '3.1.4' }),
  [`${NM}/no-quartz/package.json`]: JSON.stringify({ version: 7 }),
  [`${NM}/quartz-array/package.json`]: JSON.stringify({ quartz: ['x'], version: '1' }),
  [`${NM}/versions/package.json`]: pkg({ version: 2 }, { version: '1.0.0' }),
  [`${NM}/fallbacks/package.json`]: pkg({ configSchema: { type: 'object' }, optionSchema: {}, defaultOptions: { d: true } }),
  // For the check: configSchema wins, the optionSchema key it lacks is invisible.
  [`${NM}/both-schemas/package.json`]: pkg({ configSchema: { type: 'object', properties: { a: { type: 'string' } } }, optionSchema: { a: { type: 'string' }, b: { type: 'number' } }, defaultOptions: { a: 'x' } }),
  // The project's config, for QuartzControl's check:option-schema (handmade/check.txt).
  'quartz.config.yaml': [
    'configuration:', '  pageTitle: Check', 'plugins:',
    '  - source: github:a/dts-all', '    enabled: true', '    options: { bool: true, unknownKey: 1, nested: { a: 1 } }',
    '  - source: github:a/dts-all', '    enabled: false',
    '  - source: "@scope/npm-plugin"', '    options: { a: x, extra: [1, 2] }',
    '  - source: github:a/dts-outermost', '    options: { hreflang: true }',
    '  - source: github:a/dts-cycle',
    '  - source: broken',
    '  - options: {}',
    '  - just a string',
    '  - source: plain', '    enabled: false',
    '  - source: not-installed', '    options: { k: 1 }',
    '  - source: with-dts', '  - source: fallbacks', '  - source: both-schemas',
    '  - source: { repo: "github:x/y", name: dts-votes }', '    options: { v: "not a bool" }'
  ].join('\n') + '\n',
  [`${NM}/fallback-to-optionschema/package.json`]: pkg({ configSchema: { type: 'object', properties: {} }, optionSchema: { o: { type: 'string' } }, defaultOptions: { o: 'x', p: 1 } }),
  [`${NM}/configschema-null/package.json`]: pkg({ configSchema: null, optionSchema: { o: { type: 'string' } } }),
  [`${NM}/nothing/package.json`]: pkg({ defaultOptions: {} }),
  [`${NM}/defaults-array/package.json`]: pkg({ defaultOptions: [1] }),
  [`${NM}/broken/package.json`]: '{"quartz": ',
  [`${NM}/array-json/package.json`]: '[1, 2]',
  [`${NM}/null-json/package.json`]: 'null',
  [`${NM}/is-a-dir/package.json`]: { dir: 0o755 },
  [`${NM}/too-large/package.json`]: { fill: 1024 * 1024 + 1 },
  [`${NM}/exactly-max/package.json`]: { fill: 1024 * 1024 },
  [`${NM}/not-a-dir`]: 'a file where the package should be',
  [`${NM}/with-dts/package.json`]: pkg({ optionSchema: {} }),
  [`${NM}/with-dts/dist/index.d.ts`]: 'export interface WOptions { w: "x" | "y" }\n',
  // Page types.
  [`${NM}/@quartz-community/pt-object/package.json`]: pkg({ category: ['pageType', 'component'] }, { exports: { '.': { types: './dist/index.d.ts', import: './dist/index.js' } } }),
  [`${NM}/@quartz-community/pt-object/dist/index.js`]: 'const rehype = { frame: null, iframe: "iframe" };\nconst tags = ["frame", "noframes"];\nexport default () => ({ name: "x", match: m, frame: "canvas", body: b });\n',
  [`${NM}/@quartz-community/pt-string-export/package.json`]: pkg({ category: ['pageType'] }, { exports: { '.': './lib/entry.js' } }),
  [`${NM}/@quartz-community/pt-string-export/lib/entry.js`]: 'export const a = { "match": 1, "frame": \'quoted\' }\n',
  [`${NM}/@quartz-community/pt-main/package.json`]: pkg({ category: ['pageType'] }, { main: 'main.js' }),
  [`${NM}/@quartz-community/pt-main/main.js`]: 'const first = { frame: "no-match-here" }\nconst second = { match, frame: `template` }\nconst third = { match, frame: "third" }\n',
  [`${NM}/@quartz-community/pt-nested/package.json`]: pkg({ category: ['pageType'] }, { main: 'i.js' }),
  [`${NM}/@quartz-community/pt-nested/i.js`]: 'function f() { return [{ inner: { match: 1, frame: "deep" } }] }\nconst later = { match: 1, frame: "later" }\n',
  [`${NM}/@quartz-community/pt-category-string/package.json`]: pkg({ category: 'notapageTypex' }, { main: 'i.js' }),
  [`${NM}/@quartz-community/pt-category-string/i.js`]: 'x = { match: 1, frame: "substring" }\n',
  [`${NM}/@quartz-community/pt-not-pagetype/package.json`]: pkg({ category: ['component'] }, { main: 'i.js' }),
  [`${NM}/@quartz-community/pt-not-pagetype/i.js`]: 'x = { match: 1, frame: "never" }\n',
  [`${NM}/@quartz-community/pt-exports-string/package.json`]: pkg({ category: ['pageType'] }, { exports: './x.js', main: 'i.js' }),
  [`${NM}/@quartz-community/pt-exports-string/i.js`]: 'x = { match: 1, frame: "from-main" }\n',
  [`${NM}/@quartz-community/pt-no-import/package.json`]: pkg({ category: ['pageType'] }, { exports: { '.': { require: './r.js' } }, main: 'i.js' }),
  [`${NM}/@quartz-community/pt-no-import/i.js`]: 'x = { match: 1, frame: "main-again" }\n',
  [`${NM}/@quartz-community/pt-no-entry/package.json`]: pkg({ category: ['pageType'] }),
  [`${NM}/@quartz-community/pt-entry-missing/package.json`]: pkg({ category: ['pageType'] }, { main: 'gone.js' }),
  [`${NM}/@quartz-community/pt-entry-dir/package.json`]: pkg({ category: ['pageType'] }, { main: 'd' }),
  [`${NM}/@quartz-community/pt-entry-dir/d`]: { dir: 0o755 },
  [`${NM}/@quartz-community/pt-syntax/package.json`]: pkg({ category: ['pageType'] }, { main: 'i.js' }),
  [`${NM}/@quartz-community/pt-syntax/i.js`]: 'x = { match: 1, frame: "despite" ,,, } }}} (((\n',
  [`${NM}/@quartz-community/pt-computed/package.json`]: pkg({ category: ['pageType'] }, { main: 'i.js' }),
  [`${NM}/@quartz-community/pt-computed/i.js`]: 'x = { match() {}, frame: "method-match" }\ny = { ["match"]: 1, frame: "computed" }\nz = { match: 1, frame: name }\n',
  [`${NM}/@quartz-community/pt-broken-json/package.json`]: '{',
  // Themes.
  [`${NM}/@quartz-themes/full/theme.json`]: JSON.stringify({ meta: { styleSettingsId: ['a', 'b'], modes: ['light', 'dark'], variations: ['v'], fonts: ['F'] }, classSettings: { k1: 'css', k2: 'css' } }),
  [`${NM}/@quartz-themes/single/theme.json`]: JSON.stringify({ meta: { styleSettingsId: 'one' }, classSettings: { k: 1 } }),
  [`${NM}/@quartz-themes/no-id/theme.json`]: JSON.stringify({ meta: { modes: ['dark'] }, classSettings: { k: 1 } }),
  [`${NM}/@quartz-themes/empty-id/theme.json`]: JSON.stringify({ meta: { styleSettingsId: [] }, classSettings: { k: 1 } }),
  [`${NM}/@quartz-themes/no-classes/theme.json`]: JSON.stringify({ meta: { styleSettingsId: 'x' } }),
  [`${NM}/@quartz-themes/broken/theme.json`]: '{',
  [`${NM}/@quartz-themes/null/theme.json`]: 'null',
  [`${NM}/@quartz-themes/empty/theme.json`]: '{}'
}

const optionQueries = [
  'github:a/dts-all', 'github:a/dts-votes', 'github:a/dts-outermost', 'github:a/dts-cycle', 'github:a/dts-none',
  'github:a/dts-alias-root', 'github:a/dts-alias-scalar', 'github:a/dts-skips-node-modules', 'github:a/dts-no-dist',
  '@scope/npm-plugin', 'plain', 'no-quartz', 'quartz-array', 'versions', 'fallbacks', 'fallback-to-optionschema',
  'configschema-null', 'nothing', 'defaults-array', 'broken', 'array-json', 'null-json', 'is-a-dir', 'too-large',
  'exactly-max', 'not-a-dir', 'with-dts', 'not-installed', 'github:a/not-installed', '/abs/dts-all', './dts-all',
  { repo: 'github:x/y', name: 'dts-votes' }, { repo: 'plain' }, { repo: '../plain' }, 'a/../../b', 'a/../plain',
  'github:a/', 'https://h/x/dts-all.git#v2', '..x', '@scope/../../../etc'
]
const frameQueries = [
  'pt-object', 'pt-string-export', 'pt-main', 'pt-nested', 'pt-category-string', 'pt-not-pagetype', 'pt-exports-string',
  'pt-no-import', 'pt-no-entry', 'pt-entry-missing', 'pt-entry-dir', 'pt-syntax', 'pt-computed', 'pt-broken-json', 'pt-absent'
].map((n) => `@quartz-community/${n}`)
const frameEntries = [
  ...frameQueries.map((source, i) => ({ name: `entry-${i}`, source })),
  { name: 'object-source', source: { repo: '@quartz-community/pt-object' } },
  { name: 'pt-object', source: '@quartz-community/pt-object' }
]
const themeQueries = ['full', 'single', 'no-id', 'empty-id', 'no-classes', 'broken', 'null', 'empty', 'absent']

function runQueries(project, queries) {
  const mask = (value) => JSON.parse(JSON.stringify(value).replaceAll(project, '@P@'))
  return {
    options: queries.options.map((source) => ({ source, expected: mask(canonResult(service.getPluginOptionSchema(project, source))) })),
    frames: queries.frames && { plugins: queries.frames, expected: service.discoverBuiltinPageTypeFrames(project, queries.frames) },
    themes: queries.themes?.map((id) => ({
      id, info: service.getThemeStyleSettingsInfo(project, id) ?? null, detail: service.getLocalThemeDetail(project, id) ?? null
    }))
  }
}

{
  const w = mkdtempSync(join(tmpdir(), 'qh-option-schema-'))
  const project = join(w, 'P')
  const tree = Object.fromEntries(Object.entries(handmadeTree).map(([k, v]) => [k, v.fill !== undefined ? 'x'.repeat(v.fill) : v]))
  layOut(project, tree, w)
  const answers = runQueries(project, { options: optionQueries, frames: frameEntries, themes: themeQueries })
  write('handmade/case.json', { tree: handmadeTree, ...answers })
  // QuartzControl's own check script over the same project, as it runs from its repository.
  const check = spawnSync(process.execPath, [join(control, 'scripts', 'check-option-schema.mjs'), project], { cwd: control, encoding: 'utf-8' })
  if (check.status !== 0) throw new Error(`check-option-schema.mjs: `)
  writeFileSync(join(out, 'handmade', 'check.txt'), check.stdout.replaceAll(project, '@P@'))
  rmSync(w, { recursive: true, force: true })
}

// ── packages: the plugins gui-test uses ─────────────────────────────────────────────────────────

{
  const config = parseYaml(readFileSync(join(guiTest, 'quartz.config.yaml'), 'utf-8'))
  const entries = (config.plugins ?? []).filter((e) => e && e.source !== undefined)
  const realOut = join(out, 'real')
  const copied = new Set()
  const copy = (from) => {
    const rel = relative(guiTest, from)
    if (copied.has(rel) || !existsSync(from)) return
    copied.add(rel)
    mkdirSync(dirname(join(realOut, rel)), { recursive: true })
    cpSync(from, join(realOut, rel))
  }
  const walk = (dir, keep) => {
    if (!existsSync(dir)) return
    for (const name of readdirSync(dir)) {
      if (name === 'node_modules') continue
      const full = join(dir, name)
      if (statSync(full).isDirectory()) walk(full, keep)
      else if (keep(name)) copy(full)
    }
  }
  const PAGE_TYPE_ENTRIES = ['canvas-page', 'content-page', 'folder-page', 'tag-page']
  for (const { source } of entries) {
    const dir = service.pluginPackageDir(guiTest, source)
    if (!dir) continue
    copy(join(dir, 'package.json'))
    walk(join(dir, 'dist'), (n) => n.endsWith('.d.ts'))
  }
  for (const name of PAGE_TYPE_ENTRIES) copy(join(guiTest, 'node_modules', '@quartz-community', name, 'dist', 'index.js'))
  // The sources as gui-test writes them; a local path (an authored frame) keeps only what quartz
  // takes from it, the last segment, under a placeholder.
  const realSources = entries.map(({ source }) => (typeof source === 'string' && source.startsWith('/') ? `/@G@/${source.split('/').filter(Boolean).pop()}` : source))
  const plugins = entries.map((e, i) => ({ name: `${i}`, source: realSources[i] }))
  const answers = runQueries(realOut, { options: realSources, frames: plugins })
  write('real/case.json', answers)
}

console.log(`${sources.length} Namen, ${normalizerCases.length} Normalisierer-Fälle, ${optionQueries.length}+${frameEntries.length}+${themeQueries.length} Handfälle, gui-test nach ${out}`)
