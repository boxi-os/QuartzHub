#!/usr/bin/env node
// Golden file for SiteFonts, made by QuartzControl's own styleService.ts: collectFontFaces,
// readPreviewFonts, projectStylesheets and takenClasses on projects made of gui-test's stylesheets,
// font files and build CSS (read only, out of Fixtures/variable-graph and Fixtures/font-file), the
// theme minimal's font list, and made-up edges (a linked font file, files past the ceilings, an
// unreadable theme, plugin code).
//
//   Runtime/node/bin/node scripts/site-fonts-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { createHash } from 'node:crypto'
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const fixtures = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures')
const out = join(fixtures, 'site-fonts')
const style = await loadQuartzControl(control, 'electron/main/services/styleService.ts', { ...commonStubs, './projectDependencies': 'export function halfUnpackedModule() { return null }' })

const noto = 'font-file/files/noto-sans-latin-400-700.woff2'
const italic = 'font-file/files/noto-sans-latin-italic-400-700.woff2'
const fontsBlock = `/* --- QuartzControl:managed:fonts:start --- */
@font-face { font-family: "Noto Sans"; src: url("static/fonts/noto-sans-latin-400-700.woff2") format("woff2"); font-weight: 100 900; unicode-range: U+0000-00FF; }
@font-face { font-family: "Noto Sans"; font-style: italic; src: url("static/fonts/noto-sans-latin-italic-400-700.woff2"); font-weight: 100 900; }
@font-face { font-family: "Linked"; src: url("static/fonts/linked.woff2"); }
@font-face { font-family: "Gone"; src: url("static/fonts/gone.woff2"); }
@font-face { font-family: "Big"; src: url("static/fonts/big-a.woff2"); }
@font-face { font-family: "Big"; font-weight: 700; src: url("static/fonts/big-b.woff2"); }
@font-face { font-family: "Big"; font-weight: 900; src: url("static/fonts/big-c.woff2"); }
@font-face { font-family: "Huge"; src: url("static/fonts/huge.woff2"); }
@font-face { font-family: "Remote"; src: url("https://cdn.example/x.woff2"); }
/* --- QuartzControl:managed:fonts:end --- */`
const cases = {
  'gui-test': { real: true, theme: 'minimal', calls: [['collectFontFaces', 'minimal'], ['collectFontFaces'], ['projectStylesheets'],
    ['readPreviewFonts', ['Noto Sans', 'noto sans mono', 'Schibsted Grotesk', 'Source Sans Pro', 'IBM Plex Mono']],
    ['takenClasses', ['tpl-', 'nav-']], ['takenClasses', ['layout-box-']], ['takenClasses', []]] },
  'edges': { files: {
    'quartz/styles/custom.scss': `@use "./quartzcontrol";\n.layout-box-title {}\n.x-layout-box-no {}\n`,
    'quartz/styles/_quartzcontrol.scss': `${fontsBlock}\n`,
    'quartz/styles/custom/a.scss': '@font-face { font-family: "Own"; src: url(static/fonts/own.woff2); }\n.layout-box-hint-- {}\n--layout-box-var: 1;\n',
    'quartz/styles/custom/skip.txt': '@font-face { font-family: "Txt"; }',
    'quartz/styles/imported/b.css': '@font-face { font-family: "Imported"; }',
    'public/index.css': '@font-face { font-family: "Noto Sans"; src: url(https://site/static/fonts/x.woff2); }\n@font-face { font-family: "Built"; src: url(https://site/static/fonts/built.woff2); font-style: italic; }',
    'public/static/fonts/quartz-fonts.css': '@font-face { font-family: "Selfhosted"; src: url("static/fonts/self.woff2"); }',
    'public/static/fonts/built.woff2': { fixture: italic },
    'public/static/fonts/notes.txt': 'x',
    'quartz/static/fonts/noto-sans-latin-400-700.woff2': { fixture: noto },
    'quartz/static/fonts/noto-sans-latin-italic-400-700.woff2': { fixture: italic },
    'quartz/static/fonts/own.woff2': { size: 100 },
    'quartz/static/fonts/big-a.woff2': { size: 12 * 1024 * 1024 }, 'quartz/static/fonts/big-b.woff2': { size: 12 * 1024 * 1024 },
    'quartz/static/fonts/big-c.woff2': { size: 12 * 1024 * 1024 }, 'quartz/static/fonts/huge.woff2': { size: 65 * 1024 * 1024 },
    'quartz/static/fonts/linked.woff2': { link: 'own.woff2' },
    '.quartz/plugins/layout-box/dist/index.js': 'const c = "layout-box-content layout-box-title"; x.classList.add(`layout-box-${y}`)\n',
    '.quartz/plugins/layout-box/dist/deep/style.css': '.layout-box-deep {}', '.quartz/plugins/layout-box/src/ignored.js': '"layout-box-src"',
    '.quartz/plugins/other/dist/x.mjs': '"layout-box-from-mjs nav-thing"',
    'node_modules/@quartz-themes/broken/theme.json': '{ nope',
    'node_modules/@quartz-themes/fonts/theme.json': JSON.stringify({ meta: { fontFiles: [{ family: 'Theme Sans', weight: '100 1000' }, { style: 'italic' }, { family: 'Theme Mono', style: 'italic', weight: '400' }] } })
  }, calls: [['collectFontFaces', 'fonts'], ['collectFontFaces', 'broken'], ['collectFontFaces', 'absent'], ['projectStylesheets'],
    ['readPreviewFonts', ['noto sans', 'Linked', 'Gone', 'Big', 'Huge', 'Remote', 'Own', 'Built', 'Selfhosted']],
    ['takenClasses', ['layout-box-']], ['takenClasses', ['layout-box-', 'nav-']]] },
  'empty': { files: {}, calls: [['collectFontFaces'], ['projectStylesheets'], ['readPreviewFonts', ['x']], ['takenClasses', ['a-']]] }
}

