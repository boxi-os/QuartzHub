#!/usr/bin/env node
// Golden file for SFTPAdapter, made by QuartzControl's own deploy/sftp.ts with its real ssh2 and
// ssh2-sftp-client against the system's sshd, started here as the user on a free port of 127.0.0.1
// (own host key, own authorized_keys, `internal-sftp -d <home>`), the way the Swift test starts it
// (LocalSSHD). The connection has its host key pinned, so no dialog is asked. Each step is its
// setup (files, folders, modes and links in the work folder "@W@" and the server's start folder
// "@H@"), one run of the adapter with its context, the answer, the progress events, and afterwards
// every folder and file under "@H@" with its mode, links as their target, and the project's
// .quartz-gui/ files.
//
//   Runtime/node/bin/node scripts/sftp-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { spawn, spawnSync } from 'node:child_process'
import { chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { createServer } from 'node:net'
import { tmpdir, userInfo } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'sftp')
const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-sftp-golden-')))
const home = join(work, 'home')
const project = join(work, 'Gärten-Ü')
mkdirSync(home)
mkdirSync(join(project, '.git'), { recursive: true })
const W = (p) => p.split('@W@').join(work).split('@H@').join(home)
const mask = (text) => text.split(home).join('@H@').split(work).join('@W@')

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
const user = userInfo().username
const connection = { id: 'c1', kind: 'ssh', name: 'lokal', host: '127.0.0.1', port, username: user, authMethod: 'privateKey', keyPath: join(work, 'client'), hasSecret: false, hostKey }

const stubs = {
  ...commonStubs,
  '../../i18n': commonStubs['../i18n'],
  '../connectionsService': `export async function getConnection() { return globalThis.__connection }
export async function rememberHostKey() {}`,
  electron: 'export const dialog = { showMessageBox: async () => ({ response: 1 }) }',
  // ssh2's optional native parts, loaded in try: without them it takes its JavaScript paths.
  'cpu-features': 'throw new Error("no native module here")',
  './crypto/build/Release/sshcrypto.node': 'throw new Error("no native module here")'
}
globalThis.__connection = connection
const { sftpAdapter } = await loadQuartzControl(control, 'electron/main/services/deploy/sftp.ts', stubs)

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
async function step(name, destination, options = {}, setup = []) {
  for (const a of setup) {
    if (a.write) { mkdirSync(dirname(W(a.write[0])), { recursive: true }); writeFileSync(W(a.write[0]), a.write[1]) }
    if (a.mkdir) mkdirSync(W(a.mkdir), { recursive: true })
    if (a.rm) rmSync(W(a.rm), { recursive: true, force: true })
    if (a.chmod) chmodSync(W(a.chmod[0]), parseInt(a.chmod[1], 8))
    if (a.symlink) symlinkSync(W(a.symlink[0]), W(a.symlink[1]))
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
    result = { ok: await sftpAdapter.run(ctx, options.excludes ?? []) }
  } catch (err) {
    result = { error: String(err.message ?? err) }
  }
  steps.push({ name, destination, options, setup, result: JSON.parse(mask(JSON.stringify(result))), events: JSON.parse(mask(JSON.stringify(events))), tree: tree() })
}

const site = (remotePath, deleteRemoved = true) => ({ type: 'sftp', remotePath, transfer: 'sftp', deleteRemoved })
const build = [{ write: ['@W@/build/index.html', '<h1>Start</h1>'] }, { write: ['@W@/build/Über/ärger.html', 'ä'] }, { write: ['@W@/build/x.css', 'x{}'] },
  { write: ['@W@/build/geheim.html', 'g'] }, { mkdir: '@H@/site' }]
await step('first upload', site('@H@/site'), { excludes: ['geheim.html'] }, build)
await step('nothing to do', site('@H@/site'))
await step('a change, a removal, an exclusion', site('@H@/site'), { excludes: ['neu.html'] }, [
  { write: ['@W@/build/x.css', 'x{color:red}'] }, { rm: '@W@/build/Über' }, { write: ['@W@/build/neu.html', 'n'] }])
await step('the parent is missing', site('@H@/fehlt/site'), { id: 't2' })
await step('the login directory of another account', site('~jemand/x'), { id: 't3' })
await step('"~" is the login directory', site('~/home-site'), { id: 't4' })
await step('a deletion refused and a folder in its place', site('@H@/site'), {}, [
  { rm: '@W@/build/x.css' }, { rm: '@W@/build/neu.html' }, { rm: '@W@/build/geheim.html' },
  { write: ['@H@/site/neu.html', 'n'] }, { chmod: ['@H@/site', '555'] }])
