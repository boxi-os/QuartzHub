#!/usr/bin/env node
// Golden file for GitStatus, Sync and GitAuth, made by QuartzControl's own gitStatusService.ts,
// syncService.ts and gitAuth.ts with real git and its real runCommand. Stand-ins: the GitHub token
// (connectionsService), Quartz's template repository (a local one in the work folder, so the
// history of a shallow clone is completed without the network) and `npx`, a script on PATH that
// writes down how it was called (argv, folder, GIT_TERMINAL_PROMPT, what GIT_ASKPASS answers to
// both of git's prompts) and answers with the output and exit code the step put next to it.
// Also `parseGithubRemote` (githubService.ts), which decides whether the token goes anywhere, over
// a list of remotes.
//
// Each step is setup actions, one call and its answer, then for a sync the calls of npx and the
// state of the project (shallow or not). The Swift test replays the actions with the same git and
// the same pinned identities and dates, so commits get the same hashes.
//
//   Runtime/node/bin/node scripts/git-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { spawnSync } from 'node:child_process'
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'git')

const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-git-golden-')))
writeFileSync(join(work, 'gitconfig'), '')
process.env.GIT_CONFIG_GLOBAL = join(work, 'gitconfig')
process.env.GIT_CONFIG_NOSYSTEM = '1'
process.env.GIT_EDITOR = 'true'
process.env.PATH = `${join(work, 'bin')}:/usr/bin:/bin`
process.chdir(work)

// The npx stand-in, written by the Swift test the same way ("@W@" is the work folder).
const NPX = `#!/bin/sh
W='@W@'
{
  printf 'argv'; for a in "$@"; do printf ' [%s]' "$a"; done; printf '\\n'
  printf 'cwd %s\\n' "$(pwd -P)"
  printf 'prompt %s\\n' "\${GIT_TERMINAL_PROMPT-unset}"
  if [ -n "$GIT_ASKPASS" ]; then
    printf 'askpass mode %s\\n' "$(stat -f %Lp "$GIT_ASKPASS")"
    printf 'askpass user [%s]\\n' "$("$GIT_ASKPASS" "Username for 'https://github.com': ")"
    printf 'askpass pass [%s]\\n' "$("$GIT_ASKPASS" "Password for 'https://x-access-token@github.com': ")"
    printf '%s' "$GIT_ASKPASS" > "$W/askpass-path"
  else
    printf 'askpass none\\n'
  fi
} >> "$W/npx-calls.log"
cat "$W/npx-out.txt" 2>/dev/null
exit "$(cat "$W/npx-exit.txt" 2>/dev/null || echo 0)"
`
mkdirSync(join(work, 'bin'))
writeFileSync(join(work, 'bin', 'npx'), NPX.replaceAll('@W@', work))
chmodSync(join(work, 'bin', 'npx'), 0o755)

globalThis.__token = null
const stubs = {
  ...commonStubs,
  './connectionsService': 'export async function getGithubToken() { return globalThis.__token }',
  './createService': `export const TEMPLATE_REPO = ${JSON.stringify(join(work, 'template'))}`
}
const status = await loadQuartzControl(control, 'electron/main/services/gitStatusService.ts', stubs)
const sync = await loadQuartzControl(control, 'electron/main/services/syncService.ts', stubs)
const auth = await loadQuartzControl(control, 'electron/main/services/gitAuth.ts', stubs)
const github = await loadQuartzControl(control, 'electron/main/services/githubService.ts', stubs)

const identity = (when) => ({
  GIT_AUTHOR_NAME: 'Jörg Prüfer', GIT_AUTHOR_EMAIL: 'test@example.com', GIT_COMMITTER_NAME: 'Jörg Prüfer', GIT_COMMITTER_EMAIL: 'test@example.com',
  GIT_AUTHOR_DATE: when, GIT_COMMITTER_DATE: when
})
const sub = (text) => (typeof text === 'string' ? text.replaceAll('@W@', work) : text)

