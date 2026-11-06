#!/usr/bin/env node
// Golden file for CoreUpdate, made by QuartzControl's own updateService.ts with real git and its
// real runCommand, contentSymlink, projectDirs and jsonStore. Stand-ins: Quartz's template
// repository (a bare repository in the work folder whose HEAD each scene points at one of five
// branches), the snapshot (recorded), npm (Fixtures/core-update/npm-stub.cjs, steered by a mode
// file) and npx (a script that records `quartz build` and fails on request). Identity and dates
// of every commit are pinned, the service's own merges and amends included, so the hashes are the
// same on both sides.
//
// Each scene is a fresh project cloned from the upstream source; each step is setup actions, one
// call and its answer, then the calls of npm, npx and the snapshot and the state of the project:
// HEAD, its parents, subject and reflog entry, `git status`, the stash list, MERGE_HEAD, the two
// npm-owned files, the note in .quartz-gui/core-update.json and where content/ points.
//
//   Runtime/node/bin/node scripts/core-update-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { spawnSync } from 'node:child_process'
import { chmodSync, copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'core-update')

const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-core-update-golden-')))
const WHEN = '2026-11-06T12:00:00+01:00'
const IDENTITY = {
  GIT_AUTHOR_NAME: 'Jörg Prüfer', GIT_AUTHOR_EMAIL: 'test@example.com', GIT_COMMITTER_NAME: 'Jörg Prüfer', GIT_COMMITTER_EMAIL: 'test@example.com',
  GIT_AUTHOR_DATE: WHEN, GIT_COMMITTER_DATE: WHEN
}
// The whole environment of both sides: nothing of this machine's git or locale.
for (const key of Object.keys(process.env)) if (/^(LANG|LC_|GIT_)/.test(key)) delete process.env[key]
writeFileSync(join(work, 'gitconfig'), '')
Object.assign(process.env, IDENTITY, { GIT_CONFIG_GLOBAL: join(work, 'gitconfig'), GIT_CONFIG_NOSYSTEM: '1', GIT_EDITOR: 'true', PATH: `${join(work, 'bin')}:/usr/bin:/bin` })
process.chdir(work)

// npm, npx: the Swift test writes the same two files with its own work folder and node.
const NPX = `#!/bin/sh
printf '%s\\n' "npx $* @ $(pwd -P)" >> '@W@/npx-calls.log'
if [ "$(cat '@W@/npx-mode.txt' 2>/dev/null)" = fail ]; then echo 'build failed: stub'; exit 1; fi
echo 'Done in 1s'
`
mkdirSync(join(work, 'bin'))
copyFileSync(join(out, 'npm-stub.cjs'), join(work, 'npm-stub.cjs'))
writeFileSync(join(work, 'bin', 'npm'), `#!/bin/sh\nexec '${process.execPath}' '${work}/npm-stub.cjs' "$@"\n`)
writeFileSync(join(work, 'bin', 'npx'), NPX.replaceAll('@W@', work))
chmodSync(join(work, 'bin', 'npm'), 0o755)
chmodSync(join(work, 'bin', 'npx'), 0o755)

globalThis.__snapshots = []
const stubs = {
  ...commonStubs,
  './createService': `export const TEMPLATE_REPO = ${JSON.stringify(join(work, 'upstream.git'))}`,
  './snapshotService': 'export async function createSnapshot(project, kind, label) { globalThis.__snapshots.push([kind, label]); return { id: "snap-1" } }'
}
const service = await loadQuartzControl(control, 'electron/main/services/updateService.ts', stubs)

const sub = (text) => (typeof text === 'string' ? text.replaceAll('@W@', work) : text)
function act(action) {
  const path = action.path !== undefined ? join(work, action.path) : undefined
  switch (action.do) {
    case 'write':
      mkdirSync(dirname(path), { recursive: true })
      writeFileSync(path, sub(action.text))
      break
    case 'mkdir':
      mkdirSync(path, { recursive: true })
      break
    case 'remove':
      rmSync(path, { recursive: true, force: true })
      break
    case 'symlink':
      rmSync(path, { recursive: true, force: true })
      symlinkSync(sub(action.target), path)
      break
    case 'git': {
      const r = spawnSync('git', action.args.map(sub), { cwd: path, encoding: 'utf-8' })
      if (r.status !== 0 && !action.mayFail) throw new Error(`git ${action.args.join(' ')} in ${action.path}: ${r.stderr}`)
      break
    }
    default:
      throw new Error(`unknown action ${action.do}`)
  }
}

