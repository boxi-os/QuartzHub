#!/usr/bin/env node
// Golden file for LayoutBoxes, made by QuartzControl's own code: what the Zusätzliche-Inhalte
// editor knows about quartz-layout-box (`routes/Plugins/layoutBoxes.ts`), the form's extras for it
// (`layoutBoxRoot` and `boxSilenced` in `optionFormExtras.ts`) and the small rules of the snippet
// fields (`formatOfFile`, `imageReference`, `siblingValue` in `PluginOptionsForm/snippets.tsx`).
//
// The schema is quartz-layout-box's own configSchema from gui-test (read only, copied into the
// fixture); the Swift test normalizes it with OptionSchema. `t` answers key and arguments as JSON,
// every argument as text.
//
//   Runtime/node/bin/node scripts/layout-boxes-golden.mjs [../QuartzControl] [gui-test]
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const guiTest = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte', 'gui-test'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'layout-boxes')

const icons = 'export const ArrowLeftRight = null, ChevronsUpDown = null, Columns3 = null, LayoutPanelTop = null, ListCollapse = null, '
  + 'ListTree = null, PanelRightOpen = null, PanelTop = null, RectangleEllipsis = null, SquareChevronDown = null, Braces = null, '
  + 'FilePlus2 = null, FileUp = null, ImagePlus = null, Pencil = null'
const boxes = await loadQuartzControl(control, 'src/routes/Plugins/layoutBoxes.ts', {})
const extras = await loadQuartzControl(control, 'src/routes/Plugins/optionFormExtras.ts', { 'lucide-react': icons })
const C = 'const C = () => null; export const Button = C, Select = C, TextInput = C'
const snippets = await loadQuartzControl(control, 'src/components/PluginOptionsForm/snippets.tsx', {
  react: 'export const useCallback = (f) => f, useEffect = () => {}, useRef = () => ({}), useState = (v) => [v, () => {}]; export default {}',
  'react-i18next': 'export const useTranslation = () => ({ t: (k) => k })',
  '@uiw/react-codemirror': 'export const Transaction = {}; export default () => null',
  '@codemirror/lang-html': 'export const html = () => null',
  '@codemirror/lang-markdown': 'export const markdown = () => null',
  '@codemirror/view': 'export const EditorView = {}',
  'lucide-react': icons,
  '../ui': C,
  '../../utils/confirm': 'export const askDialog = async () => "cancel", confirmDialog = async () => false',
  '../ErrorSurface': 'export const formatIpcError = (e) => String(e)',
  '../../state/uiState': 'export const useStickyState = (k, v) => [v, () => {}]',
  '../../utils/inlineSvg': 'export const inlineSvg = () => ({ ok: false })'
})
const schemaLib = await loadQuartzControl(control, 'shared/pluginOptionSchema.ts', {})

const t = (key, args) => JSON.stringify(args === undefined ? { key }
  : { key, args: Object.fromEntries(Object.entries(args).map(([k, v]) => [k, String(v)])) })

// ── the plugin's schema ─────────────────────────────────────────────────────────────────────────
const pkgFile = join(guiTest, '.quartz', 'plugins', 'quartz-layout-box', 'package.json')
if (!existsSync(pkgFile)) throw new Error(`${pkgFile} fehlt`)
const configSchema = JSON.parse(readFileSync(pkgFile, 'utf8')).quartz.configSchema
const fields = schemaLib.normalizeJsonSchema(configSchema, 'configSchema').fields

