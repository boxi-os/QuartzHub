#!/usr/bin/env node
// Golden files for ManagedBlocks, VariableOverrides and StyleSheets, made by QuartzControl's own
// styleService.ts:
//
// - `pure.json`: the text functions (managed blocks under both marker names, copies, nesting,
//   CRLF, text before the markers in other scripts; the load-order block, the `@use` line, the
//   variable rules) on many texts, each answer recorded.
// - `steps/<case>.json`: a project's quartz/styles laid out (the stylesheets of gui-test and
//   Example, read only, also rearranged into the form of 1.0; made-up edges), a sequence of
//   service calls, and after each the answer and every file under quartz/styles.
//
//   Runtime/node/bin/node scripts/managed-styles-golden.mjs [../QuartzControl] [~/Documents/QuartzProjekte]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const projects = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'managed-styles')

const style = await loadQuartzControl(control, 'electron/main/services/styleService.ts', {
  ...commonStubs,
  './projectDependencies': 'export function halfUnpackedModule() { return null }'
}, { expose: ['renameLegacyMarkers', 'insertBeforeRules', 'upsertImportBlock', 'parseVariableOverrides', 'renderVariableOverrides', 'migrateOnWrite', 'findManagedBlocks', 'currentOrder'] })

const read = (project, path) => readFileSync(join(projects, project, 'quartz', 'styles', path), 'utf8')
const M = (id, name = 'QuartzControl') => [`/* --- ${name}:managed:${id}:start --- */`, `/* --- ${name}:managed:${id}:end --- */`]
const block = (id, body, name) => `${M(id, name)[0]}\n${body}\n${M(id, name)[1]}`

// ── the form of 1.0, made from a moved project with QuartzControl's own functions ──────────────
function asOldForm(custom, managed) {
  let text = style.stripManagedUse(custom)
  const imports = style.getManagedBlock(managed, 'imports')
  if (imports) text = style.upsertImportBlock(text, imports)
  for (const id of ['fonts', 'google-fonts', 'css-vars']) {
    const body = style.getManagedBlock(managed, id)
    if (body) text = style.upsertManagedBlock(text, id, body)
  }
  return text
}

// gui-test's google-fonts block is 470 lines of @font-face; its first four rules keep the shape
// and keep the fixtures small.
function shortGoogleFonts(text) {
  const body = style.getManagedBlock(text, 'google-fonts')
  if (!body) return text
  return style.upsertManagedBlock(text, 'google-fonts', style.splitRules(body).slice(0, 5).join('\n\n'))
}
const guiCustom = read('gui-test', 'custom.scss'), guiManaged = shortGoogleFonts(read('gui-test', '_quartzcontrol.scss'))
const exCustom = read('Example', 'custom.scss'), exManaged = shortGoogleFonts(read('Example', '_quartzcontrol.scss'))
const guiOld = asOldForm(guiCustom, guiManaged)
const fontsBody = '@font-face {\n  font-family: "A";\n  src: url("/static/fonts/a.woff2") format("woff2");\n}\n@font-face {\n  src: url( \'/static/fonts/b.woff2\'), url(/static/fonts/c.ttf);\n}'
const userRule = '.mine { background: url("/static/fonts/keep.woff2"); }'