const git = (args, cwd) => spawnSync('git', args, { cwd, encoding: 'utf-8' })
const text = (file) => (existsSync(file) ? readFileSync(file, 'utf-8') : null)
const mask = (value) => JSON.parse(JSON.stringify(value ?? null, (k, v) => (typeof v === 'string' ? v.replaceAll(work, '@W@') : v)))
function state(dir) {
  const p = join(work, dir)
  const content = join(p, 'content')
  let contentState = null
  try { contentState = lstatSync(content).isSymbolicLink() ? `link:${readlinkSync(content)}` : 'folder' } catch {}
  return mask({
    head: git(['rev-parse', '-q', '--verify', 'HEAD'], p).stdout.trim(),
    parents: git(['log', '-1', '--format=%P'], p).stdout.trim(),
    subject: git(['log', '-1', '--format=%s'], p).stdout.trim(),
    reflog: git(['reflog', '-1', '--format=%gs'], p).stdout.trim(),
    status: git(['status', '--porcelain=v1', '-z', '--untracked-files=all'], p).stdout.split('\0').filter(Boolean),
    stash: git(['stash', 'list', '--format=%gd %s'], p).stdout.split('\n').filter(Boolean),
    mergeHead: git(['rev-parse', '-q', '--verify', 'MERGE_HEAD'], p).stdout.trim(),
    packageJson: text(join(p, 'package.json')),
    lockfile: text(join(p, 'package-lock.json')),
    note: text(join(p, '.quartz-gui', 'core-update.json')),
    content: contentState
  })
}

const steps = []
async function step(name, setup, op, dir, args = {}) {
  for (const action of setup) act(action)
  for (const log of ['npm-calls.log', 'npx-calls.log']) rmSync(join(work, log), { force: true })
  globalThis.__snapshots = []
  const project = join(work, dir)
  const record = { name, setup, op, dir, args }
  try {
    switch (op) {
      case 'update': record.result = mask(await service.runCoreUpdate(project)); break
      case 'abort': record.result = mask(await service.abortCoreMerge(project)); break
      case 'status': record.result = mask(await service.getCoreUpdateStatus(project, args)); break
      case 'noteSucceeded': await service.noteInstallSucceeded(project); record.result = null; break
      case 'none': record.result = null; break
      default: throw new Error(`unknown op ${op}`)
    }
  } catch (error) {
    record.error = String(error?.message ?? error)
  }
  record.npm = (text(join(work, 'npm-calls.log')) ?? '').split('\n').filter(Boolean).map((line) => JSON.parse(line))
  record.npx = (text(join(work, 'npx-calls.log')) ?? '').replaceAll(work, '@W@')
  record.snapshots = globalThis.__snapshots
  record.state = state(dir)
  steps.push(record)
}

// ---------------------------------------------------------------------------------------------
// The upstream: five branches of one repository.
const W = (path) => `@W@/${path}`
const g = (path, args, extra = {}) => ({ do: 'git', path, args, ...extra })
const write = (path, value) => ({ do: 'write', path, text: typeof value === 'string' ? value : `${JSON.stringify(value, null, 2)}\n` })
const mode = (npm, npx = 'ok') => [write('npm-mode.txt', `${npm}\n`), write('npx-mode.txt', `${npx}\n`)]
const pkgA = {
  name: 'quartz', version: '5.0.0', type: 'module', scripts: { build: 'tsx ./quartz/bootstrap-cli.mjs' },
  dependencies: { '@quartz-themes/core': '^1.0.0', 'a-lib': '^1.0.0', 'm-lib': '^1.0.0', yaml: '^2.0.0', 'x-lib': '^1.0.0', 'z-lib': '^1.0.0' },
  devDependencies: { tsx: '^4.0.0' }
}
const pkgB = { ...pkgA, version: '5.0.1', dependencies: { ...pkgA.dependencies, '@quartz-themes/core': '^2.0.0', yaml: '^2.1.0' } }
const upLock = (pkg, generator = 'upstream') => ({ name: pkg.name, version: pkg.version, lockfileVersion: 3, generator, packages: { '': { dependencies: pkg.dependencies, devDependencies: pkg.devDependencies } } })
const withDeps = (pkg, extra, at = 'sorted') => {
  const merged = { ...pkg.dependencies, ...extra }
  const keys = at === 'end' ? [...Object.keys(pkg.dependencies), ...Object.keys(extra)] : Object.keys(merged).sort()
  return { ...pkg, dependencies: Object.fromEntries(keys.map((k) => [k, merged[k]])) }
}
const THEMES = { '@quartz-themes/default': '^2.0.0', '@quartz-themes/minimal': '^2.0.0' }
const LATE = { 'zz-theme-a': '^1.0.0', 'zz-theme-b': '^1.0.0' }
const commit = (dir, message, files = ['-A']) => [g(dir, ['add', ...files]), g(dir, ['commit', '-q', '-m', message])]

