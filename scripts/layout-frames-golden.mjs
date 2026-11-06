#!/usr/bin/env node
// Golden files for LayoutFrames and GridFrameCss, made by QuartzControl's own layoutFrameService.ts
// and shared/gridFrameCss.ts:
//
// - `write/<case>.json`: a project with frames (real ones from gui-test and Example, read only,
//   and made-up edges), the breakpoint file and the config as `readConfig` hands it out; the script
//   runs `writeAllFrames` and records every file under `.quartz-gui/authored-frames` afterwards,
//   with the sentences it returned.
// - `save.json`: `saveFrame`/`deleteFrame` runs, with the plugin calls they made.
// - `problems.json`: `frameDefinitionProblem` on broken definitions (the zod schema's first issue).
// - `candidates.json`: `groupLayoutCandidates` on made-up configs.
// - `widths.json`: `getBreakpointWidths` on breakpoint files.
//
//   Runtime/node/bin/node scripts/layout-frames-golden.mjs [../QuartzControl] [~/Documents/QuartzProjekte]
//
// The project folder is masked as @P@. Configs are read with QuartzControl's configService from a
// copy of quartz.config.yaml alone.
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const projects = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'layout-frames')

const configService = await loadQuartzControl(control, 'electron/main/services/configService.ts')
const grid = await loadQuartzControl(control, 'shared/gridFrameCss.ts')
const frames = await loadQuartzControl(control, 'electron/main/services/layoutFrameService.ts', {
  ...commonStubs,
  './configService': `export async function readConfig() {
    if (globalThis.__config instanceof Error) throw globalThis.__config
    return globalThis.__config
  }`,
  './pluginService': `
    export async function addPlugin(project, source) { globalThis.__calls.push(['add', source]); return globalThis.__answer }
    export async function installPluginSource(project, source) { globalThis.__calls.push(['install', source]); return globalThis.__answer }
    export async function removePlugin(project, name) { globalThis.__calls.push(['remove', name]); return globalThis.__answer }`
})

const work = mkdtempSync(join(tmpdir(), 'qh-frames-golden-'))
const realWork = (await import('node:fs')).realpathSync(work)
const mask = (text) => text.replaceAll(realWork, '@P@').replaceAll(work, '@P@')

// Only what the frames read: the plugin entries without their options (gui-test's carry a form's
// PGP key with an address in it) and the layout. `configuration` and `theme` stay empty.
async function readConfigOf(project) {
  const dir = join(work, 'config-' + project)
  mkdirSync(dir, { recursive: true })
  cpSync(join(projects, project, 'quartz.config.yaml'), join(dir, 'quartz.config.yaml'))
  const config = await configService.readConfig(dir)
  return { configuration: {}, theme: {}, plugins: config.plugins.map(({ options, ...entry }) => entry), ...(config.layout ? { layout: config.layout } : {}) }
}

function realFrames(project, ids) {
  const result = {}
  for (const id of ids) result[id] = readFileSync(join(projects, project, '.quartz-gui', 'authored-frames', id, 'frame.json'), 'utf8')
  return result
}

function files(root) {
  const result = {}
  const walk = (dir) => {
    if (!existsSync(dir)) return
    for (const name of readdirSync(dir).sort()) {
      const full = join(dir, name)
      if (statSync(full).isDirectory()) walk(full)
      else result[relative(root, full)] = mask(readFileSync(full, 'utf8'))
    }
  }
  walk(root)
  return result
}

