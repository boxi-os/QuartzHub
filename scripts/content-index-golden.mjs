#!/usr/bin/env node
// Golden file for ContentIndexPage, made by QuartzControl's own `createIndexPage`
// (contentService.ts): each scenario is a project (files, quartz.config.yaml, whether globby is
// installed, a linked vault) and a title, and the answer is the result or the error's key plus
// the index.md written. globby is gui-test's (node_modules linked in, read only); without it the
// fallback walk runs. Run with LANG=de_DE.UTF-8: the list is sorted with localeCompare under
// Node's default locale.
//
//   LANG=de_DE.UTF-8 Runtime/node/bin/node scripts/content-index-golden.mjs [../QuartzControl] [gui-test]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const guiTest = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte', 'gui-test'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'content-index')
if (!existsSync(join(guiTest, 'node_modules', 'globby'))) throw new Error(`no globby in ${guiTest}/node_modules`)

const content = await loadQuartzControl(control, 'electron/main/services/contentService.ts', {
  ...commonStubs,
  './backupService': 'export async function snapshotContent() { throw new Error("no backups here") }',
  './configService': `import { parse } from 'yaml'; import { readFileSync } from 'fs'
    export async function readConfig(p) { return { configuration: parse(readFileSync(p + '/quartz.config.yaml', 'utf8')).configuration } }`,
  './projectDependencies': 'export function halfUnpackedModule() { return null }'
})

const garden = {
  'x/a.md': 'a', 'x/sub/b.md': 'b', 'y/c.md': 'c', 'z.md': 'z', 'tpl/t.md': 't', 'w/w.md': 'w', 'img/pic.png': 'p',
  'Up.MD': 'u', 'Teil 10.md': '10', 'Teil 2.md': '2', 'äpfel & Birnen.md': 'ä', 'Zebra.md': 'z', '.obsidian/app.json': '{}',
  '.hidden.md': 'h', 'a[1].md': 'a', 'Ordner mit Leerzeichen/n.md': 'n', 'B-ordner/b.md': 'b', 'b.md': 'b', 'only/deep/x.md': 'x'
}
const config = (patterns) => `configuration:\n  pageTitle: Test\n  ignorePatterns: ${JSON.stringify(patterns)}\nplugins: []\n`
const scenarios = [
  { id: 'fallback-basic', files: garden, config: config(['tpl', 'private/**']), title: '  Mein Garten  ' },
  { id: 'quartz-basic', files: garden, config: config(['tpl', 'y/*']), globby: true, title: 'Mein Garten' },
  { id: 'fallback-star', files: garden, config: config(['*']), title: 'Stern' },
  { id: 'fallback-dir-slash', files: garden, config: config(['x/', '**/sub', 'Teil*']), title: 'Ordner' },
  { id: 'quartz-dir-slash', files: garden, config: config(['x/', '**/sub', 'Teil*']), globby: true, title: 'Ordner' },
  { id: 'quartz-gitignore', files: { 'geheim/g.md': 'g', 'offen/o.md': 'o', '.gitignore': 'geheim/\n' }, config: config([]), globby: true, title: 'Titel: mit Doppelpunkt' },
  { id: 'fallback-gitignore', files: { 'geheim/g.md': 'g', 'offen/o.md': 'o', '.gitignore': 'geheim/\n' }, config: config([]), title: 'yes' },
  { id: 'exists', files: { 'Index.MD': 'x', 'a.md': 'a' }, config: config([]), title: 'T' },
  { id: 'no-content', files: null, config: config([]), title: 'T' },
  { id: 'dangling-link', link: '../nirgends', files: null, config: config([]), title: 'T' },
  { id: 'linked', link: '../vault', vault: { 'Gärten-Ü/a.md': 'a', 'Notiz.md': 'n' }, config: config([]), globby: true,
    title: 'Ein sehr langer Titel für eine Startseite, der deutlich länger ist als achtzig Zeichen, damit yaml ihn faltet' },
  { id: 'encode', files: { 'a<b>.md': 'x', 'x>y/n.md': 'n', 'c\\d.md': 'c' }, config: config([]), title: '#hash "quote"' },
  { id: 'empty', files: {}, config: config([]), title: '- liste' },
  { id: 'bad-config', files: { 'tpl/t.md': 't', 'a.md': 'a' }, config: 'configuration: [unclosed\n', title: 'T' },
  { id: 'non-string-patterns', files: { 'tpl/t.md': 't', 'a.md': 'a', 'b/b.md': 'b' }, config: 'configuration:\n  ignorePatterns: [tpl, 5, null, {x: 1}]\n', title: 'T' },
]

const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-content-index-')))
const mask = (s) => s.replaceAll(work, '@W@')
const write = (root, files) => {
  for (const [rel, text] of Object.entries(files)) {
    mkdirSync(dirname(join(root, rel)), { recursive: true })
    writeFileSync(join(root, rel), text)
  }
}
const results = []
for (const s of scenarios) {
  const project = join(work, s.id, 'projekt')
  mkdirSync(project, { recursive: true })
  writeFileSync(join(project, 'quartz.config.yaml'), s.config)
  if (s.globby) symlinkSync(join(guiTest, 'node_modules'), join(project, 'node_modules'))
  if (s.vault) write(join(work, s.id, 'vault'), s.vault)
  if (s.link) symlinkSync(s.link, join(project, 'content'))
  else if (s.files) { mkdirSync(join(project, 'content'), { recursive: true }); write(join(project, 'content'), s.files) }
  let answer
  try {
    const r = await content.createIndexPage(project, s.title)
    answer = { path: mask(r.path), listSource: r.listSource, index: readFileSync(r.path, 'utf8') }
  } catch (err) {
    answer = { error: JSON.parse(err.message).key }
  }
  results.push({ ...s, answer })
}
rmSync(work, { recursive: true, force: true })
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify({ locale: Intl.DateTimeFormat().resolvedOptions().locale, scenarios: results }, null, 1) + '\n')
for (const r of results) console.log(r.id, r.answer.error ?? `${r.answer.listSource} ${r.answer.index.split('\n').length} lines`)
