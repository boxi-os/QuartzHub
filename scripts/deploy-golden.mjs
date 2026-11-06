#!/usr/bin/env node
// Golden file for Deploy, DeployStaging, FolderAdapter and RelayGuard, made by QuartzControl's own
// deploy/index.ts with its real folder adapter, staging, relayGuard, manifest, projectDirs and
// publishTargetsService. Stand-ins: the other adapters (none of them in this golden), the secrets
// (no folder target has one), mainT (key and arguments), the target ids. Each step is its setup
// (files, folders, modes, times; paths below the work folder "@W@"), one call, its answer, the
// progress events, and the whole work folder afterwards: every folder with its mode, every file
// with its mode and text, "@W@" for the work folder inside texts.
//
//   Runtime/node/bin/node scripts/deploy-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, utimesSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'deploy')
const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-deploy-golden-')))
const W = (p) => p.split('@W@').join(work)
const mask = (text) => text.split(work).join('@W@')
const project = join(work, 'Gärten-Ü')
globalThis.__ids = 0

const none = (name) => `export const ${name} = undefined`
const connections = 'export async function getSecret() { return null }\nexport async function claimLegacyTargets() { return [] }'
const stubs = {
  ...commonStubs,
  '../../i18n': commonStubs['../i18n'],
  '../connectionsService': connections,
  './connectionsService': connections,
  './sftp': none('sftpAdapter'), './ftp': none('ftpAdapter'), './rsync': none('rsyncAdapter'), './webhook': none('webhookAdapter'),
  './gitBranch': none('gitBranchAdapter'), './document': none('documentAdapter'),
  crypto: `import * as real from 'node:crypto'
export const createHash = real.createHash
export const randomBytes = real.randomBytes
export function randomUUID() {
  if ((new Error().stack ?? '').includes('writeJsonFile')) return real.randomUUID()
  globalThis.__ids += 1
  return '00000000-0000-4000-8000-' + String(globalThis.__ids).padStart(12, '0')
}`
}
const deploy = await loadQuartzControl(control, 'electron/main/services/deploy/index.ts', stubs)
const targets = await loadQuartzControl(control, 'electron/main/services/publishTargetsService.ts', stubs)
const events = []
deploy.deployEvents.on('progress', (e) => events.push({ ...e }))

function tree() {
  const found = {}
  const walk = (dir, rel) => {
    for (const name of readdirSync(dir).sort()) {
      const full = join(dir, name), r = rel ? `${rel}/${name}` : name
      if (r === 'Gärten-Ü/.git') continue
      const info = lstatSync(full)
      const mode = (info.mode & 0o7777).toString(8)
      if (info.isDirectory()) {
        found[`${r}/`] = mode
        if (info.mode & 0o400) walk(full, r)
      } else found[r] = `${mode} ${mask(readFileSync(full, 'utf-8'))}`
    }
  }
  walk(work, '')
  return found
}

const steps = []
async function step(name, op, args, setup = []) {
  for (const a of setup) {
    if (a.write) { mkdirSync(dirname(W(a.write[0])), { recursive: true }); writeFileSync(W(a.write[0]), a.write[1]) }
    if (a.mkdir) mkdirSync(W(a.mkdir), { recursive: true })
    if (a.rm) rmSync(W(a.rm), { recursive: true, force: true })
    if (a.chmod) chmodSync(W(a.chmod[0]), parseInt(a.chmod[1], 8))
    if (a.utimes) utimesSync(W(a.utimes[0]), a.utimes[1], a.utimes[1])
  }
  events.length = 0
  const p = (v) => (typeof v === 'string' ? W(v) : v)
  let result
  try {
    let value
    switch (op) {
      case 'save': value = await targets.saveTarget(project, JSON.parse(W(JSON.stringify(args[0])))); break
      case 'preview': value = await deploy.previewDeploy(project, args[0], p(args[1]) ?? undefined); break
      case 'run': value = await deploy.runDeploy(project, args[0], p(args[1]) ?? undefined, args[2]); break
      case 'upload': value = await deploy.runDirectoryUpload(project, args[0], p(args[1]), args[2], args[3], args[4] ?? undefined, args[5] ?? undefined); break
    }
    result = { ok: JSON.parse(mask(JSON.stringify(value ?? null))) }
  } catch (err) {
    result = { error: mask(String(err.message ?? err)) }
  }
  steps.push({ name, op, args, setup, result, events: JSON.parse(mask(JSON.stringify(events))), tree: tree() })
}
const id = (n) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0')
const folder = (name, dest, deleteRemoved, extra = {}) => ({ name, destination: { type: 'folder', path: dest, deleteRemoved }, ...extra })
mkdirSync(join(project, '.git'), { recursive: true })