// ── made-up frames ─────────────────────────────────────────────────────────────────────────────
const layout = (over = {}) => ({ rows: 2, cols: 2, rowGap: '1rem', columnGap: '1rem', placements: {}, ...over })
const frame = (over = {}) => ({
  id: 'frame-made',
  frameName: 'made',
  areas: [
    { id: 'a1', name: 'top', slot: 'header' },
    { id: 'a2', name: 'body', slot: 'pageBody' },
    { id: 'a3', name: 'side', slot: 'left', group: 'nav' }
  ],
  breakpoints: {
    desktop: layout({ placements: { a1: { row: 1, col: 1, rowSpan: 1, colSpan: 2 }, a2: { row: 2, col: 2, rowSpan: 1, colSpan: 1 }, a3: { row: 2, col: 1, rowSpan: 1, colSpan: 1 } } }),
    tablet: layout({ cols: 1, placements: { a1: { row: 1, col: 1, rowSpan: 1, colSpan: 1 }, a2: { row: 2, col: 1, rowSpan: 1, colSpan: 1 }, a3: { row: 1, col: 1, rowSpan: 1, colSpan: 1, hidden: true } } }),
    mobile: layout({ rows: 3, cols: 1, placements: { a1: { row: 1, col: 1, rowSpan: 1, colSpan: 1 }, a2: { row: 3, col: 1, rowSpan: 1, colSpan: 1 } } })
  },
  ...over
})
const json = (value) => JSON.stringify(value, null, 2)
const plugin = (source, layoutOf, enabled = true) => ({ source, enabled, ...(layoutOf ? { layout: layoutOf } : {}), name: String(source).split('/').pop() })
const madeConfig = {
  configuration: {}, theme: {},
  plugins: [
    plugin('github:quartz-community/explorer', { position: 'left', priority: 20, group: 'nav' }),
    plugin('github:quartz-community/search', { position: 'left', priority: 10, group: 'tools' }),
    plugin('@quartz-community/darkmode', { position: 'left', priority: 15, group: 'tools' }),
    plugin('github:quartz-community/toc', { position: 'right', priority: 5 }),
    plugin('github:quartz-community/off', { position: 'left', priority: 1, group: 'nav' }, false)
  ],
  layout: { groups: { nav: { priority: 1 } }, byPageType: { tag: { exclude: ['explorer'] }, folder: { template: 'other' }, '404': { positions: { left: [] } } } }
}

const writeCases = [
  { name: 'gui-test', frames: realFrames('gui-test', ['frame-1787519243386', 'frame-drawing', 'frame-editorial', 'frame-focus', 'frame-index']),
    breakpoints: readFileSync(join(projects, 'gui-test', '.quartz-gui', 'layout-breakpoints.json'), 'utf8'), config: await readConfigOf('gui-test') },
  { name: 'example', frames: realFrames('Example', ['frame-editorial', 'frame-index']),
    breakpoints: readFileSync(join(projects, 'Example', '.quartz-gui', 'layout-breakpoints.json'), 'utf8'), config: await readConfigOf('Example') },
  { name: 'gui-test-default-widths', frames: realFrames('gui-test', ['frame-editorial']), config: await readConfigOf('gui-test') },
  { name: 'no-frames', frames: {}, config: madeConfig },
  { name: 'made-default-widths', frames: { 'frame-made': json(frame()) }, config: madeConfig },
  { name: 'made-own-widths', frames: { 'frame-made': json(frame()) }, breakpoints: '{"tablet": 1100, "mobile": 700.5}', config: madeConfig },
  { name: 'widths-broken', frames: { 'frame-made': json(frame()) }, breakpoints: '{"tablet": 700, "mobile": 900}', config: madeConfig },
  { name: 'widths-unreadable', frames: { 'frame-made': json(frame()) }, breakpoints: '{nope', config: madeConfig },
  { name: 'config-unreadable', frames: { 'frame-made': json(frame()) }, config: new Error('YAMLParseError: bad indentation') },
  { name: 'escaped-name', frames: { 'frame-made': json(frame({ frameName: 'a "quoted" \\ name </script> ' })) }, config: madeConfig },
  { name: 'tracks-and-lines', config: madeConfig, frames: { 'frame-made': json(frame({ breakpoints: {
    desktop: layout({ rows: 2, cols: 3, columnSizes: [' 200px ', '', '  '], rowSizes: ['auto'], columnLineNames: { 0: ['start', 'edge'], 3: ['end'], 1: [] }, rowLineNames: { 2: ['bottom'] },
      maxWidth: ' 900px ', align: 'right', paddingBlock: ' 1rem 2rem ', paddingInline: '',
      placements: { a1: { row: 1, col: 1, rowSpan: 1, colSpan: 3 }, a2: { row: 2, col: 2, rowSpan: 4, colSpan: 4 }, a3: { row: 0, col: 1, rowSpan: 2, colSpan: 1 } } }),
    tablet: layout({ align: 'center', maxWidth: '', placements: {} }),
    mobile: layout({ rows: 2.5, cols: 1.5, align: 'middle', placements: { a1: { row: 1, col: 1, rowSpan: 1.5, colSpan: 1 } } })
  } })) } },
  { name: 'odd-values', config: madeConfig, frames: { 'frame-made': json(frame({
    areas: [{ id: 'a1', name: 'top', slot: 'header' }, { id: 7, name: 12, slot: 'left' }, { id: 'a3', name: 'nothing' }],
    breakpoints: {
      desktop: { rows: 1, cols: 2, placements: { a1: { row: 1, col: 1, rowSpan: 1, colSpan: 1, hidden: 0 }, 7: { row: 1, col: 2, rowSpan: 1, colSpan: 1 }, a3: { row: 1, col: 1, rowSpan: 1, colSpan: 1, hidden: 'yes' } } },
      tablet: layout({ rowGap: 3, columnGap: null, placements: { a1: null } }),
      mobile: layout({ rowGap: true, columnGap: [1, 2], placements: { a1: { col: 1, rowSpan: 1, colSpan: 1 } } })
    }
  })) } },
  { name: 'legacy', config: madeConfig, frames: { 'frame-old': json({ id: 'frame-old', frameName: 'old', rows: 2, cols: 1, gap: '2rem', extra: true,
    areas: [{ id: 'x', name: 'head', slot: 'header', row: 1, col: 1, rowSpan: 1, colSpan: 1 }, { id: 'y', name: 'main', row: 2, col: 1, rowSpan: 1, colSpan: 1, more: 1 }] }) } },
  { name: 'unreadable-frame-skipped', config: madeConfig, frames: { 'frame-made': json(frame()), 'frame-broken': '{"id": "frame-broken",', 'frame-empty': '' },
    extraFiles: { '.quartz-gui/authored-frames/stray.txt': 'not a frame' } },
  { name: 'unknown-keys-kept', config: madeConfig, frames: { 'frame-made': json({ before: 1, ...frame(), after: { deep: [1, 'x'] } }) } },
  { name: 'shape-breaks-the-write', config: madeConfig, frames: { 'frame-made': json(frame()), 'frame-bad': json({ id: 'frame-bad', frameName: 'bad', areas: [], breakpoints: { desktop: layout() } }) } },
  { name: 'id-not-a-slug', config: madeConfig, frames: { 'frame-made': json(frame({ id: '../escape' })) } }
]

