#!/usr/bin/env node
// Golden file for ContentBackups and ContentFolder.changeSource, made by QuartzControl's own
// backupService.ts and contentService.ts (`changeContentSource`): switching the content folder to
// a copy or a link, what the switch moves aside under .quartz-gui/content-backups/, listing,
// restoring and deleting those, and the refusals. The snapshot the switch asks for is recorded
// (snapshotService has its own golden); the clock is pinned. After each step: the answer, the
// progress the copy reported (as a set: Node's cp walks a folder in the file system's order), the
// snapshots asked for, and every file of the work folder.
//
//   Runtime/node/bin/node scripts/content-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { createHash } from 'node:crypto'
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'content')

const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-content-golden-')))
globalThis.__snapshots = []
const stubs = {
  ...commonStubs,
  './snapshotService': `export async function createSnapshot(project, kind, label) { globalThis.__snapshots.push([project.replace(globalThis.__work, '@W@'), kind, label ?? null]); return null }`,
  './configService': 'export async function readConfig() { throw new Error("no config here") }',
  './projectDependencies': 'export function halfUnpackedModule() { return null }'
}
globalThis.__work = work
const content = await loadQuartzControl(control, 'electron/main/services/contentService.ts', stubs)
const backups = await loadQuartzControl(control, 'electron/main/services/backupService.ts', stubs)

const RealDate = Date
let now = RealDate.parse('2026-11-06T10:00:00.000Z')
globalThis.Date = class extends RealDate {
  constructor(...args) { if (args.length === 0) super(now); else super(...args) }
  static now() { return now }
}

const sha = (data) => createHash('sha256').update(data).digest('hex')
const mask = (value) => JSON.parse(JSON.stringify(value ?? null, (k, v) => (typeof v === 'string' ? v.replaceAll(work, '@W@') : v)))

function act(action) {
  const path = action.path && join(work, action.path)
  switch (action.do) {
    case 'write': mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, action.text); break
    case 'mkdir': mkdirSync(path, { recursive: true }); break
    case 'remove': rmSync(path, { recursive: true, force: true }); break
    case 'symlink': mkdirSync(dirname(path), { recursive: true }); symlinkSync(action.target.replace('@W@', work), path); break
    case 'clock': now = RealDate.parse(action.at); break
    default: throw new Error(`unknown action ${action.do}`)
  }
}

function listing() {
  const files = {}
  const walk = (dir, rel) => {
    for (const name of readdirSync(dir).sort()) {
      const full = join(dir, name)
      const path = rel ? `${rel}/${name}` : name
      const info = lstatSync(full)
      if (info.isSymbolicLink()) files[path] = `link:${readlinkSync(full).replace(work, '@W@')}`
      else if (info.isDirectory()) { files[`${path}/`] = `dir ${(info.mode & 0o777).toString(8)}`; walk(full, path) }
      else files[path] = `${(info.mode & 0o777).toString(8)} ${sha(readFileSync(full, 'utf-8').replaceAll(work, '@W@'))}` // symlink.json names the folder
    }
  }
  walk(work, '')
  return files
}

const steps = []
async function step(name, { setup = [], op, args = [] }) {
  for (const action of setup) act(action)
  globalThis.__snapshots = []
  const progress = []
  const p = join(work, 'p')
  const at = (x) => (typeof x === 'string' ? x.replace('@W@', work) : x)
  const call = {
    change: () => content.changeContentSource(p, at(args[0]), args[1], (processed, total, file) => progress.push([processed, total, file.replace(work, '@W@')])),
    list: () => backups.listContentBackups(p),
    restore: () => backups.restoreContentBackup(p, join(p, 'content'), args[0]),
    delete: () => backups.deleteContentBackup(p, args[0])
  }[op]
  let result, error
  try {
    result = mask(await call())
  } catch (e) {
    error = { code: e.code ?? null, message: e.message.replaceAll(work, '@W@') }
  }
  steps.push({
    name, op, args, setup, ...(error ? { error } : { result }),
    // The numbers run 1, 2, …; which file got which number is the file system's order.
    progress: { count: progress.length, totals: [...new Set(progress.map((e) => e[1]))], files: progress.map((e) => e[2]).sort(), numbers: progress.map((e) => e[0]) },
    snapshots: globalThis.__snapshots,
    files: listing()
  })
}

