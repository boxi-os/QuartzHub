#!/usr/bin/env node
// Golden file for RsyncAdapter, made by QuartzControl's own deploy/rsync.ts with the system's
// rsync (openrsync on both ends) and ssh against the system's sshd, started here as the user on a free port of 127.0.0.1
// (own host key, own authorized_keys, `internal-sftp -d <home>`), the way the Swift test starts it
// (LocalSSHD). The connection has its host key pinned, so no dialog is asked. Each step is its
// setup (files, folders, modes and links in the work folder "@W@" and the server's start folder
// "@H@"), one run of the adapter with its context, the answer, the progress events, and afterwards
// every folder and file under "@H@" with its mode, links as their target, and the project's
// .quartz-gui/ files.
//
//   Runtime/node/bin/node scripts/rsync-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { spawn, spawnSync } from 'node:child_process'
import { chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { createServer } from 'node:net'
import { tmpdir, userInfo } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

// The C locale for rsync, as QuartzHub gives it (RsyncAdapter): in a UTF-8 locale openrsync escapes
// bytes 0x80 to 0x9F of a name, and "Über" came out as "\uFFFD\\#234ber".
for (const key of Object.keys(process.env)) if (key === 'LANG' || key.startsWith('LC_')) delete process.env[key]
process.env.LC_ALL = 'C'
const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'rsync')
const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-rsync-golden-')))
const home = join(work, 'home')
const project = join(work, 'Gärten-Ü')
mkdirSync(home)
mkdirSync(join(project, '.git'), { recursive: true })
const W = (p) => p.split('@W@').join(work).split('@H@').join(home)
// rsync's own lines name its process id.
const mask = (text) => text.split(home).join('@H@').split(work).join('@W@').replace(/rsync\(\d+\)/g, 'rsync(PID)').split(globalThis.__fingerprint ?? '\u0000').join('@FP@')

// The server.
const port = await new Promise((done) => { const s = createServer(); s.listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => done(p)) }) })
for (const name of ['host', 'client']) spawnSync('/usr/bin/ssh-keygen', ['-q', '-t', 'ed25519', '-N', '', '-C', name, '-f', join(work, name)])
writeFileSync(join(work, 'authorized_keys'), readFileSync(join(work, 'client.pub')))
chmodSync(join(work, 'authorized_keys'), 0o600)
writeFileSync(join(work, 'sshd_config'), [`Port ${port}`, 'ListenAddress 127.0.0.1', `HostKey ${work}/host`, `PidFile ${work}/sshd.pid`,
  `AuthorizedKeysFile ${work}/authorized_keys`, 'UsePAM no', 'StrictModes no', 'KbdInteractiveAuthentication no',
  `Subsystem sftp internal-sftp -d ${home}`, ''].join('\n'))
const sshd = spawn('/usr/sbin/sshd', ['-D', '-f', join(work, 'sshd_config'), '-E', join(work, 'sshd.log')], { stdio: 'ignore' })
await new Promise((done) => setTimeout(done, 500))
const pub = readFileSync(join(work, 'host.pub'), 'utf-8').trim().split(' ')
const { createHash } = await import('node:crypto')
const sha = (text) => createHash('sha256').update(text).digest('hex')
const hostKey = { fingerprint: `SHA256:${createHash('sha256').update(Buffer.from(pub[1], 'base64')).digest('base64').replace(/=+$/, '')}`, blob: pub[1], type: pub[0] }
globalThis.__fingerprint = hostKey.fingerprint
const user = userInfo().username
const connection = { id: 'c1', kind: 'ssh', name: 'lokal', host: '127.0.0.1', port, username: user, authMethod: 'privateKey', keyPath: join(work, 'client'), hasSecret: false, hostKey }

const stubs = {
  ...commonStubs,
  '../../i18n': commonStubs['../i18n'],
  '../connectionsService': 'export async function getConnection() { return globalThis.__connection }',
  '../environmentService': 'export function findExecutable() { return "/usr/bin/rsync" }',
  './sftp': 'export const SSH_KEEPALIVE_MS = 15000; export const SSH_KEEPALIVE_COUNT = 3; export const SSH_SILENT_SECONDS = 60'
}
globalThis.__connection = connection
const { rsyncAdapter } = await loadQuartzControl(control, 'electron/main/services/deploy/rsync.ts', stubs)

