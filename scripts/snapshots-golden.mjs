#!/usr/bin/env node
// Golden file for SnapshotStore, made by QuartzControl's own snapshotService.ts with real git and
// its real runCommand, projectDirs and contentSymlink. Only npm (the install after a restore that
// moved package.json) and repointAuthoredFrames (measured with ProjectPaths) are stand-ins that
// record their calls. The clock is pinned: `Date` answers the step's instant, git gets it as
// GIT_AUTHOR_DATE/GIT_COMMITTER_DATE, and the random tail of an id counts up (0001, 0002, …).
//
// Each step is setup actions (write, remove, chmod, symlink, a commit in the project), one call
// and its answer, then the state: per folder the refs of the store with their commit object (the
// identity masked) and tree, the store's own index, its exclude file, and every file of the work
// folder (sha-256, links as their target). Writes Fixtures/snapshots/steps.json and
// `qc-snapshots.cjs`, the same service bundled as a command, so the Swift tests can let
// QuartzControl read, restore and write a store QuartzHub wrote, and run both at once.
//
//   Runtime/node/bin/node scripts/snapshots-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { build } from '../Helpers/node_modules/esbuild/lib/main.js'
import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'snapshots')

const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-snapshots-golden-')))
// No global or system git config: commit.gpgsign or an init template of the machine must not
// reach either side. The Swift test sets the same two.
writeFileSync(join(work, 'gitconfig'), '')
process.env.GIT_CONFIG_GLOBAL = join(work, 'gitconfig')
process.env.GIT_CONFIG_NOSYSTEM = '1'
process.chdir(work)

globalThis.__calls = []
globalThis.__tail = 0
const stubs = {
  ...commonStubs,
  './runCommand': `import { runCommand as real } from './electron/main/services/runCommand.ts'
export async function runCommand(command, args, cwd, env, timeoutMs) {
  if (command === 'npm') {
    globalThis.__calls.push(['npm', ...args, cwd.replace(globalThis.__work, '@W@')])
    return { success: true, output: 'npm stub', stdout: '' }
  }
  return real(command, args, cwd, env, timeoutMs)
}`,
  './projectPaths': `export async function repointAuthoredFrames(project) { globalThis.__calls.push(['repoint', project.replace(globalThis.__work, '@W@')]) }`,
  crypto: `export function randomBytes(n) { globalThis.__tail += 1; return Buffer.from(String(globalThis.__tail).padStart(n * 2, '0'), 'hex') }`
}
globalThis.__work = work
const service = await loadQuartzControl(control, 'electron/main/services/snapshotService.ts', stubs)
const { readZip } = await loadQuartzControl(control, 'electron/main/services/zipArchive.ts', commonStubs)

// The clock. Only a call without arguments is the step's instant.
const RealDate = Date
let now = RealDate.parse('2026-11-06T10:00:00.000Z')
globalThis.Date = class extends RealDate {
  constructor(...args) { if (args.length === 0) super(now); else super(...args) }
  static now() { return now }
}
const setClock = (iso) => {
  now = RealDate.parse(iso)
  process.env.GIT_AUTHOR_DATE = iso
  process.env.GIT_COMMITTER_DATE = iso
}

const sha = (data) => createHash('sha256').update(data).digest('hex')
const git = (args, cwd, env = {}) => {
  const r = spawnSync('git', args, { cwd, encoding: 'utf-8', env: { ...process.env, ...env } })
  if (r.status !== 0) throw new Error(`git ${args.join(' ')}: ${r.stderr}`)
  return r.stdout
}
const projectCommitEnv = (when) => ({
  GIT_AUTHOR_NAME: 'Test', GIT_AUTHOR_EMAIL: 'test@example.com', GIT_COMMITTER_NAME: 'Test', GIT_COMMITTER_EMAIL: 'test@example.com',
  GIT_AUTHOR_DATE: when, GIT_COMMITTER_DATE: when
})

