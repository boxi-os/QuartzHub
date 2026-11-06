#!/usr/bin/env node
// Golden files for ProjectDependencies, made by QuartzControl's own projectDependencies.ts: each
// case lays out a project (package.json, a node_modules tree, a config with frames) and records
// what missingDependencies, halfUnpackedModule and missingAuthoredFrames answer. The Swift test
// (ProjectDependenciesTests) lays out the same tree from case.json and asks the same.
//
//   Runtime/node/bin/node scripts/deps-golden.mjs [../QuartzControl]
//
// Paths are written as @W@ (the folder holding the project as `P`). Stand-ins: the common two.
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { layOut } from './lib/tree.mjs'
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'dependencies')
const deps = await loadQuartzControl(control, 'electron/main/services/projectDependencies.ts')

const pkg = (dependencies, extra = {}) => JSON.stringify({ name: 'x', ...extra, dependencies })
const config = (sources) => `plugins:\n${sources.map((s) => `  - source: ${s}\n    enabled: true\n`).join('')}`

const cases = [
  {
    name: 'installed-and-not', tree: {
      'package.json': pkg({ sass: '^1', '@scope/a': '1', globby: '1', missing: '1' }, { optionalDependencies: { opt: '1' } }),
      'node_modules/sass/package.json': JSON.stringify({ dependencies: { chokidar: '1' }, optionalDependencies: { '@parcel/watcher': '1' } }),
      'node_modules/chokidar/package.json': JSON.stringify({ dependencies: { readdirp: '1' } }),
      // Half unpacked: the folder is there, its package.json not yet.
      'node_modules/readdirp': { dir: 0o755 },
      'node_modules/@scope/a/package.json': '{}',
      'node_modules/globby/package.json': JSON.stringify({ dependencies: { 'fast-glob': '1' } }),
      // Nested lookup: globby's own node_modules first, a broken one at the top is not asked.
      'node_modules/globby/node_modules/fast-glob/package.json': '{}',
      'node_modules/fast-glob/package.json': '{ broken',
      // A folder named node_modules is never where a lookup looks in.
      'node_modules/missing': { dir: 0o755 },
      'quartz.config.yaml': config(['@scope/a'])
    },
    ask: [['missingDependencies'], ['halfUnpackedModule', 'sass'], ['halfUnpackedModule', 'globby'],
      ['halfUnpackedModule', '@scope/a'], ['halfUnpackedModule', 'not-there'], ['halfUnpackedModule', 'missing'],
      ['missingAuthoredFrames']]
  },
  {
    name: 'cycle-and-parent', tree: {
      'package.json': pkg({ a: '1' }),
      'node_modules/a/package.json': JSON.stringify({ dependencies: { b: '1' } }),
      'node_modules/b/package.json': JSON.stringify({ dependencies: { a: '1', c: '1' } }),
      // c is only in a folder above the project: not looked for there.
      '../node_modules/c/package.json': '{ broken',
      'quartz.config.yaml': config([])
    },
    ask: [['halfUnpackedModule', 'a'], ['missingDependencies']]
  },
  {
    name: 'manifests-of-the-wrong-kind', tree: { 'package.json': '{ "dependencies": ["a", "b"] }' },
    ask: [['missingDependencies']]
  },
  { name: 'no-dependencies-key', tree: { 'package.json': '5' }, ask: [['missingDependencies']] },
  { name: 'unreadable-package-json', tree: { 'package.json': '{ nope' }, ask: [['missingDependencies'], ['missingAuthoredFrames']] },
  {
    name: 'frames', tree: {
      'package.json': pkg({}),
      '.quartz-gui/authored-frames/here/index.ts': '',
      '.quartz-gui/authored-frames/copied/index.ts': '',
      'quartz.config.yaml': config([
        '@W@/P/.quartz-gui/authored-frames/here', '@W@/P/.quartz-gui/authored-frames/gone',
        '@W@/Other/.quartz-gui/authored-frames/copied', '@W@/Other/.quartz-gui/authored-frames/elsewhere',
        '@W@/Other/plugins/not-a-frame'
      ]) + '  - source:\n      repo: x\n    enabled: true\n'
    },
    ask: [['missingAuthoredFrames']]
  },
  { name: 'config-unreadable', tree: { 'package.json': pkg({}), 'quartz.config.yaml': '- a\n' }, ask: [['missingAuthoredFrames']] }
]

rmSync(out, { recursive: true, force: true })
for (const c of cases) {
  const w = mkdtempSync(join(tmpdir(), 'qh-deps-golden-'))
  const project = join(w, 'P')
  layOut(project, c.tree, w)
  const answers = []
  for (const [fn, ...args] of c.ask) answers.push(await deps[fn](project, ...args))
  const dir = join(out, c.name)
  mkdirSync(dir, { recursive: true })
  writeFileSync(join(dir, 'case.json'), JSON.stringify({ tree: c.tree, ask: c.ask, answers }, null, 2) + '\n')
  rmSync(w, { recursive: true, force: true })
}
console.log(`${cases.length} Fälle nach ${out}`)