// ── pure ─────────────────────────────────────────────────────────────────────────────────────
const texts = {
  empty: '',
  'only whitespace': '  \n\n\t\n',
  'gui-test custom': guiCustom,
  'gui-test managed': guiManaged,
  'example managed': exManaged,
  'gui-test as 1.0': guiOld,
  'gui-test as 1.0 with the old name': guiOld.replaceAll('QuartzControl:managed', 'Quartz-GUI:managed'),
  'gui-test as 1.0, CRLF': guiOld.replaceAll('\n', '\r\n'),
  'both names, css-vars twice': `${block('css-vars', ':root {\n  --a: 1;\n}', 'Quartz-GUI')}\n\n.x {}\n\n${block('css-vars', ':root {\n  --b: 2;\n}')}\n`,
  'two copies, same name': `a {}\n${block('css-vars', ':root { --a: 1; }')}\nb {}\n\n\n${block('css-vars', ':root { --a: 2; --c: 3; }')}\n\nc {}\n`,
  'nested, same name': `${M('imports')[0]}\n@use "./custom/a";\n${block('imports', '@use "./custom/b";')}\n${M('imports')[1]}\n`,
  'old inside new (beta.2)': `${M('imports')[0]}\n@use "./custom/a";\n${block('imports', '@use "./custom/b";', 'Quartz-GUI')}\n${M('imports')[1]}\n`,
  unterminated: `x {}\n${M('fonts')[0]}\n@font-face {}\n`,
  'end before start': `${M('fonts')[1]}\nmid\n${M('fonts')[0]}\nbody\n`,
  'scripts before the markers': `// Ünïcödé 日本語 🎨🎨\n.é { content: "👩‍👩‍👧"; }\n${block('fonts', fontsBody)}\n${block('css-vars', ':root {\n  --ü: 1;\n}')}\n`,
  'fonts with absolute urls': `@use "./variables.scss" as *;\n\n${userRule}\n\n${block('fonts', fontsBody)}\n${block('google-fonts', '/* x */\n@font-face { src: url(/static/fonts/g.woff2); }')}\n`,
  'use lines': `@use "./variables.scss" as *;\n@use './_quartzcontrol.scss' as qc;\n.x {}\n`,
  'use line variants': `  @use "./quartzcontrol" as *;\n`,
  'use line not first': `.x {}\n@use   "./quartzcontrol"   ;\n`,
  'use line wrong quotes': `@use "./quartzcontrol';\n`,
  'use line in a comment-ish place': `/* @use "./quartzcontrol"; */\n`,
  'comments then rules': `// one\n/* two\n   three */\n\n.rule {}\n`,
  'charset and forward': `@charset "utf-8";\n@forward "x";\n// note\n.rule {}\n`,
  'use after rule': `.rule {}\n@use "./later";\n`,
  'rules only': `@font-face { a: b; }\n\n  @font-face {  a:   b; }\n/* lead */ @font-face { c: d; }\nx { y { z: 1 } }\n} stray\ntail text`,
  'braces unbalanced': `{ { }\n`,
  'stray close first': '} .a { b: c; }\n.d { e: f; }',
  'variables': ':root {\n  --a: 1px;\n  --b: red ;\n  --1: x;\n}\n\n:root[saved-theme="dark"] {\n  --a: 2px;\n  --c: blue;\n}\n\n:root:not([saved-theme=dark]) {\n  --d: green;\n  --a: 3px;\n}\n:root[saved-theme=\'dark\']{--e:1;}\n:root { --a: 9px; }',
  'variables, light-only with root': ':root:not([saved-theme="dark"]) {\n  --x: 1;\n}\n:root {\n  --x: 2;\n}',
  'variables, nothing': '.x { --y: 1; }'
}
const ids = ['imports', 'fonts', 'google-fonts', 'css-vars', 'imported-styles']
const pure = []
// An answer equal to the text it was given is recorded as { same: true }.
const same = (text, answer) => (answer === text ? { same: true } : answer)
for (const [name, text] of Object.entries(texts)) {
  const entry = { name, text, get: {}, strip: {}, upsert: {}, emptyUpsert: {}, spans: {} }
  for (const id of ids) {
    entry.get[id] = style.getManagedBlock(text, id)
    entry.strip[id] = same(text, style.stripManagedBlock(text, id))
    entry.upsert[id] = same(text, style.upsertManagedBlock(text, id, 'BODY'))
    entry.emptyUpsert[id] = same(text, style.upsertManagedBlock(text, id, ''))
    entry.spans[id] = style.findManagedBlocks(text, id).map(({ from, to }) => ({ from, to }))
  }
  Object.assign(entry, {
    hasUse: style.hasManagedUse(text), stripUse: same(text, style.stripManagedUse(text)), ensureUse: same(text, style.ensureManagedUse(text)),
    rename: same(text, style.renameLegacyMarkers(text)), migrate: same(text, style.migrateOnWrite(text)), relativeUrls: same(text, style.relativeFontUrls(text)),
    split: style.splitRules(text), joinTwice: same(text, style.joinUniqueRules([text, text])),
    insert: same(text, style.insertBeforeRules(text, 'INSERTED')),
    importBlock: same(text, style.upsertImportBlock(text, '@use "./custom/z";')), importBlockEmpty: same(text, style.upsertImportBlock(text, '')),
    overrides: style.parseVariableOverrides(text),
    sources: style.managedBody({ custom: text, managed: text, managedExists: true }, 'css-vars'),
    without: style.sourcesWithout({ custom: text, managed: '', managedExists: false }, 'fonts')
  })
  pure.push(entry)
}
const renders = [
  [], [{ key: 'a', light: '1' }], [{ key: 'a', light: ' ', dark: '2' }], [{ key: 'a', light: '1', dark: '' }],
  [{ key: 'a', light: '1', lightOnly: true }], [{ key: 'a', light: '1', dark: '2', lightOnly: true }], [{ key: 'a', light: '', lightOnly: true }],
  [{ key: 'b', light: '1' }, { key: 'a', light: '2', dark: '3' }, { key: 'c', light: '4', lightOnly: true }, { key: 'd', light: '', dark: '5' }]
].map((overrides) => ({ overrides, rendered: style.renderVariableOverrides(overrides) }))
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'pure.json'), JSON.stringify({ texts: pure, renders }, null, 2) + '\n')