// ---------------------------------------------------------------------------------------------
// Actions, replayed the same way by the Swift test. Paths are relative to the work folder.
function act(action) {
  const path = action.path !== undefined ? join(work, action.path) : undefined
  switch (action.do) {
    case 'write':
      mkdirSync(dirname(path), { recursive: true })
      writeFileSync(path, sub(action.text))
      break
    case 'many': // `count` files `<path>/<prefix>0000.md` …
      mkdirSync(path, { recursive: true })
      for (let i = 0; i < action.count; i++) writeFileSync(join(path, `${action.prefix}${String(i).padStart(4, '0')}.md`), `${i}\n`)
      break
    case 'mkdir':
      mkdirSync(path, { recursive: true })
      break
    case 'remove':
      rmSync(path, { recursive: true, force: true })
      break
    case 'symlink':
      rmSync(path, { force: true })
      symlinkSync(sub(action.target), path)
      break
    case 'git': { // in `path`, with a fixed identity and date; `mayFail` for a conflict
      const r = spawnSync('git', action.args.map(sub), { cwd: path, encoding: 'utf-8', env: { ...process.env, ...identity(action.when ?? '2026-11-01T10:00:00+01:00') } })
      if (r.status !== 0 && !action.mayFail) throw new Error(`git ${action.args.join(' ')}: ${r.stderr}`)
      break
    }
    case 'token':
      globalThis.__token = action.value
      break
    default:
      throw new Error(`unknown action ${action.do}`)
  }
}

const json = (value) => JSON.parse(JSON.stringify(value ?? null, (k, v) => (typeof v === 'string' ? v.replaceAll(work, '@W@') : v)))
const isShallow = (project) => spawnSync('git', ['rev-parse', '--is-shallow-repository'], { cwd: project, encoding: 'utf-8' }).stdout.trim()

const steps = []
async function step(name, setup, op, args = []) {
  for (const action of setup) act(action)
  rmSync(join(work, 'npx-calls.log'), { force: true })
  rmSync(join(work, 'askpass-path'), { force: true })
  const record = { name, setup, op, args }
  const project = args[0] !== undefined ? join(work, args[0]) : undefined
  try {
    switch (op) {
      case 'status':
        record.result = json(await status.getGitStatus(project))
        break
      case 'sync':
        record.result = json(await sync.runSync(project, ...args.slice(1)))
        record.calls = existsSync(join(work, 'npx-calls.log')) ? readFileSync(join(work, 'npx-calls.log'), 'utf-8').replaceAll(work, '@W@') : ''
        record.askpassLeft = existsSync(join(work, 'askpass-path')) ? existsSync(readFileSync(join(work, 'askpass-path'), 'utf-8')) : null
        record.shallow = isShallow(project)
        break
      case 'auth': {
        const answer = await auth.gitAuthForOrigin(project)
        const script = answer.env.GIT_ASKPASS
        const ask = (prompt) => spawnSync(script, [prompt], { encoding: 'utf-8', env: { ...process.env, ...answer.env } }).stdout
        record.result = {
          // The token's own variable is QuartzControl's name; only that one carries it.
          keys: Object.keys(answer.env).map((k) => (globalThis.__token && answer.env[k] === globalThis.__token ? '<token>' : k)).sort(),
          prompt: answer.env.GIT_TERMINAL_PROMPT ?? null,
          askpass: script ? { mode: (statSync(script).mode & 0o777).toString(8), user: ask("Username for 'https://github.com': "), pass: ask("Password for 'https://x-access-token@github.com': "), lower: ask('username: '), other: ask('Anything else? ') } : null
        }
        await answer.cleanup()
        record.removedAfterCleanup = script ? !existsSync(dirname(script)) : null
        break
      }
      case 'remotes':
        record.result = args[1].map((remote) => github.parseGithubRemote(remote))
        break
      default:
        throw new Error(`unknown op ${op}`)
    }
  } catch (error) {
    record.error = String(error?.message ?? error)
  }
  steps.push(record)
}

