#!/usr/bin/env node
// Golden files for ProjectDuplicator, made by QuartzControl's own duplicateService.ts: each case
// lays out an original (with every kind of thing SKIP names, links, odd permissions) and a vault,
// duplicates, and records the copy as a list of entries (type, mode, link target, small contents),
// the commands it ran and its answer. The Swift test (ProjectDuplicatorTests) lays out the same
// trees from source.json and compares.
//
//   Runtime/node/bin/node scripts/duplicate-golden.mjs [../QuartzControl]
//
// Stand-ins besides the common two: runCommand (notes git and npm and answers as the case says),
// contentDirPath (`join(project, 'content')`), readLockfile (three lines, as in paths-golden.mjs)
// and noteInstallSucceeded (a no-op: updateService is too large to load, and the Swift side tests
// the note on its own). Paths are written as @W@, the folder holding Original, Kopie and Vault.
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { layOut } from './lib/tree.mjs'
import { lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'duplicate')

globalThis.__calls = []
globalThis.__npm = { success: true, output: 'added 1 package' }
const { duplicateProject } = await loadQuartzControl(control, 'electron/main/services/duplicateService.ts', {
  ...commonStubs,
  './runCommand': `export async function runCommand(command, args, cwd) {
      globalThis.__calls.push([command, ...args, cwd].join(' '))
      return command === 'npm' ? globalThis.__npm : { success: false, output: 'error: No such remote' }
    }`,
  './contentService': `import { join } from 'path'
    export function contentDirPath(projectPath) { return join(projectPath, 'content') }`,
  './updateService': 'export async function noteInstallSucceeded() {}',
  './pluginService': `import { existsSync } from 'fs'
    import { readFile } from 'fs/promises'
    import { join } from 'path'
    export async function readLockfile(projectPath) {
      const path = join(projectPath, 'quartz.lock.json')
      if (!existsSync(path)) return null
      return JSON.parse(await readFile(path, 'utf-8'))
    }`
})

// path → text (a file), { link } or { dir: mode }; files may carry { text, mode }.
const original = {
  'quartz.config.yaml': 'configuration:\n  pageTitle: Original\nplugins:\n' +
    '  - source: @W@/Original/.quartz-gui/authored-frames/frame-a\n    enabled: true\n' +
    '  - source: /Users/else/plugin\n    enabled: true\n',
  'quartz.lock.json': JSON.stringify({ plugins: { 'frame-a': { source: '@W@/Original/.quartz-gui/authored-frames/frame-a' } } }, null, 2) + '\n',
  'package.json': '{ "name": "quartz" }\n',
  'quartz/styles/custom.scss': '// eigene Stile\n',
  'bin/run.sh': { text: '#!/bin/sh\necho hi\n', mode: 0o755 },
  'secret.txt': { text: 'nur ich\n', mode: 0o600 },
  'private': { dir: 0o700 },
  'private/note.md': 'privat\n',
  'docs-link': { link: 'quartz/styles' },
  'sub/node_modules/kept.js': 'only the top-level node_modules is skipped\n',
  'node_modules/x/index.js': 'skipped\n',
  'public/index.html': 'skipped\n',
  'content/a.md': 'skipped\n',
  '.quartz/plugins/frame-a': { link: '@W@/Original/.quartz-gui/authored-frames/frame-a' },
  '.quartz/plugins/rel': { link: '../../quartz' },
  '.quartz-gui/authored-frames/frame-a/index.ts': 'export default {}\n',
  '.quartz-gui/theme-presets.json': '[]',
  '.quartz-gui/layout-breakpoints.json': '{}',
  '.quartz-gui/core-update.json': '{}',
  '.quartz-gui/deploy-manifestold.json': '{}',
  '.quartz-gui/snapshots.git/HEAD': 'skipped\n',
  '.quartz-gui/content-backups/x/a.md': 'skipped\n',
  '.quartz-gui/publish-targets.json': '[]',
  '.quartz-gui/deploy-manifest.json': '{}',
  '.quartz-gui/deploy-manifest-abc.json': '{}',
  '.quartz-gui/branch-worktree-abc/.git': 'gitdir: elsewhere\n',
  '.quartz-gui/project-prefs.json': '{ "outputDir": "/Users/else/site" }',
  '.quartz-gui/logs/serve.log': 'skipped\n',
  '.quartz-gui/staging/x': 'skipped\n',
  '.quartz-gui/forms-relay.json': '{}'
}
const vault = {
  'a.md': '# A\n',
  '.obsidian/app.json': '{}',
  'again.md': { link: 'a.md' },
  'notes': { dir: 0o755 },
  'notes/b.md': '# B\n'
}