// ── steps on a project ───────────────────────────────────────────────────────────────────────
const work = mkdtempSync(join(tmpdir(), 'qh-styles-golden-'))
const mask = (text) => typeof text === 'string' ? text.replaceAll(work, '@P@') : text
const deep = (value) => JSON.parse(mask(JSON.stringify(value ?? null)))

function stylesTree(project) {
  const root = join(projects, project, 'quartz', 'styles')
  // The stylesheets under custom/ only have to exist here (the load order is resolved against
  // the disk); their text is a line.
  const tree = { 'custom.scss': read(project, 'custom.scss'), '_quartzcontrol.scss': shortGoogleFonts(read(project, '_quartzcontrol.scss')) }
  for (const name of readdirSync(join(root, 'custom')).sort()) tree[`custom/${name}`] = `// ${name}\n`
  return tree
}
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

const guiTree = stylesTree('gui-test')
const exTree = stylesTree('Example')
const { '_quartzcontrol.scss': _drop, ...guiOldTree } = { ...guiTree, 'custom.scss': guiOld }
const vars = (list) => list
const step = (call, ...args) => ({ call, args })

const cases = {
  'gui-test moved': { tree: guiTree, steps: [
    step('getVariableOverrides'), step('variableCollisions'), step('currentOrder'), step('loadedStylesheetsLastFirst'),
    step('saveVariableOverrides', vars([{ key: 'tpl-space-md', light: '1.5rem' }, { key: 'new-one', light: 'red', dark: 'blue' }, { key: 'only-light', light: '#fff', lightOnly: true }])),
    step('getVariableOverrides'),
    step('setImportOrder', ['custom/layout.scss', 'custom/foundation.scss', 'custom/does-not-exist.scss']),
    step('currentOrder'), step('repairManagedUse'), step('migrateFontUrls'),
    step('saveCustomScss', '@use "./variables.scss" as *;\n\n.mine { color: red; }\n'),
    step('saveCustomScss', '@use "./variables.scss" as *;\n@use "./quartzcontrol";\n:root { --new-one: green; }\n'),
    step('variableCollisions'),
    step('writeManagedBlocks', { fonts: null, 'google-fonts': '@font-face { src: url("/static/fonts/x.woff2"); }' }),
    step('migrateManagedStyles', { snapshot: false }),
    step('replaceCustomBody', '// fresh body\n.a {}\n')
  ] },
  'example moved': { tree: exTree, steps: [
    step('getVariableOverrides'), step('currentOrder'), step('saveVariableOverrides', []), step('getVariableOverrides'), step('setImportOrder', [])
  ] },
  'gui-test as 1.0': { tree: guiOldTree, steps: [
    step('getVariableOverrides'), step('variableCollisions'), step('currentOrder'), step('loadedStylesheetsLastFirst'),
    step('saveVariableOverrides', vars([{ key: 'tpl-space-md', light: '2rem', dark: '' }])),
    step('setImportOrder', ['custom/pages.scss', 'custom/a11y.scss']),
    step('writeManagedBlocks', { fonts: '@font-face { src: url(/static/fonts/y.woff2); }' }),
    step('repairManagedUse'),
    step('replaceCustomBody', '@use "./variables.scss" as *;\n// new body\n.b {}\n'),
    step('migrateManagedStyles', { snapshot: false }), step('variableCollisions'), step('currentOrder'),
    step('migrateManagedStyles', { snapshot: false })
  ] },
  'gui-test as 1.0 with the old name': { tree: { ...guiOldTree, 'custom.scss': guiOld.replaceAll('QuartzControl:managed', 'Quartz-GUI:managed') }, steps: [
    step('getVariableOverrides'), step('currentOrder'), step('migrateFontUrls'),
    step('writeManagedBlocks', { fonts: '@font-face { x: y; }' })
  ] },
  'repair: line deleted': { tree: { ...exTree, 'custom.scss': '@use "./variables.scss" as *;\n\n.x {}\n' }, steps: [step('repairManagedUse'), step('repairManagedUse')] },
  'repair: file missing': { tree: { 'custom.scss': '@use "./variables.scss" as *;\n@use "./quartzcontrol";\n' }, steps: [step('repairManagedUse'), step('repairManagedUse')] },
  'repair: neither': { tree: { 'custom.scss': '.x {}\n' }, steps: [step('repairManagedUse')] },
  'repair: no custom.scss': { tree: { '_quartzcontrol.scss': '// only\n' }, steps: [step('repairManagedUse'), step('getVariableOverrides')] },
  'nothing at all': { tree: {}, steps: [step('getVariableOverrides'), step('currentOrder'), step('migrateFontUrls'), step('loadedStylesheetsLastFirst'),
    step('saveVariableOverrides', vars([{ key: 'a', light: '1' }])), step('setImportOrder', ['custom/x.scss'])] },
  'font urls in both files': { tree: {
    'custom.scss': `@use "./quartzcontrol";\n${userRule}\n${block('fonts', fontsBody)}\n`,
    '_quartzcontrol.scss': `// head\n${block('fonts', fontsBody.replace('a.woff2', 'm.woff2'))}\n${block('google-fonts', '@font-face { src: url( "/static/fonts/g.woff2"); }')}\n`
  }, steps: [step('migrateFontUrls'), step('migrateFontUrls')] },
  'copies in both files': { tree: {
    'custom.scss': `@use "./quartzcontrol";\n.u {}\n${block('css-vars', ':root {\n  --a: custom;\n}')}\n${block('imports', '@use "./custom/one";\n@use "./custom/two";')}\n`,
    '_quartzcontrol.scss': `${block('imports', '@use "./custom/one";\n@use "./custom/two";')}\n\n${block('css-vars', ':root {\n  --a: managed;\n  --b: 1;\n}')}\n`,
    'custom/one.scss': '.one {}\n', 'custom/two.scss': '.two {}\n'
  }, steps: [step('getVariableOverrides'), step('currentOrder'), step('variableCollisions'),
    step('saveVariableOverrides', vars([{ key: 'b', light: '2' }]))] },
  'one copy, a line for a gone file': { tree: {
    'custom.scss': `@use "./quartzcontrol";\n`,
    '_quartzcontrol.scss': `${block('imports', '@use "./custom/one";\n@use "./custom/gone";')}\n`,
    'custom/one.scss': '.one {}\n'
  }, steps: [step('writeManagedBlocks', { 'css-vars': ':root { --x: 1; }' })] },
  'namespaces': { tree: {
    'custom.scss': '@use "./variables.scss" as *;\n.x {}\n',
    'custom/01-typo.scss': '', 'custom/typo.grafie.scss': '', 'custom/typo.scss': '', 'imported/_partial.scss': '', 'custom/a.css': '', 'custom/sub/deep.scss': '',
    'custom/typo-2.scss': '', 'custom/ns-01-typo.scss': ''
  }, steps: [
    step('setImportOrder', ['custom/01-typo.scss', 'custom/typo.grafie.scss', 'custom/typo.scss', 'imported/_partial.scss', 'custom/a.css', 'custom/typo-2.scss', 'custom/ns-01-typo.scss', 'custom/sub/deep.scss', 'other/x.scss']),
    step('currentOrder'), step('loadedStylesheetsLastFirst')
  ] },
  'collisions': { tree: {
    'custom.scss': `@use "./quartzcontrol";\n/* :root { --a: 1; } */\n/* :root {\n  --z: 1;\n} */\n// :root { --b: 1; }\n:root { --a: 2; }\n:root[saved-theme='dark'] { --c: 3; }\n:root:not([saved-theme=dark]) { --l: 1; }\nhtml :root { --a: 9; }\na:root{--x:1}\n`,
    '_quartzcontrol.scss': `${block('css-vars', ':root {\n  --a: 1;\n  --b: 1;\n  --z: 1;\n}\n\n:root[saved-theme="dark"] {\n  --c: 1;\n}\n\n:root:not([saved-theme="dark"]) {\n  --l: 1;\n}')}\n`
  }, steps: [step('variableCollisions'), step('getVariableOverrides')] },
  'a partial named without its underscore': { tree: {
    'custom.scss': `${block('imports', '@use "./custom/part";\n@use "./custom/plain";\n@use "./custom/both";')}\n.x {}\n`,
    'custom/_part.scss': '', 'custom/plain.css': '', 'custom/both.scss': '', 'custom/_both.scss': ''
  }, steps: [step('currentOrder'), step('writeManagedBlocks', { 'css-vars': ':root { --q: 1; }' })] },
  'save restores the use line only when moved': { tree: { 'custom.scss': '.x {}\n' }, steps: [step('saveCustomScss', '.y {}\n'), step('repairManagedUse')] }
}