// A: the basic run
await step('save F1', 'save', [folder('F1', '@W@/Ziel Ö', true, { excludes: ['geheim.html'] })])
await step('preview without a build', 'preview', [id(1), null])
await step('run without a build', 'run', [id(1), null, []])
const build = '@W@/Gärten-Ü/public'
await step('preview hides the target\'s exclusions', 'preview', [id(1), null], [
  { write: [`${build}/index.html`, '<h1>Start</h1>'] }, { write: [`${build}/Über/ärger.html`, 'ä'] }, { write: [`${build}/geheim.html`, 'g'] },
  { write: [`${build}/x.css`, 'x{}'] }])
await step('run', 'run', [id(1), null, []])
await step('run again', 'run', [id(1), null, []])
await step('run with a change, a removal and one unticked', 'run', [id(1), null, ['neu.html']], [
  { write: [`${build}/x.css`, 'x{color:red}'] }, { rm: `${build}/Über` }, { write: [`${build}/neu.html`, 'n'] }])
await step('the unticked one is still offered', 'preview', [id(1), null])
await step('the folder is gone', 'run', [id(1), null, []], [{ rm: '@W@/Ziel Ö' }])
await step('the folder holds none of the files', 'run', [id(1), null, []], [{ write: ['@W@/Ziel Ö/.DS_Store', 'x'] }])

// B: without deletion, then with
const bb = '@W@/build-b'
await step('save F2 without deletion', 'save', [folder('F2', '@W@/Ziel2', false)])
await step('run F2', 'run', [id(2), bb, []], [{ write: [`${bb}/index.html`, 'i'] }, { write: [`${bb}/alt.html`, 'a'] }])
await step('a removal without deletion', 'run', [id(2), bb, []], [{ rm: `${bb}/alt.html` }])
await step('deletion switched on', 'save', [{ ...folder('F2', '@W@/Ziel2', true), id: id(2) }])
await step('the removal comes', 'run', [id(2), bb, []])

// C: refused deletions
const bc = '@W@/build-c'
await step('save F3', 'save', [folder('F3', '@W@/Ziel3', true)])
await step('run F3', 'run', [id(3), bc, []], [{ write: [`${bc}/index.html`, 'i'] }, { write: [`${bc}/sub/a.html`, 'a'] }, { write: [`${bc}/b.html`, 'b'] }])
await step('one refused, one a folder', 'run', [id(3), bc, []], [
  { rm: `${bc}/sub` }, { rm: `${bc}/b.html` }, { rm: '@W@/Ziel3/b.html' }, { mkdir: '@W@/Ziel3/b.html' }, { chmod: ['@W@/Ziel3/sub', '555'] }])
await step('they are offered again', 'preview', [id(3), bc], [{ chmod: ['@W@/Ziel3/sub', '755'] }])

// D: overlap and the project itself
await step('save F4 inside the build', 'save', [folder('F4', '@W@/build-d/sub', true)])
await step('target inside the build', 'run', [id(4), '@W@/build-d', []], [{ write: ['@W@/build-d/index.html', 'i'] }])
await step('save F5 around the build', 'save', [folder('F5', '@W@', true)])
await step('build inside the target', 'run', [id(5), '@W@/build-d', []])
await step('save F6 the project', 'save', [folder('F6', '@W@/Gärten-Ü', true)])
await step('the project itself', 'run', [id(6), '@W@/build-d', []])
await step('a sibling with a longer name is no overlap', 'save', [folder('F7', '@W@/build-d-old', false)])
await step('run into the sibling', 'run', [id(7), '@W@/build-d', []])

// E, F: no target, no adapter
await step('preview of no target', 'preview', ['nope', null])
await step('run of no target', 'run', ['nope', null, []])
await step('save S1 sftp', 'save', [{ name: 'S1', connectionId: '11111111-1111-4111-8111-111111111111', destination: { type: 'sftp', remotePath: 'www', transfer: 'sftp', deleteRemoved: false } }])
await step('run without an adapter', 'run', [id(8), null, []])

// G: documents along
await step('save the document target', 'save', [{ name: 'Buch', destination: { type: 'document', path: '@W@/Bücher', bookId: 'buch', formats: ['pdf', 'epub'] } }])
await step('save F9 with documents', 'save', [folder('F9', '@W@/Ziel9', true, { withDocuments: [id(9), '99999999-9999-4999-8999-999999999999'] })])
const bg = '@W@/build-g'
await step('preview with documents', 'preview', [id(10), bg], [
  { write: [`${bg}/index.html`, 'i'] }, { write: [`${bg}/downloads/buch.pdf`, 'from the build'] }, { write: ['@W@/Bücher/buch.pdf', 'PDF'] },
  { utimes: [`${bg}/index.html`, 1793000000] }, { utimes: ['@W@/Bücher/buch.pdf', 1792000000] }])
await step('run with documents', 'run', [id(10), bg, []])
await step('documents switched off', 'save', [{ ...folder('F9', '@W@/Ziel9', true), id: id(10) }])
await step('run without them deletes them', 'run', [id(10), bg, []])

