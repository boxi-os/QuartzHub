#!/usr/bin/env node
// Golden file for GitBranchAdapter, made by QuartzControl's own deploy/gitBranch.ts with its real
// runCommand, gitAuth and projectDirs, against a local bare repository as "origin" (no token goes
// anywhere: the remote is not github.com). git is /usr/bin/git with an empty global config;
// identity and dates are pinned in the environment and the commit message's clock, so the shas are
// the same on both sides. Each step is its setup (files and git commands, paths below "@W@"), one
// call of the adapter, its answer, the progress events, and the state: origin's refs, the
// branch's tree with the subject and parent count of its tip, the project's worktrees and what is
// under .quartz-gui/.
//
//   Runtime/node/bin/node scripts/git-branch-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { spawnSync } from 'node:child_process'
import { chmodSync, existsSync, readFileSync, mkdirSync, mkdtempSync, readdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'git-branch')
const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-git-branch-golden-')))
const W = (p) => p.split('@W@').join(work)
const mask = (text) => text.split(work).join('@W@')

const identity = {
  GIT_AUTHOR_NAME: 'Jörg Prüfer', GIT_AUTHOR_EMAIL: 'test@example.com', GIT_COMMITTER_NAME: 'Jörg Prüfer', GIT_COMMITTER_EMAIL: 'test@example.com',
  GIT_AUTHOR_DATE: '2026-11-06T10:00:00+01:00', GIT_COMMITTER_DATE: '2026-11-06T10:00:00+01:00'
}
writeFileSync(join(work, 'gitconfig'), '')
// The same environment the Swift test gives its git: nothing of this machine's.
for (const key of Object.keys(process.env)) if (key.startsWith('GIT_') || key === 'LANG' || key.startsWith('LC_')) delete process.env[key]
Object.assign(process.env, { PATH: '/usr/bin:/bin', GIT_CONFIG_GLOBAL: join(work, 'gitconfig'), GIT_CONFIG_NOSYSTEM: '1', GIT_EDITOR: 'true', ...identity })

const stubs = {
  ...commonStubs,
  '../../i18n': commonStubs['../i18n'],
  './connectionsService': 'export async function getGithubToken() { return undefined }'
}
const { gitBranchAdapter } = await loadQuartzControl(control, 'electron/main/services/deploy/gitBranch.ts', stubs)

const RealDate = Date
const now = RealDate.parse('2026-11-06T10:00:00.000Z')
globalThis.Date = class extends RealDate {
  constructor(...args) { if (args.length === 0) super(now); else super(...args) }
  static now() { return now }
}

const git = (args, cwd) => spawnSync('/usr/bin/git', args, { cwd, encoding: 'utf-8' })
const project = join(work, 'Gärten-Ü')
const origin = join(work, 'origin.git')

function state() {
  const refs = git(['for-each-ref', '--format=%(refname) %(objectname)'], origin).stdout
  const branches = {}
  for (const line of refs.split('\n').filter(Boolean)) {
    const [ref, sha] = line.split(' ')
    if (!ref.startsWith('refs/heads/') || ref === 'refs/heads/main') continue
    branches[ref] = {
      sha,
      subject: git(['log', '-1', '--format=%s', sha], origin).stdout,
      parents: git(['log', '-1', '--format=%P', sha], origin).stdout.trim(),
      tree: git(['ls-tree', '-r', '-z', sha], origin).stdout.split('\0').filter(Boolean)
    }
  }
  const worktrees = git(['worktree', 'list', '--porcelain'], project).stdout.split('\n').filter((l) => l.startsWith('worktree ')).map(mask)
  const gui = existsSync(join(project, '.quartz-gui')) ? readdirSync(join(project, '.quartz-gui')).sort() : null
  const gitignore = existsSync(join(project, '.gitignore')) ? readFileSync(join(project, '.gitignore'), 'utf-8') : null
  return { refs: mask(refs), branches, worktrees, gui, gitignore }
}

const steps = []
async function step(name, op, target, setup = []) {
  for (const a of setup) {
    if (a.write) { mkdirSync(dirname(W(a.write[0])), { recursive: true }); writeFileSync(W(a.write[0]), a.write[1]) }
    if (a.rm) rmSync(W(a.rm), { recursive: true, force: true })
    if (a.chmod) chmodSync(W(a.chmod[0]), parseInt(a.chmod[1], 8))
    if (a.git) {
      const r = git(a.git[1].map(W), W(a.git[0]))
      if (r.status !== 0 && !a.mayFail) throw new Error(`git ${a.git[1].join(' ')}: ${r.stderr}`)
    }
  }
  const events = []
  const ctx = { projectPath: project, target: JSON.parse(W(JSON.stringify(target))), buildDir: join(work, 'build'), secret: null,
    emitProgress: (processed, total, currentFile) => events.push({ processed, total, currentFile }) }
  let result
  try {
    result = { ok: JSON.parse(mask(JSON.stringify(op === 'preview' ? await gitBranchAdapter.preview(ctx) : await gitBranchAdapter.run(ctx, ['index.html'])))) }
  } catch (err) {
    result = { error: mask(String(err.message ?? err)) }
  }
  steps.push({ name, op, target, setup, result, events, state: state() })
}