const src = 'upstream-src'
const upstream = [
  { do: 'mkdir', path: src }, g(src, ['init', '-q', '-b', 'a']),
  write(`${src}/.gitignore`, 'node_modules/\n.quartz-gui/\npublic/\n'), write(`${src}/README.md`, '# Quartz\n'),
  write(`${src}/quartz/index.ts`, 'export const version = 1\nexport const name = "quartz"\n'),
  write(`${src}/package.json`, pkgA), write(`${src}/package-lock.json`, upLock(pkgA)), ...commit(src, 'A'),
  g(src, ['checkout', '-q', '-b', 'b']), write(`${src}/package.json`, pkgB), write(`${src}/package-lock.json`, upLock(pkgB)), ...commit(src, 'B: packages'),
  g(src, ['checkout', '-q', '-b', 'e']), write(`${src}/quartz/index.ts`, 'export const version = 2\nexport const name = "quartz"\n'), ...commit(src, 'E: index'),
  g(src, ['checkout', '-q', '-b', 'c', 'b']), write(`${src}/content/.gitkeep`, ''), ...commit(src, 'C: content'),
  g(src, ['checkout', '-q', '-b', 'f', 'b']), write(`${src}/docs/guide.md`, '# Guide\n'), ...commit(src, 'F: docs'),
  g(src, ['checkout', '-q', '-b', 'b2', 'a']), write(`${src}/README.md`, '# Quartz\n\nMore.\n'), ...commit(src, 'B2: readme'),
  g('', ['clone', '-q', '--bare', W(src), W('upstream.git')]),
  g('upstream.git', ['fetch', '-q', 'origin', '+refs/heads/*:refs/heads/*'])
]
await step('the upstream', upstream, 'none', src)

let sceneCount = 0
function scene(branch, up, clone = []) {
  sceneCount += 1
  const dir = `p${String(sceneCount).padStart(2, '0')}`
  return {
    dir,
    setup: [
      g('', ['clone', '-q', ...clone, '--branch', branch, W(src), W(dir)]), g(dir, ['remote', 'remove', 'origin']),
      g('upstream.git', ['symbolic-ref', 'HEAD', `refs/heads/${up}`]), ...mode('ok')
    ]
  }
}
const upstreamAt = (branch) => g('upstream.git', ['symbolic-ref', 'HEAD', `refs/heads/${branch}`])