mkdirSync(join(out, 'write'), { recursive: true })
for (const file of readdirSync(join(out, 'write'))) rmSync(join(out, 'write', file))
for (const c of writeCases) {
  const project = join(work, 'p-' + c.name)
  rmSync(project, { recursive: true, force: true })
  for (const [id, text] of Object.entries(c.frames)) {
    mkdirSync(join(project, '.quartz-gui', 'authored-frames', id), { recursive: true })
    writeFileSync(join(project, '.quartz-gui', 'authored-frames', id, 'frame.json'), text)
  }
  for (const [path, text] of Object.entries(c.extraFiles ?? {})) {
    mkdirSync(dirname(join(project, path)), { recursive: true })
    writeFileSync(join(project, path), text)
  }
  mkdirSync(project, { recursive: true })
  if (c.breakpoints !== undefined) {
    mkdirSync(join(project, '.quartz-gui'), { recursive: true })
    writeFileSync(join(project, '.quartz-gui', 'layout-breakpoints.json'), c.breakpoints)
  }
  globalThis.__config = c.config
  const problems = await frames.writeAllFrames(project)
  writeFileSync(join(out, 'write', `${c.name}.json`), JSON.stringify({
    frames: c.frames, breakpoints: c.breakpoints ?? null, extraFiles: c.extraFiles ?? {},
    config: c.config instanceof Error ? { error: String(c.config) } : c.config,
    problems: problems.map(mask),
    files: files(join(project, '.quartz-gui'))
  }, null, 2) + '\n')
}

