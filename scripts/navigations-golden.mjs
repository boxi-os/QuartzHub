#!/usr/bin/env node
// Golden file for NavigationVariants, InstanceClass and LayoutEntries, made by QuartzControl's
// own code: the variant table and the reasons an option does nothing (`navigationVariants.ts`,
// `navigationRoot` in `optionFormExtras.ts`), the classes it gives (`instanceClass.ts`) and
// duplicating with renumbering (`LayoutEditor/utils.ts`).
//
// The schema is quartz-navigations' own configSchema from gui-test (read only, copied into the
// fixture); the Swift test normalizes it with OptionSchema. `t` answers key and arguments as JSON,
// every argument as text.
//
//   Runtime/node/bin/node scripts/navigations-golden.mjs [../QuartzControl] [gui-test]
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const guiTest = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte', 'gui-test'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'navigations')

const icons = 'export const ArrowLeftRight = null, ChevronsUpDown = null, Columns3 = null, LayoutPanelTop = null, ListCollapse = null, '
  + 'ListTree = null, PanelRightOpen = null, PanelTop = null, RectangleEllipsis = null, SquareChevronDown = null'
const stubs = { 'lucide-react': icons }
const variants = await loadQuartzControl(control, 'src/routes/Plugins/navigationVariants.ts', stubs)
const cls = await loadQuartzControl(control, 'src/routes/Plugins/instanceClass.ts', stubs)
const utils = await loadQuartzControl(control, 'src/routes/LayoutEditor/utils.ts', stubs)
const extras = await loadQuartzControl(control, 'src/routes/Plugins/optionFormExtras.ts', stubs)
const schemaLib = await loadQuartzControl(control, 'shared/pluginOptionSchema.ts', {})

const t = (key, args) => JSON.stringify(args === undefined ? { key }
  : { key, args: Object.fromEntries(Object.entries(args).map(([k, v]) => [k, String(v)])) })

// ── the plugin's schema ─────────────────────────────────────────────────────────────────────────
const pkgFile = join(guiTest, '.quartz', 'plugins', 'quartz-navigations', 'package.json')
if (!existsSync(pkgFile)) throw new Error(`${pkgFile} fehlt`)
const pkg = JSON.parse(readFileSync(pkgFile, 'utf8'))
const configSchema = pkg.quartz.configSchema
const fields = schemaLib.normalizeJsonSchema(configSchema, 'configSchema').fields

// ── variants and reasons ────────────────────────────────────────────────────────────────────────
const keys = [...new Set([...fields.map((f) => f.key), ...variants.VARIANT_KEYS, 'columns', 'nothing'])]
const mobiles = [undefined, 'same', 'accordion', 'offcanvas', 'select', 'hidden', 'weird']
const noEffect = []
for (const v of variants.NAV_VARIANTS.map((x) => x.value))
  for (const mobile of mobiles)
    for (const key of keys) {
      const why = variants.noEffectReason(key, v, mobile)
      noEffect.push({ key, variant: v, mobile: mobile ?? null, none: variants.hasNoEffect(key, v, mobile), why })
    }

const optionSets = [
  {}, { variant: 'accordion' }, { variant: 'vertical' }, { variant: 'horizontal' }, { variant: 'nonsense' }, { variant: 7 },
  { variant: 'tree', mobile: 'accordion' }, { variant: 'bar', mobile: 'select' }, { variant: 'select' }, { variant: 'pager', mobile: 'accordion' },
  { variant: 'dropdown', mobile: 'offcanvas' }, { variant: 'tabs', mobile: 'hidden' }, { mobile: 'weird' }
]
const roots = []
for (const options of optionSets)
  for (const lang of ['de', 'en'])
    for (const withVariant of [false, true]) {
      const root = extras.navigationRoot(options, fields, t, lang, withVariant)
      roots.push({
        options, lang, withVariant,
        variant: variants.variantOf(options),
        reasons: Object.fromEntries(keys.map((k) => [k, root.inactiveReason(k)])),
        hide: keys.filter((k) => root.hideUnlessSet(k)),
        lead: { has: keys.filter((k) => root.lead.has(k)).concat(root.lead.has('variant') ? ['variant'] : []), title: root.lead.title, empty: root.lead.empty, note: root.lead.note ?? null }
      })
    }

// ── classes ─────────────────────────────────────────────────────────────────────────────────────
// Without `options` when there are none: a key holding undefined keeps its place in a spread but
// not in JSON, which no config read from a file has.
const opt = (options) => (options === undefined ? {} : { options })
const nav = (options, extra = {}) => ({ name: 'quartz-navigations', source: 'github:boxi-os/quartz-navigations', enabled: true, ...opt(options), ...extra })
const box = (options, extra = {}) => ({ name: 'quartz-layout-box', source: 'github:boxi-os/quartz-layout-box', enabled: true, ...opt(options), ...extra })
const plugins = [
  nav({ variant: 'tree', className: 'nav-tree' }), nav({ title: 'Menü', className: '  nav-menue  extra nav-menue-2 ' }),
  box({ file: 'snippets/Hinweis.md', className: 'layout-box-hinweis' }), box({ className: '1bad' }),
  { name: 'explorer', source: '@quartz-community/explorer', enabled: true, options: { className: 'nav-2024' } }
]
const styled = new Set(['layout-box-title', 'layout-box-hint', 'nav-styled'])
const names = ['Explorer', 'Über uns', 'Grüße & Straße', 'Ça va?', 'İstanbul', 'ΣΟΦΟΣ', '😀 Emoji', '---', '', '   ', 'a'.repeat(60),
  'x-'.repeat(25), 'Ｆｕｌｌｗｉｄｔｈ', 'ﬁle', 'tree', 'menue', 'menue-2', 'styled', '2024', 'Ⅻ', 'café́', 'Å']