function tree() {
  const found = {}
  const walk = (dir, rel) => {
    for (const name of readdirSync(dir).sort()) {
      const full = join(dir, name), r = rel ? `${rel}/${name}` : name
      const info = lstatSync(full)
      const mode = (info.mode & 0o7777).toString(8)
      if (info.isSymbolicLink()) found[r] = `link ${mask(readlinkSync(full))}`
      else if (info.isDirectory()) { found[`${r}/`] = mode; if (info.mode & 0o500) walk(full, r) }
      else found[r] = `${mode} ${readFileSync(full, 'utf-8')}`
    }
  }
  walk(home, 'H')
  if (existsSync(join(project, '.quartz-gui'))) walk(join(project, '.quartz-gui'), 'gui')
  return found
}

const steps = []
async function step(name, destination, options = {}, setup = [], call = 'run') {
  for (const a of setup) {
    if (a.write) { mkdirSync(dirname(W(a.write[0])), { recursive: true }); writeFileSync(W(a.write[0]), a.write[1]) }
    if (a.mkdir) mkdirSync(W(a.mkdir), { recursive: true })
    if (a.rm) rmSync(W(a.rm), { recursive: true, force: true })
    if (a.chmod) chmodSync(W(a.chmod[0]), parseInt(a.chmod[1], 8))
    if (a.symlink) symlinkSync(W(a.symlink[0]), W(a.symlink[1]))
    if (a.keygen && !existsSync(W(a.keygen))) spawnSync('/usr/bin/ssh-keygen', ['-q', '-t', 'ed25519', '-N', '', '-C', 'stranger', '-f', W(a.keygen)])
  }
  const events = []
  const target = { id: options.id ?? 't1', name: 'Web', connectionId: 'c1', destination: JSON.parse(W(JSON.stringify(destination))), excludes: [] }
  const ctx = {
    projectPath: project, target, buildDir: W(options.build ?? '@W@/build'), secret: null,
    ...(options.keepLocalModes ? { keepLocalModes: true } : {}),
    ...(options.relayFolders ? { relayFolders: options.relayFolders.map(W) } : {}),
    ...(options.onlyPaths ? { onlyPaths: options.onlyPaths } : {}),
    ...(options.ownGeneration ? { ownGeneration: options.ownGeneration } : {}),
    emitProgress: (processed, total, currentFile) => events.push({ processed, total, currentFile: currentFile ?? null })
  }
  let result
  try {
    globalThis.__connection = options.connection ? JSON.parse(W(JSON.stringify({ ...connection, ...options.connection }))) : connection
    result = { ok: call === 'preview' ? await rsyncAdapter.preview(ctx) : await rsyncAdapter.run(ctx, options.excludes ?? []) }
  } catch (err) {
    result = { error: String(err.message ?? err) }
  }
  console.error("==", name, JSON.stringify(result).slice(0, 400))
  steps.push({ name, call, destination, options, setup, result: JSON.parse(mask(JSON.stringify(result))), events: JSON.parse(mask(JSON.stringify(events))), tree: tree() })
}

const site = (remotePath, deleteRemoved = true) => ({ type: 'sftp', remotePath, transfer: 'rsync', deleteRemoved })
const build = [{ write: ['@W@/build/index.html', '<h1>Start</h1>'] }, { write: ['@W@/build/Über/ärger.html', 'ä'] }, { write: ['@W@/build/x.css', 'x{}'] },
  { write: ['@W@/build/geheim.html', 'g'] }, { mkdir: '@H@/site' }]
await step('preview of an empty folder', site('@H@/site'), {}, build, 'preview')
await step('first upload', site('@H@/site'), { excludes: ['geheim.html'] })
await step('nothing to do', site('@H@/site'), { excludes: ['geheim.html'] })
await step('a change, a removal, an exclusion', site('@H@/site'), { excludes: ['neu.html', 'geheim.html'] }, [
  { write: ['@W@/build/x.css', 'x{color:red}'] }, { rm: '@W@/build/Über' }, { write: ['@W@/build/neu.html', 'n'] },
  { write: ['@W@/build/unter/neu.html', 'u'] }])