const target = (branch, extra = {}) => ({ id: 'branch-1', name: 'Pages', destination: { type: 'git-branch', branch, provider: 'github' }, excludes: [], ...extra })
const setup = [
  { git: ['@W@', ['init', '-q', '--bare', '-b', 'main', '@W@/origin.git']] },
  { write: ['@W@/Gärten-Ü/README.md', 'Projekt\n'] },
  { git: ['@W@', ['init', '-q', '-b', 'main', '@W@/Gärten-Ü']] },
  { git: ['@W@/Gärten-Ü', ['add', '-A']] }, { git: ['@W@/Gärten-Ü', ['commit', '-q', '-m', 'Start']] },
  { git: ['@W@/Gärten-Ü', ['remote', 'add', 'origin', '@W@/origin.git']] }, { git: ['@W@/Gärten-Ü', ['push', '-q', 'origin', 'main']] },
  { write: ['@W@/Gärten-Ü/.git/info/exclude', '*.css\n'] },
  { write: ['@W@/build/index.html', '<h1>Start</h1>'] }, { write: ['@W@/build/ä.html', 'ä'] }, { write: ['@W@/build/sub/x.css', 'x{}'] }
]
await step('preview of a new branch', 'preview', target('gh-pages'), setup)
await step('first deploy', 'run', target('gh-pages'))
await step('unchanged', 'run', target('gh-pages'))
const change = [{ write: ['@W@/build/ä.html', 'ä neu'] }, { rm: '@W@/build/sub' }, { write: ['@W@/build/neu ö.html', 'n'] }, { rm: '@W@/build/index.html' },
  { write: ['@W@/build/start.html', '<h1>Start</h1>'] }]
await step('preview after a change and a move', 'preview', target('gh-pages'), change)
await step('deploy replaces the branch', 'run', target('gh-pages'))
await step('a leftover worktree is cleared', 'run', target('gh-pages'), [
  { write: ['@W@/build/more.html', 'm'] }, { git: ['@W@/Gärten-Ü', ['worktree', 'add', '--detach', '@W@/Gärten-Ü/.quartz-gui/branch-worktree-branch-1']] }])
await step('second target on its own branch', 'run', target('pages', { id: 'branch-2' }))
await step('a stale registration of the old shared path is pruned', 'run', target('gh-pages'), [
  { write: ['@W@/build/prune.html', 'p'] }, { git: ['@W@/Gärten-Ü', ['worktree', 'add', '--detach', '@W@/Gärten-Ü/.quartz-gui/branch-worktree']] },
  { rm: '@W@/Gärten-Ü/.quartz-gui/branch-worktree' }])
await step('the lease refuses a branch that moved since the fetch', 'run', target('gh-pages'), [
  { write: ['@W@/build/lease.html', 'l'] }, { git: ['@W@', ['clone', '-q', '--bare', '@W@/origin.git', '@W@/other.git']] },
  { git: ['@W@/other.git', ['update-ref', 'refs/heads/gh-pages', 'refs/heads/main']] },
  { git: ['@W@/Gärten-Ü', ['config', 'remote.origin.pushurl', '@W@/other.git']] }])
await step('the checked-out branch is refused', 'run', target('main'), [{ git: ['@W@/Gärten-Ü', ['config', '--unset', 'remote.origin.pushurl']] }])
await step('origin\'s default is refused', 'preview', target('live'), [
  { git: ['@W@/Gärten-Ü', ['symbolic-ref', 'refs/remotes/origin/HEAD', 'refs/remotes/origin/live']] }])
await step('without origin', 'run', target('gh-pages'), [{ git: ['@W@/Gärten-Ü', ['remote', 'remove', 'origin']] }])
await step('preview without origin', 'preview', target('gh-pages'))
await step('wrong type', 'run', { id: 'x', name: 'x', destination: { type: 'folder', path: '/x', deleteRemoved: false }, excludes: [] },
  [{ git: ['@W@/Gärten-Ü', ['remote', 'add', 'origin', '@W@/origin.git']] }])
await step('a push that is refused', 'run', target('gh-pages'), [
  { write: ['@W@/build/again.html', 'a'] }, { write: ['@W@/origin.git/hooks/pre-receive', '#!/bin/sh\necho "nope from the hook" >&2\nexit 1\n'] }, { chmod: ['@W@/origin.git/hooks/pre-receive', '755'] }])

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'steps.json'), JSON.stringify({ identity, steps }, null, 1) + '\n')
rmSync(work, { recursive: true, force: true })
console.log(`${steps.length} steps`)
