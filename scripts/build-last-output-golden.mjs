#!/usr/bin/env node
// Golden file for BuildOutput.info, made by QuartzControl's own buildService.ts (`getBuildOutput`,
// with the real buildOutputGuard and projectDirs): for each case a tree is laid out under a fresh
// folder W, every entry that is no link gets the modification time the case names (or a fixed
// default, so nothing depends on the clock), and the script records what getBuildOutput answered,
// or that it rejected. The times are written into the fixture, so the Swift test sets the same.
//
//   Runtime/node/bin/node scripts/build-last-output-golden.mjs [../QuartzControl]
//
// `@W@` in a path, link target or answer is W.
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { layOut } from './lib/tree.mjs'
import { chmodSync, mkdirSync, mkdtempSync, realpathSync, rmSync, statSync, utimesSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'build-output')

const nothing = 'export {}'
const service = await loadQuartzControl(control, 'electron/main/services/buildService.ts', {
  ...commonStubs,
  './layoutFrameService': nothing, './fontService': nothing, './styleService': nothing,
  './projectPaths': 'export async function repointAuthoredFrames() {}',
  './runningServersStore': 'export async function record() {}; export async function remove() {}; export async function takeAll() { return {} }',
  './serverDiscovery': 'export async function discoverServers() { return { servers: [] } }',
  './projectDependencies': 'export async function missingDependencies() { return [] }',
  './runCommand': 'export function needsShell() { return false }',
  // The real guard: looksLikeBuild is part of the answer.
  './buildOutputGuard': "export { looksLikeQuartzBuild } from './electron/main/services/buildOutputGuard.ts'",
  'tree-kill': 'export default function treeKill() {}'
})

// Milliseconds with a fraction, as Node's mtimeMs carries one; toISOString drops it.
const DEFAULT_TIME = 1600000000000.25
const project = { 'proj/quartz.config.yaml': 'plugins: []\n', 'proj/content/index.md': '# Start\n' }
const site = (dir) => ({
  [`${dir}/index.html`]: '<html></html>',
  [`${dir}/404.html`]: 'nope',
  [`${dir}/static/x.css`]: 'body{}',
  [`${dir}/Gärten-Ü/über.html`]: 'ü'
})

const cases = [
  { name: 'missing' },
  { name: 'a-file', tree: { 'proj/public': 'not a folder' } },
  { name: 'empty', tree: { 'proj/public': { dir: 0o755 } } },
  { name: 'only-empty-folders', tree: { 'proj/public/a/b': { dir: 0o755 }, 'proj/public/c': { dir: 0o755 } } },
  { name: 'built', tree: site('proj/public'), times: { 'proj/public/static/x.css': 1700000000123.456 } },
  { name: 'newest-deep', tree: site('proj/public'), times: { 'proj/public/Gärten-Ü/über.html': 1750000000999.9 } },
  { name: 'not-a-build', tree: { 'proj/public/notes.md': 'mine', 'proj/public/b.md': 'mine too' } },
  { name: 'empty-string-is-default', outputDir: '', tree: site('proj/public') },
  { name: 'dist', outputDir: 'dist', tree: { ...site('proj/dist'), 'proj/public/index.html': 'old' } },
  { name: 'outside', outputDir: '../site', tree: site('site') },
  { name: 'absolute', outputDir: '@W@/elsewhere/out', tree: site('elsewhere/out') },
  { name: 'link-to-file', tree: { ...site('proj/public'), 'proj/public/linked.txt': { link: '@W@/target.txt' }, 'target.txt': '12345' },
    times: { 'target.txt': 1800000000000 } },
  { name: 'dangling-link', tree: { ...site('proj/public'), 'proj/public/gone': { link: '@W@/nowhere' } } },
  { name: 'public-is-a-link', tree: { ...site('real'), 'proj/public': { link: '@W@/real' } } },
  { name: 'unreadable-folder', tree: { ...site('proj/public'), 'proj/public/locked': { dir: 0o000 } } }
]

const recorded = []
for (const c of cases) {
  const w = realpathSync(mkdtempSync(join(tmpdir(), 'qh-last-output-')))
  const tree = { ...project, ...(c.tree ?? {}) }
  layOut(w, tree, w)
  // Every entry that is no link, and every folder on the way to one, gets a time: a folder's time
  // counts when a link to it is stat'ed, and the clock must not reach the answer.
  const times = {}
  for (const path of Object.keys(tree)) {
    // A string has a `link` method (String.prototype.link), so ask for an object first.
    if (typeof tree[path] === "object" && tree[path].link !== undefined) continue
    const parts = path.split('/')
    for (let i = 1; i <= parts.length; i++) times[parts.slice(0, i).join('/')] = DEFAULT_TIME
  }
  Object.assign(times, c.times ?? {})
  const ordered = Object.keys(times).sort((a, b) => b.split('/').length - a.split('/').length)
  for (const path of ordered) {
    if (tree[path]?.dir === 0) continue
    utimesSync(join(w, path), times[path] / 1000, times[path] / 1000)
  }
  const outputDir = c.outputDir?.replaceAll('@W@', w)
  let expected
  try {
    const info = await service.getBuildOutput(join(w, 'proj'), outputDir)
    expected = JSON.parse(JSON.stringify(info).replaceAll(w, '@W@'))
  } catch {
    expected = { rejected: true }
  }
  for (const [path, spec] of Object.entries(tree)) if (spec?.dir !== undefined) chmodSync(join(w, path), 0o755)
  rmSync(w, { recursive: true, force: true })
  recorded.push({ name: c.name, tree, times, outputDir: c.outputDir ?? null, expected })
}

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'last-output.json'), JSON.stringify(recorded, null, 2) + '\n')
console.log(`${recorded.length} Fälle nach ${out}`)
