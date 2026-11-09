#!/usr/bin/env node
// Golden file for LayoutBoard, PageTypeOverride and the overview cells of LayoutStage, made by
// QuartzControl's own code: `routes/LayoutEditor/utils.ts`, `pageTypeOverride.ts` and
// `frameShape`/`roomOf`/`showsOn` of `LayoutOverview.tsx` (exposed at bundle time). `stateOf` lives
// inside the overview's component and cannot be loaded; it is copied below word for word and says
// so (the counter-check is a diff against LayoutOverview.tsx).
//
// Boards: gui-test's and Example's own configs, read with configService.readConfig (read only, home
// masked), with gui-test's five frames; and a made-up board with the edges: duplicates, a parked
// component, a switched-off duplicate, a layout given as a list, dead and string excludes, an
// unknown template, a `{}` override.
//
//   Runtime/node/bin/node scripts/layout-board-golden.mjs [../QuartzControl] [QuartzProjekte]
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const projects = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'layout-board')

const lucide = new Proxy({}, { get: () => null })
const icons = 'export default null; ' + ['Ban', 'Blocks', 'ChevronDown', 'CircleDashed', 'CircleOff', 'EyeOff', 'Files', 'Filter', 'HelpCircle',
  'LayoutGrid', 'Monitor', 'Pin', 'PowerOff', 'Puzzle', 'Smartphone', 'SquareDashed', 'Table2', 'Unlink2', 'ArrowLeftRight',
  'ChevronsUpDown', 'Columns3', 'LayoutPanelTop', 'ListCollapse', 'ListTree', 'PanelRightOpen', 'PanelTop', 'RectangleEllipsis',
  'SquareChevronDown'].map((n) => `export const ${n} = null;`).join(' ')
void lucide
const stubs = {
  'lucide-react': icons,
  'react-i18next': 'export function useTranslation() { return { t: (k) => k } }',
  '../../components/ui': 'export const Badge = null, Card = null, CardHeading = null, InfoNote = null',
  './ComponentChip': 'export const ComponentPill = null; export function conditionLabel(t, c) { return c }; export function groupColor() { return null }',
  '../../state/uiState': 'export function useStickyState(k, v) { return [v, () => {}] }',
  'react/jsx-runtime': 'export const jsx = null, jsxs = null, Fragment = null',
}
const utils = await loadQuartzControl(control, 'src/routes/LayoutEditor/utils.ts', stubs)
const pto = await loadQuartzControl(control, 'src/routes/LayoutEditor/pageTypeOverride.ts', stubs)
const overview = await loadQuartzControl(control, 'src/routes/LayoutEditor/LayoutOverview.tsx', stubs, { expose: ['frameShape', 'roomOf', 'showsOn'] })
const grid = await loadQuartzControl(control, 'shared/gridFrameCss.ts', {})
const { readConfig } = await loadQuartzControl(control, 'electron/main/services/configService.ts')

// ── copied from LayoutOverview.tsx (stateOf), unchanged but for the closure it read: ─────────────
// config, shapes, FRAME_BREAKPOINTS and the helpers are passed in.
function stateOfCopied(config, shapes, i, pt) {
  const { getLayout } = utils
  const { overrideOf, isPositionCleared, isExcluded } = pto
  const { roomOf, showsOn } = overview
  const FRAME_BREAKPOINTS = grid.FRAME_BREAKPOINTS
  const layout = getLayout(config.plugins[i])
  const override = overrideOf(config, pt)
  if (isPositionCleared(override, layout.position)) return { state: 'cleared' }
  if (isExcluded(override, config.plugins[i])) return { state: 'excluded' }
  const shape = shapes.get(pt)
  if (shape === null || shape === undefined) return { state: 'unknown' }
  const room = roomOf(shape, layout.position, layout.group)
  if (room === null) return { state: 'noArea' }
  if (room !== 'all' && room.length === 0) return { state: 'hiddenArea' }
  if (room !== 'all' && room.length < FRAME_BREAKPOINTS.length) {
    const on = room.filter((bp) => showsOn(layout.display, bp))
    return on.length === 0 ? { state: 'noWidth' } : { state: 'someWidths', on }
  }
  return { state: 'shown' }
}
// ── end of the copy ─────────────────────────────────────────────────────────────────────────────

