#!/usr/bin/env node
// Golden file for ComponentSelectors and PreviewMarks, and the marking script as PreviewScript.swift,
// both from QuartzControl's own code: `data/componentSelectors.ts`, `utils/sitePreview.ts`, the
// helpers of `components/SitePreview.tsx` (exposed at bundle time) and `previewScript` of
// `electron/main/services/previewHighlight.ts`, written out as QuartzControl's bundle compiles it.
// The Gegenprobe for the script: run this again, `git diff` stays empty.
//
//   Runtime/node/bin/node scripts/site-preview-golden.mjs [../QuartzControl]
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const core = join(here, '..', 'Packages', 'QuartzHubCore')
const out = join(core, 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'site-preview')

const icons = 'export const ArrowLeftRight = null, ChevronsUpDown = null, Columns3 = null, LayoutPanelTop = null, ListCollapse = null, '
  + 'ListTree = null, PanelRightOpen = null, PanelTop = null, RectangleEllipsis = null, SquareChevronDown = null, MonitorPlay = null, '
  + 'Play = null, RefreshCw = null, Square = null'
const selectors = await loadQuartzControl(control, 'src/data/componentSelectors.ts', { 'lucide-react': icons })
const util = await loadQuartzControl(control, 'src/utils/sitePreview.ts', {})
const C = 'const C = () => null; export const Button = C, Card = C, CardHeading = C, SegmentedControl = C, TextInput = C, Toggle = C'
const component = await loadQuartzControl(control, 'src/components/SitePreview.tsx', {
  react: 'export const useEffect = () => {}, useRef = () => ({}), useState = (v) => [v, () => {}]; export default {}',
  'react-i18next': 'export const useTranslation = () => ({ t: (k) => k })',
  'lucide-react': icons,
  './ui': C,
  '../state/uiState': 'export const useStickyState = (k, v) => [v, () => {}], peekStickyState = () => null',
  '../state/announcer': 'export const announce = () => {}',
  '../utils/serverStatus': 'export const serverErrorText = () => null'
}, { expose: ['nearestPage', 'markSentence', 'samePage'] })
const highlight = await loadQuartzControl(control, 'electron/main/services/previewHighlight.ts', {
  electron: 'export const BrowserWindow = { getAllWindows: () => [] }',
  './buildService': 'export const getServerStatus = () => ({ state: "stopped" })'
}, { expose: ['previewScript'] })

const t = (key, args) => JSON.stringify(args === undefined ? { key }
  : { key, args: Object.fromEntries(Object.entries(args).map(([k, v]) => [k, String(v)])) })

// ── selectors ───────────────────────────────────────────────────────────────────────────────────
const nav = (className, extra = {}) => ({ name: 'quartz-navigations', source: 'github:boxi-os/quartz-navigations', enabled: true,
  ...(className === undefined ? {} : { options: { className } }), layout: { position: 'left', priority: 10 }, ...extra })
const box = (className) => ({ name: 'quartz-layout-box', source: 'github:boxi-os/quartz-layout-box', enabled: true,
  ...(className === undefined ? {} : { options: { className } }), layout: { position: 'header', priority: 10 } })
const plugins = [
  nav('nav-tree'), nav('nav-tree nav-tree-2'), nav('nav-tree nav-tree-2 nav-tree-3'), nav(undefined), nav('  '), nav('1bad'),
  box('layout-box-mark'), box('layout-box-mark layout-box-mark-2'), box(undefined), box('a b c'),
  { name: 'explorer', source: '@quartz-community/explorer', enabled: true, layout: { position: 'left', priority: 1 } },
  { name: 'explorer', source: '@quartz-community/explorer', enabled: true, layout: { position: 'right', priority: 1 } },
  { name: 'footer', source: '@quartz-community/footer', enabled: true, options: { className: 'x' }, layout: { position: 'footer', priority: 1 } },
  { name: 'unknown-thing', source: 'x', enabled: true, layout: { position: 'left', priority: 1 } }
]
const entries = plugins.map((p) => ({ entry: p, result: selectors.entrySelector(p, plugins) }))
// What "Komponente wählen" on the CSS tab offers: one per selector, a placed component's root and
// an instance's own class, with and without its copies. A plugin without a layout block is none.
const listPlugins = [...plugins, { name: 'graph', source: '@quartz-community/graph', enabled: true }]
const list = selectors.componentSelectors(listPlugins)