// H: the relay
const relay = '@W@/relay-src'
const generated = (g) => `<?php\nreturn [\n  'generation' => '${g}',\n];\n`
await step('save F11 for the relay', 'save', [folder('Web', '@W@/Web', false)])
await step('relay upload', 'upload', [id(11), relay, 'forms', `relay-${id(11)}`, null, null], [
  { write: [`${relay}/send.php`, '<?php // send'] }, { write: [`${relay}/config.php`, '<?php // secret'] },
  { write: [`${relay}/config.generated.php`, generated('0123456789abcdef')] }, { write: [`${relay}/counters/.htaccess`, 'Deny from all'] },
  { chmod: [`${relay}/config.php`, '640'] }, { chmod: [`${relay}/counters`, '750'] }, { chmod: [relay, '751'] }])
await step('relay upload again sends everything', 'upload', [id(11), relay, 'forms', `relay-${id(11)}`, null, null],
  [{ write: ['@W@/Web/forms/counters/42', '1'] }])
await step('relay folder that is not one', 'upload', [id(11), relay, '../x', `relay-${id(11)}`, null, null])
await step('relay folder "."', 'upload', [id(11), relay, '.', `relay-${id(11)}`, null, null])
await step('relay folder with slashes around', 'upload', [id(11), relay, '/forms/', `relay-${id(11)}`, null, null])
await step('save a webhook target', 'save', [{ name: 'Hook', destination: { type: 'webhook' } }])
await step('relay through a webhook', 'upload', [id(12), relay, 'forms', 'relay-x', null, null])
await step('relay through no target', 'upload', ['nope', relay, 'forms', 'relay-x', null, null])
const removeList = ['send.php', 'config.php', 'config.generated.php']
await step('remove a foreign relay', 'upload', [id(11), '@W@/empty', 'forms', `relay-${id(11)}`, removeList, '0123456789abcdef'], [
  { mkdir: '@W@/empty' }, { write: ['@W@/Web/forms/config.generated.php', generated('fedcba9876543210')] }])
await step('remove one without the line', 'upload', [id(11), '@W@/empty', 'forms', `relay-${id(11)}`, removeList, '0123456789abcdef'],
  [{ write: ['@W@/Web/forms/config.generated.php', '<?php return [];'] }])
await step('remove one that cannot be read', 'upload', [id(11), '@W@/empty', 'forms', `relay-${id(11)}`, removeList, '0123456789abcdef'],
  [{ rm: '@W@/Web/forms/config.generated.php' }, { mkdir: '@W@/Web/forms/config.generated.php' }])
await step('remove our own', 'upload', [id(11), '@W@/empty', 'forms', `relay-${id(11)}`, removeList, '0123456789abcdef'],
  [{ rm: '@W@/Web/forms/config.generated.php' }, { write: ['@W@/Web/forms/config.generated.php', generated('0123456789abcdef')] }])
await step('upload once more', 'upload', [id(11), relay, 'forms', `relay-${id(11)}`, null, null])
await step('remove one deleted by hand, without its generation file', 'upload', [id(11), '@W@/empty', 'forms', `relay-${id(11)}`, removeList, '0123456789abcdef'],
  [{ rm: '@W@/Web/forms/send.php' }, { rm: '@W@/Web/forms/config.generated.php' }])
await step('and upload it again', 'upload', [id(11), relay, 'forms', `relay-${id(11)}`, null, null])
await step('removing refused', 'upload', [id(11), '@W@/empty', 'forms', `relay-${id(11)}`, removeList, '0123456789abcdef'],
  [{ chmod: ['@W@/Web/forms', '555'] }])
await step('removing nothing', 'upload', [id(11), '@W@/empty', 'forms', `relay-${id(11)}`, [], '0123456789abcdef'],
  [{ chmod: ['@W@/Web/forms', '755'] }])
await step('remove our own at last', 'upload', [id(11), '@W@/empty', 'forms', `relay-${id(11)}`, removeList, '0123456789abcdef'])
await step('remove again', 'upload', [id(11), '@W@/empty', 'forms', `relay-${id(11)}`, removeList, '0123456789abcdef'])
await step('remove with the folder gone', 'upload', [id(11), '@W@/empty', 'forms', `relay-${id(11)}`, removeList, null], [{ rm: '@W@/Web/forms' }])
await step('remove with the drive gone', 'upload', [id(11), '@W@/empty', 'forms', `relay-${id(11)}`, removeList, null], [{ rm: '@W@/Web' }])

// D again, last, so the ids above stay as they are
await step('save F13 into a folder "..alt" of the build', 'save', [folder('F13', '@W@/build-d/..alt', false)])
await step('a folder "..alt" is inside', 'run', [id(13), '@W@/build-d', []])

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'steps.json'), JSON.stringify({ steps }, null, 1) + '\n')
rmSync(work, { recursive: true, force: true })
console.log(`${steps.length} steps`)