const mask = (value) => JSON.parse(JSON.stringify(value).replaceAll(homedir(), '/Users/example'))
const frameDir = join(projects, 'gui-test', '.quartz-gui', 'authored-frames')
const frames = readdirSync(frameDir).sort().map((d) => grid.migrateGridFrameDefinition(JSON.parse(readFileSync(join(frameDir, d, 'frame.json'), 'utf8'))))

const entry = (source, extra = {}) => {
  const name = source.split('/').pop().split('#')[0]
  return { source, ...extra, name, enabled: extra.enabled ?? true }
}
const made = {
  configuration: { pageTitle: 'Brett', locale: 'de-DE' },
  theme: {},
  plugins: [
    entry('github:quartz-community/explorer', { layout: { position: 'left', priority: 20, group: 'top' } }),
    entry('github:quartz-community/search', { layout: { position: 'left', priority: 10, display: 'desktop-only', condition: 'not-index' } }),
    entry('github:boxi-os/quartz-navigations', { options: { id: 'nav', variant: 'tree' }, layout: { position: 'header', priority: 10 } }),
    entry('github:boxi-os/quartz-navigations', { options: { id: 'nav2', className: 'nav-zwei' }, layout: { position: 'header', priority: 20, group: 'toolbar' } }),
    entry('github:boxi-os/quartz-navigations', { enabled: false, layout: { position: 'footer', priority: 5 } }),
    entry('github:quartz-community/footer', { enabled: false, layout: { position: 'footer', priority: 10 } }),
    entry('github:boxi-os/quartz-layout-box', { options: { html: '<p>Hi</p>', className: 'layout-box-hi' }, layout: { position: 'afterBody', priority: 30, groupOptions: { grow: true, order: 2 } } }),
    entry('github:quartz-community/backlinks', { layout: { position: 'right', priority: 10, display: 'mobile-only', group: 'side' } }),
    entry('github:quartz-community/graph', { layout: ['right', 5] }),
    entry('github:quartz-community/content-page', {}),
    entry('github:quartz-community/folder-page', { enabled: false }),
    entry('github:quartz-community/canvas-page', {}),
    entry('github:quartz-community/syntax-highlighting', {}),
    entry('@quartz-community/tag-list', { layout: { position: 'beforeBody', priority: 10, group: 'meta' } }),
  ],
  layout: {
    groups: { toolbar: { direction: 'row', gap: '1rem' }, meta: { direction: 'column' } },
    byPageType: {
      content: { exclude: ['search', 'quartz-layout-box'], positions: { right: [], left: 'nein' } },
      tag: { exclude: ['explorer', 'tag-list', 'unbekannt'], template: 'gibtsnicht' },
      excalidraw: { template: 'minimal' },
      bases: {},
      zeichnung: { template: 'drawing' },
      canvas: { positions: { beforeBody: [] } },
      '404': { template: 'focus', exclude: [] },
    },
  },
}

const boards = [
  { name: 'gui-test', config: mask(await readConfig(join(projects, 'gui-test'))), frames },
  { name: 'Example', config: mask(await readConfig(join(projects, 'Example'))), frames: [] },
  { name: 'made', config: made, frames },
]
const pluginFrames = { 'canvas-page': 'canvas' }

