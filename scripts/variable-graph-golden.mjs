#!/usr/bin/env node
// Golden files for VariableGraph and CssVariables, made by QuartzControl's own
// variableGraphService.ts and shared/cssVariables.ts:
//
// - `real/`: gui-test's stylesheets, the CSS of its last build (public/, 26 files) and the
//   theme.json of @quartz-themes/minimal, copied (read only).
// - `graphs.json`: getVariableGraph for projects made of those and of made-up CSS (strings and
//   comments with braces, @media and @layer, minified rules, data URLs, numeric names, a stray
//   brace, broken theme files, an own output folder).
// - `catalog.json`: the variable catalog, hexToHsl, defaultValueFor, isWritableCssValue and the
//   callout colours.
//
//   Runtime/node/bin/node scripts/variable-graph-golden.mjs [../QuartzControl] [~/Documents/QuartzProjekte]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const projects = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'variable-graph')

const graph = await loadQuartzControl(control, 'electron/main/services/variableGraphService.ts', {
  ...commonStubs, './projectDependencies': 'export function halfUnpackedModule() { return null }'
})
const css = await loadQuartzControl(control, 'shared/cssVariables.ts', {})

// ── the real inputs ──────────────────────────────────────────────────────────────────────────
rmSync(out, { recursive: true, force: true })
const gui = join(projects, 'gui-test')
const copyTree = (from, to, keep) => {
  for (const name of readdirSync(from)) {
    const full = join(from, name)
    if (statSync(full).isDirectory()) copyTree(full, join(to, name), keep)
    else if (keep(name)) { mkdirSync(to, { recursive: true }); cpSync(full, join(to, name)) }
  }
}
copyTree(join(gui, 'quartz', 'styles'), join(out, 'real', 'styles'), (n) => /\.(scss|css)$/.test(n))
copyTree(join(gui, 'public'), join(out, 'real', 'public'), (n) => n.endsWith('.css'))
mkdirSync(join(out, 'real', 'themes', 'minimal'), { recursive: true })
cpSync(join(gui, 'node_modules', '@quartz-themes', 'minimal', 'theme.json'), join(out, 'real', 'themes', 'minimal', 'theme.json'))

// ── made-up inputs ───────────────────────────────────────────────────────────────────────────
const M = (id) => [`/* --- QuartzControl:managed:${id}:start --- */`, `/* --- QuartzControl:managed:${id}:end --- */`]
const edgeBuild = [
  ':root{--a:1px;--b:var(--a);--c:var( --b ) var(--missing)}',
  '[data-section^="{{"] { --scoped: 1; }',
  '/* { not a rule } */ :root { --after-comment: ok; }',
  '@layer quartz-base { :root { --layered: blue; --self: var(--self); } :root[saved-theme="dark"] { --layered: navy; } @supports (x: y) { :root { --deep: 1; } } }',
  '@media (prefers-reduced-motion: reduce) { :root { --motion: 0s; } }',
  'html[saved-theme=dark] body h1 { --not-global: 1; }',
  'html, body { --html-light: 1; } body[saved-theme=\'dark\'] { --html-light: 2; }',
  ':root { --data: url("data:image/svg+xml;utf8,<svg style=\'fill:red;\'/>"); --multi: var(\n  --a\n) ; --1: one; --tpl-own: from-build; }',
  ':root { --quoted: "a;b}c"; --paren: calc((1px + 2px) * 3); --unclosed: "x\n; --next: y; }',
  // An unlayered light-only value over a layered dark one: dark mode gets the light value.
  '@layer quartz-base { :root[saved-theme="dark"] { --fallback: navy; } :root { --fallback: blue; } } :root { --fallback: red; }',
  // After a stray brace nothing more is read, not even a clean rule two rules later.
  '.x { color: red } } :root { --after-stray: lost; } :root { --after-stray-2: lost; }'
].join('\n')
const edgeTheme = {
  light: { base: ':root { --tl: #fff; --shared: var(--tl); --tpl-own: theme; } .later { --scoped-theme: 1 }' },
  dark: { base: ':root { --tl: #000; --shared: var(--tl) }', other: ':root { --ignored: 1 }' },
  brokenVarLinks: { '--tl': ['--dangling-a', '--dangling-b'], '--shared': ['--tl'] }
}
const ownStyles = {
  'custom.scss': `@use "./quartzcontrol";\n// :root { --commented: 'x }\n:root { --tpl-own: from-custom; --project-only: 1; }\n:root[saved-theme="dark"] { --project-only: 2; }\n@media (x) { :root { --media-own: 1; } }\n.scoped { --not-own: 1; }\n`,
  '_quartzcontrol.scss': `${M('imports')[0]}\n@use "./custom/one";\n${M('imports')[1]}\n\n${M('css-vars')[0]}\n:root {\n  --tpl-own: from-page;\n  --page-only: 3;\n}\n${M('css-vars')[1]}\n`,
  'custom/one.scss': ':root { --from-one: 1; --project-only: from-one; --a: one-wins; }\n'
}