mkdirSync(join(out, 'steps'), { recursive: true })
for (const file of readdirSync(join(out, 'steps'))) rmSync(join(out, 'steps', file))
for (const [name, c] of Object.entries(cases)) {
  const project = join(work, name.replace(/[^\w-]+/g, '-'))
  const styles = join(project, 'quartz', 'styles')
  mkdirSync(styles, { recursive: true })
  for (const [path, text] of Object.entries(c.tree)) {
    mkdirSync(dirname(join(styles, path)), { recursive: true })
    writeFileSync(join(styles, path), text)
  }
  // Each step records the files it changed (null: removed), against the state before it.
  const results = []
  let before = filesOf(styles)
  for (const s of c.steps) {
    let result
    try { result = await style[s.call](project, ...s.args) } catch (error) { result = { threw: String(error) } }
    const after = filesOf(styles)
    const changed = {}
    for (const path of new Set([...Object.keys(before), ...Object.keys(after)])) {
      if (before[path] !== after[path]) changed[path] = after[path] ?? null
    }
    results.push({ ...s, result: deep(result === undefined ? null : result), changed })
    before = after
  }
  writeFileSync(join(out, 'steps', `${name.replace(/[^\w-]+/g, '-')}.json`), JSON.stringify({ name, tree: c.tree, steps: results }, null, 2) + '\n')
}
rmSync(work, { recursive: true, force: true })
console.log(`managed-styles: ${pure.length} texts, ${renders.length} renders, ${Object.keys(cases).length} step cases`)
