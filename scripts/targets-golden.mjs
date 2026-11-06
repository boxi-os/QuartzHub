#!/usr/bin/env node
// Golden file for PublishTargets and DeployManifests, made by QuartzControl's own
// publishTargetsService.ts and deploy/manifest.ts with their real projectDirs and jsonStore. Only
// the legacy claim (QuartzHub takes none over), the ids and the clock are stand-ins. Each step is
// its setup (files written or removed in the project, relative paths), one call and its answer,
// and every file under .quartz-gui/ plus .gitignore afterwards (temp files and quarantine names
// masked). A manifest's keys are in the order QuartzControl's hashes finished; the test compares
// those files as sets of entries, everything else by bytes.
//
// Also the input rules: QuartzControl's `savePublishTargetInput` zod schema over a list of inputs.
//
//   Runtime/node/bin/node scripts/targets-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'targets')
const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-targets-golden-')))
const project = join(work, 'Gärten-Ü')
globalThis.__ids = 0

const stubs = {
  ...commonStubs,
  './connectionsService': 'export async function claimLegacyTargets() { return [] }',
  crypto: `import * as real from 'node:crypto'
export const createHash = real.createHash
export function randomBytes(n) { return real.randomBytes(n) }
export function randomUUID() {
  if ((new Error().stack ?? '').includes('writeJsonFile')) return real.randomUUID()
  globalThis.__ids += 1
  return '00000000-0000-4000-8000-' + String(globalThis.__ids).padStart(12, '0')
}`
}
const targets = await loadQuartzControl(control, 'electron/main/services/publishTargetsService.ts', stubs)
const manifest = await loadQuartzControl(control, 'electron/main/services/deploy/manifest.ts', stubs)
const schemas = await loadQuartzControl(control, 'electron/main/ipc/schemas.ts', {})

const RealDate = Date
let now = RealDate.parse('2026-11-06T10:00:00.000Z')
globalThis.Date = class extends RealDate {
  constructor(...args) { if (args.length === 0) super(now); else super(...args) }
  static now() { return now }
}

function files() {
  const found = {}
  const walk = (dir, rel) => {
    if (!existsSync(dir)) return
    for (const name of readdirSync(dir).sort()) {
      const full = join(dir, name), r = rel ? `${rel}/${name}` : name
      try { if (readdirSync(full)) { walk(full, r); continue } } catch {}
      found[r.replace(/corrupt-[^/]*$/, 'corrupt-*')] = readFileSync(full, 'utf-8')
    }
  }
  walk(join(project, '.quartz-gui'), '.quartz-gui')
  if (existsSync(join(project, '.gitignore'))) found['.gitignore'] = readFileSync(join(project, '.gitignore'), 'utf-8')
  return found
}

const steps = []
async function step(name, op, args, fn, setup = []) {
  for (const action of setup) {
    if (action.write) { mkdirSync(dirname(join(project, action.write[0])), { recursive: true }); writeFileSync(join(project, action.write[0]), action.write[1]) }
    if (action.rm) rmSync(join(project, action.rm), { recursive: true, force: true })
    if (action.clock) now = RealDate.parse(action.clock)
  }
  let result
  try {
    result = { ok: (await fn()) ?? null }
  } catch (err) {
    result = { error: String(err.message ?? err).split(project).join('@P@') }
  }
  steps.push({ name, op, args, setup, result, files: files() })
}
const id = (n) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0')
const C1 = '11111111-1111-4111-8111-111111111111', C2 = '22222222-2222-4222-8222-222222222222'

// ── targets ─────────────────────────────────────────────────────────────────────────────────
mkdirSync(join(project, '.git'), { recursive: true })
await step('list without a file', 'targets:list', [], () => targets.listTargets(project))
const sftp = { name: 'Webspace', connectionId: C1, destination: { type: 'sftp', remotePath: 'httpdocs', transfer: 'sftp', deleteRemoved: true }, excludes: [] }
await step('save sftp', 'targets:save', [sftp], () => targets.saveTarget(project, sftp))
const folder = { name: 'Ordner Ü', destination: { type: 'folder', path: '/Volumes/Share/site', deleteRemoved: false }, excludes: ['a.html'] }
await step('save folder', 'targets:save', [folder], () => targets.saveTarget(project, folder))
const branch = { name: 'Pages', destination: { type: 'git-branch', branch: 'gh-pages', provider: 'github' } }
await step('save branch without excludes', 'targets:save', [branch], () => targets.saveTarget(project, branch))
const doc = { name: 'Buch', destination: { type: 'document', path: '/Users/x/Bücher', bookId: 'buch', formats: ['pdf', 'epub'] }, withDocuments: [id(9)] }
await step('save document (no documents of its own)', 'targets:save', [doc], () => targets.saveTarget(project, doc))
const hook = { name: 'Hook', connectionId: C2, destination: { type: 'webhook' }, withDocuments: [id(4)] }
await step('save webhook (no documents)', 'targets:save', [hook], () => targets.saveTarget(project, hook))
const withDocs = { name: 'Mit Buch', destination: { type: 'folder', path: '/srv/www', deleteRemoved: true }, withDocuments: [id(4)] }
await step('save folder with documents', 'targets:save', [withDocs], () => targets.saveTarget(project, withDocs))
await step('save folder with an empty documents list', 'targets:save', [{ ...withDocs, id: id(6), withDocuments: [] }],
  () => targets.saveTarget(project, { ...withDocs, id: id(6), withDocuments: [] }))