// ---------------------------------------------------------------------------------------------
// Actions, replayed the same way by the Swift test. Paths are relative to the work folder; "@W@"
// in a link target is the work folder.
function act(action) {
  const path = action.path && join(work, action.path)
  switch (action.do) {
    case 'write':
      mkdirSync(dirname(path), { recursive: true })
      writeFileSync(path, action.text)
      break
    case 'many': // `count` files under `path`, named n0000.md …, with `text` plus the number
      mkdirSync(path, { recursive: true })
      for (let i = 0; i < action.count; i++) writeFileSync(join(path, `n${String(i).padStart(4, '0')}.md`), `${action.text} ${i}\n`)
      break
    case 'remove':
      rmSync(path, { recursive: true, force: true })
      break
    case 'chmod':
      chmodSync(path, parseInt(action.mode, 8))
      break
    case 'symlink':
      mkdirSync(dirname(path), { recursive: true })
      symlinkSync(action.target.replace('@W@', work), path)
      break
    case 'git': // in a project, with a fixed identity and date
      git(action.args, path, projectCommitEnv(action.when ?? '2026-11-01T00:00:00Z'))
      break
    case 'clock':
      setClock(action.at)
      break
    case 'handRef': { // a ref made by hand: an existing snapshot's tree under a commit without a subject
      const store = join(path, '.quartz-gui', 'snapshots.git')
      const tree = git(['--git-dir', store, 'rev-parse', `refs/snapshots/${action.from}^{tree}`], work).trim()
      const commit = git(['--git-dir', store, 'commit-tree', tree, '-m', ''], work, projectCommitEnv('2026-11-06T09:00:00Z')).trim()
      git(['--git-dir', store, 'update-ref', `refs/snapshots/${action.id}`, commit], work)
      break
    }
    default:
      throw new Error(`unknown action ${action.do}`)
  }
}

// ---------------------------------------------------------------------------------------------
// The state after a step.
const BIG = 200
function listing(root) {
  const files = {}
  const walk = (dir, rel) => {
    for (const name of readdirSync(dir).sort()) {
      const full = join(dir, name)
      const path = rel ? `${rel}/${name}` : name
      if (path === '.git' || path === '.quartz-gui/snapshots.git') continue
      const info = lstatSync(full)
      if (info.isSymbolicLink()) files[path] = `link:${readlinkSync(full).replace(work, '@W@')}`
      else if (info.isDirectory()) { files[`${path}/`] = 'dir'; walk(full, path) }
      else files[path] = `${(info.mode & 0o777).toString(8)} ${info.mode & 0o400 ? sha(readFileSync(full)) : 'unreadable'}`
    }
  }
  if (existsSync(root)) walk(root, '')
  return files
}
const digestIfBig = (object) => (Object.keys(object).length > BIG ? { count: Object.keys(object).length, digest: sha(JSON.stringify(object)) } : object)

function storeState(root) {
  const store = join(work, root, '.quartz-gui', 'snapshots.git')
  if (!existsSync(join(store, 'HEAD'))) return null
  const g = (args) => git(['--git-dir', store, ...args], work)
  const refs = g(['for-each-ref', '--format=%(refname) %(objectname)', 'refs/snapshots/']).split('\n').filter(Boolean).map((line) => {
    const [ref, commit] = line.split(' ')
    const object = g(['cat-file', 'commit', commit]).replace(/^(author|committer) .* <[^>]*>/gm, '$1 @ID@')
    const tree = g(['ls-tree', '-r', '-z', commit]).split('\0').filter(Boolean)
    // Trees once, in a table of their own: most steps leave most refs as they were.
    const key = sha(tree.join('\n'))
    trees[key] ??= tree.length > BIG ? { count: tree.length } : tree
    return { ref, object, tree: key }
  })
  const index = existsSync(join(store, 'index')) ? g(['ls-files', '-s', '-z']).split('\0').filter(Boolean) : null
  const exclude = existsSync(join(store, 'info', 'exclude')) ? readFileSync(join(store, 'info', 'exclude'), 'utf-8') : null
  return { refs, index: index && index.length > BIG ? { count: index.length, digest: sha(index.join('\n')) } : index, exclude }
}