const W = (path) => `@W@/${path}`
const g = (path, args, extra = {}) => ({ do: 'git', path, args, ...extra })
const write = (path, text) => ({ do: 'write', path, text })
const when = (iso) => ({ when: iso })

// ---------------------------------------------------------------------------------------------
// git status
await step('no repository', [{ do: 'mkdir', path: 'plain' }, write('plain/a.md', 'a\n')], 'status', ['plain'])
await step('missing folder', [], 'status', ['nowhere'])
await step('repository without a commit', [
  { do: 'mkdir', path: 's' }, g('s', ['init', '-q', '-b', 'main']),
  write('s/a.md', 'a\n'), write('s/B.md', 'b\n'), write('s/Ärger.md', 'ä\n'), write('s/with space.md', 's\n'),
  write('s/quote"d.md', 'q\n'), write('s/new\nline.md', 'n\n'), write('s/_under.md', 'u\n'), write('s/10.md', '10\n'), write('s/9.md', '9\n'),
  write('s/dir/x.md', 'x\n'), write('s/dir/y.md', 'y\n')
], 'status', ['s'])
const lines = (n) => Array.from({ length: n }, (_, i) => `${i + 1}`).join('\n') + '\n'
await step('first commit, everything clean', [
  write('s/big.md', lines(50)), write('s/? orig.md', 'o\n'), g('s', ['add', '-A']), g('s', ['commit', '-q', '-m', 'Erster Stand: „Über“ & "mehr"', '-m', 'Zweiter Absatz\nmit Zeile'], when('2026-11-01T10:00:00+01:00'))
], 'status', ['s'])
await step('every kind of change', [
  write('s/a.md', 'a2\n'), // modified, unstaged
  write('s/B.md', 'b2\n'), g('s', ['add', 'B.md']), // modified, staged
  write('s/9.md', '9a\n'), g('s', ['add', '9.md']), write('s/9.md', '9b\n'), // both
  { do: 'remove', path: 's/10.md' }, // deleted, unstaged
  g('s', ['rm', '-q', '_under.md']), // deleted, staged
  g('s', ['mv', 'with space.md', 'renamed space.md']), // renamed, staged
  g('s', ['mv', '? orig.md', 'from-question.md']), // renamed from a name that reads as a record
  { do: 'symlink', path: 's/quote"d.md', target: 'a.md' }, // type change
  write('s/added.md', 'neu\n'), g('s', ['add', 'added.md']), // added
  write('s/added2.md', 'neu\n'), g('s', ['add', 'added2.md']), write('s/added2.md', 'neu2\n'), // added, then modified
  write('s/zzz-untracked.md', 'u\n'), write('s/Ö-untracked.md', 'u\n'), write('s/newdir/deep/f.md', 'f\n')
], 'status', ['s'])
await step('a copy, when status looks for copies', [
  g('s', ['config', 'status.renames', 'copies']), write('s/big.md', lines(51)), write('s/copy-of-big.md', lines(51)), g('s', ['add', 'big.md', 'copy-of-big.md'])
], 'status', ['s'])
await step('an ignored file', [write('s/.gitignore', 'ignored.md\n'), write('s/ignored.md', 'i\n')], 'status', ['s'])
await step('a broken index', [
  { do: 'mkdir', path: 'broken' }, g('broken', ['init', '-q', '-b', 'main']), write('broken/a.md', 'a\n'), g('broken', ['add', 'a.md']),
  write('broken/.git/index', 'garbage that is not an index at all')
], 'status', ['broken'])