// ── save and delete ────────────────────────────────────────────────────────────────────────────
const saveRuns = []
{
  const project = join(work, 'save')
  mkdirSync(project, { recursive: true })
  globalThis.__config = madeConfig
  const step = async (label, run) => {
    globalThis.__calls = []
    globalThis.__answer = { success: true, output: 'cli says ok' }
    let result
    try { result = await run() } catch (error) { result = { threw: String(error) } }
    saveRuns.push({ label, result: JSON.parse(mask(JSON.stringify(result ?? null))), calls: JSON.parse(mask(JSON.stringify(__calls))), files: files(join(project, '.quartz-gui')) })
  }
  await step('new frame registers', () => frames.saveFrame(project, frame()))
  await step('existing frame only rewrites', () => frames.saveFrame(project, frame({ frameName: 'renamed' })))
  await step('new frame without snapshot installs', () => frames.saveFrame(project, frame({ id: 'frame-two' }), { snapshot: false }))
  await step('legacy definition is migrated', () => frames.saveFrame(project, { id: 'frame-old', frameName: 'old', rows: 1, cols: 1, gap: '0', areas: [{ id: 'x', name: 'only', slot: 'pageBody', row: 1, col: 1, rowSpan: 1, colSpan: 1 }] }))
  await step('a problem writes nothing', () => frames.saveFrame(project, frame({ id: 'frame-three', areas: [{ id: 'a', name: 'twice' }, { id: 'b', name: 'twice' }] })))
  await step('widths rewrite every frame', () => frames.saveBreakpointWidths(project, { tablet: 1000, mobile: 600 }))
  await step('delete', () => frames.deleteFrame(project, 'frame-two'))
  await step('delete with a bad id throws', () => frames.deleteFrame(project, '../x'))
  globalThis.__answer = { success: false, output: 'cli failed' }
  await step('a failing add keeps the files', async () => { globalThis.__answer = { success: false, output: 'cli failed' }; return frames.saveFrame(project, frame({ id: 'frame-four' })) })
}
writeFileSync(join(out, 'save.json'), JSON.stringify(saveRuns, null, 2) + '\n')

