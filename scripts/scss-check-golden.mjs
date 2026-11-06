#!/usr/bin/env node
// Golden file for ScssCheck, made by QuartzControl's own styleService.ts: checkStyles,
// checkStyleSource and readQuartzFrameMeasures on projects whose quartz/styles are copies of
// gui-test's and Example's (read only) or made up, each with node_modules/sass linked to the sass
// in Helpers/node_modules - the version gui-test has (1.104.1), so both sides compile with the same
// Sass. The Swift test (ScssCheckTests) lays out the same projects and asks the sass-check helper.
//
//   Runtime/node/bin/node scripts/scss-check-golden.mjs [../QuartzControl] [~/Documents/QuartzProjekte]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const projects = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'scss-check')
const sass = join(here, '..', 'Helpers', 'node_modules', 'sass')

const style = await loadQuartzControl(control, 'electron/main/services/styleService.ts', commonStubs)

// The trees: path under quartz/styles → text. `@gui@` / `@example@` take that project's stylesheets.
const stylesOf = (project) => {
  const dir = join(projects, project, 'quartz', 'styles')
  const tree = {}
  const walk = (d, prefix) => {
    for (const name of readdirSync(d).sort()) {
      const full = join(d, name)
      if (statSync(full).isDirectory()) { walk(full, `${prefix}${name}/`); continue }
      tree[`${prefix}${name}`] = readFileSync(full, 'utf8')
    }
  }
  walk(dir, '')
  return tree
}
const gui = stylesOf('gui-test')
const example = stylesOf('Example')
const M = (id) => [`/* --- QuartzControl:managed:${id}:start --- */`, `/* --- QuartzControl:managed:${id}:end --- */`]
const quartzOnly = { 'variables.scss': gui['variables.scss'], 'base.scss': gui['base.scss'] }

const cases = {
  'gui-test': { tree: gui, calls: [['checkStyles'], ['readQuartzFrameMeasures'],
    ['checkStyleSource', 'custom.scss', gui['custom.scss']], ['checkStyleSource', '_quartzcontrol.scss', gui['_quartzcontrol.scss']],
    ['checkStyleSource', 'custom/layout.scss', '.a { color: $nope; }\n'], ['checkStyleSource', 'custom/layout.scss', '@use "../variables" as *;\n.a { width: $desktop; }\n']] },
  'example': { tree: example, calls: [['checkStyles'], ['readQuartzFrameMeasures']] },
  'syntax error in custom.scss': { tree: { ...quartzOnly, 'custom.scss': '@use "./variables.scss" as *;\n\n.a {\n  color: red\n  .b { }\n' }, calls: [['checkStyles']] },
  'error in a loaded file': { tree: { ...quartzOnly, 'custom.scss': `${M('imports')[0]}\n@use "./custom/broken";\n${M('imports')[1]}\n`, 'custom/broken.scss': '.x {\n  width: 10px +;\n}\n' }, calls: [['checkStyles']] },
  'undefined variable': { tree: { ...quartzOnly, 'custom.scss': '.a { color: $missing; }\n' }, calls: [['checkStyles']] },
  'beta.2 block inside ours': { tree: { ...quartzOnly,
    'custom.scss': `${M('imports')[0]}\n@use "./custom/a";\n/* --- Quartz-GUI:managed:imports:start --- */\n@use "./custom/a";\n/* --- Quartz-GUI:managed:imports:end --- */\n${M('imports')[1]}\n`,
    'custom/a.scss': '.a {}\n' }, calls: [['checkStyles']] },
  'the managed file missing': { tree: { ...quartzOnly, 'custom.scss': '@use "./variables.scss" as *;\n@use "./quartzcontrol";\n' }, calls: [['checkStyles']] },
  'an error in a dependency': { tree: { ...quartzOnly, 'custom.scss': '@use "sass:math";\n.a { width: math.div(1px, 0px) + 1em; }\n' }, calls: [['checkStyles']] },
  'no custom.scss': { tree: quartzOnly, calls: [['checkStyles'], ['readQuartzFrameMeasures']] },
  'no sass': { tree: { 'custom.scss': '.a {}\n', ...quartzOnly }, sass: 'none', calls: [['checkStyles'], ['checkStyleSource', 'custom.scss', '.a {}'], ['readQuartzFrameMeasures']] },
  'sass still unpacking': { tree: { 'custom.scss': '.a {}\n', ...quartzOnly }, sass: 'half', calls: [['checkStyles'], ['readQuartzFrameMeasures']] },
  'css file': { tree: { ...quartzOnly, 'custom.scss': '' }, calls: [['checkStyleSource', 'custom/plain.css', '.a { color: red; }\n'], ['checkStyleSource', 'custom/plain.css', '.a { .b { c: d } }\n$x: 1;\n'], ['checkStyleSource', 'imported/x.scss', '@use "./missing";\n']] },
  'measures: no variables': { tree: { 'custom.scss': '', 'base.scss': gui['base.scss'] }, calls: [['readQuartzFrameMeasures']] },
  'measures: no base': { tree: { 'custom.scss': '', 'variables.scss': gui['variables.scss'] }, calls: [['readQuartzFrameMeasures']] },
  'measures: base without a cap': { tree: { 'custom.scss': '', 'variables.scss': gui['variables.scss'], 'base.scss': '.page {\n  margin: 0 auto;\n  .inner { max-width: 10px; }\n}\n' }, calls: [['readQuartzFrameMeasures']] },
  'measures: a cap it cannot evaluate': { tree: { 'custom.scss': '', 'variables.scss': gui['variables.scss'], 'base.scss': '.page {\n  max-width: calc(#{$nowhere} + 300px);\n}\n' }, calls: [['readQuartzFrameMeasures']] },
  'measures: a cap in px': { tree: { 'custom.scss': '', 'variables.scss': gui['variables.scss'], 'base.scss': '\n.page{max-width:1400px;}' }, calls: [['readQuartzFrameMeasures']] },
  'measures: a grid missing': { tree: { 'custom.scss': '', 'base.scss': gui['base.scss'], 'variables.scss': gui['variables.scss'].replace(/\$tabletGrid:[\s\S]*?\);/, '$tabletGrid: (rowGap: 5px);') }, calls: [['readQuartzFrameMeasures']] },
  'measures: breakpoints in em': { tree: { 'custom.scss': '', 'base.scss': gui['base.scss'], 'variables.scss': gui['variables.scss'].replace(/mobile:\s*\d+px/, 'mobile: 50em') }, calls: [['readQuartzFrameMeasures']] },
  // The two counter-checks that first went uncaught: a track with a space inside parentheses, and
  // an error in a file outside quartz/styles.
  'measures: a track with parentheses': { tree: { 'custom.scss': '', 'base.scss': gui['base.scss'],
    'variables.scss': gui['variables.scss'].replace('templateColumns: "#{$sidePanelWidth} auto #{$sidePanelWidth}"', 'templateColumns: "minmax(0, 1fr) auto #{$sidePanelWidth}"') }, calls: [['readQuartzFrameMeasures']] },
  'an error outside quartz/styles': { tree: { ...quartzOnly, 'custom.scss': '@use "../outside";\n', '../outside.scss': '.x { width: 1px +; }\n' }, calls: [['checkStyles']] },
  'measures: broken variables': { tree: { 'custom.scss': '', 'base.scss': gui['base.scss'], 'variables.scss': '$x: (;\n' }, calls: [['readQuartzFrameMeasures']] }
}

