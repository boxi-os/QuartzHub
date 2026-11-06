#!/usr/bin/env node
// Golden file for BuildOutputGuard, made by QuartzControl's own buildOutputGuard.ts: for each case
// a tree is laid out under a fresh directory W (the home is W/home, the project W/home/proj unless
// the case says otherwise), and assessOutputDir answers for the case's output folder. Also
// looksLikeQuartzBuild for a few folders.
//
//   Runtime/node/bin/node scripts/build-output-golden.mjs [../QuartzControl]
//
// Stand-in: HOME (os.homedir() reads it). `@W@` in a path or link target is W.
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { layOut } from './lib/tree.mjs'
import { chmodSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'build-output')

const guard = await loadQuartzControl(control, 'electron/main/services/buildOutputGuard.ts', commonStubs)

const project = {
  'home/proj/quartz.config.yaml': 'plugins: []\n',
  'home/proj/content/index.md': '# Start\n',
  'home/proj/content/sub/a.md': 'a\n',
  'home/proj/quartz/static/x.css': '',
  'home/proj/.git/HEAD': 'ref: refs/heads/main\n',
  'home/proj/.quartz-gui/logs/build.log': '',
  'home/proj/.quartz-cache/x': '',
  'home/proj/node_modules/x/package.json': '{}',
  'home/notes/a.md': 'mine\n',
  'home/notes/b.md': 'mine\n',
  'elsewhere/proj/quartz.config.yaml': ''
}
const built = (dir, ...more) => Object.fromEntries([`${dir}/index.html`, ...more.map((m) => `${dir}/${m}`)].map((p) => [p, '']))

const cases = [
  { name: 'default-missing' },
  { name: 'default-empty', tree: { 'home/proj/public': { dir: 0o755 } } },
  { name: 'empty-string-is-default', outputDir: '', tree: built('home/proj/public', 'static/x.css') },
  { name: 'default-built', tree: built('home/proj/public', 'static/x.css') },
  { name: 'index-only', tree: built('home/proj/public') },
  { name: 'index-and-404', tree: built('home/proj/public', '404.html') },
  { name: 'index-and-feed', tree: built('home/proj/public', 'index.xml') },
  { name: 'index-and-sitemap', tree: built('home/proj/public', 'sitemap.xml') },
  { name: 'notes', outputDir: '../notes' },
  { name: 'a-file', outputDir: 'out.txt', tree: { 'home/proj/out.txt': 'x' } },
  { name: 'dist-new', outputDir: 'dist' },
  { name: 'the-project', outputDir: '.' },
  { name: 'the-project-slash', outputDir: './' },
  { name: 'the-project-absolute', outputDir: '@W@/home/proj' },
  { name: 'parent-is-home', outputDir: '..' },
  { name: 'root', outputDir: '/' },
  { name: 'home', project: 'elsewhere/proj', outputDir: '@W@/home' },
  { name: 'home-slash', project: 'elsewhere/proj', outputDir: '@W@/home/' },
  { name: 'beside-home', project: 'elsewhere/proj', outputDir: '@W@/home/notes' },
  ...['content', 'content/sub', './content/../content', 'quartz', 'quartz/static', '.git', '.quartz-gui', '.quartz-gui/logs',
    '.quartz-cache', 'node_modules', 'node_modules/x'].map((d) => ({ name: `protected ${d}`, outputDir: d })),
  ...['contents', 'content-old', '.quartz-gui-x', 'quartz2'].map((d) => ({ name: `not-protected ${d}`, outputDir: d })),
  { name: 'sibling-prefix', outputDir: '../proj-old', tree: { 'home/proj-old/x.md': '' } },
  { name: 'unreadable', outputDir: 'locked', tree: { 'home/proj/locked': { dir: 0o000 } } },
  // Spellings the list of names does not see, all reaching the same folders on APFS. QuartzHub
  // asks by the real path as well (BuildOutputGuardTests, `deviations`).
  { name: 'case Content', outputDir: 'Content' },
  { name: 'case NODE_MODULES/x', outputDir: 'NODE_MODULES/x' },
  { name: 'case HOME', project: 'elsewhere/proj', outputDir: '@W@/HOME' },
  { name: 'link to content', outputDir: 'site', tree: { 'home/proj/site': { link: '@W@/home/proj/content' } } },
  { name: 'below a link to content', outputDir: 'site/sub', tree: { 'home/proj/site': { link: '@W@/home/proj/content' } } },
  { name: 'link to home', project: 'elsewhere/proj', outputDir: 'out', tree: { 'elsewhere/proj/out': { link: '@W@/home' } } },
  { name: 'link to the project', outputDir: '../alias', tree: { 'home/alias': { link: '@W@/home/proj' } } },
  { name: 'case PUBLIC built', outputDir: 'PUBLIC', tree: built('home/proj/public', 'static/x.css') }
]

const recorded = []
for (const c of cases) {
  const w = realpathSync(mkdtempSync(join(tmpdir(), 'qh-output-')))
  layOut(w, { ...project, ...(c.tree ?? {}) }, w)
  process.env.HOME = join(w, 'home')
  const projectPath = join(w, c.project ?? 'home/proj')
  const outputDir = c.outputDir?.replaceAll('@W@', w)
  const verdict = await guard.assessOutputDir(projectPath, outputDir)
  for (const [path, spec] of Object.entries(c.tree ?? {})) if (spec.dir !== undefined) chmodSync(join(w, path), 0o755)
  rmSync(w, { recursive: true, force: true })
  recorded.push({ name: c.name, tree: c.tree ?? {}, project: c.project ?? 'home/proj', outputDir: c.outputDir ?? null, expected: verdict })
}

const looks = [
  { name: 'none', tree: {} },
  { name: 'index-only', tree: { 'index.html': '' } },
  { name: 'static-only', tree: { static: { dir: 0o755 } } },
  { name: 'index-static', tree: { 'index.html': '', static: { dir: 0o755 } } },
  { name: 'index-dir', tree: { 'index.html': { dir: 0o755 }, '404.html': '' } },
  { name: 'Index-case', tree: { 'INDEX.html': '', '404.html': '' } }
].map((l) => {
  const w = realpathSync(mkdtempSync(join(tmpdir(), 'qh-looks-')))
  layOut(join(w, 'd'), l.tree, w)
  return guard.looksLikeQuartzBuild(join(w, 'd')).then((answer) => {
    rmSync(w, { recursive: true, force: true })
    return { ...l, expected: answer }
  })
})

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify({ project, assess: recorded, looks: await Promise.all(looks) }, null, 2) + '\n')
console.log(`${recorded.length} Fälle nach ${out}`)