// upstream, ahead and behind
await step('with an upstream, ahead and behind', [
  { do: 'mkdir', path: 'origin.git' }, g('origin.git', ['init', '-q', '--bare', '-b', 'main']),
  { do: 'mkdir', path: 'u' }, g('u', ['init', '-q', '-b', 'main']), write('u/a.md', 'a\n'), g('u', ['add', 'a.md']), g('u', ['commit', '-q', '-m', 'one']),
  g('u', ['remote', 'add', 'origin', W('origin.git')]), g('u', ['push', '-q', '-u', 'origin', 'main']),
  g('', ['clone', '-q', W('origin.git'), W('other')]), write('other/b.md', 'b\n'), g('other', ['add', 'b.md']), g('other', ['commit', '-q', '-m', 'other'], when('2026-11-02T10:00:00+01:00')),
  g('other', ['push', '-q', 'origin', 'main']),
  write('u/c.md', 'c\n'), g('u', ['add', 'c.md']), g('u', ['commit', '-q', '-m', 'mine 1'], when('2026-11-03T10:00:00+01:00')),
  write('u/d.md', 'd\n'), g('u', ['add', 'd.md']), g('u', ['commit', '-q', '-m', 'mine 2'], when('2026-11-03T11:00:00+01:00')),
  g('u', ['fetch', '-q'])
], 'status', ['u'])
await step('an upstream that is gone', [
  g('u', ['checkout', '-q', '-b', 'feature']), g('u', ['push', '-q', '-u', 'origin', 'feature']), g('u', ['push', '-q', 'origin', '--delete', 'feature']),
  g('u', ['fetch', '-q', '--prune'])
], 'status', ['u'])
await step('detached', [g('u', ['checkout', '-q', '--detach', 'HEAD~1'])], 'status', ['u'])

// operations in progress
const conflictRepo = (dir) => [
  { do: 'mkdir', path: dir }, g(dir, ['init', '-q', '-b', 'main']), write(`${dir}/c.md`, 'base\n'), write(`${dir}/z.md`, 'z\n'), g(dir, ['add', '-A']), g(dir, ['commit', '-q', '-m', 'base']),
  g(dir, ['checkout', '-q', '-b', 'other']), write(`${dir}/c.md`, 'theirs\n'), g(dir, ['commit', '-q', '-am', 'theirs'], when('2026-11-02T10:00:00+01:00')),
  g(dir, ['checkout', '-q', 'main']), write(`${dir}/c.md`, 'ours\n'), g(dir, ['commit', '-q', '-am', 'ours'], when('2026-11-03T10:00:00+01:00'))
]
await step('a merge with a conflict', [...conflictRepo('m'), write('m/z.md', 'changed\n'), write('m/new.md', 'n\n'), g('m', ['merge', '-q', 'other'], { mayFail: true })], 'status', ['m'])
await step('a rebase with a conflict', [...conflictRepo('r'), g('r', ['rebase', '-q', 'other'], { mayFail: true })], 'status', ['r'])
await step('a cherry-pick with a conflict', [...conflictRepo('c'), g('c', ['cherry-pick', 'other'], { mayFail: true })], 'status', ['c'])
await step('a revert with a conflict', [
  ...conflictRepo('v'), write('v/c.md', 'later\n'), g('v', ['commit', '-q', '-am', 'later'], when('2026-11-04T10:00:00+01:00')),
  g('v', ['revert', '--no-edit', 'HEAD~1'], { mayFail: true })
], 'status', ['v'])
await step('a linked worktree with a cherry-pick in progress', [
  ...conflictRepo('wtmain'), g('wtmain', ['worktree', 'add', '-q', '-b', 'wtb', W('wt'), 'main']), g('wt', ['cherry-pick', 'other'], { mayFail: true })
], 'status', ['wt'])
await step('the main worktree of it, nothing in progress', [], 'status', ['wtmain'])