const slugs = names.map((name) => ({ name, nav: cls.suggestClass('nav-', name, 'navigation', plugins, styled),
  box: cls.suggestClass('layout-box-', name, 'box', plugins, new Set()) }))
const unique = ['nav-tree', 'nav-menue', 'nav-menue-2', 'nav-menue-3', 'nav-2024', 'nav-x', 'layout-box-title', 'layout-box-hinweis-2', 'nav-styled']
  .map((c) => ({ candidate: c, result: cls.uniqueClass(c, plugins, styled) }))
const entries = [...plugins, nav(undefined), nav({ className: 7 }), nav({ title: '  ' , variant: 'mega' }), box({ file: 'a\\b\\c.tar.gz' }), box({ file: 'noext' }),
  box({ file: '.hidden' }), { name: 'x', source: 'x', enabled: true }]
const perEntry = entries.map((e) => ({ entry: e, tokens: cls.classTokens(e), own: cls.ownClass(e), source: cls.classSource(e),
  copy: cls.withOwnClassForCopy({ ...e, layout: { position: 'left', priority: 1 } }, e, plugins, styled) }))
const withs = [undefined, {}, { className: '' }, { className: '  a  b ' }, { className: 5 }, { other: 1 }].map((o) => ({ options: o ?? null, result: cls.withClass(o, 'nav-x') }))

// ── duplicating ─────────────────────────────────────────────────────────────────────────────────
const L = (position, priority, extra = {}) => ({ layout: { position, priority, ...extra } })
const board = [
  { name: 'page-title', source: '@quartz-community/page-title', enabled: true, ...L('header', 20) },
  nav({ variant: 'bar', id: 'main', className: 'nav-bar' }, L('header', 10)),
  { name: 'markdown', source: '@quartz-community/markdown', enabled: true, order: 10 },
  nav({ variant: 'tree' }, L('left', 30)),
  { name: 'search', source: '@quartz-community/search', enabled: true, ...L('header', 30, { group: 'g' }) },
  nav({ title: 'Fuß', id: 'f' }, L('footer', 5)),
  box({ file: 'x.md' }, L('left', 10)),
  { name: 'odd', source: 'odd', enabled: true, ...L('body', 1) },
  { name: 'array', source: 'array', enabled: true, layout: ['x'] },
  { name: 'x', source: { repo: 'github:someone/quartz-navigations' }, enabled: true, options: { id: 'keep' }, ...L('right', 1) },
  { name: 'page-title', source: '@quartz-community/page-title', enabled: true, ...L('header', 15) }
]
// An entry in a position the board does not know threw in QuartzControl (`positions[...]` is
// undefined); QuartzHub answers nil there, as for an entry without a layout.
const duplicates = board.map((_, i) => {
  try {
    return { index: i, result: utils.duplicateAfter(board, i, styled) ?? null }
  } catch (err) {
    return { index: i, result: null, threw: String(err.message) }
  }
})
const positionMap = utils.buildPositionMap(board)
// placeComponent: every entry into every position at the end, and a few at a place and with a group.
const places = [
  ...board.flatMap((_, i) => utils.POSITIONS.map((position) => ({ index: i, position }))),
  { index: 0, position: 'header', insertIndex: 0 }, { index: 4, position: 'header', insertIndex: 1, group: null },
  { index: 1, position: 'header', insertIndex: 9, group: 'g' }, { index: 3, position: 'left', insertIndex: -1 },
  { index: 6, position: 'footer', insertIndex: 0, group: 'neu' }
].map((c) => ({ ...c, layouts: utils.placeComponent(board, positionMap, c.index, c.position, c.insertIndex, c.group).map((p) => p.layout ?? null) }))
const ranks = Object.fromEntries(utils.duplicateRanks(board))
const refs = board.map((_, i) => utils.componentRef(board, i))

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'schema.json'), JSON.stringify(configSchema, null, 1) + '\n')
writeFileSync(join(out, 'cases.json'), JSON.stringify({
  keys, noEffect, roots,
  classes: { plugins, styled: [...styled], slugs, unique, perEntry, withs },
  board, duplicates, positionMap, ranks, refs, places,
  variantPositions: Object.fromEntries(variants.NAV_VARIANTS.map((v) => [v.value, v.position])),
  readAgainst: variants.NAVIGATIONS_READ_AGAINST, sameCode: variants.NAVIGATIONS_SAME_CODE
}, null, 1) + '\n')
console.log(`navigations: ${noEffect.length} reasons, ${roots.length} roots, ${slugs.length} slugs, ${perEntry.length} entries, ${duplicates.length} duplicates`)