const cases = [
  { name: 'blank', content: { contentStrategy: 'blank' } },
  { name: 'copy', content: { contentStrategy: 'copy', contentSource: '@W@/Vault' } },
  { name: 'symlink', content: { contentStrategy: 'symlink', contentSource: '@W@/Vault' } },
  { name: 'install-fails', content: { contentStrategy: 'blank' }, npm: { success: false, output: 'ERR! network' } },
  { name: 'not-a-project', content: { contentStrategy: 'blank' }, source: { 'package.json': '{}' } },
  { name: 'config-unreadable', content: { contentStrategy: 'blank' }, source: { 'quartz.config.yaml': '- a\n' } },
  { name: 'target-has-files', content: { contentStrategy: 'blank' }, target: { '.DS_Store': '' } },
  { name: 'target-inside-source', content: { contentStrategy: 'blank' }, targetPath: '@W@/Original/sub/Kopie' },
  { name: 'content-missing', content: { contentStrategy: 'copy', contentSource: '@W@/Nirgends' } },
  { name: 'content-holds-target', content: { contentStrategy: 'symlink', contentSource: '@W@' } }
]

function record(root, w) {
  const mask = (text) => text.replaceAll(w, '@W@')
  const entries = []
  const walk = (dir, rel) => {
    for (const name of readdirSync(dir).sort()) {
      const full = join(dir, name)
      const path = rel ? `${rel}/${name}` : name
      const stat = lstatSync(full)
      const mode = (stat.mode & 0o7777).toString(8)
      if (stat.isSymbolicLink()) entries.push({ path, link: mask(readlinkSync(full)) })
      else if (stat.isDirectory()) { entries.push({ path, dir: mode }); walk(full, path) }
      else entries.push({ path, mode, text: mask(readFileSync(full, 'utf-8')) })
    }
  }
  walk(root, '')
  return entries
}

rmSync(out, { recursive: true, force: true })
for (const c of cases) {
  const w = mkdtempSync(join(tmpdir(), 'qh-duplicate-golden-'))
  const fill = (text) => text?.replaceAll('@W@', w)
  layOut(join(w, 'Original'), c.source ?? original, w)
  layOut(join(w, 'Vault'), vault, w)
  const targetPath = fill(c.targetPath ?? '@W@/Kopie')
  if (c.target) layOut(targetPath, c.target, w)
  globalThis.__calls = []
  globalThis.__npm = c.npm ?? { success: true, output: 'added 1 package' }
  const result = await duplicateProject({
    sourcePath: join(w, 'Original'), targetDirectory: targetPath,
    contentStrategy: c.content.contentStrategy, contentSource: fill(c.content.contentSource)
  })
  const dir = join(out, c.name)
  mkdirSync(dir, { recursive: true })
  const mask = (text) => text.replaceAll(w, '@W@')
  writeFileSync(join(dir, 'case.json'), JSON.stringify({
    source: c.source ?? original, vault, target: c.target ?? null, targetPath: c.targetPath ?? '@W@/Kopie',
    content: c.content, npm: c.npm ?? { success: true, output: 'added 1 package' }
  }, null, 2) + '\n')
  writeFileSync(join(dir, 'expected.json'), JSON.stringify({
    success: result.success, output: mask(result.output), calls: globalThis.__calls.map(mask),
    tree: result.success || c.npm ? record(targetPath, w) : null
  }, null, 2) + '\n')
  rmSync(w, { recursive: true, force: true })
}
console.log(`${cases.length} Fälle nach ${out}`)