// ── one box's options ───────────────────────────────────────────────────────────────────────────
// `null` stands for "no options"; JSON has no undefined.
const optionSets = [
  null, {}, { html: '<b>x</b>' }, { html: '' }, { html: null }, { html: null, file: 'a.md' }, { html: 5 }, { file: 'a.md' },
  { file: '' }, { file: null }, { file: 7 }, { dir: './quartz/static/snippets/' }, { dir: '' }, { dir: '.' }, { dir: './' },
  { dir: ' x\\y// ' }, { dir: null }, { dir: 3 }, { file: 'a.md', dir: 'content/snips' }, { html: 't', file: 'a.md' },
  { file: 'a.md', byLang: { en: { file: 'b.md' }, fr: { html: '<i>fr</i>' }, de: null, es: [1], it: 'str', nl: { dir: 'other' }, pt: { file: null }, ru: { html: null } } },
  { html: '<img src="{{root}}/static/images/Bild%20eins.png">', byLang: { en: { html: 'static/images/Bild eins.png' }, de: { file: 'x.md' } } },
  { byLang: { en: { html: 7 } } }, { byLang: { en: { file: 5 } } }, { byLang: { en: { dir: false } } }, { byLang: null }, { byLang: [] },
  { byLang: 'x' }, { html: null, byLang: { en: { html: 'e' } } }, { file: null, byLang: { en: { file: 'x.md' } } },
  { dir: null, byLang: { 1: { file: 'one.md' }, 0: { file: 'zero.md' }, en: { dir: './a/' } } }, { html: null, byLang: { en: { file: null, dir: null } } },
  ['array'], 'str'
]
const installedVersions = [null, '0.4.0', '0.4.1', '0.4.2', '0.3.9', 'garbage']
const lift = (v) => (v === null ? undefined : v)
const options = optionSets.map((o) => {
  const v = lift(o)
  return {
    options: o,
    withoutNulls: boxes.withoutNulls(v),
    kind: boxes.boxContentKind(v),
    dir: boxes.boxDir(v),
    merged: boxes.mergedVariants(v).map(([lang, merged]) => ({ lang: lang ?? null, merged })),
    broken: Object.fromEntries(installedVersions.map((i) => [String(i), boxes.brokenOptions(v, lift(i))])),
    refs: boxes.snippetRefs(v),
    htmls: boxes.boxHtmls(v),
    ownText: boxes.langsWithOwnText(v)
  }
})
const nullBreaks = Object.fromEntries(installedVersions.map((i) => [String(i), boxes.nullBreaks(lift(i))]))
const dirs = ['', '.', './', ' ./quartz/static/snippets/ ', 'a\\b\\', 'a//', './/', '././x', '..', '../x/', ' x ', '﻿x']
  .map((d) => ({ dir: d, normalized: boxes.normalizeDir(d) }))
const images = [['a <img src="static/images/a.png">', 'a.png'], ['static/images/Bild%20eins.png', 'Bild eins.png'], ['static/images/Bild eins.png', 'Bild eins.png'],
  ['static/images/ü.png', 'ü.png'], ['static/images/%C3%BC.png', 'ü.png'], ['images/a.png', 'a.png'], ['static/images/a.png', 'A.png']]
  .map(([text, name]) => ({ text, name, result: boxes.mentionsImage(text, name) }))

// ── the boxes of a config, and renaming a snippet ───────────────────────────────────────────────
const opt = (o) => (o === undefined ? {} : { options: o })
const box = (o, extra = {}) => ({ name: 'quartz-layout-box', source: 'github:boxi-os/quartz-layout-box', enabled: true, ...opt(o), ...extra })
const plugins = [
  box({ file: 'a.md' }), box({}), box(undefined), box({ file: 'a.md', dir: './quartz/static/snippets/' }), box({ file: 'a.md', dir: 'other' }),
  box({ html: 'x', file: 'a.md' }),
  box({ file: 'a.md', byLang: { en: { file: 'b.md' }, fr: {}, de: { dir: 'other' }, es: { html: 't' }, it: { file: null }, nl: [1] } }),
  box({ file: 'b.md', byLang: { en: { file: 'a.md' }, fr: {} } }), box({ file: null, byLang: { en: {} } }), box({ file: 5 }),
  { name: 'explorer', source: '@quartz-community/explorer', enabled: true, options: { file: 'a.md' } },
  box(['array']), box('str'), box(null),
  { name: 'x', source: { repo: 'github:someone/quartz-layout-box' }, enabled: false, options: { file: 'a.md', byLang: { en: { file: 'a.md', dir: 'other' } } } },
  { name: 'y', source: 'github:boxi-os/quartz-layout-box#v0.4.2', enabled: true, options: { dir: 'other', byLang: { en: { dir: 'quartz/static/snippets' } } } },
  { name: 'z', source: { name: 'quartz-layout-box', repo: 'whatever' }, enabled: true, options: { dir: '.', file: 'a.md' } }
]
const boxList = boxes.boxesOf({ plugins }).map((b) => ({ index: b.index, occurrence: b.occurrence }))
const renames = [['quartz/static/snippets', 'a.md', 'c.md'], ['quartz/static/snippets', 'snippet.html', 'start.html'],
  ['quartz/static/snippets', 'b.md', 'a.md'], ['other', 'a.md', 'z.md'], ['.', 'a.md', 'q.md'], ['nowhere', 'a.md', 'b.md']]
  .map(([dir, from, to]) => ({ dir, from, to, ...boxes.renameSnippetRefs(plugins, dir, from, to) }))