const work = mkdtempSync(join(tmpdir(), 'qh-scss-golden-'))
mkdirSync(out, { recursive: true })
const results = []
for (const [name, c] of Object.entries(cases)) {
  const project = join(work, name.replace(/[^\w-]+/g, '-'))
  for (const [path, text] of Object.entries(c.tree)) {
    mkdirSync(dirname(join(project, 'quartz', 'styles', path)), { recursive: true })
    writeFileSync(join(project, 'quartz', 'styles', path), text)
  }
  mkdirSync(join(project, 'quartz', 'styles'), { recursive: true })
  writeFileSync(join(project, 'package.json'), '{ "name": "golden", "private": true }\n')
  if (c.sass !== 'none') {
    mkdirSync(join(project, 'node_modules'), { recursive: true })
    if (c.sass === 'half') mkdirSync(join(project, 'node_modules', 'sass'))
    else symlinkSync(sass, join(project, 'node_modules', 'sass'))
  }
  const answers = []
  for (const [call, ...args] of c.calls) {
    const answer = await style[call](project, ...args)
    answers.push({ call, args, answer: JSON.parse(JSON.stringify(answer).replaceAll(project, '@P@')) })
  }
  results.push({ name, tree: Object.fromEntries(Object.entries(c.tree).map(([p, t]) => [p, t === gui[p] ? { gui: p } : t === example[p] ? { example: p } : t])), sass: c.sass ?? 'linked', answers })
}
// The stylesheets of gui-test and Example once, the cases point at them.
writeFileSync(join(out, 'gui-test.json'), JSON.stringify(gui, null, 2) + '\n')
writeFileSync(join(out, 'example.json'), JSON.stringify(example, null, 2) + '\n')
writeFileSync(join(out, 'cases.json'), JSON.stringify(results, null, 2) + '\n')
rmSync(work, { recursive: true, force: true })
console.log(`scss-check: ${results.length} projects, ${results.reduce((n, r) => n + r.answers.length, 0)} answers`)
for (const r of results) for (const a of r.answers) console.log(`  ${r.name} ${a.call}: ${JSON.stringify(a.answer).slice(0, 150)}`)