const W = (path, text) => ({ do: 'write', path, text })
const at = (iso) => ({ do: 'clock', at: iso })
try {
  await step('nothing moved aside yet: an empty list, and no folder made for it', {
    setup: [W('p/quartz.config.yaml', 'a: 1\n'), W('p/content/index.md', '# Alt\n'), W('p/content/Über.md', 'ü\n'), { do: 'symlink', path: 'p/content/zurück.md', target: 'index.md' }, W('p/content/.obsidian/app.json', '{}\n'),
      W('s/a.md', 'A\n'), W('s/Bilder/b.png', 'png'), W('s/.hidden.md', 'h\n'), { do: 'mkdir', path: 's/leer' }, { do: 'symlink', path: 's/relativ.md', target: 'a.md' }, { do: 'symlink', path: 's/Verknüpfung.md', target: 'a.md' },
      { do: 'symlink', path: 's/absolut.md', target: '@W@/s/a.md' }, { do: 'symlink', path: 's/ordner', target: 'Bilder' }, { do: 'symlink', path: 's/hängt', target: 'gibt-es-nicht' },
      W('v/note.md', 'Vault\n'), W('v/.obsidian/x.json', '{}\n')],
    op: 'list'
  })
  await step('a copy: a snapshot, the old folder aside, the new one copied with its links made absolute', { op: 'change', args: ['@W@/s', 'copy'] })
  await step('the folder aside, counted and measured', { op: 'list' })
  await step('a link to a vault: the copy goes aside', { setup: [at('2026-11-06T10:01:00.000Z')], op: 'change', args: ['@W@/v', 'symlink'] })
  await step('a copy again: the link is recorded, not followed', { setup: [at('2026-11-06T10:02:00.000Z')], op: 'change', args: ['@W@/s', 'copy'] })
  await step('three entries, newest first, the link with its target', {
    setup: [W('p/.quartz-gui/content-backups/.DS_Store', 'x'), { do: 'mkdir', path: 'p/.quartz-gui/content-backups/kein-datum' },
      W('p/.quartz-gui/content-backups/2026-01-01T00-00-00-000Z/symlink.json', '{ kaputt'), W('p/.quartz-gui/content-backups/2026-01-02T00-00-00-000Z/content/x.md', 'x\n'),
      W('p/.quartz-gui/content-backups/2026-01-03T00-00-00-000Z', 'eine Datei mit dem Namen einer Sicherung')],
    op: 'list'
  })
  await step('restoring the link: the current folder goes aside first', { setup: [at('2026-11-06T10:03:00.000Z')], op: 'restore', args: ['2026-11-06T10-02-00-000Z'] })
  await step('restoring a folder: copied, not moved', { setup: [at('2026-11-06T10:04:00.000Z')], op: 'restore', args: ['2026-11-06T10-01-00-000Z'] })
  await step('and the same folder a second time', { setup: [at('2026-11-06T10:05:00.000Z')], op: 'restore', args: ['2026-11-06T10-01-00-000Z'] })
  await step('restoring the first folder: its relative link comes back absolute', { setup: [at('2026-11-06T10:05:30.000Z')], op: 'restore', args: ['2026-11-06T10-00-00-000Z'] })
  await step('restoring an unreadable link record', { setup: [at('2026-11-06T10:06:00.000Z')], op: 'restore', args: ['2026-01-01T00-00-00-000Z'] })
  await step('restoring one that is not there', { setup: [at('2026-11-06T10:07:00.000Z')], op: 'restore', args: ['2025-01-01T00-00-00-000Z'] })
  await step('deleting one', { op: 'delete', args: ['2026-11-06T10-01-00-000Z'] })
  await step('deleting a name that is no id does nothing', { op: 'delete', args: ['kein-datum'] })
  await step('deleting one that is not there does nothing', { op: 'delete', args: ['2025-01-01T00-00-00-000Z'] })
  await step('the list after all that', { op: 'list' })
  await step('a source that is not there', { op: 'change', args: ['@W@/fehlt', 'copy'] })
  await step('a source inside the content folder', { op: 'change', args: ['@W@/p/content/sub', 'copy'], setup: [{ do: 'remove', path: 'p/content' }, W('p/content/sub/x.md', 'x\n')] })
  await step('a content folder inside the source', { op: 'change', args: ['@W@/p', 'copy'] })
  await step('a folder next to content/ whose name begins the same is not inside it', {
    setup: [at('2026-11-06T10:07:30.000Z'), W('p/contentalt/y.md', 'y\n')], op: 'change', args: ['@W@/p/contentalt', 'copy']
  })
  await step('a project without a content folder', { setup: [at('2026-11-06T10:08:00.000Z'), { do: 'remove', path: 'p/content' }], op: 'change', args: ['@W@/v', 'symlink'] })
  await step('a dangling link as content folder: nothing goes aside, and the new link fails', {
    setup: [at('2026-11-06T10:09:00.000Z'), { do: 'remove', path: 'p/content' }, { do: 'symlink', path: 'p/content', target: '@W@/weg' }],
    op: 'change', args: ['@W@/v', 'symlink']
  })
  await step('a source with a slash at the end is linked as it was given', {
    setup: [at('2026-11-06T10:10:00.000Z'), { do: 'remove', path: 'p/content' }], op: 'change', args: ['@W@/v/', 'symlink']
  })
} finally {
  rmSync(out, { recursive: true, force: true })
  mkdirSync(out, { recursive: true })
  // workLength: a link's size is the length of its target, and absolute targets name this folder.
  writeFileSync(join(out, 'steps.json'), JSON.stringify({ workLength: Buffer.byteLength(work), steps }, null, 1) + '\n')
  rmSync(work, { recursive: true, force: true })
}
console.log(`${steps.length} steps → ${out}`)