// ── frameDefinitionProblem ─────────────────────────────────────────────────────────────────────
const good = frame()
const withDesktop = (over) => frame({ breakpoints: { ...good.breakpoints, desktop: { ...good.breakpoints.desktop, ...over } } })
const problemInputs = [
  ['good', good],
  ['null', null], ['string', 'frame'], ['array', []],
  ['id missing', { ...good, id: undefined }], ['id bad', frame({ id: 'Frame..x' })], ['id number', frame({ id: 5 })], ['id too long', frame({ id: 'a'.repeat(65) })],
  ['frameName empty', frame({ frameName: '' })], ['frameName long', frame({ frameName: 'n'.repeat(121) })],
  ['areas missing', { ...good, areas: undefined }], ['areas object', frame({ areas: {} })], ['areas too many', frame({ areas: Array.from({ length: 201 }, (_, i) => ({ id: `a${i}`, name: `n${i}` })) })],
  ['area null', frame({ areas: [null] })], ['area name bad', frame({ areas: [{ id: 'a', name: '1abc' }] })], ['area name long', frame({ areas: [{ id: 'a', name: 'a'.repeat(65) }] })],
  ['area id long', frame({ areas: [{ id: 'i'.repeat(129), name: 'x' }] })], ['area slot bad', frame({ areas: [{ id: 'a', name: 'x', slot: 'sidebar' }] })],
  ['area slot null', frame({ areas: [{ id: 'a', name: 'x', slot: null }] })], ['area group bad', frame({ areas: [{ id: 'a', name: 'x', slot: 'left', group: 'has space' }] })],
  ['breakpoints missing', { ...good, breakpoints: undefined }], ['tablet missing', frame({ breakpoints: { desktop: good.breakpoints.desktop, mobile: good.breakpoints.mobile } })],
  ['rows zero', withDesktop({ rows: 0 })], ['rows 51', withDesktop({ rows: 51 })], ['rows fraction', withDesktop({ rows: 1.5 })], ['rows string', withDesktop({ rows: '2' })],
  ['rows NaN-ish', withDesktop({ rows: null })], ['rows huge fraction', withDesktop({ rows: 60.5 })], ['cols negative fraction', withDesktop({ cols: -0.5 })],
  ['columnSizes bad char', withDesktop({ columnSizes: ['1fr;'] })], ['columnSizes long', withDesktop({ columnSizes: ['1'.repeat(41)] })],
  ['columnSizes long and bad', withDesktop({ columnSizes: [';'.repeat(41)] })], ['columnSizes too many', withDesktop({ columnSizes: Array(51).fill('1fr') })],
  ['columnSizes too many and bad', withDesktop({ columnSizes: [...Array(50).fill('1fr'), '{'] })],
  ['rowGap missing', withDesktop({ rowGap: undefined })], ['rowGap brackets', withDesktop({ rowGap: '[a]' })], ['maxWidth bad', withDesktop({ maxWidth: 'url(x)' + '"' })],
  ['align bad', withDesktop({ align: 'justify' })], ['paddingBlock number', withDesktop({ paddingBlock: 4 })],
  ['line names key bad', withDesktop({ columnLineNames: { abc: ['x'] } })], ['line names key long', withDesktop({ columnLineNames: { ['<script>alert(1)</script>' + 'x'.repeat(3000)]: ['x'] } })],
  ['line names value bad', withDesktop({ columnLineNames: { 0: ['has space'] } })], ['line names too many', withDesktop({ columnLineNames: { 0: Array(9).fill('a') } })],
  ['line names empty name', withDesktop({ rowLineNames: { 0: [''] } })], ['line names not array', withDesktop({ rowLineNames: { 0: 'a' } })],
  ['placements missing', withDesktop({ placements: undefined })], ['placement key long', withDesktop({ placements: { ['p'.repeat(3000)]: { row: 1, col: 1, rowSpan: 1, colSpan: 1 } } })],
  ['placement row zero', withDesktop({ placements: { a1: { row: 0, col: 1, rowSpan: 1, colSpan: 1 } } })], ['placement hidden string', withDesktop({ placements: { a1: { row: 1, col: 1, rowSpan: 1, colSpan: 1, hidden: 'no' } } })],
  ['placement missing span', withDesktop({ placements: { a1: { row: 1, col: 1, rowSpan: 1 } } })], ['placement null', withDesktop({ placements: { a1: null } })],
  ['two issues: id and areas', { ...good, id: '', areas: 3 }], ['two issues in one layout', withDesktop({ rows: 0, cols: 'x' })],
  ['area issue before breakpoint issue', frame({ areas: [{ id: 'a', name: '-' }], breakpoints: { desktop: null } })],
  ['duplicate name', frame({ areas: [{ id: 'a', name: 'same' }, { id: 'b', name: 'same' }] })],
  ['duplicate group on a slot', frame({ areas: [{ id: 'a', name: 'one', slot: 'left', group: 'g' }, { id: 'b', name: 'two', slot: 'left', group: 'g' }] })],
  ['same group on two slots', frame({ areas: [{ id: 'a', name: 'one', slot: 'left', group: 'g' }, { id: 'b', name: 'two', slot: 'right', group: 'g' }] })],
  ['group without slot twice', frame({ areas: [{ id: 'a', name: 'one', group: 'g' }, { id: 'b', name: 'two', group: 'g' }] })],
  ['legacy good', { id: 'frame-old', frameName: 'old', rows: 1, cols: 1, gap: '0', areas: [{ id: 'x', name: 'only', slot: 'pageBody', row: 1, col: 1, rowSpan: 1, colSpan: 1 }] }],
  ['legacy areas not a list', { id: 'frame-old', frameName: 'old', rows: 1, cols: 1, gap: '0', areas: 'x' }],
  ['legacy area null', { id: 'frame-old', frameName: 'old', rows: 1, cols: 1, gap: '0', areas: [null] }],
  ['legacy gap bad', { id: 'frame-old', frameName: 'old', rows: 1, cols: 1, gap: '{', areas: [] }],
  ['legacy rows zero', { id: 'frame-old', frameName: 'old', rows: 0, cols: 1, gap: '0', areas: [] }]
]
const problems = problemInputs.map(([label, input]) => ({ label, input: input === undefined ? null : JSON.parse(JSON.stringify(input)), problem: frames.frameDefinitionProblem(input) }))
writeFileSync(join(out, 'problems.json'), JSON.stringify(problems, null, 2) + '\n')

