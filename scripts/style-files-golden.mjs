#!/usr/bin/env node
// Golden files for StyleFiles and StylesheetConsolidation, made by QuartzControl's own
// styleService.ts and shared/stylesheetConsolidation.ts:
//
// - `legacy/`: the template's 31 stylesheets before 1.1 and their order, out of QuartzControl's git
//   history (f2cdb69~1, the commit before the template itself was put together).
// - `pure.json`: planConsolidation, wasConsolidated, canConsolidate, legacyCount, splitBase,
//   isConsolidatedOrder and the two predicates on made-up orders and files.
// - `steps/<case>.json`: a project's quartz/styles, a sequence of calls (list, read, write, create,
//   rename, delete, import, references, consolidate with the snapshot stubbed), after each the
//   answer and every changed file.
//
//   Runtime/node/bin/node scripts/style-files-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'style-files')

const style = await loadQuartzControl(control, 'electron/main/services/styleService.ts', {
  ...commonStubs,
  './snapshotService': 'export async function createSnapshot(project, kind) { globalThis.__snapshots.push(kind); return { id: "snap-1" } }',
  './projectDependencies': 'export function halfUnpackedModule() { return null }'
})
const plan = await loadQuartzControl(control, 'shared/stylesheetConsolidation.ts', {})

// ── the 31 ───────────────────────────────────────────────────────────────────────────────────
const show = (rev, p) => execFileSync('git', ['-C', control, 'show', `${rev}:${p}`], { encoding: 'utf8', maxBuffer: 1e8 })
const legacyOrder = [...show('f2cdb69~1', 'scripts/example-template/style-order.mjs').matchAll(/^\s+'([a-z0-9-]+)'/gm)].map((m) => m[1])
const legacy = Object.fromEntries(legacyOrder.map((n) => [n, show('f2cdb69~1', `scripts/example-template/styles/${n}.scss`)]))
rmSync(out, { recursive: true, force: true })
mkdirSync(join(out, 'legacy'), { recursive: true })
for (const [name, text] of Object.entries(legacy)) writeFileSync(join(out, 'legacy', `${name}.scss`), text)
writeFileSync(join(out, 'legacy', 'order.json'), JSON.stringify(legacyOrder, null, 2) + '\n')

// ── pure ─────────────────────────────────────────────────────────────────────────────────────
const C = (n) => `custom/${n}.scss`
const files31 = Object.fromEntries(legacyOrder.map((n) => [C(n), legacy[n]]))
const order31 = legacyOrder.map(C)
const header = (t) => `// ${t} - put together by QuartzControl; each section is named after its former stylesheet.\n`
const earlier = (t) => `// ${t} - put together by QuartzControl from the stylesheets named in the sections below.\n`
const planCases = [
  ['the 31 with own files around', ['custom/eigene-erste.scss', ...order31, C('callouts'), C('fix')], files31, ['custom/eigene-erste.scss', ...order31, C('callouts'), C('fix')]],
  ['the 31 alone', order31, files31, order31],
  ['one switched off', order31.filter((p) => p !== C('nav-darkmode')), files31, order31],
  ['only three loaded', [C('nav-header'), C('fix'), C('body-code'), C('a11y')], files31, order31],
  ['base with only foundation sections', [C('base'), C('own'), C('nav-header')], { [C('base')]: '/* ---- box model */\na { b: c; }\n\n/* ---- focus */\n:focus { x: y; }\n', [C('nav-header')]: '.h {}' }, [C('base'), C('own'), C('nav-header')]],
  // An own file right after base goes after layout, where base's own rules mostly went.
  ['an own file after base', [C('base'), C('own'), C('nav-header')], { [C('base')]: '/* ---- box model */\n.a{}\n/* ---- columns */\n.c{}\n', [C('nav-header')]: '.h {}' }, [C('base'), C('own'), C('nav-header')]],
  ['base with an unknown heading', [C('base')], { [C('base')]: 'intro\n/* ---- box model */\n.a{}\n/* ---- my own */\n.m{}\n/* ---- typographic rhythm */\n.t{}\n/* -- too short */\n' }, [C('base')]],
  ['a user layout.scss beside the 31', [...order31, C('layout')], { ...files31, [C('layout')]: '.mine {}' }, [...order31, C('layout'), C('layout-2')]],
  ['put together before (header)', [C('layout'), C('nav-header')], { [C('layout')]: header('layout') + 'x', [C('nav-header')]: '' }, [C('layout'), C('nav-header')]],
  ['put together before (earlier header)', [C('layout'), C('nav-header')], { [C('layout')]: earlier('layout') + 'x' }, [C('layout'), C('nav-header')]],
  ['template first line', [C('content'), C('nav-header')], { [C('content')]: '// Content: title and date, typographic rhythm, text, code, maths, diagrams and media.  \nrest' }, [C('content')]],
  ['template first line but not loaded', [C('nav-header')], { [C('content')]: '// Content: title and date, typographic rhythm, text, code, maths, diagrams and media.\n' }, [C('content'), C('nav-header')]],
  ['only a11y and plugin-layout-box', [C('a11y'), C('plugin-layout-box')], files31, [C('a11y'), C('plugin-layout-box')]],
  ['imported and css', ['imported/x.scss', C('nav-header'), 'custom/nav-search.css', C('body-media')], files31, ['imported/x.scss', C('nav-header'), 'custom/nav-search.css', C('body-media')]],
  ['empty', [], {}, []]
]
// Files equal to one of the 31 are written as { legacy: name }; a plan's new files in full only for
// the first case, otherwise as their SHA-1 and length (the Swift test hashes its own the same way).
const sha1 = (text) => createHash('sha1').update(text).digest('hex')
const refer = (files) => Object.fromEntries(Object.entries(files).map(([p, t]) => [p, p.startsWith('custom/') && legacy[p.slice(7, -5)] === t ? { legacy: p.slice(7, -5) } : t]))
const compact = (result, full) => full ? result : { ...result, write: Object.fromEntries(Object.entries(result.write).map(([p, t]) => [p, { sha1: sha1(t), length: t.length }])) }
const pure = {
  plans: planCases.map(([name, order, files, onDisk], index) => ({ name, order, files: refer(files), onDisk, plan: compact(plan.planConsolidation(order, files, onDisk), index === 0),
    was: plan.wasConsolidated(files, order), can: plan.canConsolidate(order, plan.wasConsolidated(files, order)),
    count: plan.legacyCount(order, plan.wasConsolidated(files, order)), consolidatedOrder: plan.isConsolidatedOrder(order) })),
  predicates: ['custom/base.scss', 'custom/a11y.scss', 'custom/layout.scss', 'custom/nav-header.css', 'imported/nav-header.scss', 'custom/foundation.scss', 'custom/x.scss', 'custom/sub/layout.scss', 'custom/plugin-layout-box.scss']
    .map((p) => ({ path: p, legacyOnly: plan.isLegacyOnlyStylesheet(p), consolidatedOnly: plan.isConsolidatedOnlyStylesheet(p) })),
  markers: ['base', 'a', 'x'.repeat(98)].map((n) => ({ name: n, marker: plan.sectionMarker(n) }))
}
writeFileSync(join(out, 'pure.json'), JSON.stringify(pure, null, 2) + '\n')