const seedManifest = (n) => ({ write: [`.quartz-gui/deploy-manifest-${id(n)}.json`, '{\n  "index.html": "abc"\n}'] })
await step('rename keeps the manifest', 'targets:save', [{ ...sftp, id: id(1), name: 'Neu' }], () => targets.saveTarget(project, { ...sftp, id: id(1), name: 'Neu' }), [seedManifest(1)])
await step('rsync keeps the manifest', 'targets:save', [{ ...sftp, id: id(1), destination: { ...sftp.destination, transfer: 'rsync' } }],
  () => targets.saveTarget(project, { ...sftp, id: id(1), destination: { ...sftp.destination, transfer: 'rsync' } }))
await step('deletion off keeps the manifest', 'targets:save', [{ ...sftp, id: id(1), destination: { ...sftp.destination, deleteRemoved: false } }],
  () => targets.saveTarget(project, { ...sftp, id: id(1), destination: { ...sftp.destination, deleteRemoved: false } }))
await step('another path forgets it', 'targets:save', [{ ...sftp, id: id(1), destination: { ...sftp.destination, remotePath: 'httpdocs/blog' } }],
  () => targets.saveTarget(project, { ...sftp, id: id(1), destination: { ...sftp.destination, remotePath: 'httpdocs/blog' } }))
// The same path as the step before: only the connection changes.
const blog = { ...sftp, id: id(1), destination: { ...sftp.destination, remotePath: 'httpdocs/blog' } }
await step('another connection forgets it', 'targets:save', [{ ...blog, connectionId: C2 }],
  () => targets.saveTarget(project, { ...blog, connectionId: C2 }), [seedManifest(1)])
await step('another provider forgets it', 'targets:save', [{ ...branch, id: id(3), destination: { ...branch.destination, provider: 'codeberg' } }],
  () => targets.saveTarget(project, { ...branch, id: id(3), destination: { ...branch.destination, provider: 'codeberg' } }), [seedManifest(3)])
await step('folder moved forgets it', 'targets:save', [{ ...folder, id: id(2), destination: { ...folder.destination, path: '/Volumes/Share/site2' } }],
  () => targets.saveTarget(project, { ...folder, id: id(2), destination: { ...folder.destination, path: '/Volumes/Share/site2' } }), [seedManifest(2)])
await step('an edit without excludes keeps them', 'targets:save', [{ id: id(2), name: 'Ordner Ü', destination: folder.destination }],
  () => targets.saveTarget(project, { id: id(2), name: 'Ordner Ü', destination: folder.destination }))
await step('an unknown id is a new target', 'targets:save', [{ ...folder, id: id(77) }], () => targets.saveTarget(project, { ...folder, id: id(77) }))
await step('get', 'targets:get', [id(2)], () => targets.getTarget(project, id(2)))
await step('get none', 'targets:get', [id(99)], () => targets.getTarget(project, id(99)))
await step('using a connection', 'targets:using', [C2], () => targets.targetsUsingConnection(project, C2))
await step('delete', 'targets:delete', [id(5)], () => targets.deleteTarget(project, id(5)))
const later = JSON.stringify([{ id: id(1), name: 'Alt', destination: { type: 'folder', path: '/a', deleteRemoved: false }, later: { x: 1 }, connectionId: null }], null, 2)
await step('an entry a later version wrote', 'targets:save', [{ id: id(1), name: 'Alt 2', destination: { type: 'folder', path: '/a', deleteRemoved: false } }],
  () => targets.saveTarget(project, { id: id(1), name: 'Alt 2', destination: { type: 'folder', path: '/a', deleteRemoved: false } }),
  [{ write: ['.quartz-gui/publish-targets.json', later] }, { rm: `.quartz-gui/deploy-manifest-${id(1)}.json` }])