// the cap
await step('more than 500 changes', [
  { do: 'mkdir', path: 'big' }, g('big', ['init', '-q', '-b', 'main']), { do: 'many', path: 'big/t', prefix: 't', count: 20 }, g('big', ['add', '-A']), g('big', ['commit', '-q', '-m', 'tracked']),
  ...Array.from({ length: 20 }, (_, i) => write(`big/t/t${String(i).padStart(4, '0')}.md`, 'changed\n')),
  { do: 'many', path: 'big', prefix: 'u', count: 510 }
], 'status', ['big'])

await step('a conflict behind 500 changes', [
  ...conflictRepo('big2'), g('big2', ['checkout', '-q', '-b', 'many']), { do: 'many', path: 'big2/a', prefix: 'f', count: 505 }, g('big2', ['add', '-A']),
  g('big2', ['commit', '-q', '-m', 'many']), g('big2', ['checkout', '-q', 'main']), g('big2', ['merge', '-q', 'many']),
  g('big2', ['merge', '-q', 'other'], { mayFail: true }),
  ...Array.from({ length: 505 }, (_, i) => write(`big2/a/f${String(i).padStart(4, '0')}.md`, 'changed\n'))
], 'status', ['big2'])

// ---------------------------------------------------------------------------------------------
// parseGithubRemote
const REMOTES = [
  'https://github.com/o/r', 'https://github.com/o/r.git', 'https://github.com/o/r.git/', 'https://github.com/o/r/', 'https://github.com/o',
  'https://github.com/', 'https://github.com', 'https://www.github.com/o/r', 'https://api.github.com/repos/x/y', 'https://GitHub.COM/O/R',
  'HTTPS://github.com/o/r', 'http://github.com/o/r', 'https://user:pw@github.com/o/r', 'https://x-access-token@github.com/o/r', 'https://@github.com/o/r',
  'https://a@b@github.com/o/r', 'https://github.com@evil.com/o/r', 'https://github.com:443/o/r', 'https://github.com:8443/o/r', 'https://github.com:/o/r',
  'https://github.com:99999/o/r', 'https://github.com:80a/o/r', 'https://github.com/o/r?x=1', 'https://github.com/o/r#frag', 'https://github.com?x/o/r',
  'https://github.com/o/r/tree/main', 'https://github.com/ö/r', 'https://github.com/o/r with space', 'https://github.com/o%20x/r', 'https://github.com/./o/r',
  'https://github.com/o/../x/r', 'https://github.com/o/%2e%2E/x/r', 'https://github.com/o/.%2e/x/r', 'https://github.com/%2e/o/r', 'https://github.com/o/r/..',
  'https://github.com//o/r', 'https://github.com.evil.com/o/r', 'https://evilgithub.com/o/r', 'https://github.com./o/r', 'https://github.com/o/r^x',
  'https://github.com/o/{r}', 'https://github.com/o/r|x', 'https://github.com/o/[r]', 'https://github.com/"o"/r', 'https://github.com/o/r`',
  'https://github.com/<o>/r', "https://github.com/o'/r", 'https://github.com/o/r~!$&()*+,;=:@', 'https://github.com/o/r\u007f', 'https://github.com/o/r\u0001x',
  'https://github.com/o\t/r', 'https://git\nhub.com/o/r', 'https://github.com/o/r\r\n', '  https://github.com/o/r  \n', '\u0001https://github.com/o/r',
  'https://xn--github-xyz.com/o/r', 'https://\uff47ithub.com/o/r', 'https://G\u0130THUB.com/o/r', 'https://github%2Ecom/o/r', 'https://github.com%2fo/r',
  'https://[::1]/o/r', 'https://github.com/o/r.git.git', 'https://github.com/o/r.GIT', 'https:github.com/o/r', 'https:/github.com/o/r',
  'https:///github.com/o/r', 'https:\\\\github.com\\o\\r', 'https://github.com\\o\\r', 'http:github.com/o/r', 'ws://github.com/o/r',
  'ftp://github.com/o/r', 'file://github.com/o/r', 'file:///github.com/o/r', 'file://localhost/o/r', 'ssh://git@github.com/o/r.git',
  'ssh://git@GitHub.com/o/r', 'ssh://github.com:22/o/r', 'git://github.com/o/r', 'git+ssh://git@github.com/o/r', 'ssh:github.com/o/r',
  'ssh://git@github.com', 'ssh://git@github.com/./o/r', 'ssh://git@github.com/o r/x', 'ssh://git@github.com/ö/r', 'Ssh://git@github.com/o/r',
  'git@github.com:o/r.git', 'git@github.com:o/r', 'git@github.com:o', 'git@github.com:/o/r', 'org-1@github.com:o/r.git',
  '@github.com:o/r', 'git@gitlab.com:o/r', 'git@github.com:o/r/x', 'git@github.com:o/r\n', 'git@github.com:ö/r',
  'a\n@github.com:o/r', 'git@github.com:o/r\u2028x', 'git@github.com:o/r\u0085x', 'git@github.com:o/r\fx', 'git@GitHub.com:o/r',
  'git@github.com:o//r', 'git@github.com:o/r.git\n', 'gh:o/r', '', 'not a url',
  '/local/path', 'C:\\x', '1:2', 'https://github.com/o/r\u00a0', 'https://github.com/o/r%'
]
await step('remotes', [], 'remotes', [undefined, REMOTES])

