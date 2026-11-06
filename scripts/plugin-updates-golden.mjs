#!/usr/bin/env node
// Golden file for PluginUpdates, made by QuartzControl's own updateService.ts
// (`getPluginsUpdateStatus`, `updatePlugin`) with real git against local repositories: one plugin
// repository with a branch, a lightweight and an annotated tag, a name that is both a branch and a
// tag, and a newer HEAD; lockfiles with every kind of entry. npx is a script that records its
// arguments; the snapshot is recorded.
//
//   Runtime/node/bin/node scripts/plugin-updates-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { spawnSync } from 'node:child_process'
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'plugin-updates')

const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-plugin-updates-golden-')))
// The identity and date GitGolden's replay pins (GitGolden.swift), so the hashes match.
const WHEN = '2026-11-01T10:00:00+01:00'
for (const key of Object.keys(process.env)) if (/^(LANG|LC_|GIT_)/.test(key)) delete process.env[key]
writeFileSync(join(work, 'gitconfig'), '')
Object.assign(process.env, {
  GIT_AUTHOR_NAME: 'Jörg Prüfer', GIT_AUTHOR_EMAIL: 'test@example.com', GIT_COMMITTER_NAME: 'Jörg Prüfer', GIT_COMMITTER_EMAIL: 'test@example.com',
  GIT_AUTHOR_DATE: WHEN, GIT_COMMITTER_DATE: WHEN, GIT_CONFIG_GLOBAL: join(work, 'gitconfig'), GIT_CONFIG_NOSYSTEM: '1',
  PATH: `${join(work, 'bin')}:/usr/bin:/bin`
})
const NPX = `#!/bin/sh
printf '%s\\n' "npx $* @ $(pwd -P)" >> '@W@/npx-calls.log'
echo 'Installed plugins'
`
mkdirSync(join(work, 'bin'))
writeFileSync(join(work, 'bin', 'npx'), NPX.replaceAll('@W@', work))
chmodSync(join(work, 'bin', 'npx'), 0o755)

globalThis.__snapshots = []
const service = await loadQuartzControl(control, 'electron/main/services/updateService.ts', {
  ...commonStubs,
  './createService': 'export const TEMPLATE_REPO = "/nowhere"',
  './snapshotService': 'export async function createSnapshot(project, kind, label) { globalThis.__snapshots.push([kind, label]); return { id: "snap-1" } }'
})

const sub = (text) => text.replaceAll('@W@', work)
function act(action) {
  const path = action.path !== undefined ? join(work, action.path) : undefined
  if (action.do === 'write') { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, sub(action.text)) }
  else if (action.do === 'mkdir') mkdirSync(path, { recursive: true })
  else if (action.do === 'git') {
    const r = spawnSync('git', action.args.map(sub), { cwd: path, encoding: 'utf-8' })
    if (r.status !== 0) throw new Error(`git ${action.args.join(' ')}: ${r.stderr}`)
  } else throw new Error(`unknown action ${action.do}`)
}
const mask = (value) => JSON.parse(JSON.stringify(value ?? null, (k, v) => (typeof v === 'string' ? v.replaceAll(work, '@W@') : v)))
const git = (args, cwd) => spawnSync('git', args, { cwd: join(work, cwd), encoding: 'utf-8' }).stdout.trim()

const steps = []
async function step(name, setup, op, args = []) {
  for (const action of setup) act(action)
  rmSync(join(work, 'npx-calls.log'), { force: true })
  globalThis.__snapshots = []
  const record = { name, setup, op, args }
  try {
    if (op === 'status') record.result = mask(await service.getPluginsUpdateStatus(join(work, 'p')))
    else if (op === 'update') record.result = mask(await service.updatePlugin(join(work, 'p'), ...args))
    else record.result = null
  } catch (error) {
    record.error = String(error?.message ?? error)
  }
  record.npx = existsSync(join(work, 'npx-calls.log')) ? readFileSync(join(work, 'npx-calls.log'), 'utf-8').replaceAll(work, '@W@') : ''
  record.snapshots = globalThis.__snapshots
  steps.push(record)
}

