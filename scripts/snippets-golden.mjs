#!/usr/bin/env node
// Golden file for Snippets and PackagePaths, made by QuartzControl's own snippetService.ts and
// templatePackage/shared.ts: one made-up project with snippet folders, pictures, links in and out,
// reserved folders and the build output, and a sequence of calls (list, read, write, import,
// rename, trash, the SVG source), after each the answer, every changed file and what went to the
// trash (Electron's shell.trashItem replaced by a recorder).
//
//   Runtime/node/bin/node scripts/snippets-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'snippets')

const snippets = await loadQuartzControl(control, 'electron/main/services/snippetService.ts', {
  ...commonStubs,
  electron: 'export const shell = { trashItem: async (p) => { if (globalThis.__trashFails) throw new Error("no trash here"); globalThis.__trash.push(p); require("fs").rmSync(p) } }',
  './projectPrefsService': `import { readFileSync } from 'fs'
    import { join } from 'path'
    export async function getPrefs(p) { try { return JSON.parse(readFileSync(join(p, '.quartz-gui', 'project-prefs.json'), 'utf8')) } catch { return {} } }`
})
const shared = await loadQuartzControl(control, 'electron/main/services/templatePackage/shared.ts', commonStubs)

const big = 'x'.repeat(2 * 1024 * 1024 + 1)
// path → text, { link }, { dir: true }, { size }
const tree = {
  'snippets/a.md': '# A\n', 'snippets/b.html': '<p>b</p>', 'snippets/c.HTM': '<p>c</p>', 'snippets/.hidden.md': 'h', 'snippets/x.txt': 'x',
  'snippets/file10.md': '10', 'snippets/file2.md': '2', 'snippets/Äpfel.md': 'ä', 'snippets/apfel.md': 'a', 'snippets/Zebra.md': 'z', 'snippets/_under.md': 'u', 'snippets/10-start.md': 's',
  'snippets/link-to-file.md': { link: 'a.md' }, 'snippets/link-to-dir.md': { link: '../other' }, 'snippets/link-out.md': { link: '../../outside/secret.md' },
  'snippets/big.md': big, 'snippets/sub/deep.md': 'deep',
  'other/o.md': 'o', 'linked': { link: 'other' }, 'public/p.md': 'p', 'out-dir/q.md': 'q',
  '.git/x.md': 'g', 'node_modules/n.md': 'n', 'quartz/static/images/pic.png': 'png', 'quartz/static/images/Pic2.SVG': '<svg/>', 'quartz/static/images/notes.md': 'n',
  'content': { link: '../outside' },
  '../outside/secret.md': 'secret', '../outside/drawing.svg': '<svg><circle/></svg>', '../outside/big.svg': '<svg>' + big + '</svg>', '../outside/key.txt': 'KEY',
  '../outside/photo.jpg': 'jpg', '../outside/folder.md': { dir: true }, '../outside/snippet.md': 'from outside'
}
const step = (call, ...args) => ({ call, args })
const steps = [
  ...['snippets', 'missing', '../outside', '/abs', '.', '', '.git', '.GIT/x', 'node_modules', 'quartz/../node_modules', 'public', 'public/sub', 'linked', 'snippets/sub', 'content', 'quartz/.quartz-gui'].map((d) => step('listSnippets', d)),
  step('listStaticImages'),
  step('readSnippet', 'snippets', 'a.md'), step('readSnippet', 'snippets', 'x.txt'), step('readSnippet', 'snippets', 'link-out.md'), step('readSnippet', 'snippets', 'link-to-file.md'),
  step('readSnippet', 'snippets', 'big.md'), step('readSnippet', '../outside', 'secret.md'), step('readSnippet', 'snippets', '../other/o.md'), step('readSnippet', 'linked', 'o.md'),
  step('readSnippet', 'snippets', 'sub/deep.md'), step('readSnippet', 'public', 'p.md'),
  step('writeSnippet', 'snippets', 'neu.md', 'neu', false), step('writeSnippet', 'snippets', 'neu.md', 'anders', false), step('writeSnippet', 'snippets', 'neu.md', 'anders', true),
  step('writeSnippet', 'linked', 'x.md', 'x', false), step('writeSnippet', 'snippets', 'link-to-file.md', 'x', true), step('writeSnippet', 'snippets', ' spaced.md ', 's', false),
  step('writeSnippet', 'snippets', 'bad/name.md', 'x', false), step('writeSnippet', 'snippets', '.dot.md', 'x', false), step('writeSnippet', 'snippets', 'no.txt', 'x', false),
  step('writeSnippet', 'snippets', 'a:b.md', 'x', false), step('writeSnippet', 'fresh/dir', 'f.md', 'f', false), step('writeSnippet', 'snippets', 'huge.md', big, false),
  step('writeSnippet', 'public', 'p2.md', 'p', false), step('writeSnippet', 'content', 'c.md', 'c', false), step('writeSnippet', 'snippets', 'UPPER.MD', 'u', false),
  step('importSnippet', 'snippets', '@OUT@/snippet.md', undefined, false), step('importSnippet', 'snippets', '@OUT@/snippet.md', undefined, false),
  step('importSnippet', 'snippets', '@OUT@/snippet.md', 'renamed.html', false), step('importSnippet', 'snippets', '@OUT@/key.txt', 'key.md', false),
  step('importSnippet', 'snippets', '@OUT@/folder.md', undefined, false), step('importSnippet', 'snippets', '@OUT@/snippet.md', undefined, true),
  step('importSnippet', 'snippets', '@P@/snippets/big.md', 'big2.md', false),
  step('importStaticImage', '@OUT@/photo.jpg', undefined, false), step('importStaticImage', '@OUT@/photo.jpg', 'foto.jpeg', false), step('importStaticImage', '@OUT@/photo.jpg', undefined, false),
  step('importStaticImage', '@OUT@/secret.md', 'secret.png', false),
  step('readSvgSource', '@OUT@/drawing.svg'), step('readSvgSource', '@OUT@/secret.md'), step('readSvgSource', '@OUT@/big.svg'), step('readSvgSource', '@OUT@/nothing.svg'),
  step('renameStaticFile', 'snippet', 'snippets', 'neu.md', 'umbenannt.md'), step('renameStaticFile', 'snippet', 'snippets', 'umbenannt.md', 'a.md'),
  step('renameStaticFile', 'snippet', 'snippets', 'umbenannt.md', 'UMBENANNT.md'), step('renameStaticFile', 'snippet', 'snippets', 'fehlt.md', 'x.md'),
  step('renameStaticFile', 'snippet', 'snippets', 'link-to-file.md', 'x.md'), step('renameStaticFile', 'snippet', undefined, 'a.md', 'x.md'),
  step('renameStaticFile', 'image', undefined, 'pic.png', 'bild.png'), step('renameStaticFile', 'image', undefined, 'bild.png', 'bild.png'), step('renameStaticFile', 'image', 'ignored', 'bild.png', 'bild.md'),
  step('trashStaticFile', 'snippet', 'snippets', 'b.html'), step('trashStaticFile', 'snippet', 'snippets', 'b.html'), step('trashStaticFile', 'image', undefined, 'bild.png'),
  step('trashStaticFile', 'snippet', 'linked', 'o.md'), step('trashFails'), step('trashStaticFile', 'snippet', 'snippets', 'c.HTM'),
  step('listSnippets', 'snippets'), step('listStaticImages')
]
const pathCases = [['/p', 'a'], ['/p', 'a/b'], ['/p', '../x'], ['/p', '/abs'], ['/p', '.'], ['/p', ''], ['/p', 'a/../b'], ['/p', 'a/../../x'], ['/p/', 'a'], ['/p', 'a//b/'], ['/p', '..'], ['/p', '...']]

