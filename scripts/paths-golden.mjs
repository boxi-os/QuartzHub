#!/usr/bin/env node
// Golden files for ProjectPaths, made by QuartzControl's own projectPaths.ts: each case lays out a
// small project tree (config, lockfile, links under .quartz/plugins), runs repointProjectPaths or
// repointAuthoredFrames on it, and records what the three places hold afterwards. The Swift test
// (ProjectPathsTests) lays out the same tree from tree.json and compares.
//
//   Runtime/node/bin/node scripts/paths-golden.mjs [../QuartzControl]
//
// Paths are written as placeholders: @A@ is the folder the tree was laid out in (the original),
// @B@ the folder the operation works on (the copy; for repointAuthoredFrames the same tree under a
// new name). Stand-ins besides the common two: readLockfile, which in QuartzControl sits in
// pluginService.ts with the CLI and the build service around it; it is three lines and is the
// same here.
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { cpSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, rmSync, symlinkSync, writeFileSync, existsSync, lstatSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'paths')

const { repointProjectPaths, repointAuthoredFrames } = await loadQuartzControl(control, 'electron/main/services/projectPaths.ts', {
  ...commonStubs,
  './pluginService': `import { existsSync } from 'fs'
    import { readFile } from 'fs/promises'
    import { join } from 'path'
    export async function readLockfile(projectPath) {
      const path = join(projectPath, 'quartz.lock.json')
      if (!existsSync(path)) return null
      return JSON.parse(await readFile(path, 'utf-8'))
    }`
})

const frame = (root, id) => `${root}/.quartz-gui/authored-frames/${id}`
const config = (sources) =>
  `configuration:\n  pageTitle: Pfade\nplugins:\n${sources.map((s) => `  - source: ${s}\n    enabled: true\n`).join('')}`
const lock = (entries) => JSON.stringify({ version: '1.0.0', plugins: entries }, null, 2) + '\n'

const full = {
  dirs: ['.quartz-gui/authored-frames/frame-a', 'plugins-local/p', 'content'],
  files: {
    'quartz.config.yaml': config([
      frame('@A@', 'frame-a'), '@A@/plugins-local/p', '@A@', '@A@/./plugins-local/../plugins-local/p/',
      '/Users/else/plugin', '@A@x/sibling', '@A@/..x/odd', './relative', 'github:quartz-community/explorer'
    ]) + '  - source:\n      repo: "@A@/as-object"\n    enabled: true\n',
    'quartz.lock.json': lock({
      'frame-a': { source: frame('@A@', 'frame-a'), resolved: frame('@A@', 'frame-a'), commit: 'local' },
      p: { source: '@A@/plugins-local/p', resolved: '/Users/else/resolved', commit: 'x' },
      remote: { source: 'github:quartz-community/explorer', resolved: 'https://github.com/quartz-community/explorer.git' },
      broken: 'not an object'
    })
  },
  links: {
    '.quartz/plugins/frame-a': frame('@A@', 'frame-a'),
    '.quartz/plugins/p': '../../plugins-local/p',
    // Relative, and up into the original: resolved against the link's own folder it is inside @A@.
    '.quartz/plugins/up': '../../../Original/plugins-local/p',
    '.quartz/plugins/gone': '@A@/plugins-local/gone',
    '.quartz/plugins/outside': '/usr/lib'
  }
}

const cases = [
  { name: 'duplicate', run: 'repointProjectPaths', tree: full },
  {
    // Copied outside the app: only the frames that exist here are taken.
    name: 'frames', run: 'repointAuthoredFrames', tree: {
      dirs: ['.quartz-gui/authored-frames/frame-a'],
      files: {
        'quartz.config.yaml': config([frame('@A@', 'frame-a'), frame('@A@', 'frame-b'), '@A@/plugins-local/p']),
        'quartz.lock.json': lock({ 'frame-a': { source: frame('@A@', 'frame-a'), resolved: frame('@A@', 'frame-a') } })
      },
      links: { '.quartz/plugins/frame-a': frame('@A@', 'frame-a'), '.quartz/plugins/frame-b': frame('@A@', 'frame-b') }
    }
  },
  {
    name: 'no-config', run: 'repointProjectPaths', tree: {
      dirs: [], files: { 'quartz.lock.json': lock({ p: { source: '@A@/p' } }) }, links: { '.quartz/plugins/p': '@A@/p' }
    }
  },
  {
    name: 'unreadable-lock', run: 'repointProjectPaths', tree: {
      dirs: ['p'], files: { 'quartz.config.yaml': config(['@A@/p']), 'quartz.lock.json': '{ "plugins": ' }, links: {}
    }
  },
  {
    // A list where QuartzControl expects an object: Object.values takes its items.
    name: 'lock-as-list', run: 'repointProjectPaths', tree: {
      dirs: [], files: { 'quartz.config.yaml': config([]), 'quartz.lock.json': lock([{ source: '@A@/p' }, 7]) }, links: {}
    }
  }
]

function layOut(root, tree, a) {
  const fill = (text) => text.replaceAll('@A@', a)
  for (const dir of tree.dirs) mkdirSync(join(root, dir), { recursive: true })
  for (const [path, text] of Object.entries(tree.files)) {
    mkdirSync(dirname(join(root, path)), { recursive: true })
    writeFileSync(join(root, path), fill(text))
  }
  for (const [path, target] of Object.entries(tree.links)) {
    mkdirSync(dirname(join(root, path)), { recursive: true })
    symlinkSync(fill(target), join(root, path))
  }
}

function record(root, a, b) {
  const mask = (text) => text.replaceAll(b, '@B@').replaceAll(a, '@A@')
  const read = (path) => (existsSync(join(root, path)) ? mask(readFileSync(join(root, path), 'utf-8')) : null)
  const links = {}
  const dir = join(root, '.quartz/plugins')
  if (existsSync(dir)) {
    for (const name of readdirSync(dir).sort()) {
      if (lstatSync(join(dir, name)).isSymbolicLink()) links[name] = mask(readlinkSync(join(dir, name)))
    }
  }
  return { config: read('quartz.config.yaml'), lock: read('quartz.lock.json'), links }
}

rmSync(out, { recursive: true, force: true })
for (const c of cases) {
  const work = mkdtempSync(join(tmpdir(), 'qh-paths-golden-'))
  const a = join(work, 'Original')
  const b = join(work, 'Kopie')
  mkdirSync(a)
  layOut(a, c.tree, a)
  cpSync(a, b, { recursive: true, verbatimSymlinks: true })
  if (c.run === 'repointProjectPaths') await repointProjectPaths(a, b)
  else await repointAuthoredFrames(b)
  const dir = join(out, c.name)
  mkdirSync(dir, { recursive: true })
  writeFileSync(join(dir, 'tree.json'), JSON.stringify({ run: c.run, ...c.tree }, null, 2) + '\n')
  writeFileSync(join(dir, 'expected.json'), JSON.stringify(record(b, a, b), null, 2) + '\n')
  rmSync(work, { recursive: true, force: true })
}
console.log(`${cases.length} Fälle nach ${out}`)