await step('a folder where a file was', site('@H@/site'), {}, [{ chmod: ['@H@/site', '755'] }, { rm: '@H@/site/x.css' }, { mkdir: '@H@/site/x.css/inhalt' }])
await step('a file where a folder must go', site('@H@/site'), {}, [{ write: ['@W@/build/a/b.html', 'b'] }, { write: ['@H@/site/a', 'datei'] }])
await step('the one-time pass to 0644', site('@H@/alt'), { id: 't5', build: '@W@/build-alt' }, [
  { write: ['@W@/build-alt/index.html', 'i'] }, { mkdir: '@H@/alt' }, { write: ['@H@/alt/old.html', 'o'] }, { chmod: ['@H@/alt/old.html', '666'] },
  { write: ['@H@/alt/private.html', 'p'] }, { chmod: ['@H@/alt/private.html', '600'] }, { write: ['@W@/outside.html', 'secret'] }, { chmod: ['@W@/outside.html', '666'] },
  { symlink: ['@W@/outside.html', '@H@/alt/link.html'] }, { mkdir: '@H@/alt/dir.html' }, { chmod: ['@H@/alt/dir.html', '777'] },
  { mkdir: '@H@/alt/dir2.html' }, { chmod: ['@H@/alt/dir2.html', '666'] }, { write: ['@W@/build-alt/dir2.html', 'e'] },
  { write: ['@W@/build-alt/old.html', 'o'] }, { write: ['@W@/build-alt/private.html', 'p'] }, { write: ['@W@/build-alt/link.html', 'l'] },
  { write: ['@W@/build-alt/dir.html', 'd'] },
  { write: ['@W@/Gärten-Ü/.quartz-gui/deploy-manifest-t5.json', JSON.stringify(Object.fromEntries(['old.html', 'private.html', 'link.html', 'dir.html']
    .concat(['dir2.html']).map((n) => [n, sha({ 'old.html': 'o', 'private.html': 'p', 'link.html': 'l', 'dir.html': 'd', 'dir2.html': 'e' }[n])])), null, 2)] }])
await step('the pass runs once', site('@H@/alt'), { id: 't5', build: '@W@/build-alt' }, [{ chmod: ['@H@/alt/private.html', '666'] }])
await step('a site below a linked folder', site('@H@/verlinkt/site'), { id: 't7', build: '@W@/build-alt' }, [{ mkdir: '@H@/echt' },
  { symlink: ['@H@/echt', '@H@/verlinkt'] }])
// The relay: what runDirectoryUpload gives the adapter.
const relay = (remotePath, deleteRemoved = false) => ({ type: 'sftp', remotePath, transfer: 'sftp', deleteRemoved })
const relaySetup = [{ write: ['@W@/relay/send.php', '<?php // send'] }, { write: ['@W@/relay/config.php', '<?php // secret'] },
  { write: ['@W@/relay/config.generated.php', "<?php\nreturn [\n  'generation' => '0123456789abcdef',\n];\n"] }, { write: ['@W@/relay/counters/.htaccess', 'Deny'] },
  { chmod: ['@W@/relay/config.php', '640'] }, { chmod: ['@W@/relay/counters', '750'] }, { chmod: ['@W@/relay', '751'] }, { mkdir: '@H@/web' }]
const relayOptions = { id: 'relay-t6', build: '@W@/relay', keepLocalModes: true, relayFolders: ['@H@/web/forms'] }
await step('relay upload', relay('@H@/web/forms'), relayOptions, relaySetup)
await step('relay upload over a folder that went 0700', relay('@H@/web/forms'), relayOptions, [{ chmod: ['@H@/web/forms', '700'] },
  { write: ['@W@/Gärten-Ü/.quartz-gui/deploy-manifest-relay-t6.json', '{}\n'] }])
await step('relay folder is a link', relay('@H@/web/link'), { ...relayOptions, relayFolders: ['@H@/web/link'] }, [{ symlink: ['@H@/web/forms', '@H@/web/link'] }])
const remove = (generation) => ({ id: 'relay-t6', build: '@W@/empty', keepLocalModes: true, relayFolders: ['@H@/web/forms'], onlyPaths: ['send.php', 'config.php', 'config.generated.php'], ownGeneration: generation })
const removeManifest = { write: ['@W@/Gärten-Ü/.quartz-gui/deploy-manifest-relay-t6.json', JSON.stringify({ 'send.php': 'remove', 'config.php': 'remove', 'config.generated.php': 'remove' }, null, 2)] }
await step('remove a foreign relay', relay('@H@/web/forms', true), remove('fedcba9876543210'), [{ mkdir: '@W@/empty' }, removeManifest])
await step('removal refused', relay('@H@/web/forms', true), remove('0123456789abcdef'), [removeManifest, { chmod: ['@H@/web/forms', '555'] }])
await step('remove our own', relay('@H@/web/forms', true), remove('0123456789abcdef'), [removeManifest, { chmod: ['@H@/web/forms', '755'] }])
await step('remove again', relay('@H@/web/forms', true), remove('0123456789abcdef'), [removeManifest])

sshd.kill()
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'steps.json'), JSON.stringify({ steps }, null, 1) + '\n')
rmSync(work, { recursive: true, force: true })
console.log(`${steps.length} steps`)
process.exit(0)