// ── the form's extras ───────────────────────────────────────────────────────────────────────────
const keys = [...new Set([...fields.map((f) => f.key), 'html', 'file', 'dir', 'placeholders', 'enabled', 'x'])]
const entryValues = [{}, { html: 't' }, { html: null }, { file: 'x' }, { html: '' }]
const aboves = [{}, { html: 't' }, { html: null }, { file: 'a', html: 'b' }]
const roots = []
for (const o of optionSets.filter((x) => x !== null && typeof x === 'object' && !Array.isArray(x)))
  for (const installed of installedVersions)
    for (const withTiles of [true, false]) {
      const silenced = extras.boxSilenced(o, lift(installed))
      const root = extras.layoutBoxRoot(o, lift(installed), t, withTiles)
      roots.push({
        options: o, installed, withTiles,
        silenced: keys.filter((k) => silenced(k)),
        reasons: Object.fromEntries(keys.map((k) => [k, root.inactiveReason(k)])),
        hide: keys.filter((k) => root.hideUnlessSet(k)),
        lead: { has: keys.filter((k) => root.lead.has(k)), title: root.lead.title, empty: root.lead.empty },
        entry: entryValues.flatMap((entry) => aboves.map((above) => ({ entry, above,
          reasons: Object.fromEntries(['file', 'dir', 'html', 'title'].map((k) => [k, root.entryReason(k, entry, above)])) })))
      })
    }

// ── the snippet fields ──────────────────────────────────────────────────────────────────────────
const formats = ['a.md', 'A.MD', 'x.html', 'x.htm', 'x', 'x.md.html', '.md', 'ä.Md', 'x.markdown']
  .map((name) => ({ name, format: snippets.formatOfFile(name) }))
const references = ['images/a.png', 'images/Bild eins.png', 'images/sub/ü & ß.png', "images/(x)!'*~.svg", 'images/100%.png', 'images/a#b?.png']
  .flatMap((path) => ['html', 'markdown'].map((format) => ({ path, format, reference: snippets.imageReference(path, format) })))
const siblingSets = [{}, { dir: 'mine' }, { dir: '' }, { dir: null }, { placeholders: false }, { title: 'T' }]
const siblings = siblingSets.flatMap((values) => ['dir', 'placeholders', 'file', 'title', 'nothing']
  .map((key) => ({ values, key, value: ((v) => (v === undefined ? '__undefined' : v))(snippets.siblingValue(key, values, fields)) })))

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'schema.json'), JSON.stringify(configSchema, null, 1) + '\n')
writeFileSync(join(out, 'cases.json'), JSON.stringify({
  constants: {
    readAgainst: boxes.LAYOUT_BOX_READ_AGAINST, sameCode: boxes.LAYOUT_BOX_SAME_CODE, nullSafeSince: boxes.NULL_SAFE_SINCE,
    dir: boxes.DEFAULT_SNIPPET_DIR, file: boxes.DEFAULT_SNIPPET_FILE, placeholders: boxes.LAYOUT_BOX_PLACEHOLDERS,
    frontmatter: boxes.LAYOUT_BOX_FRONTMATTER_PLACEHOLDER, images: boxes.IMAGES_DIR
  },
  options, nullBreaks, dirs, images, plugins, boxes: boxList, renames, keys, roots, formats, references, siblings
}, null, 1) + '\n')
console.log(`layout-boxes: ${options.length} option sets, ${renames.length} renames, ${roots.length} roots, ${references.length} references, ${siblings.length} siblings`)