// ── reports ─────────────────────────────────────────────────────────────────────────────────────
const vp = { width: 1280, height: 640 }
const good = { source: 'quartzcontrol-preview', selector: '.x', found: 2, visible: 1, rect: { x: 1, y: 2, width: 3, height: 4 }, viewport: vp }
const reports = [
  good, { ...good, selector: null }, { ...good, rect: null }, { ...good, source: 'other' }, { ...good, selector: 5 },
  { ...good, found: 1.5 }, { ...good, found: -1 }, { ...good, found: 10000 }, { ...good, found: 9999, visible: 9999 },
  { ...good, visible: 3 }, { ...good, viewport: null }, { ...good, viewport: { width: 'a', height: 1 } },
  { ...good, rect: { x: 0, y: 0, width: 0, height: 4 } }, { ...good, rect: { x: 0, y: 0, width: 3 } }, { ...good, rect: 'r' },
  { ...good, found: '2' }, null, 'text', [], { ...good, rect: undefined }, { ...good, viewport: { width: 1e308, height: -5 } }
].map((data) => ({ data: data === undefined ? null : data, result: util.parsePreviewReport(data) }))

// ── zoom ────────────────────────────────────────────────────────────────────────────────────────
const zooms = []
for (const rect of [{ x: 0, y: 0, width: 200, height: 40 }, { x: 900, y: 1500, width: 300, height: 900 }, { x: 10, y: 10, width: 1200, height: 30 },
  { x: -50, y: -20, width: 80, height: 80 }, { x: 1200, y: 600, width: 2, height: 2 }])
  for (const frame of [{ width: 1280, height: 1300 }, { width: 390, height: 2000 }])
    for (const box of [{ width: 600, height: 640 }, { width: 300, height: 400 }])
      for (const base of [0.47, 1])
        zooms.push({ rect, frame, box, base, result: util.zoomOnto(rect, frame, box, base) })

// ── pages and sentences ─────────────────────────────────────────────────────────────────────────
const lists = [['a/b/c', 'en/a/b', 'index'], ['x'], ['/en/guide/page', 'de/guide/page', 'en/other'], ['Über/x', 'Über/y']]
const shown = ['', 'en/guide/start', 'de/guide/x', '/Über/z', 'Über/z', 'index', 'a/b/']
const nearest = lists.flatMap((list) => shown.map((page) => ({ list, page, result: component.nearestPage(list, page) })))
const same = [['a', '/a/'], ['//a//', 'a'], ['a/b', 'a'], ['Über', 'Über'], ['', '/']].map(([a, b]) => ({ a, b, result: component.samePage(a, b) }))
const sentences = []
for (const found of [0, 2]) for (const visible of [0, 1, 2]) {
  if (visible > found) continue
  for (const matches of [1, 3]) for (const ownClass of [false, true]) for (const pages of [null, ['a'], ['b']]) {
    const report = { source: 'quartzcontrol-preview', selector: '.x', found, visible, rect: null, viewport: vp }
    sentences.push({ found, visible, matches, ownClass, pages, page: '/a/',
      result: component.markSentence(report, { selector: '.x', name: 'Nav', matches, ownClass, pages }, '/a/', t) })
  }
}

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify({ entries, listPlugins, list, reports, zooms, nearest, same, sentences }, null, 1) + '\n')

// ── the script ──────────────────────────────────────────────────────────────────────────────────
const source = highlight.previewScript.toString()
if (source.includes('"""#')) throw new Error('the script would end the Swift string')
writeFileSync(join(core, 'Sources', 'QuartzHubCore', 'Plugins', 'PreviewScript.swift'), `// Generated by scripts/site-preview-golden.mjs from QuartzControl's
// electron/main/services/previewHighlight.ts (\`previewScript\`, as its bundle compiles it). Do not edit:
// run the script again; an empty \`git diff\` afterwards is the Gegenprobe.

/// The script that marks a component in the previewed site and reports where it is, QuartzControl's
/// \`previewScript\` word for word. It reports with \`parent.postMessage\`; in QuartzHub's web view
/// the site is the top frame, so \`parent\` is the page itself and \`SitePreviewMarks\` listens there.
public enum PreviewScript {
  public static let source = #"""
${source}
"""#

  /// The call that installs it (again), as QuartzControl's \`highlightInPreview\` builds it.
  public static func call(selector: String?, focus: Bool) -> String {
    "(\\(source))(\\(selector.map { JSJSON.compact(.string($0)) } ?? "null"), \\(focus))"
  }
}
`)
console.log(`site-preview: ${entries.length} entries, ${reports.length} reports, ${zooms.length} zooms, ${nearest.length} pages, ${sentences.length} sentences, script ${source.length} chars`)
