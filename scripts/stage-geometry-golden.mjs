#!/usr/bin/env node
// Golden file for StageGeometry and FrameEditing, made by QuartzControl's own code:
// `routes/LayoutEditor/stageGeometry.ts` and `defaultFrame.ts` whole, and the module-level helpers
// of `FrameBuilder.tsx` (exposed at bundle time; `Date.now()` in a new frame's id replaced by a
// fixed one). The edits FrameBuilder's component makes (span, visibility, resize, drop) live in the
// component and are checked by hand in StageGeometryTests.
//
// Frames: gui-test's five (read only), a made-up one with overlaps, an area past the grid, hidden
// group areas, two plain areas on one slot and line names; lengths: what frames hold and the edges
// of the little calc() parser.
//
//   Runtime/node/bin/node scripts/stage-geometry-golden.mjs [../QuartzControl] [QuartzProjekte]
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const projects = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'stage-geometry')

const geo = await loadQuartzControl(control, 'src/routes/LayoutEditor/stageGeometry.ts', {})
const def = await loadQuartzControl(control, 'src/routes/LayoutEditor/defaultFrame.ts', {}, { replace: [['`frame-${Date.now()}`', "'frame-fixed'"]] })
const fb = await loadQuartzControl(control, 'src/routes/LayoutEditor/FrameBuilder.tsx', {
  '../../utils/confirm': 'export async function confirmDialog() { return true }',
  '../../state/announcer': 'export function announce() {}',
  '../../state/uiState': 'export function useStickyState(k, v) { return [v, () => {}] }',
  '../../components/ErrorSurface': 'export function formatIpcError(e) { return String(e) }',
  '../../components/DevServerRestartHint': 'export default function DevServerRestartHint() { return null }',
}, {
  expose: ['slugify', 'nextAreaName', 'emptyDraft', 'placementAt', 'overlaps', 'withPlacement', 'slotWarnings', 'placementWarnings', 'fitsGrid', 'slotToName'],
  replace: [['`frame-${Date.now()}`', "'frame-fixed'"]],
})
const grid = await loadQuartzControl(control, 'shared/gridFrameCss.ts', {})

// ── lengths ─────────────────────────────────────────────────────────────────────────────────────
const values = ['0', '12px', '1.5rem', '10%', '5vw', 'calc((300px - 8rem) / 3)', 'calc(100% - 2rem)', 'min(20rem, 30%)', 'max(10px, 2vw)',
  'clamp(10px, 5vw, 40px)', 'clamp(1px, 2px)', 'auto', 'min-content', '2em', 'var(--x)', '', '  4px  ', '1px+2px', '1px + 2px', '1px - -2px',
  '2 * 3px', '3px * 2', '3px * 2px', '6px / 2', '6px / 0', '6px / 2px', '(2px)', '((2px + 1px) * 2)', '-5px', '+.5rem', '.5px', '1.px',
  '1e2px', '1E-1rem', '5', '0px', 'calc(5)', 'calc(1px, 2px)', 'CALC(2px)', 'Min(1px,2px)', '10PX', '7Rem', '1px 2px', 'calc(1px', 'px',
  'min( 1px , 2px )', '1.e1px']
const contexts = [{ percentBase: 1456, viewport: 1456 }, { percentBase: 300, viewport: 390 }]
const lengths = values.flatMap((v) => contexts.map((ctx) => ({ value: v, ...ctx, px: geo.lengthToPx(v, ctx) })))

// ── tracks ──────────────────────────────────────────────────────────────────────────────────────
const trackSets = [['320px', 'auto', '320px'], ['1fr', '1fr'], ['1fr', '2fr', '200px'], ['minmax(100px, 2fr)', '1fr'], ['auto', '1fr'],
  ['min-content', '1fr'], ['var(--w)'], ['900px', '900px', '1fr'], ['0px'], [], ['.5fr', '1.5fr'], ['calc((300px - 8rem) / 3)', '1fr', 'calc((300px - 8rem) / 3)'],
  ['20%', '1fr'], ['MINMAX(0, 3fr)']]
const tracks = trackSets.flatMap((sizes) => [{ inner: 1456, gap: 12, viewport: 1456 }, { inner: 390, gap: 0, viewport: 390 }]
  .map((o) => ({ sizes, ...o, ...geo.stageTracks(sizes, o) })))

