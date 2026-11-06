#!/usr/bin/env node
// Golden file for SFTPAdapter and RsyncAdapter on a real Linux host: QuartzControl's own
// deploy/sftp.ts (ssh2) and deploy/rsync.ts (macOS's rsync as sender) against debian-vm, where the
// receiver is rsync 3.5.0, OpenSSH's sftp-server serves "qchost" and internal-sftp without setstat
// serves "qcsftp" (docs: reference_relay_vm_harness). Logins with a test key (comment qh-8b-test in
// both accounts' authorized_keys). Each step: setup commands run on the host as the account, one run
// of the adapter, its answer, the progress, and afterwards the test folders on the host (type, mode,
// path, link target; sha-256 of each file). The Swift test (DebianVMTests, QH_VM_TESTS=1) replays it.
//
//   Runtime/node/bin/node scripts/vm-golden.mjs <private key> [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { spawnSync } from 'node:child_process'
import { chmodSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

for (const key of Object.keys(process.env)) if (key === 'LANG' || key.startsWith('LC_')) delete process.env[key]
process.env.LC_ALL = 'C'
const here = dirname(fileURLToPath(import.meta.url))
const key = resolve(process.argv[2])
const control = resolve(process.argv[3] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'vm')
const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-vm-golden-')))
const project = join(work, 'Gärten-Ü')
mkdirSync(join(project, '.git'), { recursive: true })
const HOST = 'debian.local'
// Where each account may write; removed before and after.
const R = { qchost: '/srv/qc/www/qh8b', qcsftp: '/srv/qc/www/nochmod/qh8b' }
const W = (p) => p.split('@W@').join(work).split('@R@').join(R.qchost).split('@N@').join(R.qcsftp)
const mask = (text) => text.split(work).join('@W@').split(R.qcsftp).join('@N@').split(R.qchost).join('@R@').replace(/rsync\(\d+\)/g, 'rsync(PID)')

const ssh = (user, command) => {
  const r = spawnSync('/usr/bin/ssh', ['-F', '/dev/null', '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=accept-new',
    '-o', `UserKnownHostsFile=${work}/kh`, '-i', key, `${user}@${HOST}`, command], { encoding: 'utf-8' })
  return r.stdout
}
const scan = spawnSync('/usr/bin/ssh-keyscan', ['-t', 'ed25519', HOST], { encoding: 'utf-8' }).stdout.trim().split('\n').find((l) => l.includes('ssh-ed25519')).split(' ')
const { createHash } = await import('node:crypto')
const hostKey = { fingerprint: `SHA256:${createHash('sha256').update(Buffer.from(scan[2], 'base64')).digest('base64').replace(/=+$/, '')}`, blob: scan[2], type: scan[1] }
const connection = (user) => ({ id: user, kind: 'ssh', name: user, host: HOST, port: 22, username: user, authMethod: 'privateKey', keyPath: key, hasSecret: false, hostKey })

const stubs = {
  ...commonStubs,
  '../../i18n': commonStubs['../i18n'],
  '../connectionsService': 'export async function getConnection(id) { return globalThis.__connections[id] }\nexport async function rememberHostKey() {}',
  '../environmentService': 'export function findExecutable() { return "/usr/bin/rsync" }',
  electron: 'export const dialog = { showMessageBox: async () => ({ response: 1 }) }',
  'cpu-features': 'throw new Error("no native module here")',
  './crypto/build/Release/sshcrypto.node': 'throw new Error("no native module here")'
}
globalThis.__connections = { qchost: connection('qchost'), qcsftp: connection('qcsftp'),
  ftp: { id: 'ftp', kind: 'ftp', name: 'ftp', host: HOST, port: 21, username: 'qchost', secure: false, hasSecret: true } }
const { sftpAdapter } = await loadQuartzControl(control, 'electron/main/services/deploy/sftp.ts', stubs)
const { ftpAdapter } = await loadQuartzControl(control, 'electron/main/services/deploy/ftp.ts', stubs)
const { rsyncAdapter } = await loadQuartzControl(control, 'electron/main/services/deploy/rsync.ts', { ...stubs, './sftp': 'export const SSH_KEEPALIVE_MS = 15000; export const SSH_KEEPALIVE_COUNT = 3; export const SSH_SILENT_SECONDS = 60' })

// The state on the host: what the test folders hold.
const listing = 'for d in /srv/qc/www/qh8b /srv/qc/www/nochmod/qh8b "$HOME/qh8b-site" "$HOME/qh8b-site2"; do [ -e "$d" ] && find "$d" -printf "%y %m %p %l\\n" | sort; done; for d in /srv/qc/www/qh8b /srv/qc/www/nochmod/qh8b "$HOME/qh8b-site" "$HOME/qh8b-site2"; do [ -e "$d" ] && find "$d" -type f -readable -exec sha256sum {} + | sort -k2; done; true'
const reset = 'rm -rf /srv/qc/www/qh8b "$HOME/qh8b-site" "$HOME/qh8b-site2"; mkdir -p /srv/qc/www/qh8b'
// qcsftp has no shell (internal-sftp only): its folder is listed and removed by the admin account.
const admin = (command) => spawnSync('/usr/bin/ssh', ['-o', 'BatchMode=yes', 'debian-vm', command], { encoding: 'utf-8' }).stdout
const state = () => mask(ssh('qchost', listing) + admin('sudo find /srv/qc/www/nochmod/qh8b -printf "%y %m %u %p\\n" 2>/dev/null | sort; true'))

const steps = []
async function step(name, adapter, user, destination, options = {}, setup = [], remote = []) {
  for (const a of setup) {
    if (a.write) { mkdirSync(dirname(W(a.write[0])), { recursive: true }); writeFileSync(W(a.write[0]), a.write[1]) }
    if (a.chmod) chmodSync(W(a.chmod[0]), parseInt(a.chmod[1], 8))
    if (a.mkdir) mkdirSync(W(a.mkdir), { recursive: true })
  }
  for (const [account, command] of remote) account === 'admin' ? admin(W(command)) : ssh(account, W(command))
  const events = []
  const target = { id: options.id ?? 't1', name: 'Web', connectionId: user, destination: JSON.parse(W(JSON.stringify(destination))), excludes: [] }
  const ctx = {
    projectPath: project, target, buildDir: W(options.build ?? '@W@/build'), secret: adapter === 'ftp' ? process.env.QH_FTP_PW : null,
    ...(options.keepLocalModes ? { keepLocalModes: true } : {}),
    ...(options.relayFolders ? { relayFolders: options.relayFolders.map(W) } : {}),
    ...(options.onlyPaths ? { onlyPaths: options.onlyPaths } : {}),
    ...(options.ownGeneration ? { ownGeneration: options.ownGeneration } : {}),
    emitProgress: (processed, total, currentFile) => events.push({ processed, total, currentFile: currentFile ?? null })
  }
  let result
  try {
    result = { ok: await (adapter === 'rsync' ? rsyncAdapter : adapter === 'ftp' ? ftpAdapter : sftpAdapter).run(ctx, options.excludes ?? []) }
  } catch (err) {
    result = { error: String(err.message ?? err) }
  }
  console.error('==', name, mask(JSON.stringify(result)).slice(0, 300))
  steps.push({ name, adapter, user, destination, options, setup, remote, result: JSON.parse(mask(JSON.stringify(result))), events: JSON.parse(mask(JSON.stringify(events))), state: state() })
}

ssh('qchost', reset)
admin('sudo rm -rf /srv/qc/www/nochmod/qh8b; sudo -u qcsftp mkdir -p /srv/qc/www/nochmod/qh8b')
const sftp = (remotePath, deleteRemoved = true) => ({ type: 'sftp', remotePath, transfer: 'sftp', deleteRemoved })
const rsync = (remotePath, deleteRemoved = true) => ({ type: 'sftp', remotePath, transfer: 'rsync', deleteRemoved })
const build = [{ write: ['@W@/build/index.html', '<h1>Start</h1>'] }, { write: ['@W@/build/Über/ärger.html', 'ä'] }, { write: ['@W@/build/x.css', 'x{}'] }]
const relayFiles = [{ write: ['@W@/relay/send.php', '<?php // send'] }, { write: ['@W@/relay/config.php', '<?php // secret'] },
  { write: ['@W@/relay/config.generated.php', "<?php\nreturn [\n  'generation' => '0123456789abcdef',\n];\n"] }, { write: ['@W@/relay/counters/.htaccess', 'Deny'] },
  { chmod: ['@W@/relay/config.php', '640'] }, { chmod: ['@W@/relay/counters', '750'] }, { chmod: ['@W@/relay', '751'] }]
const relay = (id, folders) => ({ id, build: '@W@/relay', keepLocalModes: true, relayFolders: folders })
const remove = (id, folders, generation) => ({ id, build: '@W@/empty', keepLocalModes: true, relayFolders: folders, onlyPaths: ['send.php', 'config.php', 'config.generated.php'], ownGeneration: generation })

await step('sftp: a site, its files 0644', 'sftp', 'qchost', sftp('@R@/site'), {}, build, [['qchost', 'mkdir -p @R@/site']])
await step('sftp: "~" is the login directory of another account', 'sftp', 'qchost', sftp('~qcsftp/x'), { id: 't2' })
await step('sftp: "~/…" below the login directory', 'sftp', 'qchost', sftp('~/qh8b-site'), { id: 't3' })
await step('sftp: the relay with its modes', 'sftp', 'qchost', sftp('@R@/web/forms', false), relay('relay-a', ['@R@/web/forms']), [...relayFiles], [['qchost', 'mkdir -p @R@/web']])
await step('sftp: a server that sets no modes', 'sftp', 'qcsftp', sftp('@N@/forms', false), relay('relay-b', ['@N@/forms']))
await step('sftp: removing a relay the server keeps', 'sftp', 'qchost', sftp('@R@/web/forms', true), remove('relay-a', ['@R@/web/forms'], '0123456789abcdef'),
  [{ write: ['@W@/Gärten-Ü/.quartz-gui/deploy-manifest-relay-a.json', JSON.stringify({ 'send.php': 'remove', 'config.php': 'remove', 'config.generated.php': 'remove' })] },
    { mkdir: '@W@/empty' }], [['qchost', 'chmod 555 @R@/web/forms']])
await step('rsync: a site with umlauts', 'rsync', 'qchost', rsync('@R@/rsite'), {}, [], [['qchost', 'chmod 755 @R@/web/forms; mkdir -p @R@/rsite']])
await step('rsync: the parent is missing', 'rsync', 'qchost', rsync('@R@/fehlt/rsite'), { id: 't4' })
await step('rsync: the relay into a folder not there yet', 'rsync', 'qchost', rsync('@R@/rweb/neu/forms', false),
  relay('relay-c', ['@R@/rweb/neu', '@R@/rweb/neu/forms']), [], [['qchost', 'mkdir -p @R@/rweb']])
await step('rsync: the relay folder is a link', 'rsync', 'qchost', rsync('@R@/rweb/link', false), relay('relay-d', ['@R@/rweb/link']), [],
  [['qchost', 'ln -s @R@/rweb/neu/forms @R@/rweb/link']])
await step('rsync: removing a relay the server keeps', 'rsync', 'qchost', rsync('@R@/rweb/neu/forms', true),
  remove('relay-c', ['@R@/rweb/neu', '@R@/rweb/neu/forms'], '0123456789abcdef'), [], [['qchost', 'chmod 555 @R@/rweb/neu/forms']])
await step('rsync: removing our own', 'rsync', 'qchost', rsync('@R@/rweb/neu/forms', true),
  remove('relay-c', ['@R@/rweb/neu', '@R@/rweb/neu/forms'], '0123456789abcdef'), [], [['qchost', 'chmod 755 @R@/rweb/neu/forms']])
await step('rsync: removing again', 'rsync', 'qchost', rsync('@R@/rweb/neu/forms', true), remove('relay-c', ['@R@/rweb/neu', '@R@/rweb/neu/forms'], '0123456789abcdef'))

const ftp = (remotePath, deleteRemoved = true) => ({ type: 'ftp', remotePath, deleteRemoved })
await step('ftp: a site with umlauts', 'ftp', 'ftp', ftp('@R@/fsite'), { id: 'f1' }, [], [['qchost', 'mkdir -p @R@/fsite']])
await step('ftp: nothing to do', 'ftp', 'ftp', ftp('@R@/fsite'), { id: 'f1' })
await step('ftp: the parent is missing', 'ftp', 'ftp', ftp('@R@/fehlt/fsite'), { id: 'f2' })
await step('ftp: "~" of another account', 'ftp', 'ftp', ftp('~qcsftp/x'), { id: 'f3' })
await step('ftp: a relative path from the login directory', 'ftp', 'ftp', ftp('qh8b-site2'), { id: 'f4' })
await step('ftp: a deletion refused and a folder in its place', 'ftp', 'ftp', ftp('@R@/fsite'), { id: 'f1', build: '@W@/fbuild' },
  [{ write: ['@W@/fbuild/index.html', '<h1>Start</h1>'] }], [['qchost', 'rm @R@/fsite/x.css; mkdir @R@/fsite/x.css; touch @R@/fsite/x.css/inhalt; chmod 555 @R@/fsite/Über']])
await step('ftp: the relay with its modes', 'ftp', 'ftp', ftp('@R@/fweb/forms', false), relay('relay-f', ['@R@/fweb/forms']), [],
  [['qchost', 'chmod 755 @R@/fsite/Über; mkdir -p @R@/fweb']])
const chmodOff = "sudo sed -i 's/^chmod_enable=YES/chmod_enable=NO/' /etc/vsftpd.conf && sudo systemctl restart vsftpd"
const chmodOn = "sudo sed -i 's/^chmod_enable=NO/chmod_enable=YES/' /etc/vsftpd.conf && sudo systemctl restart vsftpd"
await step('ftp: a server that refuses SITE CHMOD', 'ftp', 'ftp', ftp('@R@/fweb2/forms', false), relay('relay-h', ['@R@/fweb2/forms']), [],
  [['qchost', 'mkdir -p @R@/fweb2'], ['admin', chmodOff]])
await step('ftp: the relay folder is a link', 'ftp', 'ftp', ftp('@R@/fweb/link', false), relay('relay-g', ['@R@/fweb/link']), [],
  [['admin', chmodOn], ['qchost', 'ln -s @R@/fweb/forms @R@/fweb/link']])
await step('ftp: removing a foreign relay', 'ftp', 'ftp', ftp('@R@/fweb/forms', true), remove('relay-f', ['@R@/fweb/forms'], '0123456789abcdef'),
  [{ write: ['@W@/Gärten-Ü/.quartz-gui/deploy-manifest-relay-f.json', JSON.stringify({ 'send.php': 'remove', 'config.php': 'remove', 'config.generated.php': 'remove' })] }],
  [['qchost', "cp @R@/fweb/forms/config.generated.php /tmp/qh8c-generated; printf '<?php\\nreturn [\\n  \\x27generation\\x27 => \\x27fedcba9876543210\\x27,\\n];\\n' > @R@/fweb/forms/config.generated.php"]])
await step('ftp: removing a relay the server keeps', 'ftp', 'ftp', ftp('@R@/fweb/forms', true), remove('relay-f', ['@R@/fweb/forms'], '0123456789abcdef'),
  [{ write: ['@W@/Gärten-Ü/.quartz-gui/deploy-manifest-relay-f.json', JSON.stringify({ 'send.php': 'remove', 'config.php': 'remove', 'config.generated.php': 'remove' })] }],
  [['qchost', 'cp /tmp/qh8c-generated @R@/fweb/forms/config.generated.php; rm /tmp/qh8c-generated; chmod 555 @R@/fweb/forms']])
await step('ftp: removing our own', 'ftp', 'ftp', ftp('@R@/fweb/forms', true), remove('relay-f', ['@R@/fweb/forms'], '0123456789abcdef'),
  [{ write: ['@W@/Gärten-Ü/.quartz-gui/deploy-manifest-relay-f.json', JSON.stringify({ 'send.php': 'remove', 'config.php': 'remove', 'config.generated.php': 'remove' })] }],
  [['qchost', 'chmod 755 @R@/fweb/forms']])
await step('ftp: removing again', 'ftp', 'ftp', ftp('@R@/fweb/forms', true), remove('relay-f', ['@R@/fweb/forms'], '0123456789abcdef'),
  [{ write: ['@W@/Gärten-Ü/.quartz-gui/deploy-manifest-relay-f.json', JSON.stringify({ 'send.php': 'remove', 'config.php': 'remove', 'config.generated.php': 'remove' })] }])

ssh('qchost', 'chmod -R u+w /srv/qc/www/qh8b 2>/dev/null; rm -rf /srv/qc/www/qh8b "$HOME/qh8b-site" "$HOME/qh8b-site2"')
admin('sudo rm -rf /srv/qc/www/nochmod/qh8b')
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'steps.json'), JSON.stringify({ hostKey, steps }, null, 1) + '\n')
rmSync(work, { recursive: true, force: true })
console.log(`${steps.length} steps`)
process.exit(0)