await step('a file of the wrong shape', 'targets:list', [], () => targets.listTargets(project), [{ write: ['.quartz-gui/publish-targets.json', '{"a":1}'] }])

// ── manifests ───────────────────────────────────────────────────────────────────────────────
rmSync(join(project, '.quartz-gui'), { recursive: true, force: true })
const T = 'tgt', U = 'other'
await step('read without a file', 'manifest:read', [T], () => manifest.readManifest(project, T))
await step('the legacy manifest goes to the first who asks', 'manifest:read', [T], () => manifest.readManifest(project, T),
  [{ write: ['.quartz-gui/deploy-manifest.json', '{"index.html":"old"}'] }])
await step('and not to the second', 'manifest:read', [U], () => manifest.readManifest(project, U))
await step('a broken manifest takes the legacy one', 'manifest:read', [U], () => manifest.readManifest(project, U),
  [{ write: [`.quartz-gui/deploy-manifest-${U}.json`, '{"x":'] }, { write: ['.quartz-gui/deploy-manifest.json', '{"a.html":"1"}'] }])
const build = [
  { write: ['public/index.html', '<h1>Start</h1>'] }, { write: ['public/Gärten/Über uns.html', 'über'] }, { write: ['public/b.css', 'b{}'] },
  { write: ['public/sub/deep/x.txt', 'x'] }, { write: ['public/Zebra.html', 'z'] }, { write: ['public/ärger.html', 'ä'] }, { write: ['public/a.html', 'a'] }
]
await step('diff against nothing', 'manifest:diff', [T, 'public'], () => manifest.diffAgainstManifest(project, T, join(project, 'public')),
  [{ rm: `.quartz-gui/deploy-manifest-${T}.json` }, ...build])
await step('commit all', 'manifest:commit', [T, 'public', []], () => manifest.commitManifest(project, T, join(project, 'public'), []))
await step('diff after a change', 'manifest:diff', [T, 'public'], () => manifest.diffAgainstManifest(project, T, join(project, 'public')),
  [{ write: ['public/b.css', 'b{color:red}'] }, { rm: 'public/sub' }, { write: ['public/neu.html', 'n'] }])
await step('commit with exclusions', 'manifest:commit', [T, 'public', ['b.css', 'neu.html', 'sub/deep/x.txt']],
  () => manifest.commitManifest(project, T, join(project, 'public'), ['b.css', 'neu.html', 'sub/deep/x.txt']))
await step('diff keeps the excluded', 'manifest:diff', [T, 'public'], () => manifest.diffAgainstManifest(project, T, join(project, 'public')))
await step('commit removes a removal not excluded', 'manifest:commit', [T, 'public', []], () => manifest.commitManifest(project, T, join(project, 'public'), []),
  [{ rm: 'public/a.html' }])
await step('diff of an empty build', 'manifest:diff', [U, 'empty'], () => manifest.diffAgainstManifest(project, U, join(project, 'empty')),
  [{ write: ['empty/.keep', ''] }, { rm: 'empty/.keep' }])
await step('diff of a missing build', 'manifest:diff', [U, 'missing'], () => manifest.diffAgainstManifest(project, U, join(project, 'missing')))
await step('modes not settled', 'manifest:modesSettled', [T], () => manifest.modesSettled(project, T))
await step('settle modes', 'manifest:settleModes', [T], () => manifest.settleModes(project, T), [{ clock: '2026-11-06T11:00:00.000Z' }])
await step('modes settled', 'manifest:modesSettled', [T], () => manifest.modesSettled(project, T))
await step('reanchor clears the hashes', 'manifest:reanchor', [T], () => manifest.reanchorTildeManifest(project, T), [{ clock: '2026-11-06T12:00:00.000Z' }])
await step('reanchor once only', 'manifest:reanchor', [T], () => manifest.reanchorTildeManifest(project, T), [{ write: [`.quartz-gui/deploy-manifest-${T}.json`, '{"q":"1"}'] }])
await step('reanchor without a manifest', 'manifest:reanchor', ['none'], () => manifest.reanchorTildeManifest(project, 'none'))
await step('forget', 'manifest:forget', [T], () => manifest.forgetManifest(project, T))
await step('forget none', 'manifest:forget', ['none'], () => manifest.forgetManifest(project, 'none'))