// ── steps ────────────────────────────────────────────────────────────────────────────────────
const M = (id) => [`/* --- QuartzControl:managed:${id}:start --- */`, `/* --- QuartzControl:managed:${id}:end --- */`]
const imports = (paths) => `${M('imports')[0]}\n${paths.map((p) => `@use "./${p.replace(/\.(scss|css)$/, '')}";`).join('\n')}\n${M('imports')[1]}`
const legacyTree = (order, { moved = false, extra = {} } = {}) => {
  const tree = { ...extra }
  for (const n of legacyOrder) tree[C(n)] = legacy[n]
  if (moved) {
    tree['custom.scss'] = '@use "./variables.scss" as *;\n\n@use "./quartzcontrol";\n\n// body\n'
    tree['_quartzcontrol.scss'] = `// head\n\n${imports(order)}\n`
  } else {
    tree['custom.scss'] = `@use "./variables.scss" as *;\n\n${imports(order)}\n\n// body\n`
  }
  return tree
}
const step = (call, ...args) => ({ call, args })
const own = { [C('eigene-erste')]: '.erste {}\n', [C('callouts')]: '// meine eigene\n.mine {}\n', [C('fix')]: '.fix {}\n' }
const cases = {
  'consolidate the 31': { tree: legacyTree(['custom/eigene-erste.scss', ...order31, C('callouts'), C('fix')], { extra: own }), steps: [
    step('listStyleFiles'), step('consolidateStylesheets'), step('listStyleFiles'), step('consolidateStylesheets')
  ] },
  'consolidate, moved, one switched off': { tree: legacyTree(order31.filter((p) => p !== C('nav-darkmode')), { moved: true }), steps: [
    step('listStyleFiles'), step('consolidateStylesheets'), step('setImportOrder', '@ORDER+nav-darkmode'), step('listStyleFiles'), step('consolidateStylesheets')
  ] },
  'nothing to consolidate': { tree: { 'custom.scss': `${imports([C('layout'), C('a11y')])}\n`, [C('layout')]: '// Layout: sticky header, columns and their scrolling, panels, breakpoints, footer.\n', [C('a11y')]: '' }, steps: [
    step('listStyleFiles'), step('consolidateStylesheets')
  ] },
  'files': { tree: { 'custom.scss': '@use "./variables.scss" as *;\n.x {}\n', 'imported/old.css': '.old {}', 'custom/orphan.scss': '', 'in/fremd.scss': '.fremd {}\n', 'in/plain.css': 'p {}' }, steps: [
    step('listStyleFiles'), step('createStyleFile', 'neu'), step('createStyleFile', 'neu'), step('createStyleFile', 'zwei.css'), step('createStyleFile', '01-typo'),
    step('listStyleFiles'), step('renameStyleFile', 'custom/neu.scss', 'umbenannt'), step('renameStyleFile', 'custom/umbenannt.scss', 'umbenannt.scss'),
    step('renameStyleFile', 'custom/umbenannt.scss', 'zwei.css'), step('renameStyleFile', 'custom/orphan.scss', 'waise'),
    step('writeStyleFile', 'custom/umbenannt.scss', '.u { color: red; }\n'), step('readStyleFile', 'custom/umbenannt.scss'), step('readStyleFile', 'custom/fehlt.scss'),
    step('writeStyleFile', '_quartzcontrol.scss', '// written by hand\n'), step('readStyleFile', '_quartzcontrol.scss'),
    step('deleteStyleFile', 'custom/zwei.css'), step('deleteStyleFile', 'custom/nie-da.scss'),
    step('importStyleFile', '@IN@/fremd.scss'), step('importStyleFile', '@IN@/plain.css'), step('listStyleFiles')
  ] },
  'references': { tree: { 'custom.scss': '',
    '../.quartz/plugins/demo/styles/a.scss': '.a {}', '../.quartz/plugins/demo/dist/x.scss': 'no', '../.quartz/plugins/demo/node_modules/m.scss': 'no',
    '../.quartz/plugins/demo/b/c/d/e/f/g/deep.scss': 'deep', '../.quartz/plugins/demo/b/c/d/e/f/g/h/deeper.scss': 'deeper', '../.quartz/plugins/demo/z.css': 'css',
    ...Object.fromEntries(Array.from({ length: 22 }, (_, i) => [`../.quartz/plugins/many/s${String(i).padStart(2, '0')}.scss`, `.s${i} {}`]))
  }, steps: [step('getStyleReferences', 'demo'), step('getStyleReferences', 'many'), step('getStyleReferences', 'none')] }
}