// ---------------------------------------------------------------------------------------------
// gitAuthForOrigin
const authCase = async (name, origin, token) => {
  const dir = `auth-${steps.length}`
  const setup = [{ do: 'mkdir', path: dir }, g(dir, ['init', '-q', '-b', 'main'])]
  if (origin !== null) setup.push(g(dir, ['remote', 'add', 'origin', origin]))
  setup.push({ do: 'token', value: token })
  await step(name, setup, 'auth', [dir])
}
await authCase('https on github with a token', 'https://github.com/o/r.git', 'ghp_secret"$`\\token')
await authCase('http on github with a token', 'http://github.com/o/r', 'ghp_x')
await authCase('www.github.com', 'https://www.github.com/o/r', 'ghp_x')
await authCase('ssh on github', 'git@github.com:o/r.git', 'ghp_x')
await authCase('ssh:// on github', 'ssh://git@github.com/o/r.git', 'ghp_x')
await authCase('another host', 'https://gitlab.com/o/r.git', 'ghp_x')
await authCase('a host that only looks like it', 'https://github.com.evil.com/o/r', 'ghp_x')
await authCase('upper-case scheme', 'HTTPS://github.com/o/r', 'ghp_x')
await authCase('no token', 'https://github.com/o/r.git', null)
await authCase('an empty token', 'https://github.com/o/r.git', '')
await authCase('no origin', null, 'ghp_x')
await step('no repository at all', [{ do: 'mkdir', path: 'auth-plain' }, { do: 'token', value: 'ghp_x' }], 'auth', ['auth-plain'])