const diff = [{ path: 'a', status: 'added' }, { path: 'b', status: 'changed' }, { path: 'c', status: 'removed' }, { path: 'd', status: 'removed' }, { path: 'e', status: 'changed' }]
const partitions = []
for (const excludes of [[], ['a'], ['c'], ['a', 'd', 'x']]) {
  for (const deleteRemoved of [true, false]) partitions.push({ args: [diff, excludes, deleteRemoved], result: manifest.partitionDiff(diff, excludes, deleteRemoved) })
}

// ── the input rules ─────────────────────────────────────────────────────────────────────────
const d = (destination, extra = {}) => ({ name: 'T', destination, ...extra })
const inputs = [
  d({ type: 'sftp', remotePath: 'httpdocs', transfer: 'sftp', deleteRemoved: true }), d({ type: 'sftp', remotePath: '/', transfer: 'sftp', deleteRemoved: true }),
  d({ type: 'sftp', remotePath: '/', transfer: 'rsync', deleteRemoved: false }), d({ type: 'sftp', remotePath: '~', transfer: 'sftp', deleteRemoved: true }),
  d({ type: 'sftp', remotePath: 'a/../b', transfer: 'sftp', deleteRemoved: false }), d({ type: 'sftp', remotePath: ' ', transfer: 'sftp', deleteRemoved: false }),
  d({ type: 'sftp', remotePath: 'x', transfer: 'scp', deleteRemoved: false }), d({ type: 'sftp', remotePath: 'x', transfer: 'sftp' }),
  d({ type: 'sftp', remotePath: 'x', transfer: 'sftp', deleteRemoved: 'yes' }), d({ type: 'ftp', remotePath: 'www', deleteRemoved: true }),
  d({ type: 'ftp', remotePath: '.', deleteRemoved: true }), d({ type: 'ftp', remotePath: '.', deleteRemoved: false }), d({ type: 'ftp', remotePath: 'x'.repeat(4097), deleteRemoved: false }),
  d({ type: 'folder', path: '/srv/www', deleteRemoved: true }), d({ type: 'folder', path: 'srv/www', deleteRemoved: true }), d({ type: 'folder', path: '', deleteRemoved: true }),
  d({ type: 'webhook' }), d({ type: 'webhook', extra: 1 }), d({ type: 'git-branch', branch: 'gh-pages', provider: 'github' }),
  d({ type: 'git-branch', branch: 'pages', provider: 'codeberg' }), d({ type: 'git-branch', branch: 'gh-pages', provider: 'bitbucket' }),
  d({ type: 'git-branch', branch: '-x', provider: 'github' }), d({ type: 'git-branch', branch: 'a..b', provider: 'github' }),
  d({ type: 'git-branch', branch: 'x.lock', provider: 'github' }), d({ type: 'git-branch', branch: 'feature/x_y-1.2', provider: 'gitlab' }),
  d({ type: 'git-branch', branch: 'ä', provider: 'github' }), d({ type: 'document', path: '/b', bookId: 'buch-1', formats: ['pdf'] }),
  d({ type: 'document', path: '/b', bookId: 'Buch', formats: ['pdf'] }), d({ type: 'document', path: '/b', bookId: 'buch', formats: [] }),
  d({ type: 'document', path: '/b', bookId: 'buch', formats: ['pdf', 'epub', 'html', 'pdf'] }), d({ type: 'document', path: '/b', bookId: 'buch', formats: ['docx'] }),
  d({ type: 'ssh' }), d({}), d({ type: 'webhook' }, { name: '' }), d({ type: 'webhook' }, { name: 'x'.repeat(201) }),
  d({ type: 'webhook' }, { connectionId: C1 }), d({ type: 'webhook' }, { connectionId: 'not-a-uuid' }), d({ type: 'webhook' }, { connectionId: '11111111-1111-9111-8111-111111111111' }),
  d({ type: 'webhook' }, { excludes: ['a', 'x'.repeat(4097)] }), d({ type: 'webhook' }, { withDocuments: [C1, C2] }),
  d({ type: 'webhook' }, { withDocuments: Array(21).fill(C1) }), d({ type: 'webhook' }, { withDocuments: ['x'] }),
  d({ type: 'webhook' }, { connectionId: '00000000-0000-0000-0000-000000000000' }), d({ type: 'webhook' }, { connectionId: 'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF' })
]
const rules = inputs.map((input) => ({ input, valid: schemas.savePublishTargetInput.safeParse(input).success }))

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'steps.json'), JSON.stringify({ steps, partitions, rules }, null, 1) + '\n')
rmSync(work, { recursive: true, force: true })
console.log(`${steps.length} steps, ${partitions.length} partitions, ${rules.length} rules`)