const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-snippets-golden-')))
const project = join(work, 'project')
mkdirSync(project, { recursive: true })
mkdirSync(join(project, '.quartz-gui'), { recursive: true })
writeFileSync(join(project, '.quartz-gui', 'project-prefs.json'), '{ "outputDir": "" }')
const lay = (base) => {
  for (const [path, spec] of Object.entries(tree)) {
    const full = join(base, path)
    mkdirSync(dirname(full), { recursive: true })
    if (typeof spec === 'string') writeFileSync(full, spec)
    else if (spec.link) symlinkSync(spec.link, full)
    else if (spec.dir) mkdirSync(full, { recursive: true })
  }
}
lay(project)
const files = () => {
  const result = {}
  const walk = (d) => {
    for (const name of readdirSync(d).sort()) {
      const full = join(d, name)
      const info = lstatSync(full)
      const rel = relative(work, full)
      if (info.isSymbolicLink()) result[rel] = { link: readlinkSync(full) }
      else if (info.isDirectory()) walk(full)
      else result[rel] = readFileSync(full, 'utf8').length > 1000 ? { length: readFileSync(full).length } : readFileSync(full, 'utf8')
    }
  }
  walk(work)
  return result
}
const results = []
let before = files()
globalThis.__trashFails = false
for (const s of steps) {
  globalThis.__trash = []
  let result
  if (s.call === 'trashFails') { globalThis.__trashFails = true; result = null } else {
    const args = s.args.map((a) => (typeof a === 'string' ? a.replace('@OUT@', join(work, 'outside')).replace('@P@', project) : a))
    try { result = (await snippets[s.call](...(s.call === 'readSvgSource' ? args : [project, ...args]))) ?? null } catch (error) { result = { threw: String(error) } }
  }
  const after = files()
  const changed = {}
  for (const path of new Set([...Object.keys(before), ...Object.keys(after)])) if (JSON.stringify(before[path]) !== JSON.stringify(after[path])) changed[path] = after[path] ?? null
  results.push({ call: s.call, args: s.args.map((a) => a ?? null), result: JSON.parse(JSON.stringify(result).replaceAll(work, '@W@')), changed, trash: globalThis.__trash.map((p) => p.replace(work, '@W@')) })
  before = after
}
const paths = []
for (const [dir, name] of pathCases) {
  paths.push({ dir, name, contained: shared.containedPath(dir, name) })
}
// writableTarget against the laid-out project.
for (const name of ['snippets/a.md', 'snippets/new/x.md', 'linked/x.md', 'snippets/link-to-file.md', 'content/x.md', '../x', 'snippets', 'fresh/a/b.md']) {
  paths.push({ dir: '@P@', name, writable: (await shared.writableTarget(project, name))?.replace(work, '@W@') ?? null })
}
rmSync(work, { recursive: true, force: true })
rmSync(out, { recursive: true, force: true })
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify({ tree: Object.fromEntries(Object.entries(tree).map(([p, s]) => [p, s === big ? { length: big.length } : s])), bigLength: big.length, bigSvg: true, steps: results, paths }, null, 2) + '\n')
console.log(`snippets: ${results.length} steps, ${paths.length} path cases`)
for (const r of results) console.log(`  ${r.call} ${JSON.stringify(r.args).slice(0, 60)}: ${JSON.stringify(r.result).slice(0, 140)}${r.trash.length ? ' trash ' + r.trash : ''}`)