const steps = []
const trees = {}
const json = (value) => JSON.parse(JSON.stringify(value ?? null, (k, v) => (typeof v === 'string' ? v.replaceAll(work, '@W@') : v)))
async function step(name, { setup = [], root = 'p', op, args = [], qhDiffers }) {
  for (const action of setup) act(action)
  globalThis.__calls = []
  const project = join(work, root)
  const call = ({
    list: () => service.listSnapshots(project),
    settings: () => service.getSettings(project),
    saveSettings: () => service.saveSettings(project, ...args),
    create: () => service.createSnapshot(project, ...args),
    diff: () => service.diffSnapshot(project, ...args),
    fileDiff: () => service.fileDiff(project, ...args),
    restore: () => service.restoreSnapshot(project, ...args),
    delete: () => service.deleteSnapshot(project, ...args),
    migrate: () => service.migrateConfigBackups(project),
    prune: () => service.pruneAutomatic(project),
    export: async () => {
      const target = join(work, 'exports', `${args[0]}.zip`)
      mkdirSync(dirname(target), { recursive: true })
      await service.exportSnapshot(project, args[0], target)
      // Unpacked with QuartzControl's readZip: names and contents, not the bytes (dates are git's).
      // Folders are not entries there; zipinfo mangled a name with an umlaut.
      const files = readZip(readFileSync(target))
      rmSync(target)
      return Object.fromEntries([...files.keys()].sort().map((name) => [name, sha(files.get(name))]))
    }
  })[op]
  let result, error
  try {
    result = json(await call())
  } catch (e) {
    error = e.message.replaceAll(work, '@W@')
  }
  // The folder of the step, and the vault next to the project that links into it.
  const state = {}
  for (const r of root === 'p' ? ['p', 'v'] : [root]) state[r] = { store: storeState(r), files: digestIfBig(listing(join(work, r))) }
  steps.push({ name, root, op, args, setup, ...(error !== undefined ? { error } : { result }), calls: globalThis.__calls, state, ...(qhDiffers ? { qhDiffers } : {}) })
}

// ---------------------------------------------------------------------------------------------
const W = (path, text) => ({ do: 'write', path, text })
const T0 = '2026-11-06T10:00:00.000Z'
const at = (iso) => ({ do: 'clock', at: iso })
const id = (iso, n) => `${iso.replace(/[:.]/g, '-')}-${String(n).padStart(4, '0')}`

const initial = [
  W('p/quartz.config.yaml', 'configuration:\n  pageTitle: Erste\n'),
  W('p/package.json', '{ "name": "p", "dependencies": { "a": "^1.0.0" } }\n'),
  W('p/package-lock.json', '{}\n'),
  W('p/quartz.lock.json', '{}\n'),
  // `.quartz-gui/` is in every project's .gitignore already: the line QuartzControl appends carries a
  // translated comment, which the mainT stand-in would write as its key (QuartzGuiWriter has its own test).
  W('p/.gitignore', 'node_modules\n.quartz-gui/\n'),
  W('p/content/index.md', '# Start\n'),
  W('p/content/Über uns.md', 'Wir\n'),
  W('p/content/sub/a.md', 'A\n'),
  W('p/content/.obsidian/app.json', '{}\n'),
  W('p/content/.DS_Store', 'x'),
  W('p/.DS_Store', 'x'),
  W('p/quartz/components/x.tsx', 'export default 1\n'),
  W('p/node_modules/a/index.js', 'module.exports = 1\n'),
  W('p/public/index.html', '<p>\n'),
  W('p/.quartz/cache.txt', 'c\n'),
  W('p/.quartz-cache/c.txt', 'c\n'),
  W('p/tsconfig.tsbuildinfo', '{}\n'),
  W('p/.quartz-gui/project-prefs.json', '{"a":1}\n'),
  W('p/.quartz-gui/logs/server.log', 'log\n'),
  W('p/.quartz-gui/deploy-manifest-x.json', '{}\n'),
  W('p/.quartz-gui/staging/s.txt', 's\n'),
  W('p/.quartz-gui/authored-frames/f1/index.ts', 'export {}\n'),
  W('p/.quartz-gui/content-backups/2026-01-01T00-00-00-000Z/content/old.md', 'old\n'),
  { do: 'git', path: 'p', args: ['init', '-q', '-b', 'main'] },
  { do: 'git', path: 'p', args: ['add', '-A'] },
  { do: 'git', path: 'p', args: ['commit', '-q', '-m', 'Initial'] },
  at(T0)
]