await step('a file deleted on the server comes back', site('@H@/site'), { excludes: ['neu.html', 'geheim.html'] }, [{ rm: '@H@/site/x.css' }], 'preview')
await step('without deletion', site('@H@/site', false), { excludes: ['neu.html'] }, [{ write: ['@H@/site/extra.html', 'e'] }])
await step('the parent is missing', site('@H@/fehlt/site'))
await step('a path with a space', site('@H@/mit leer'))
await step('a path with a shell character', site('@H@/neu!'))
await step('a path that starts with "-"', site('-strich'), {}, [], 'preview')
await step('a changed host key', site('@H@/site'), { connection: { hostKey: { fingerprint: 'SHA256:anders', blob: 'AAAAC3NzaC1lZDI1NTE5AAAAIOYSnVIJ8WzgwbFPdqq3K1LUpRVNXDvvx5u5umIQPgqa', type: 'ssh-ed25519' } } })
await step('a password connection', site('@H@/site'), { connection: { authMethod: 'password', keyPath: undefined } })
await step('a pin without its key', site('@H@/site'), { connection: { hostKey: { fingerprint: hostKey.fingerprint, blob: '', type: '' } } })
await step('a key the server does not know', site('@H@/site'), { connection: { keyPath: '@W@/stranger' } }, [{ keygen: '@W@/stranger' }])
// The relay: what runDirectoryUpload gives the adapter.
const relay = (remotePath, deleteRemoved = false) => ({ type: 'sftp', remotePath, transfer: 'rsync', deleteRemoved })
const relaySetup = [{ write: ['@W@/relay/send.php', '<?php // send'] }, { write: ['@W@/relay/config.php', '<?php // secret'] },
  { write: ['@W@/relay/config.generated.php', "<?php\nreturn [\n  'generation' => '0123456789abcdef',\n];\n"] }, { write: ['@W@/relay/counters/.htaccess', 'Deny'] },
  { chmod: ['@W@/relay/config.php', '640'] }, { chmod: ['@W@/relay/counters', '750'] }, { chmod: ['@W@/relay', '751'] }, { mkdir: '@H@/web' }]
const relayOptions = { id: 'relay-t6', build: '@W@/relay', keepLocalModes: true, relayFolders: ['@H@/web/forms'] }
await step('relay upload', relay('@H@/web/forms'), relayOptions, relaySetup)
await step('relay upload into a missing folder', relay('@H@/web/neu/forms'), { ...relayOptions, relayFolders: ['@H@/web/neu', '@H@/web/neu/forms'] })
await step('relay folder is a link', relay('@H@/web/link'), { ...relayOptions, relayFolders: ['@H@/web/link'] }, [{ symlink: ['@H@/web/forms', '@H@/web/link'] }])
const remove = (generation) => ({ id: 'relay-t6', build: '@W@/empty', keepLocalModes: true, relayFolders: ['@H@/web/forms'], onlyPaths: ['send.php', 'config.php', 'config.generated.php'], ownGeneration: generation })
// A relay on the server as an upload would have left it (openrsync as the receiver lists no folder
// that is missing in rsync 3.x's words, so the upload above stops; debian-vm measures that).
const placed = [{ mkdir: '@W@/empty' }, { write: ['@H@/web/forms/send.php', '<?php // send'] }, { write: ['@H@/web/forms/config.php', '<?php // secret'] },
  { write: ['@H@/web/forms/config.generated.php', "<?php\nreturn [\n  'generation' => '0123456789abcdef',\n];\n"] }, { write: ['@H@/web/forms/counters/7', '1'] }]
await step('remove a foreign relay', relay('@H@/web/forms', true), remove('fedcba9876543210'), [...placed,
  { write: ['@H@/web/forms/config.generated.php', "<?php\nreturn [\n  'generation' => 'fedcba9876543211',\n];\n"] }])
await step('removal refused', relay('@H@/web/forms', true), remove('0123456789abcdef'), [...placed, { chmod: ['@H@/web/forms', '555'] }])
await step('remove our own', relay('@H@/web/forms', true), remove('0123456789abcdef'), [{ chmod: ['@H@/web/forms', '755'] }])
await step('remove again', relay('@H@/web/forms', true), remove('0123456789abcdef'))
await step('remove where there is no folder', relay('@H@/web/nichts', true), { ...remove('0123456789abcdef'), relayFolders: ['@H@/web/nichts'] })

sshd.kill()
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'steps.json'), JSON.stringify({ steps }, null, 1) + '\n')
rmSync(work, { recursive: true, force: true })
console.log(`${steps.length} steps`)
process.exit(0)