const g = (path, args) => ({ do: 'git', path, args })
const write = (path, value) => ({ do: 'write', path, text: typeof value === 'string' ? value : `${JSON.stringify(value, null, 2)}\n` })
const repo = [
  { do: 'mkdir', path: 'plugin' }, g('plugin', ['init', '-q', '-b', 'main']),
  write('plugin/index.js', '1\n'), g('plugin', ['add', '-A']), g('plugin', ['commit', '-q', '-m', 'one']),
  g('plugin', ['tag', 'light']), g('plugin', ['tag', '-a', 'v1', '-m', 'v1']), g('plugin', ['branch', 'dev']),
  g('plugin', ['tag', 'both']), g('plugin', ['branch', 'both']),
  write('plugin/index.js', '2\n'), g('plugin', ['commit', '-q', '-am', 'two']), g('plugin', ['branch', '-f', 'both']),
  g('plugin', ['branch', 'feature/x']), g('plugin', ['branch', 'other/x', 'dev']),
  g('plugin', ['tag', '-a', 'rel/v2', '-m', 'v2', 'dev']),
  { do: 'mkdir', path: 'p' }
]
await step('the plugin repository', repo, 'none')
const one = git(['rev-parse', 'dev'], 'plugin')
const two = git(['rev-parse', 'main'], 'plugin')
const R = '@W@/plugin'
const lock = (plugins) => write('p/quartz.lock.json', { version: '1.0.0', plugins })

await step('no lockfile', [], 'status')
await step('lockfile unreadable', [write('p/quartz.lock.json', '{ nope')], 'status')
await step('no plugins key', [write('p/quartz.lock.json', { version: '1' })], 'status')
await step('plugins null', [lock(null)], 'status')
await step('plugins an array', [lock([{ resolved: R, commit: one }, 'x'])], 'status')
await step('plugins a string', [lock('ab')], 'status')
await step('every kind of entry', [lock({
  local: { source: './x', commit: 'local', resolved: R },
  unresolved: { source: 'github:a/b', commit: one },
  emptyResolved: { resolved: '', commit: one },
  current: { resolved: R, commit: two },
  behind: { resolved: R, commit: one },
  noCommit: { resolved: R },
  branch: { resolved: R, ref: 'dev', commit: one },
  branchBehind: { resolved: R, ref: 'main', commit: one },
  lightTag: { resolved: R, ref: 'light', commit: one },
  annotatedTag: { resolved: R, ref: 'v1', commit: one },
  annotatedTagBehind: { resolved: R, ref: 'v1', commit: two },
  annotatedTailMatch: { resolved: R, ref: 'v2', commit: one },
  branchAndTag: { resolved: R, ref: 'both', commit: one },
  tailMatch: { resolved: R, ref: 'x', commit: one },
  missingRef: { resolved: R, ref: 'nope', commit: one },
  emptyRef: { resolved: R, ref: '', commit: two },
  unreachable: { resolved: '@W@/nothing-here', commit: one },
  dashed: { resolved: '--upload-pack=touch @W@/pwned', commit: one },
  dashedRef: { resolved: R, ref: '--upload-pack=touch @W@/pwned', commit: one },
  string: 'just a string',
  number: 3
})], 'status')
await step('nothing ran from a dashed source', [], 'none')
steps.at(-1).result = existsSync(join(work, 'pwned'))
await step('an entry that is null', [lock({ a: null })], 'status')

await step('update all', [], 'update', [])
await step('update one', [], 'update', ['@quartz-community/explorer'])
await step('update an empty name', [], 'update', [''])

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'steps.json'), `${JSON.stringify({ npx: NPX, steps }, null, 1)}\n`)
console.log(`${steps.length} steps, ${steps.filter((s) => s.error).length} with an error`)
rmSync(work, { recursive: true, force: true })