try {
  const first = id(T0, 1)
  await step('a project without a store lists nothing and creates nothing', { setup: initial, op: 'list' })
  await step('the default settings: a real content folder is included', { op: 'settings' })
  await step('a manual snapshot, the label on one line', { op: 'create', args: ['manual', '  Vor dem\n  Umbau\t '] })
  await step('nothing changed: an automatic one is skipped', { op: 'create', args: ['configChange', ''] })
  const T1 = '2026-11-06T10:01:00.000Z'
  await step('a config change', { setup: [at(T1), W('p/quartz.config.yaml', 'configuration:\n  pageTitle: Zweite\n')], op: 'create', args: ['configChange', ''] })
  await step('a second one within 15 minutes is coalesced', { setup: [at('2026-11-06T10:06:00.000Z'), W('p/quartz.config.yaml', 'configuration:\n  pageTitle: Dritte\n')], op: 'create', args: ['configChange', ''] })
  const T2 = '2026-11-06T10:17:00.000Z'
  await step('16 minutes later it is not', { setup: [at(T2), W('p/quartz.config.yaml', 'configuration:\n  pageTitle: Vierte\n')], op: 'create', args: ['configChange', ''] })
  await step('a plugin change with nothing changed is skipped', { op: 'create', args: ['pluginChange', 'github:x/y'] })
  const T3 = '2026-11-06T10:18:00.000Z'
  await step('a manual one with nothing changed is kept', { setup: [at(T3)], op: 'create', args: ['manual', 'zweimal'] })
  await step('the comparison: added, removed, changed, a name with an umlaut, .quartz-gui, excluded folders', {
    setup: [at('2026-11-06T10:20:00.000Z'), W('p/content/neu.md', 'neu\n'), { do: 'remove', path: 'p/content/sub/a.md' }, W('p/content/Über uns.md', 'Wir alle\n'),
      W('p/content/B.md', 'B\n'), W('p/content/a.md', 'a\n'), W('p/.quartz-gui/project-prefs.json', '{"a":2}\n'), W('p/node_modules/b/index.js', '2\n'), W('p/public/neu.html', 'n\n'), W('p/package.json', '{ "name": "p", "dependencies": { "a": "^2.0.0" } }\n')],
    op: 'diff', args: [first]
  })
  await step('one file\'s diff', { op: 'fileDiff', args: [first, 'quartz.config.yaml'] })
  await step('one file\'s diff, a name with an umlaut', { op: 'fileDiff', args: [first, 'content/Über uns.md'] })
  await step('content off', { op: 'saveSettings', args: [false] })
  await step('with content off the snapshot leaves it out, though the index had it', { setup: [at('2026-11-06T10:21:00.000Z')], op: 'create', args: ['contentChange', ''] })
  await step('and the comparison then reports it removed', { op: 'diff', args: [first], qhDiffers: 'contentLeftOut' })
  await step('content on again', { op: 'saveSettings', args: [true] })
  await step('a file the store tracks', { setup: [at('2026-11-06T10:22:00.000Z'), W('p/notes.tmp', 'eins\n')], op: 'create', args: ['manual', 'tmp'] })
  await step('stays tracked when the project ignores it later (the index decides)', {
    setup: [at('2026-11-06T10:23:00.000Z'), W('p/.gitignore', 'node_modules\n.quartz-gui/\n*.tmp\n'), W('p/notes.tmp', 'zwei\n'), W('p/other.tmp', 'neu\n')],
    op: 'create', args: ['manual', 'tmp2']
  })
  await step('a label longer than 120 characters', { setup: [at('2026-11-06T10:24:00.000Z')], op: 'create', args: ['manual', 'x'.repeat(100) + ' ' + 'y'.repeat(99)] })
  await step('restoring everything: a snapshot first, files back, npm and the frame repair', { setup: [at('2026-11-06T10:25:00.000Z')], op: 'restore', args: [first] })
  await step('restoring two files, one the snapshot never had', {
    setup: [at('2026-11-06T10:26:00.000Z'), W('p/content/neu.md', 'wieder\n'), W('p/quartz.config.yaml', 'configuration:\n  pageTitle: Fünfte\n')],
    op: 'restore', args: [id(T1, 2), { paths: ['quartz.config.yaml', 'content/neu.md'] }]
  })
  await step('restoring with the project\'s HEAD moved back', {
    setup: [at('2026-11-06T10:27:00.000Z'), W('p/README.md', 'neu\n'), { do: 'git', path: 'p', args: ['add', 'README.md'] }, { do: 'git', path: 'p', args: ['commit', '-q', '-m', 'Readme'], when: '2026-11-02T00:00:00Z' }],
    op: 'restore', args: [first, { resetProjectHead: true }]
  })
  await step('a file git cannot read: the staging fails out loud', {
    setup: [at('2026-11-06T10:28:00.000Z'), W('p/geheim.md', 'g\n'), { do: 'chmod', path: 'p/geheim.md', mode: '000' }],
    op: 'create', args: ['manual', 'kaputt']
  })
  await step('an unknown id: the comparison', { setup: [{ do: 'chmod', path: 'p/geheim.md', mode: '644' }, { do: 'remove', path: 'p/geheim.md' }], op: 'diff', args: ['2020-01-01T00-00-00-000Z-ffff'] })
  await step('an unknown id: the restore', { op: 'restore', args: ['2020-01-01T00-00-00-000Z-ffff'] })
  await step('an unknown id: deleting is quiet', { op: 'delete', args: ['2020-01-01T00-00-00-000Z-ffff'] })
  await step('an unknown id: the export', { op: 'export', args: ['2020-01-01T00-00-00-000Z-ffff'] })
  await step('the export of a snapshot', { op: 'export', args: [first] })
  await step('deleting one', { op: 'delete', args: [id(T3, 4)] })
  await step('a hand-made ref with an empty subject reads as manual', { setup: [{ do: 'handRef', path: 'p', from: first, id: '2026-11-06T09-00-00-000Z-beef' }], op: 'list' })

  // content/ as a link into a vault
  await step('a linked content folder is never included, whatever the file says', {
    setup: [{ do: 'remove', path: 'p/content' }, W('v/notes/a.md', 'Vault\n'), W('v/notes/b.md', 'B\n'), { do: 'symlink', path: 'p/content', target: '@W@/v/notes' }],
    op: 'settings'
  })
  await step('a snapshot with a linked content folder', { setup: [at('2026-11-06T10:30:00.000Z')], op: 'create', args: ['manual', 'vault'] })
  await step('restoring everything leaves the vault alone and says so', { setup: [at('2026-11-06T10:31:00.000Z')], op: 'restore', args: [first], qhDiffers: 'storeIndex' })
  await step('restoring one note through the link writes nothing into the vault', { setup: [at('2026-11-06T10:32:00.000Z')], op: 'restore', args: [first, { paths: ['content/index.md'] }], qhDiffers: 'storeIndex' })
  await step('turning content on is refused for a link', { op: 'saveSettings', args: [true], qhDiffers: 'storeIndex' })

  // the old config backups
  await step('the old config backups become snapshots with their own dates', {
    setup: [at('2026-11-06T10:40:00.000Z'),
      W('p/.quartz-gui/backups/2026-08-22T10-00-00-000Z.yaml', 'configuration:\n  pageTitle: Alt eins\n'),
      W('p/.quartz-gui/backups/2026-08-23T11-30-00-500Z.yaml', 'configuration:\n  pageTitle: Alt zwei\n'),
      W('p/.quartz-gui/backups/2026-11-06T09-50-00-000Z.yaml', 'configuration:\n  pageTitle: Alt drei\n'),
      W('p/.quartz-gui/backups/.DS_Store', 'x'), W('p/.quartz-gui/backups/notizen.txt', 'n'),
      W('p/.quartz-gui/backups/2026-08-24T09-00-00-000Z.yml', 'falsche Endung\n')],
    op: 'migrate', qhDiffers: 'storeIndex'
  })
  await step('and a second migration finds nothing', { op: 'migrate', qhDiffers: 'storeIndex' })
  await step('the thinning took the older of the two from August', { op: 'list', qhDiffers: 'storeIndex' })
  await step('the comparison of an imported one is that file only', { op: 'diff', args: ['2026-11-06T09-50-00-000Z-0000'] })
  await step('restoring an imported one restores that file only', { setup: [at('2026-11-06T10:41:00.000Z')], op: 'restore', args: ['2026-11-06T09-50-00-000Z-0000'] })

  // thinning, in a project of its own
  const thin = [W('t/quartz.config.yaml', 'v: 0\n'), W('t/.gitignore', '.quartz-gui/\n'), { do: 'git', path: 't', args: ['init', '-q', '-b', 'main'] }, { do: 'git', path: 't', args: ['add', '-A'] }, { do: 'git', path: 't', args: ['commit', '-q', '-m', 'Initial'] }]
  const ages = [
    ['2026-08-20T10:00:00.000Z', 'configChange'], ['2026-08-25T10:00:00.000Z', 'pluginChange'], ['2026-08-26T10:00:00.000Z', 'manual'],
    ['2026-09-20T10:00:00.000Z', 'coreUpdate'], ['2026-10-10T10:00:00.000Z', 'configChange'], ['2026-10-11T10:00:00.000Z', 'restore'],
    ['2026-10-16T08:00:00.000Z', 'styleMigration'], ['2026-10-16T09:00:00.000Z', 'contentChange'],
    // six days and a bit, two calendar days of one week: by day both stay
    ['2026-10-30T14:00:00.000Z', 'configChange'], ['2026-10-31T06:00:00.000Z', 'pluginChange'],
    ['2026-11-02T08:00:00.000Z', 'configChange'], ['2026-11-02T20:00:00.000Z', 'pluginChange'], ['2026-11-03T23:59:59.000Z', 'styleChange'],
    ['2026-11-04T00:00:01.000Z', 'configChange'], ['2026-11-05T09:00:00.000Z', 'configChange'], ['2026-11-05T11:00:00.000Z', 'pluginChange'],
    ['2026-11-06T08:00:00.000Z', 'configChange'], ['2026-11-06T09:00:00.000Z', 'pluginChange']
  ]
  for (const [i, [when, kind]] of ages.entries()) {
    await step(`thinning: ${kind} at ${when}`, { root: 't', setup: [...(i === 0 ? thin : []), at(when), W('t/quartz.config.yaml', `v: ${i + 1}\n`)], op: 'create', args: [kind, ''] })
  }
  await step('thinning: a new one thins the old ones by day, week and month', { root: 't', setup: [at('2026-11-06T10:00:00.000Z'), W('t/quartz.config.yaml', 'v: 99\n')], op: 'create', args: ['configChange', ''] })
  await step('thinning: a run on its own finds nothing more', { root: 't', op: 'prune' })
  await step('thinning: a week later', { root: 't', setup: [at('2026-11-13T10:00:00.000Z')], op: 'prune' })

  // folders that are not a repository, or one without a commit: QuartzControl writes git's error
  // into the subject (QuartzHub writes "-")
  await step('a folder that is no repository', { root: 'n', setup: [W('n/quartz.config.yaml', 'n: 1\n'), at('2026-11-06T11:00:00.000Z')], op: 'create', args: ['manual', 'ohne git'], qhDiffers: 'projectHead' })
  await step('a repository without a commit', { root: 'e', setup: [W('e/quartz.config.yaml', 'e: 1\n'), W('e/.gitignore', '.quartz-gui/\n'), { do: 'git', path: 'e', args: ['init', '-q', '-b', 'main'] }], op: 'create', args: ['manual', 'leer'], qhDiffers: 'projectHead' })

  // the settings file
  await step('settings that are no JSON', { setup: [{ do: 'remove', path: 'p/content' }, W('p/content/x.md', 'x\n'), W('p/.quartz-gui/snapshot-settings.json', '{ kaputt')], op: 'settings' })
  await step('settings that say null', { setup: [W('p/.quartz-gui/snapshot-settings.json', 'null')], op: 'settings', qhDiffers: 'settings' })
  await step('settings with a string', { setup: [W('p/.quartz-gui/snapshot-settings.json', '{"includeContent":"ja"}')], op: 'settings', qhDiffers: 'settings' })
  await step('settings with false', { setup: [W('p/.quartz-gui/snapshot-settings.json', '{"includeContent":false}')], op: 'settings' })
  await step('no content folder at all', { setup: [{ do: 'remove', path: 'p/content' }, { do: 'remove', path: 'p/.quartz-gui/snapshot-settings.json' }], op: 'settings' })

  // a restore of more paths than one argv takes
  const bigInit = [W('b/quartz.config.yaml', 'b: 1\n'), W('b/.gitignore', '.quartz-gui/\n'), { do: 'many', path: 'b/content', count: 1100, text: 'eins' }, { do: 'git', path: 'b', args: ['init', '-q', '-b', 'main'] }, { do: 'git', path: 'b', args: ['add', '-A'] }, { do: 'git', path: 'b', args: ['commit', '-q', '-m', 'Initial'] }, at('2026-11-06T12:00:00.000Z')]
  await step('a big project', { root: 'b', setup: bigInit, op: 'create', args: ['manual', 'groß'] })
  const paths = [...Array(1100).keys()].map((i) => `content/n${String(i).padStart(4, '0')}.md`).concat([...Array(1050).keys()].map((i) => `content/extra/x${i}.md`))
  await step('restoring 2150 named paths, 1050 of them to delete', {
    root: 'b', setup: [at('2026-11-06T12:01:00.000Z'), { do: 'many', path: 'b/content', count: 1100, text: 'zwei' }, { do: 'many', path: 'b/content/extra', count: 0, text: '' },
      ...[...Array(1050).keys()].map((i) => W(`b/content/extra/x${i}.md`, `${i}\n`))],
    op: 'restore', args: [steps.at(-1).result.id, { paths }]
  })
} finally {
  // the fixture before the work folder goes
  rmSync(out, { recursive: true, force: true })
  mkdirSync(out, { recursive: true })
  writeFileSync(join(out, 'steps.json'), JSON.stringify({ steps, trees }) + '\n')
  chmodSync(work, 0o755)
  spawnSync('chmod', ['-R', 'u+rwX', work])
  rmSync(work, { recursive: true, force: true })
}

