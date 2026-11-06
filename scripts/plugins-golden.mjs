#!/usr/bin/env node
// Golden files for PluginCommands, made by QuartzControl's own pluginService.ts: each case lays out
// a project, lets runCommand answer npm and npx as the case says (an npm that installs creates the
// package folders), runs one operation and records the commands, the build service's
// forgetDependencyErrors calls and the answer. The Swift test (PluginCommandsTests) does the same
// with stand-in scripts for npm and npx.
//
//   Runtime/node/bin/node scripts/plugins-golden.mjs [../QuartzControl]
//
// Stand-ins: runCommand, the snapshot store (notes, not compared: QuartzHub's snapshot comes with
// point 7), forgetDependencyErrors, mainT. projectDependencies, configService and the rest are
// QuartzControl's.
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { layOut } from './lib/tree.mjs'
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'plugins')

globalThis.__log = []
globalThis.__answers = {}
const plugins = await loadQuartzControl(control, 'electron/main/services/pluginService.ts', {
  ...commonStubs,
  './snapshotService': 'export async function createSnapshot() {}',
  './buildService': 'export function forgetDependencyErrors(p) { globalThis.__log.push(`forget ${p}`) }',
  './runCommand': `import { mkdirSync, writeFileSync } from 'fs'
    import { dirname, join } from 'path'
    export async function runCommand(command, args, cwd) {
      globalThis.__log.push([command, ...args, cwd].join(' '))
      const answer = globalThis.__answers[command === 'npm' ? 'npm' : args[2]] ?? { success: true, output: '' }
      for (const path of answer.creates ?? []) {
        mkdirSync(dirname(join(cwd, path)), { recursive: true })
        writeFileSync(join(cwd, path), '{}')
      }
      return { success: answer.success, output: answer.output }
    }`
})

const ESC = '\u001b'
const installOutput = [
  `${ESC}[1mInstalling plugins from quartz.lock.json${ESC}[22m`,
  `  ${ESC}[32m✓${ESC}[39m explorer`,
  `  ${ESC}[31m✗${ESC}[39m frame-a: local path missing`,
  '  ✗ frame-b: local path missing',
  '  ✗ frame-a: again',
  '✗ @scope/x: at the start of a line',
  '  ✗ no-colon here',
  `⚠ Installed 1 plugin(s), 3 failed`
].join('\n')

const deps = { 'package.json': JSON.stringify({ dependencies: { sass: '1', globby: '1' } }) }
const installed = { ...deps, 'node_modules/sass/package.json': '{}', 'node_modules/globby/package.json': '{}' }

const cases = [
  { name: 'install-nothing-missing', tree: installed, run: ['installFromLock'], answers: { install: { success: true, output: installOutput } } },
  {
    name: 'install-npm-first', tree: deps, run: ['installFromLock'], answers: {
      npm: { success: true, output: 'added 2 packages\n', creates: ['node_modules/sass/package.json', 'node_modules/globby/package.json'] },
      install: { success: true, output: '  ✓ explorer\n' }
    }
  },
  {
    name: 'install-npm-incomplete', tree: deps, run: ['installFromLock'], answers: {
      npm: { success: true, output: 'added 1 package', creates: ['node_modules/sass/package.json'] },
      install: { success: true, output: '' }
    }
  },
  { name: 'install-npm-fails', tree: deps, run: ['installFromLock'], answers: { npm: { success: false, output: 'ERR! network' } } },
  { name: 'install-no-package-json', tree: {}, run: ['installFromLock'], answers: { install: { success: true, output: 'ok' } } },
  { name: 'install-cli-fails', tree: installed, run: ['installFromLock'], answers: { install: { success: false, output: installOutput } } },
  { name: 'add', tree: installed, run: ['installPluginSource', 'github:quartz-community/explorer'], answers: { add: { success: true, output: 'added' } } },
  { name: 'remove', tree: installed, run: ['removePlugin', 'explorer'], answers: { remove: { success: false, output: 'not found' } } },
  { name: 'prune', tree: installed, run: ['prunePlugins'], answers: { prune: { success: true, output: 'pruned 2' } } }
]

rmSync(out, { recursive: true, force: true })
for (const c of cases) {
  const w = mkdtempSync(join(tmpdir(), 'qh-plugins-golden-'))
  const project = join(w, 'P')
  layOut(project, c.tree, w)
  globalThis.__log = []
  globalThis.__answers = c.answers
  const [fn, ...args] = c.run
  const result = await plugins[fn](project, ...args)
  const mask = (text) => text.replaceAll(w, '@W@')
  const dir = join(out, c.name)
  mkdirSync(dir, { recursive: true })
  writeFileSync(join(dir, 'case.json'), JSON.stringify({
    tree: c.tree, run: c.run, answers: c.answers,
    expected: { result: { ...result, output: mask(result.output) }, log: globalThis.__log.map(mask) }
  }, null, 2) + '\n')
  rmSync(w, { recursive: true, force: true })
}
console.log(`${cases.length} Fälle nach ${out}`)