// ── frames ──────────────────────────────────────────────────────────────────────────────────────
const frameDir = join(projects, 'gui-test', '.quartz-gui', 'authored-frames')
const frames = readdirSync(frameDir).sort().map((d) => grid.migrateGridFrameDefinition(JSON.parse(readFileSync(join(frameDir, d, 'frame.json'), 'utf8'))))
const made = {
  id: 'frame-made', frameName: 'brett',
  areas: [
    { id: 'a', name: 'kopf', slot: 'header' }, { id: 'b', name: 'links', slot: 'left' }, { id: 'c', name: 'links-zwei', slot: 'left' },
    { id: 'd', name: 'werkzeug', slot: 'right', group: 'werkzeug' }, { id: 'e', name: 'seite', slot: 'pageBody' },
    { id: 'f', name: 'leer' }, { id: 'g', name: 'unten', slot: 'footer', group: 'unten' }, { id: 'h', name: 'kopf', slot: 'afterBody', group: 'werkzeug' },
    { id: 'i', name: 'nach', slot: 'afterBody', group: 'werkzeug' },
  ],
  breakpoints: {
    desktop: { rows: 3, cols: 3, columnSizes: ['200px', '', '1fr'], rowGap: '1rem', columnGap: '2%', maxWidth: '1200px', align: 'right', paddingInline: '5%', paddingBlock: '8px',
      columnLineNames: { 0: ['start'], 3: ['end'] },
      placements: { a: { row: 1, col: 1, rowSpan: 1, colSpan: 3 }, b: { row: 2, col: 1, rowSpan: 2, colSpan: 1 }, c: { row: 2, col: 1, rowSpan: 1, colSpan: 1 },
        e: { row: 2, col: 2, rowSpan: 1, colSpan: 1 }, d: { row: 2, col: 3, rowSpan: 1, colSpan: 1 }, g: { row: 3, col: 2, rowSpan: 1, colSpan: 4 },
        f: { row: 3, col: 3, rowSpan: 1, colSpan: 1, hidden: true } } },
    tablet: { rows: 2, cols: 2, rowGap: '0', columnGap: 'var(--g)', align: 'center', maxWidth: '50vw',
      placements: { a: { row: 1, col: 1, rowSpan: 1, colSpan: 2 }, e: { row: 2, col: 1, rowSpan: 1, colSpan: 1 }, d: { row: 2, col: 2, rowSpan: 1, colSpan: 1, hidden: true } } },
    mobile: { rows: 1, cols: 1, rowGap: '4px', columnGap: '4px', placements: { e: { row: 1, col: 1, rowSpan: 1, colSpan: 1 }, i: { row: 5, col: 1, rowSpan: 1, colSpan: 1 } } },
  },
}
const allFrames = [...frames, made, fb.emptyDraft()]
const BPS = grid.FRAME_BREAKPOINTS
const perFrame = allFrames.map((frame) => ({
  frame,
  stage: Object.fromEntries(BPS.map((bp) => [bp, geo.stageFrame(frame.breakpoints[bp], bp)])),
  slotWarnings: Object.fromEntries(BPS.map((bp) => {
    const w = fb.slotWarnings(frame, bp)
    return [bp, { ...w, hiddenGroups: w.hiddenGroups.map((a) => a.id) }]
  })),
  placementWarnings: Object.fromEntries(BPS.map((bp) => {
    const w = fb.placementWarnings(frame, bp)
    return [bp, { overlapping: w.overlapping.map(([a, b]) => [a.id, b.id]), outside: w.outside.map((a) => a.id) }]
  })),
  cells: Object.fromEntries(BPS.map((bp) => {
    const l = frame.breakpoints[bp]
    const rows = []
    for (let r = 0; r <= l.rows + 1; r++) for (let c = 0; c <= l.cols + 1; c++) rows.push(fb.placementAt(l, frame.areas, r, c)?.id ?? null)
    return [bp, rows]
  })),
  overlaps: Object.fromEntries(BPS.map((bp) => {
    const l = frame.breakpoints[bp]
    const res = []
    for (const a of frame.areas) for (const [rs, cs] of [[1, 1], [2, 2], [1, 3]]) res.push(fb.overlaps(l, frame.areas, 1, 1, rs, cs, a.id), fb.overlaps(l, frame.areas, 2, 2, rs, cs))
    return [bp, res]
  })),
  fits: Object.fromEntries(BPS.map((bp) => [bp, frame.areas.map((a) => (frame.breakpoints[bp].placements[a.id] ? fb.fitsGrid(frame.breakpoints[bp], frame.breakpoints[bp].placements[a.id]) : null))])),
  nextAreaName: fb.nextAreaName(frame.areas),
  withPlacement: frame.areas.slice(0, 3).map((a) => fb.withPlacement(frame, 'tablet', a.id, { row: 2, col: 1, rowSpan: 1, colSpan: 2, hidden: false })),
}))

// ── names and Quartz's frame ────────────────────────────────────────────────────────────────────
const slugs = ['  Seiten Leiste ', 'Über uns', '---a--b---', '', '!!!', 'Kopf_2', 'ABC def', 'grid-area', 'ÄÖÜ', 'x'].map((t) => ({ text: t, slug: fb.slugify(t) }))
const slots = ['header', 'left', 'right', 'beforeBody', 'pageBody', 'afterBody', 'footer'].map((s) => ({ slot: s, name: fb.slotToName(s) }))
const measured = {
  grids: { desktop: { columns: ['18rem', 'auto', '18rem', '10px'], rowGap: '6px', columnGap: '8px' }, tablet: { columns: ['300px', 'auto'], rowGap: '6px', columnGap: '9px' },
    mobile: { columns: ['auto'], rowGap: '2px', columnGap: '3px' } },
  breakpoints: { mobile: 700, desktop: 1100 },
  pageMaxWidth: null,
}
const standard = [
  { measures: null, frame: def.quartzDefaultFrame('standard') },
  { measures: measured, frame: def.quartzDefaultFrame('eigen', measured), fit: Object.fromEntries(BPS.map((bp) => [bp, def.columnsFit(measured, bp)])) },
]
const shown = ['desktop-only', 'mobile-only', 'all', undefined, 'other'].flatMap((d) => BPS.map((bp) => ({ display: d ?? null, bp, shown: geo.shownInView(d, bp) })))

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify({ lengths, tracks, perFrame, slugs, slots, standard, quartzMeasures: def.QUARTZ_MEASURES, shown, reference: geo.STAGE_REFERENCE_WIDTH }))
console.log(`stage-geometry: ${lengths.length} lengths, ${tracks.length} track sets, ${perFrame.length} frames, ${slugs.length} slugs`)