const result = []
for (const { name, config, frames } of boards) {
  const plugins = config.plugins
  const items = utils.componentItems(plugins).map(({ index }) => index)
  const parked = utils.parkedIndices(plugins)
  const pageTypes = utils.derivePageTypes(config)
  const changed = (next, i) => next[i]?.layout ?? null
  const perComponent = items.map((i) => ({
    index: i,
    ref: utils.componentRef(plugins, i),
    group: [changed(utils.withGroup(plugins, i, 'neu'), i), changed(utils.withGroup(plugins, i, ''), i)],
    display: ['all', 'desktop-only', 'mobile-only', undefined].map((d) => changed(utils.withDisplay(plugins, i, d), i)),
    condition: ['  has-tags ', '', 'eigene'].map((c) => changed(utils.withCondition(plugins, i, c), i)),
    enabled: [false, true].map((e) => Object.keys(utils.withEnabled(plugins, i, e)[i]).join(',') + '=' + utils.withEnabled(plugins, i, e)[i].enabled),
    groupOption: [['grow', true], ['grow', false], ['shrink', false], ['shrink', true], ['basis', '10rem'], ['basis', ''], ['basis', 'auto'],
      ['order', 3], ['order', 0], ['order', undefined], ['align', 'start'], ['align', 'center']]
      .map(([k, v]) => ({ key: k, value: v ?? null, entry: changed(utils.withGroupOption(plugins, i, k, v), i) })),
    options: [utils.withOptions(plugins, i, undefined)[i], utils.withOptions(plugins, i, { neu: 1 })[i]].map((e) => ({ keys: Object.keys(e), options: e.options ?? null })),
  }))
  const appends = []
  for (const i of utils.distinctComponentChips(plugins).map((c) => c.index).slice(0, 6))
    for (const [position, insertIndex] of [['left', undefined], ['header', 0], ['footer', 1], ['afterBody', 99], ['right', -1]]) {
      const r = utils.appendDuplicateToPosition(plugins, i, position, insertIndex, new Set(['nav-zwei-2']))
      appends.push({ index: i, position, insertIndex: insertIndex ?? null, layouts: r ? r.plugins.map((p) => p.layout ?? null) : null, copy: r ? r.plugins[r.newIndex] : null, newIndex: r ? r.newIndex : null })
    }
  const types = [...pageTypes, 'nonexistent']
  const firstOfName = utils.distinctComponentChips(plugins).map((c) => c.index)
  const typeCases = types.map((pt) => {
    const override = pto.overrideOf(config, pt)
    const slice = (c) => ({ keys: Object.keys(c.layout?.byPageType ?? {}), value: c.layout?.byPageType?.[pt] ?? null })
    return {
      pageType: pt,
      override,
      customizes: pto.hasPageTypeOverride(config.layout?.byPageType?.[pt]),
      dead: [...pto.deadExcludes(config, override)],
      excluded: items.map((i) => pto.isExcluded(override, plugins[i])),
      cleared: utils.POSITIONS.map((p) => pto.isPositionCleared(override, p)),
      withExcluded: firstOfName.flatMap((i) => [true, false].map((x) => ({ index: i, excluded: x, ...slice(pto.withExcluded(config, pt, plugins[i], x)) }))),
      withCleared: utils.POSITIONS.flatMap((p) => [true, false].map((x) => ({ position: p, cleared: x, ...slice(pto.withPositionCleared(config, pt, p, x)) }))),
      withTemplate: [undefined, 'default', 'editorial'].map((tp) => ({ template: tp ?? null, ...slice(pto.withTemplate(config, pt, tp)) })),
      without: slice(pto.withoutOverride(config, pt)),
      resolved: pto.resolvedFrame(config, pt, pluginFrames),
    }
  })
  const names = [...frames.map((f) => f.frameName), 'default', 'full-width', 'minimal', 'canvas', 'gibtsnicht']
  const plugSet = new Set(Object.values(pluginFrames))
  const shapeOf = (n) => {
    const s = overview.frameShape(n, frames, plugSet)
    return s && { plain: Object.fromEntries(s.plain), groups: Object.fromEntries(s.groups) }
  }
  const shapes = new Map(pageTypes.map((pt) => [pt, overview.frameShape(pto.resolvedFrame(config, pt, pluginFrames).name, frames, plugSet)]))
  const placed = utils.POSITIONS.flatMap((p) => utils.buildBoardPositionMap(plugins, parked)[p])
  result.push({
    name, config, frames,
    pageTypes,
    nameCounts: Object.fromEntries(utils.duplicateNameCounts(plugins)),
    trayChips: utils.distinctComponentChips(plugins).map((c) => c.index),
    parked: [...parked],
    boardPositions: utils.buildBoardPositionMap(plugins, parked),
    groupNames: utils.groupNamesOf(config, frames),
    perComponent, appends, typeCases,
    shapes: Object.fromEntries(names.map((n) => [n, shapeOf(n)])),
    cells: placed.map((i) => ({ index: i, states: pageTypes.map((pt) => stateOfCopied(config, shapes, i, pt)) })),
  })
}
const ranges = [[1200, 800], [1100, 700], [1024.5, 640]].flatMap(([tablet, mobile]) =>
  ['desktop', 'tablet', 'mobile'].map((bp) => ({ bp, tablet, mobile, label: utils.breakpointRangeLabel(bp, { tablet, mobile }) })))

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify({ boards: result, ranges, pluginFrames }) + '\n')
console.log(`layout-board: ${result.map((b) => `${b.name} ${b.perComponent.length} components, ${b.typeCases.length} page types, ${b.cells.length} rows`).join('; ')}`)