// 1 up to date: the shortcut
{
  const s = scene('b', 'b')
  await step('up to date: status', s.setup, 'status', s.dir, {})
  await step('up to date: update', [], 'update', s.dir)
}
// 2 fast-forward, and the status before and after; one branch only, so upstream's commit is unknown
{
  const s = scene('a', 'b', ['--single-branch', '--no-local'])
  await step('fast-forward: status without fetch', s.setup, 'status', s.dir, {})
  await step('fast-forward: status with fetch', [], 'status', s.dir, { resolveInstalled: true })
  await step('fast-forward: update', [], 'update', s.dir)
  await step('fast-forward: status after', [], 'status', s.dir, {})
}
// 3 own commit: a merge commit of this run, the lockfile npm rewrote amended into it
{
  const s = scene('a', 'b')
  await step('own commit: update', [...s.setup, write(`${s.dir}/README.md`, '# Mine\n'), ...commit(s.dir, 'mine')], 'update', s.dir)
  await step('own commit: status', [], 'status', s.dir, { resolveInstalled: true })
}
// 4 R1: themes committed next to core, both files conflict; npm fails twice, then gets through
{
  const s = scene('a', 'b')
  const ours = withDeps(pkgA, THEMES)
  await step('R1: run 1, npm fails', [...s.setup, write(`${s.dir}/package.json`, ours), write(`${s.dir}/package-lock.json`, upLock(ours, 'own')),
    ...commit(s.dir, 'themes'), ...mode('eacces')], 'update', s.dir)
  await step('R1: status while pending', [], 'status', s.dir, {})
  await step('R1: run 2, npm fails again', [], 'update', s.dir)
  await step('R1: run 3', mode('ok'), 'update', s.dir)
  await step('R1: status after', [], 'status', s.dir, {})
}
// 5 R2: themes uncommitted, an own commit on the README, a clean merge: they stay uncommitted
{
  const s = scene('a', 'b')
  await step('R2: update', [...s.setup, write(`${s.dir}/README.md`, '# Mine\n'), ...commit(s.dir, 'mine'),
    write(`${s.dir}/package.json`, withDeps(pkgA, THEMES))], 'update', s.dir)
}
// 6 R3: themes committed at the end of the block, a clean merge: the amend runs, nothing to put back
{
  const s = scene('a', 'b')
  const ours = withDeps(pkgA, LATE, 'end')
  await step('R3: update', [...s.setup, write(`${s.dir}/package.json`, ours), write(`${s.dir}/package-lock.json`, upLock(ours)),
    ...commit(s.dir, 'late themes')], 'update', s.dir)
}
// 7 R4/R5: run 1 fails at npm, the user adds a script and leaves it uncommitted, run 2: no amend
{
  const s = scene('a', 'b')
  const ours = withDeps(pkgA, THEMES)
  await step('R5: run 1, npm fails', [...s.setup, write(`${s.dir}/package.json`, ours), write(`${s.dir}/package-lock.json`, upLock(ours, 'own')),
    ...commit(s.dir, 'themes'), ...mode('eacces')], 'update', s.dir)
  await step('R5: run 2 over a script of the user', [...mode('ok'), write(`${s.dir}/package.json`, { ...pkgB, scripts: { ...pkgB.scripts, mine: 'echo mine' } })],
    'update', s.dir)
}
// 8 R6: the same without the user's edit: the amend runs
{
  const s = scene('a', 'b')
  const ours = withDeps(pkgA, THEMES)
  await step('R6: run 1, npm fails', [...s.setup, write(`${s.dir}/package.json`, ours), write(`${s.dir}/package-lock.json`, upLock(ours, 'own')),
    ...commit(s.dir, 'themes'), ...mode('eacces')], 'update', s.dir)
  await step('R6: run 2', mode('ok'), 'update', s.dir)
}
// 9 uncommitted themes over a fast-forward
{
  const s = scene('a', 'b')
  await step('uncommitted, fast-forward', [...s.setup, write(`${s.dir}/package.json`, withDeps(pkgA, THEMES))], 'update', s.dir)
}
// 10 committed, then removed uncommitted: the plan cannot replay it, git decides
{
  const s = scene('a', 'b')
  const ours = withDeps(pkgA, THEMES)
  await step('removed uncommitted', [...s.setup, write(`${s.dir}/package.json`, ours), ...commit(s.dir, 'themes'),
    write(`${s.dir}/package.json`, withDeps(pkgA, { '@quartz-themes/default': '^2.0.0' }))], 'update', s.dir)
}
// 11 uncommitted themes, a conflict in another file: the merge stops; again; abort brings them back
{
  const s = scene('a', 'e')
  await step('conflict elsewhere: run 1', [...s.setup, write(`${s.dir}/quartz/index.ts`, 'export const version = 9\nexport const name = "quartz"\n'),
    ...commit(s.dir, 'mine'), write(`${s.dir}/package.json`, withDeps(pkgA, THEMES))], 'update', s.dir)
  await step('conflict elsewhere: run 2 while the merge stands', [], 'update', s.dir)
  await step('conflict elsewhere: status', [], 'status', s.dir, {})
  await step('conflict elsewhere: abort', [], 'abort', s.dir)
  await step('conflict elsewhere: abort again', [], 'abort', s.dir)
}
// 12 the lockfile taken out of the index and ignored
{
  const s = scene('a', 'b')
  await step('lockfile untracked', [...s.setup, g(s.dir, ['rm', '-q', '--cached', 'package-lock.json']),
    write(`${s.dir}/.gitignore`, 'node_modules/\n.quartz-gui/\npublic/\npackage-lock.json\n'), ...commit(s.dir, 'no lockfile'),
    write(`${s.dir}/package.json`, withDeps(pkgA, THEMES))], 'update', s.dir)
}
// 13 an uncommitted change to a file upstream touches: the merge does not begin
{
  const s = scene('a', 'b2')
  await step('local change in the way', [...s.setup, write(`${s.dir}/README.md`, '# Local\n'), write(`${s.dir}/package.json`, withDeps(pkgA, THEMES))], 'update', s.dir)
}
// 14 the abort, refused and with losses
{
  const conflict = (s) => [...s.setup, write(`${s.dir}/quartz/index.ts`, 'export const version = 9\nexport const name = "quartz"\n'), ...commit(s.dir, 'mine')]
  const a = scene('a', 'e')
  await step('abort: edited after the stop, run', conflict(a), 'update', a.dir)
  await step('abort: edited after the stop', [write(`${a.dir}/package.json`, { ...pkgB, description: 'edited' }),
    write(`${a.dir}/package-lock.json`, { edited: true }), write(`${a.dir}/README.md`, '# Unstaged\n')], 'abort', a.dir)
  await step('abort: edited after the stop, given up', [g(a.dir, ['checkout', '--', 'package.json', 'package-lock.json'])], 'abort', a.dir)
  const b = scene('a', 'e')
  await step('abort: own staged file, run', conflict(b), 'update', b.dir)
  await step('abort: own staged file', [write(`${b.dir}/notes.md`, 'mine\n'), g(b.dir, ['add', 'notes.md'])], 'abort', b.dir)
  const c = scene('a', 'e')
  await step('abort: intent to add, run', conflict(c), 'update', c.dir)
  await step('abort: intent to add', [write(`${c.dir}/later.md`, 'later\n'), g(c.dir, ['add', '-N', 'later.md'])], 'abort', c.dir)
  const d = scene('a', 'e')
  await step('abort: untracked in the way, run', conflict(d), 'update', d.dir)
  await step('abort: untracked in the way', [g(d.dir, ['rm', '-q', '--cached', 'README.md'])], 'abort', d.dir)
  const e = scene('a', 'e')
  await step('abort: staged on a merged file, run', conflict(e), 'update', e.dir)
  await step('abort: staged on a merged file', [write(`${e.dir}/package.json`, { ...pkgB, description: 'staged' }), g(e.dir, ['add', 'package.json'])], 'abort', e.dir)
  const f = scene('a', 'e')
  await step('abort: nothing in progress', f.setup, 'abort', f.dir)
}
// 15 three versions of package.json at once: hands off
{
  const s = scene('a', 'b')
  await step('three versions', [...s.setup, write(`${s.dir}/package.json`, withDeps(pkgA, { '@quartz-themes/default': '^2.0.0' })), g(s.dir, ['add', 'package.json']),
    write(`${s.dir}/package.json`, withDeps(pkgA, THEMES))], 'update', s.dir)
}
// 16 notes: unreadable, invalid entries, one from an older version without filesAtHead
{
  const s = scene('a', 'b')
  await step('note unreadable', [...s.setup, write(`${s.dir}/.quartz-gui/core-update.json`, '{ not json')], 'update', s.dir)
  const t = scene('a', 'b')
  await step('note with invalid entries: status', [...t.setup, write(`${t.dir}/.quartz-gui/core-update.json`, {
    installPendingFor: 'abc', reinstall: [{ name: '-x', section: 'dependencies', range: '1' }, { name: 'ok', section: 'bogus', range: '1' }, 'str', null,
      { name: 'fine', section: 'dependencies', range: '^1.0.0' }], filesAtHead: 'yes', installFailed: 1, putBack: ['fine', '', '-y', 3]
  })], 'status', t.dir, {})
  await step('note with invalid entries: update', [], 'update', t.dir)
  const u = scene('a', 'b')
  const ours = withDeps(pkgA, THEMES)
  await step('old note: run 1, npm fails', [...u.setup, write(`${u.dir}/package.json`, ours), write(`${u.dir}/package-lock.json`, upLock(ours, 'own')),
    ...commit(u.dir, 'themes'), ...mode('eacces')], 'update', u.dir)
  {
    // The note as a version before filesAtHead wrote it: the same note without that field.
    const parsed = JSON.parse(readFileSync(join(work, u.dir, '.quartz-gui', 'core-update.json'), 'utf-8'))
    delete parsed.filesAtHead
    await step('old note: the note loses filesAtHead', [write(`${u.dir}/.quartz-gui/core-update.json`, parsed)], 'none', u.dir)
  }
  await step('old note: run 2', mode('ok'), 'update', u.dir)
}
// 17 the user's own stash above the app's
{
  const s = scene('a', 'e')
  await step('own stash: run 1', [...s.setup, write(`${s.dir}/quartz/index.ts`, 'export const version = 9\nexport const name = "quartz"\n'),
    ...commit(s.dir, 'mine'), write(`${s.dir}/package.json`, withDeps(pkgA, THEMES))], 'update', s.dir)
  await step('own stash: merge aborted by hand, own stash', [g(s.dir, ['merge', '--abort']), write(`${s.dir}/README.md`, '# Stashed\n'),
    g(s.dir, ['stash', 'push', '-q', '-m', 'own work', '--', 'README.md']), write(`${s.dir}/package.json`, withDeps(pkgA, THEMES))], 'update', s.dir)
  await step('own stash: abort', [], 'abort', s.dir)
}
// 18 the note's list taken in hand: a theme line committed by the user, and one removed
{
  const s = scene('a', 'b')
  const ours = withDeps(pkgA, THEMES)
  await step('answered: run 1, npm fails', [...s.setup, write(`${s.dir}/package.json`, ours), write(`${s.dir}/package-lock.json`, upLock(ours, 'own')),
    ...commit(s.dir, 'themes'), ...mode('eacces')], 'update', s.dir)
  await step('answered: status', [], 'status', s.dir, {})
  await step('answered: the user commits one theme back by hand, run 2', [...mode('ok'),
    write(`${s.dir}/package.json`, withDeps(pkgB, { '@quartz-themes/default': '^2.0.0' })), ...commit(s.dir, 'one theme', ['package.json'])], 'update', s.dir)
  const t = scene('a', 'b')
  await step('unreadable history: run 1', [...t.setup, write(`${t.dir}/package.json`, ours), write(`${t.dir}/package-lock.json`, upLock(ours, 'own')),
    ...commit(t.dir, 'themes'), ...mode('eacces')], 'update', t.dir)
  await step('unreadable history: the noted commit is gone, run 2', [...mode('ok'), { do: 'git', path: t.dir, args: ['reset', '-q', '--hard', 'HEAD~1'] },
    g(t.dir, ['reflog', 'expire', '--expire=now', '--all']), g(t.dir, ['gc', '-q', '--prune=now']),
    write(`${t.dir}/package.json`, pkgA), write(`${t.dir}/package-lock.json`, upLock(pkgA)), ...commit(t.dir, 'themes gone')], 'update', t.dir)
}
// 19 content is a link to a vault: parked for the merge, back afterwards
{
  const s = scene('a', 'c')
  await step('content link', [...s.setup, { do: 'mkdir', path: 'vault' }, write('vault/note.md', '# Note\n'),
    { do: 'symlink', path: `${s.dir}/content`, target: W('vault') }], 'update', s.dir)
}
// 20 a failed install noted, then reported as succeeded
{
  const s = scene('a', 'b')
  await step('note install succeeded: run 1', [...s.setup, write(`${s.dir}/README.md`, '# Mine\n'), ...commit(s.dir, 'mine'), ...mode('eacces')], 'update', s.dir)
  await step('note install succeeded: status', [], 'status', s.dir, {})
  await step('note install succeeded', [], 'noteSucceeded', s.dir)
  await step('note install succeeded: status after', [], 'status', s.dir, {})
}
// 21 the warm-up build fails; npm resolves its own ranges; a peer install fails between two calls
{
  const s = scene('a', 'b')
  await step('warm-up fails', [...s.setup, write(`${s.dir}/README.md`, '# Mine\n'), ...commit(s.dir, 'mine'), ...mode('ok', 'fail')], 'update', s.dir)
  const t = scene('a', 'b')
  const ours = { ...withDeps(pkgA, THEMES), devDependencies: { ...pkgA.devDependencies, 'kind-of': '^6.0.0' }, peerDependencies: { 'kind-of': '^6.0.0' } }
  await step('npm resolves, a peer call fails: run 1', [...t.setup, write(`${t.dir}/package.json`, ours), ...mode('fail-peer')], 'update', t.dir)
  await step('npm resolves, a peer call fails: status', [], 'status', t.dir, {})
  await step('npm resolves: run 2', mode('resolve'), 'update', t.dir)
  // The lines this app's npm wrote back, committed by the user (Git-Sync): still the app's writing.
  const u = scene('a', 'b')
  await step('put back, then committed: run 1', [...u.setup, write(`${u.dir}/package.json`, ours), ...mode('fail-peer')], 'update', u.dir)
  await step('put back, then committed: run 2', [...mode('ok'), ...commit(u.dir, 'sync', ['package.json'])], 'update', u.dir)
  // A line that only contains a noted name is no answer: the needle is the name in quotes.
  const v = scene('a', 'b')
  const themed = withDeps(pkgA, THEMES)
  await step('a name inside another: run 1', [...v.setup, write(`${v.dir}/package.json`, themed), write(`${v.dir}/package-lock.json`, upLock(themed, 'own')),
    ...commit(v.dir, 'themes'), ...mode('eacces')], 'update', v.dir)
  await step('a name inside another: run 2', [...mode('ok'),
    write(`${v.dir}/package.json`, { ...pkgB, devDependencies: { ...pkgB.devDependencies, '@quartz-themes/default-extra': '^1.0.0' } }), ...commit(v.dir, 'other', ['package.json'])],
    'update', v.dir)
}
// 22 the run that finishes an earlier one, the lockfile staged apart and its tree at HEAD: the
// files were not at HEAD when it began, so no amend
{
  const s = scene('a', 'b')
  const ours = withDeps(pkgA, THEMES)
  await step('staged lockfile, tree at HEAD: run 1', [...s.setup, write(`${s.dir}/package.json`, ours), write(`${s.dir}/package-lock.json`, upLock(ours, 'own')),
    ...commit(s.dir, 'themes'), ...mode('eacces')], 'update', s.dir)
  await step('staged lockfile, tree at HEAD: run 2', [...mode('ok'), write(`${s.dir}/package-lock.json`, { staged: true }), g(s.dir, ['add', 'package-lock.json']),
    g(s.dir, ['restore', '--worktree', '--source=HEAD', '--', 'package-lock.json'])], 'update', s.dir)
}
// 23 upstream re-pins what the project re-pinned: upstream wins, and the run says so
{
  const s = scene('a', 'b')
  await step('upstream wins', [...s.setup, write(`${s.dir}/package.json`, withDeps(pkgA, { '@quartz-themes/core': '^1.5.0' }))], 'update', s.dir)
}
// 24 the note's head is real, its entries partly unsafe
{
  const s = scene('a', 'b')
  await step('unsafe entries under a real head: the project', [...s.setup], 'none', s.dir)
  const head = spawnSync('git', ['rev-parse', 'HEAD'], { cwd: join(work, s.dir), encoding: 'utf-8' }).stdout.trim()
  await step('unsafe entries under a real head: status', [write(`${s.dir}/.quartz-gui/core-update.json`, {
    installPendingFor: head, reinstall: [{ name: '-x', section: 'dependencies', range: '1' }, { name: 'fine', section: 'dependencies', range: '-1' },
      { name: 'good', section: 'devDependencies', range: '^1.0.0' }, { name: '', section: 'dependencies', range: '1' }],
    filesAtHead: true, installFailed: false, putBack: ['good', 'nobody', '-z']
  })], 'status', s.dir, {})
  await step('unsafe entries under a real head: update', [], 'update', s.dir)
}
// 25 the merge commit pushed before the run that finishes it: no amend
{
  const s = scene('a', 'b')
  const ours = withDeps(pkgA, THEMES)
  await step('pushed: run 1, npm fails', [...s.setup, write(`${s.dir}/package.json`, ours), write(`${s.dir}/package-lock.json`, upLock(ours, 'own')),
    ...commit(s.dir, 'themes'), ...mode('eacces')], 'update', s.dir)
  await step('pushed: run 2', [...mode('ok'), { do: 'mkdir', path: `${s.dir}-origin.git` }, g(`${s.dir}-origin.git`, ['init', '-q', '--bare']),
    g(s.dir, ['remote', 'add', 'origin', W(`${s.dir}-origin.git`)]), g(s.dir, ['push', '-q', '-u', 'origin', 'a'])], 'update', s.dir)
}
// 26 an amend next to the user's other uncommitted work: only the two files go into it
{
  const s = scene('a', 'b')
  const ours = withDeps(pkgA, LATE, 'end')
  await step('amend beside other work', [...s.setup, write(`${s.dir}/package.json`, ours), write(`${s.dir}/package-lock.json`, upLock(ours)),
    ...commit(s.dir, 'late themes'), write(`${s.dir}/README.md`, '# Unstaged\n')], 'update', s.dir)
}
// 27 staged themes, a conflict elsewhere, abort: they come back staged
{
  const s = scene('a', 'e')
  await step('staged themes: run', [...s.setup, write(`${s.dir}/quartz/index.ts`, 'export const version = 9\nexport const name = "quartz"\n'),
    ...commit(s.dir, 'mine'), write(`${s.dir}/package.json`, withDeps(pkgA, THEMES)), g(s.dir, ['add', 'package.json'])], 'update', s.dir)
  await step('staged themes: abort', [], 'abort', s.dir)
}
// 28 a merge the user began by hand over the app's stash, made on another HEAD
{
  const s = scene('a', 'e')
  await step('foreign merge: run', [...s.setup, write(`${s.dir}/quartz/index.ts`, 'export const version = 9\nexport const name = "quartz"\n'),
    ...commit(s.dir, 'mine'), write(`${s.dir}/package.json`, withDeps(pkgA, THEMES))], 'update', s.dir)
  await step('foreign merge: abort', [g(s.dir, ['merge', '--abort']), write(`${s.dir}/README.md`, '# Later\n'), ...commit(s.dir, 'later', ['README.md']),
    g(s.dir, ['merge', 'FETCH_HEAD'], { mayFail: true })], 'abort', s.dir)
}
// 29 a committed theme, one more uncommitted, a conflict elsewhere: the sentence names what the stash holds
{
  const s = scene('a', 'e')
  await step('committed and uncommitted themes', [...s.setup, write(`${s.dir}/quartz/index.ts`, 'export const version = 9\nexport const name = "quartz"\n'),
    write(`${s.dir}/package.json`, withDeps(pkgA, { '@quartz-themes/default': '^2.0.0' })), ...commit(s.dir, 'mine'),
    write(`${s.dir}/package.json`, withDeps(pkgA, THEMES))], 'update', s.dir)
}
// 30 an old note for another head, and the files no longer at HEAD
{
  const s = scene('a', 'b')
  const ours = withDeps(pkgA, THEMES)
  await step('note for another head: run 1', [...s.setup, write(`${s.dir}/package.json`, ours), write(`${s.dir}/package-lock.json`, upLock(ours, 'own')),
    ...commit(s.dir, 'themes'), ...mode('eacces')], 'update', s.dir)
  await step('note for another head: run 2', [...mode('ok'), write(`${s.dir}/README.md`, '# Later\n'), ...commit(s.dir, 'later', ['README.md']),
    write(`${s.dir}/package.json`, { ...pkgB, scripts: { ...pkgB.scripts, mine: 'echo mine' } })], 'update', s.dir)
}
// explainGitFailure, a pure function, over git's texts and the lists the abort hands in
const explain = (await loadQuartzControl(control, 'electron/main/services/updateService.ts', stubs, { expose: ['explainGitFailure'] })).explainGitFailure
const texts = {
  symlink: "error: 'content/.gitkeep' is beyond a symbolic link\n",
  local: 'error: Your local changes to the following files would be overwritten by merge:\n\tREADME.md\nPlease commit your changes or stash them before you merge.\nAborting\n',
  localUpper: 'error: Your LOCAL CHANGES TO THE FOLLOWING FILES WOULD BE OVERWRITTEN by merge:\n',
  unmerged: 'error: Merging is not possible because you have unmerged files.\n',
  mergeHead: 'fatal: You have not concluded your merge (MERGE_HEAD exists).\n',
  entry: "error: Entry 'package.json' not uptodate. Cannot merge.\nfatal: Could not reset index file to revision 'HEAD'.\n",
  twoEntries: "error: Entry 'a b.md' not uptodate. Cannot merge.\nerror: Entry 'c.md' not uptodate. Cannot merge.\n",
  entryMidLine: "note: error: Entry 'x.md' not uptodate. Cannot merge.\n",
  untracked: "error: Untracked working tree file 'README.md' would be overwritten by merge.\nfatal: Could not reset index file to revision 'HEAD'.\n",
  resetOnly: "fatal: Could not reset index file to revision 'HEAD'.\n",
  other: 'fatal: something else\n',
  empty: ''
}
const lists = [
  [], [['package.json', 'package-lock.json']], [['package.json'], ['package.json']], [['a.md', 'b.md'], ['b.md'], [], ['b.md']],
  [[], [], ['README.md', 'x.md']], [[], [], [], [], ['later.md']], [['later.md', 'p.md'], ['p.md'], [], ['p.md'], ['later.md']]
]
const explained = []
for (const [key, text] of Object.entries(texts)) {
  for (const args of lists) explained.push({ text: key, args, result: explain(text, ...args) })
}

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'steps.json'), `${JSON.stringify({ npx: NPX, steps, texts, explained }, null, 1)}\n`)
console.log(`${steps.length} steps, ${steps.filter((s) => s.error).length} with an error`)
rmSync(work, { recursive: true, force: true })