const work = mkdtempSync(join(tmpdir(), 'qh-style-files-golden-'))
const filesOf = (dir) => {
  const result = {}
  const walk = (d) => {
    if (!existsSync(d)) return
    for (const name of readdirSync(d).sort()) {
      const full = join(d, name)
      if (statSync(full).isDirectory()) walk(full)
      else result[relative(dir, full)] = readFileSync(full, 'utf8')
    }
  }
  walk(dir)
  return result
}
mkdirSync(join(out, 'steps'), { recursive: true })
for (const [name, c] of Object.entries(cases)) {
  const project = join(work, name.replace(/[^\w-]+/g, '-'))
  const styles = join(project, 'quartz', 'styles')
  mkdirSync(styles, { recursive: true })
  const treeOut = {}
  for (const [path, text] of Object.entries(c.tree)) {
    // The 31 are laid out from legacy/, not repeated in every case.
    const isLegacy = path.startsWith('custom/') && legacy[path.slice(7, -5)] === text
    treeOut[path] = isLegacy ? { legacy: path.slice(7, -5) } : text
    const full = path.startsWith('../') ? join(project, path.slice(3)) : path.startsWith('in/') ? join(project, path) : join(styles, path)
    mkdirSync(dirname(full), { recursive: true })
    writeFileSync(full, text)
  }
  const results = []
  let before = filesOf(styles)
  for (const s of c.steps) {
    globalThis.__snapshots = []
    let args = s.args.map((a) => (typeof a === 'string' ? a.replace('@IN@', join(project, 'in')) : a))
    if (args[0] === '@ORDER+nav-darkmode') args = [[...(await style.listStyleFiles(project)).files.filter((f) => f.imported).map((f) => f.relativePath), C('nav-darkmode')]]
    let result
    try { result = (await style[s.call](project, ...args)) ?? null } catch (error) { result = { threw: String(error) } }
    const after = filesOf(styles)
    const changed = {}
    for (const path of new Set([...Object.keys(before), ...Object.keys(after)])) if (before[path] !== after[path]) changed[path] = after[path] ?? null
    results.push({ ...s, args: s.args, result: JSON.parse(JSON.stringify(result).replaceAll(project, '@P@')), changed, snapshots: globalThis.__snapshots })
    before = after
  }
  writeFileSync(join(out, 'steps', `${name.replace(/[^\w-]+/g, '-')}.json`), JSON.stringify({ name, tree: treeOut, steps: results }, null, 2) + '\n')
}
rmSync(work, { recursive: true, force: true })
console.log(`style-files: ${legacyOrder.length} legacy stylesheets, ${pure.plans.length} plans, ${Object.keys(cases).length} step cases`)