const sha1 = (data) => createHash('sha1').update(data).digest('hex')
const work = mkdtempSync(join(tmpdir(), 'qh-site-fonts-golden-'))
const results = []
for (const [name, c] of Object.entries(cases)) {
  const project = join(work, name)
  mkdirSync(project, { recursive: true })
  if (c.real) {
    cpSync(join(fixtures, 'variable-graph', 'real', 'styles'), join(project, 'quartz', 'styles'), { recursive: true })
    cpSync(join(fixtures, 'variable-graph', 'real', 'public'), join(project, 'public'), { recursive: true })
    mkdirSync(join(project, 'quartz', 'static', 'fonts'), { recursive: true })
    for (const file of ['noto-sans-latin-400-700.woff2', 'noto-sans-latin-italic-400-700.woff2', 'noto-sans-mono-latin-400-700.woff2']) {
      cpSync(join(fixtures, 'font-file', 'files', file), join(project, 'quartz', 'static', 'fonts', file))
    }
    mkdirSync(join(project, 'node_modules', '@quartz-themes', 'minimal'), { recursive: true })
    cpSync(join(fixtures, 'variable-graph', 'real', 'themes', 'minimal', 'theme.json'), join(project, 'node_modules', '@quartz-themes', 'minimal', 'theme.json'))
  }
  for (const [path, spec] of Object.entries(c.files ?? {})) {
    const full = join(project, path)
    mkdirSync(dirname(full), { recursive: true })
    if (typeof spec === 'string') writeFileSync(full, spec)
    else if (spec.fixture) cpSync(join(fixtures, spec.fixture), full)
    else if (spec.link) symlinkSync(spec.link, full)
    else writeFileSync(full, Buffer.alloc(spec.size, 7))
  }
  const answers = []
  for (const [call, ...args] of c.calls) {
    let answer = await style[call](project, ...args)
    if (call === 'readPreviewFonts') answer = { built: answer.built, faces: answer.faces.map(({ data, ...face }) => ({ ...face, length: data.length, sha1: sha1(Buffer.from(data)) })) }
    answers.push({ call, args, answer: JSON.parse(JSON.stringify(answer).replaceAll(project, '@P@')) })
  }
  results.push({ name, real: c.real ?? false, files: c.files ?? {}, answers })
}
rmSync(work, { recursive: true, force: true })
rmSync(out, { recursive: true, force: true })
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify(results, null, 2) + '\n')
console.log(`site-fonts: ${results.length} projects`)
for (const r of results) for (const a of r.answers) console.log(`  ${r.name} ${a.call}: ${JSON.stringify(a.answer).slice(0, 160)}`)