const cases = [
  { name: 'gui-test', styles: 'real', build: 'real' },
  { name: 'gui-test with minimal', styles: 'real', build: 'real', theme: 'minimal' },
  { name: 'gui-test without a build', styles: 'real' },
  { name: 'minimal alone', theme: 'minimal' },
  { name: 'edges', styles: ownStyles, build: { 'index.css': edgeBuild, 'nested/deep.css': ':root { --nested: 1 }', 'node_modules/x.css': ':root { --ignored: 1 }', 'dist/y.css': ':root { --ignored2: 1 }' }, theme: { edge: edgeTheme } },
  { name: 'edges in an own output folder', styles: ownStyles, build: { 'index.css': edgeBuild }, outputDir: 'site-out' },
  { name: 'broken theme files', theme: { 'not-json': '{', 'no-base': { light: { base: 5 }, dark: {} }, 'links-only': { brokenVarLinks: { '--x': ['--y'] } } }, themeId: 'not-json' },
  { name: 'a theme without base', theme: { 'no-base': { light: { base: 5 }, dark: {} } }, themeId: 'no-base' },
  { name: 'a theme with only links', theme: { 'links-only': { brokenVarLinks: { '--x': ['--y', 'z'] } } }, themeId: 'links-only' },
  { name: 'a theme that is not installed', themeId: 'nowhere' },
  { name: 'many build files', build: Object.fromEntries(Array.from({ length: 55 }, (_, i) => [`f${String(i).padStart(2, '0')}.css`, `:root { --f${i}: ${i}; }`])) }
]

const work = mkdtempSync(join(tmpdir(), 'qh-graph-golden-'))
const results = []
for (const c of cases) {
  const project = join(work, c.name.replace(/[^\w-]+/g, '-'))
  mkdirSync(join(project, 'quartz', 'styles'), { recursive: true })
  if (c.styles === 'real') cpSync(join(out, 'real', 'styles'), join(project, 'quartz', 'styles'), { recursive: true })
  else for (const [p, t] of Object.entries(c.styles ?? {})) { mkdirSync(dirname(join(project, 'quartz', 'styles', p)), { recursive: true }); writeFileSync(join(project, 'quartz', 'styles', p), t) }
  const buildDir = join(project, c.outputDir ?? 'public')
  if (c.build === 'real') cpSync(join(out, 'real', 'public'), buildDir, { recursive: true })
  else for (const [p, t] of Object.entries(c.build ?? {})) { mkdirSync(dirname(join(buildDir, p)), { recursive: true }); writeFileSync(join(buildDir, p), t) }
  let themeId = c.themeId
  if (c.theme === 'minimal') {
    mkdirSync(join(project, 'node_modules', '@quartz-themes', 'minimal'), { recursive: true })
    cpSync(join(out, 'real', 'themes', 'minimal', 'theme.json'), join(project, 'node_modules', '@quartz-themes', 'minimal', 'theme.json'))
    themeId = 'minimal'
  } else if (c.theme) {
    for (const [id, theme] of Object.entries(c.theme)) {
      mkdirSync(join(project, 'node_modules', '@quartz-themes', id), { recursive: true })
      writeFileSync(join(project, 'node_modules', '@quartz-themes', id, 'theme.json'), typeof theme === 'string' ? theme : JSON.stringify(theme))
    }
    themeId ??= Object.keys(c.theme)[0]
  }
  const result = await graph.getVariableGraph(project, themeId, c.outputDir)
  results.push({ ...c, themeId: themeId ?? null, graph: JSON.parse(JSON.stringify(result)) })
}
rmSync(work, { recursive: true, force: true })
writeFileSync(join(out, 'graphs.json'), JSON.stringify(results, null, 2) + '\n')

// ── the catalog ──────────────────────────────────────────────────────────────────────────────
const hexes = ['#284b63', '284b63', '#FFF', '#ffffff', '#000000', '#7f7f7f', '#ff0000', '#00ff00', '#0000ff', '#ff00ff', '#123456', '#abcdef', '#e5e5e5', '#zzzzzz', '', '#12345', '#c0ffee', '#808000', '#008080', '#3b82f6']
const palette = { lightMode: { light: '#faf8f8', lightgray: '#e5e5e5', gray: '#b8b8b8', darkgray: '#4e4e4e', dark: '#2b2b2b', secondary: '#284b63', tertiary: '#84a59d', highlight: 'rgba(143, 159, 169, 0.15)', textHighlight: '#fff23688' },
  darkMode: { light: '#161618', secondary: '#7b97aa' } }
const typography = { header: 'Schibsted Grotesk', body: 'Source Sans Pro', code: 'IBM Plex Mono' }
const values = ['red', 'rgb(0 0 0 / 50%)', 'a}', '{', 'x;y', '/* c', 'c */', 'a\\b', 'calc(1px + 2px)', '', '"quoted"', 'url(x/y)']
const catalog = {
  variables: css.CSS_VARIABLES,
  callouts: css.CALLOUT_COLORS,
  hsl: hexes.map((hex) => ({ hex, hsl: css.hexToHsl(hex) })),
  defaults: css.CSS_VARIABLES.flatMap((def) => ['light', 'dark'].map((mode) => ({ key: def.key, mode, value: css.defaultValueFor(def, palette, typography, mode) }))),
  defaultsWithoutColors: css.CSS_VARIABLES.map((def) => ({ key: def.key, value: css.defaultValueFor(def, {}, undefined, 'light') })),
  writable: values.map((value) => ({ value, writable: css.isWritableCssValue(value) })),
  calloutValues: [undefined, '', '#448aff', 'var(--secondary)', 'var(--lightgray)', 'var(--missing)', 'var(--sec-ondary)', 'var( --secondary)']
    .flatMap((value) => ['light', 'dark'].map((mode) => ({ value: value ?? null, mode, resolved: css.resolveCalloutColorValue(value, palette, mode) }))),
  palette, typography
}
writeFileSync(join(out, 'catalog.json'), JSON.stringify(catalog, null, 2) + '\n')
console.log(`variable-graph: ${results.length} graphs, ${catalog.variables.length} catalog entries`)
for (const r of results) console.log(`  ${r.name}: ${Object.keys(r.graph.vars).length} vars, ${Object.keys(r.graph.dependents).length} with dependents, sources ${JSON.stringify(r.graph.sources)}`)