// ---------------------------------------------------------------------------------------------
// runSync
const answer = (output, exit = 0) => [write('npx-out.txt', output), write('npx-exit.txt', `${exit}\n`)]
await step('sync: a project to push from', [
  { do: 'mkdir', path: 'remote.git' }, g('remote.git', ['init', '-q', '--bare', '-b', 'main']),
  { do: 'mkdir', path: 'y' }, g('y', ['init', '-q', '-b', 'main']), write('y/a.md', 'a\n'), g('y', ['add', 'a.md']), g('y', ['commit', '-q', '-m', 'one']),
  g('y', ['remote', 'add', 'origin', W('remote.git')]), { do: 'token', value: null }, ...answer('Done!\n')
], 'sync', ['y'])
await step('sync: push only', [], 'sync', ['y', 'push'])
await step('sync: pull only', [], 'sync', ['y', 'pull'])
await step('sync: both, without commit', [], 'sync', ['y', 'both', { commit: false }])
await step('sync: without commit but a message', [], 'sync', ['y', 'push', { commit: false, message: 'ignored' }])
await step('sync: a message, trimmed', [], 'sync', ['y', 'push', { commit: true, message: '  Mein Stand „jetzt“  ' }])
await step('sync: a message of spaces', [], 'sync', ['y', 'push', { commit: true, message: '   ' }])
await step('sync: a message that looks like an option', [], 'sync', ['y', 'push', { commit: true, message: '--no-push' }])
await step('sync: a push the CLI reports in prose', answer('Pushing your changes\nAn error occurred while pushing to remote origin.\nCheck that you have push access to the remote repository.\n'), 'sync', ['y', 'push'])
await step('sync: a pull the CLI reports in prose', answer('An error occurred while pulling updates from your repository.\n'), 'sync', ['y', 'pull'])
await step('sync: the sentence, but a failing exit too', answer('An error occurred while pushing to remote origin.\n', 1), 'sync', ['y', 'push'])
await step('sync: a failing exit', answer('fatal: something\n', 2), 'sync', ['y'])
await step('sync: the sentence in other words', answer('an error occurred while pushing\n'), 'sync', ['y'])
await step('sync: to github with a token', [
  g('y', ['remote', 'set-url', 'origin', 'https://github.com/o/r.git']), { do: 'token', value: 'ghp_sync' }, ...answer('Done!\n')
], 'sync', ['y', 'push'])
await step('sync: a pull to github with a token', [], 'sync', ['y', 'pull'])
await step('sync: to github over ssh', [g('y', ['remote', 'set-url', 'origin', 'git@github.com:o/r.git'])], 'sync', ['y', 'push'])

// shallow clones
const full = [
  { do: 'mkdir', path: 'template' }, g('template', ['init', '-q', '-b', 'main']),
  write('template/a.md', '1\n'), g('template', ['add', 'a.md']), g('template', ['commit', '-q', '-m', 'one'], when('2026-10-01T10:00:00+02:00')),
  write('template/a.md', '2\n'), g('template', ['commit', '-q', '-am', 'two'], when('2026-10-02T10:00:00+02:00')),
  write('template/a.md', '3\n'), g('template', ['commit', '-q', '-am', 'three'], when('2026-10-03T10:00:00+02:00'))
]
await step('sync: shallow, with quartz-upstream', [
  ...full, g('', ['clone', '-q', '--depth', '1', `file://${W('template')}`, W('sh1')]),
  g('sh1', ['remote', 'add', 'quartz-upstream', W('template')]), ...answer('Done!\n')
], 'sync', ['sh1', 'push'])
await step('sync: shallow, the second time', [], 'sync', ['sh1', 'push'])
await step('sync: shallow, without quartz-upstream (the template)', [g('', ['clone', '-q', '--depth', '1', `file://${W('template')}`, W('sh2')])], 'sync', ['sh2', 'both'])
await step('sync: shallow, quartz-upstream does not answer', [
  g('', ['clone', '-q', '--depth', '1', `file://${W('template')}`, W('sh3')]), g('sh3', ['remote', 'add', 'quartz-upstream', W('nothing-here')])
], 'sync', ['sh3', 'push'])
await step('sync: shallow, a pull does not complete it', [g('', ['clone', '-q', '--depth', '1', `file://${W('template')}`, W('sh4')])], 'sync', ['sh4', 'pull'])
await step('sync: shallow, quartz-upstream empty', [
  g('', ['clone', '-q', '--depth', '1', `file://${W('template')}`, W('sh5')]), g('sh5', ['config', 'remote.quartz-upstream.url', ''])
], 'sync', ['sh5', 'push'])
await step('sync: not a repository', [{ do: 'mkdir', path: 'syncplain' }], 'sync', ['syncplain', 'push'])

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'steps.json'), JSON.stringify({ npx: NPX, steps }, null, 1) + '\n')
console.log(`${steps.length} steps, ${steps.filter((s) => s.error).length} with an error`)
rmSync(work, { recursive: true, force: true })