// ── groupLayoutCandidates ──────────────────────────────────────────────────────────────────────
const candidateConfigs = [
  ['made', madeConfig, 'made'],
  ['made, other frame', madeConfig, 'other'],
  ['gui-test editorial', await readConfigOf('gui-test'), 'editorial'],
  ['gui-test index', await readConfigOf('gui-test'), 'index'],
  ['gui-test focus', await readConfigOf('gui-test'), 'focus'],
  ['example editorial', await readConfigOf('Example'), 'editorial'],
  ['no layout', { plugins: [plugin('a/b', { position: 'left', priority: 1, group: 'g' })] }, 'x'],
  ['ties keep order', { plugins: [
    plugin('a/one', { position: 'left', priority: 5, group: 'g2' }), plugin('a/two', { position: 'left', priority: 5, group: 'g1' }),
    plugin('a/three', { position: 'left', priority: 1, group: 'g3' })], layout: { groups: { g3: { priority: 5 } } } }, 'x'],
  ['odd priorities', { plugins: [
    plugin('a/one', { position: 'left', group: 'g1' }), plugin('a/two', { position: 'left', priority: '3', group: 'g2' }),
    plugin('a/three', { position: 'left', priority: 2, group: 'g3' }), plugin('a/four', { position: 'right', priority: null, group: 'g4' })],
    layout: { groups: { g1: { priority: 'x' }, g4: {} } } }, 'x'],
  ['no group, falsy group, disabled', { plugins: [
    plugin('a/one', { position: 'left', priority: 1 }), plugin('a/two', { position: 'left', priority: 2, group: '' }),
    plugin('a/three', { position: 'left', priority: 3, group: 'g' }, false), { source: 'a/four', layout: { position: 'left', priority: 4, group: 'h' } },
    plugin('a/five', { position: 'left', priority: 0, group: 'h' }, 1)] }, 'x'],
  ['exclude by quartz name', { plugins: [
    plugin('@quartz-community/explorer', { position: 'left', priority: 1, group: 'nav' }), plugin('github:org/search#v2', { position: 'left', priority: 2, group: 'tools' }),
    plugin({ repo: 'https://github.com/org/graph.git' }, { position: 'right', priority: 1, group: 'viz' }), plugin({ repo: 'x', name: 'named' }, { position: 'right', priority: 2, group: 'other' })],
    layout: { byPageType: {
      a: { exclude: ['explorer'] }, b: { exclude: ['@quartz-community/explorer'] }, c: { exclude: ['search'] }, d: { exclude: ['graph', 'named'] },
      e: { exclude: [] }, f: { template: 'x', exclude: ['search'] }, g: { template: null, exclude: ['search'] }, h: { positions: { right: [], left: ['x'] } },
      i: { positions: { left: [] }, exclude: ['search'] }, j: null, k: 'string', l: { exclude: 'search' } } } }, 'x'],
  // A missing priority makes V8's comparator answer NaN; its sort (one run, then binary insertion)
  // then puts the groups where a plain stable sort would not. Equal group priorities hand the
  // order of first appearance through.
  ['missing priority, V8 order', { plugins: [
    plugin('a/b', { position: 'left', priority: 2, group: 'gb' }), plugin('a/c', { position: 'left', priority: 1, group: 'gc' }),
    plugin('a/a', { position: 'left', group: 'ga' }), plugin('a/d', { position: 'left', priority: 0, group: 'gd' })],
    layout: { groups: { ga: { priority: 5 }, gb: { priority: 5 }, gc: { priority: 5 }, gd: { priority: 5 } } } }, 'x'],
  ['positions with numeric names', { plugins: [
    plugin('a/one', { position: 'left', priority: 1, group: 'g' }), plugin('a/two', { position: '2', priority: 1, group: 'h' }), plugin('a/three', { position: '1', priority: 1, group: 'i' })],
    layout: { byPageType: { a: { positions: { 2: [] } } } } }, 'x']
]
const candidates = candidateConfigs.map(([label, config, frameName]) => ({ label, frameName, config, candidates: grid.groupLayoutCandidates(config, frameName) }))
writeFileSync(join(out, 'candidates.json'), JSON.stringify(candidates, null, 2) + '\n')

// ── getBreakpointWidths ────────────────────────────────────────────────────────────────────────
const widthFiles = [null, '{"tablet": 1100, "mobile": 700}', '{"tablet": "1100", "mobile": "700"}', '{"tablet": 700, "mobile": 700}',
  '{"tablet": 1100}', '{"tablet": null, "mobile": null}', '[1, 2]', '{"tablet": 1e3, "mobile": 1.5, "extra": 1}', '{"tablet": " 900 ", "mobile": ""}',
  '{"tablet": true, "mobile": false}', '{"tablet": [1100], "mobile": [[700]]}', 'nope', '{"tablet": "0x50", "mobile": "1e1"}']
const widths = []
for (const text of widthFiles) {
  const project = join(work, 'w')
  rmSync(project, { recursive: true, force: true })
  mkdirSync(join(project, '.quartz-gui'), { recursive: true })
  if (text !== null) writeFileSync(join(project, '.quartz-gui', 'layout-breakpoints.json'), text)
  widths.push({ file: text, widths: await frames.getBreakpointWidths(project) })
}
writeFileSync(join(out, 'widths.json'), JSON.stringify(widths, null, 2) + '\n')

rmSync(work, { recursive: true, force: true })
console.log(`layout-frames: ${writeCases.length} write cases, ${saveRuns.length} save steps, ${problems.length} problems, ${candidates.length} candidate configs, ${widths.length} width files`)