// QuartzControl's service as a command, for the Swift tests: `node qc-snapshots.cjs <op> <project>
// [json args]` prints {result} or {error}. npm and the frame repair do nothing there.
await build({
  stdin: {
    contents: `import * as s from './electron/main/services/snapshotService.ts'
const [op, project, raw] = process.argv.slice(2)
const args = raw ? JSON.parse(raw) : []
const ops = { list: s.listSnapshots, settings: s.getSettings, saveSettings: s.saveSettings, create: s.createSnapshot, diff: s.diffSnapshot, fileDiff: s.fileDiff, restore: s.restoreSnapshot, delete: s.deleteSnapshot, export: s.exportSnapshot, migrate: s.migrateConfigBackups, prune: s.pruneAutomatic }
ops[op](project, ...args).then((result) => process.stdout.write(JSON.stringify({ result: result ?? null })), (e) => process.stdout.write(JSON.stringify({ error: e.message })))`,
    resolveDir: control, loader: 'ts', sourcefile: 'qc-snapshots-entry.ts'
  },
  bundle: true, platform: 'node', format: 'cjs', outfile: join(out, 'qc-snapshots.cjs'), logLevel: 'warning', absWorkingDir: control,
  alias: { '@shared': join(control, 'shared') },
  banner: { js: '// QuartzControl\'s snapshotService.ts as a command, bundled by scripts/snapshots-golden.mjs. Do not edit.' },
  plugins: [{
    name: 'stand-ins',
    setup(b) {
      const cli = {
        '../i18n': commonStubs['../i18n'],
        './projectPaths': 'export async function repointAuthoredFrames() {}',
        './runCommand': `import { runCommand as real } from './electron/main/services/runCommand.ts'
export async function runCommand(command, args, cwd, env, timeoutMs) { return command === 'npm' ? { success: true, output: '', stdout: '' } : real(command, args, cwd, env, timeoutMs) }`
      }
      for (const specifier of Object.keys(cli)) b.onResolve({ filter: new RegExp(`^${specifier.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&')}$`) }, () => ({ path: specifier, namespace: 'stub' }))
      b.onLoad({ filter: /.*/, namespace: 'stub' }, (a) => ({ contents: cli[a.path], loader: 'js', resolveDir: control }))
    }
  }]
})
console.log(`${steps.length} steps → ${out}`)
