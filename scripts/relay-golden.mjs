#!/usr/bin/env node
// Golden file for FormsRelay, made by QuartzControl's own formsService.ts (relayState,
// saveRelaySettings, relayUpload, relayExport, relayRemove, excludeFromSite) with its real
// connectionsService, publishTargetsService, jsonStore, deploy/index.ts and folder adapter. The
// plugin's command line is Fixtures/forms/fake-cli.mjs; the probe after an upload goes to
// Fixtures/forms/relay-server.mjs through the same `net.request` stand-in as
// relay-probe-golden.mjs. Stand-ins as in connections-golden.mjs: `safeStorage` "encrypts" as
// `enc:<text>`, ids and random bytes count up (one counter for connections and targets), the clock
// stands still. Each step is its setup, one call, its answer, the command line's log, the requests
// the server saw, forms-relay.json and the target folder afterwards (every folder's mode, every
// file's mode and text).
//
//   Runtime/node/bin/node scripts/relay-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { spawn } from 'node:child_process'
import { request as httpRequest } from 'node:http'
import { chmodSync, copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { createInterface } from 'node:readline'
import { createServer } from 'node:net'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { EventEmitter } from 'node:events'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const fixtures = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'forms')
const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-relay-golden-')))
const project = join(work, 'Gärten-Ü')
const profile = join(work, 'profile')
const plugin = join(project, '.quartz', 'plugins', 'quartz-forms')
process.env.PATH = `${dirname(process.execPath)}:${process.env.PATH}`
globalThis.__profile = profile
globalThis.__ids = 0
globalThis.__bytes = 0

const server = spawn(process.execPath, [join(fixtures, 'relay-server.mjs')], { stdio: ['ignore', 'pipe', 'inherit'] })
const port = await new Promise((resolve) => createInterface({ input: server.stdout }).once('line', (l) => resolve(JSON.parse(l).port)))
const closedPort = await new Promise((resolve) => { const s = createServer().listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => resolve(p)) }) })

// The same stand-in as relay-probe-golden.mjs.
globalThis.__net = {
  request({ url }) {
    const req = new EventEmitter()
    const headers = {}
    let current = null
    let aborted = false
    let hops = 0
    const codes = { ECONNREFUSED: 'net::ERR_CONNECTION_REFUSED', ECONNRESET: 'net::ERR_CONNECTION_RESET' }
    const go = (target, tainted) => {
      if (aborted) return
      const u = new URL(target)
      const viaProxy = u.hostname.endsWith('.test')
      const h = { ...headers, host: u.host }
      if (tainted && 'Origin' in headers) h.Origin = 'null'
      const host = u.hostname.replace(/^\[|\]$/g, '')
      current = httpRequest(viaProxy
        ? { host: '127.0.0.1', port, path: u.href, method: 'GET', headers: h }
        : { host, port: u.port || 80, path: u.pathname + u.search, method: 'GET', headers: h })
      current.on('response', (res) => {
        if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && hops < 20) {
          hops += 1
          res.resume()
          const next = new URL(Buffer.from(res.headers.location, 'latin1').toString('utf8'), u).href
          req.emit('redirect', res.statusCode, 'GET', next, res.headers)
          if (!aborted) go(next, tainted || new URL(next).origin !== u.origin)
          return
        }
        const out = new EventEmitter()
        out.statusCode = res.statusCode
        res.on('data', (c) => out.emit('data', c))
        res.on('end', () => out.emit('end'))
        req.emit('response', out)
      })
      current.on('error', (e) => { if (!aborted) req.emit('error', new Error(e.message === 'socket hang up' ? 'net::ERR_EMPTY_RESPONSE' : codes[e.code] ?? `net::ERR_FAILED ${e.code}`)) })
      current.end()
    }
    req.setHeader = (k, v) => { headers[k] = v }
    req.abort = () => { aborted = true; current?.destroy() }
    req.end = () => go(url, false)
    return req
  }
}

const none = (name) => `export const ${name} = undefined`
const stubs = {
  ...commonStubs,
  '../i18n': `${commonStubs['../i18n']}\nexport function mainLanguage() { return '@LANG@' }`,
  '../../i18n': commonStubs['../i18n'],
  electron: `export const app = { getPath: () => globalThis.__profile }
export const safeStorage = {
  isEncryptionAvailable: () => true,
  encryptString: (s) => Buffer.from('enc:' + s, 'utf8'),
  decryptString: (b) => { const t = b.toString('utf8'); if (!t.startsWith('enc:')) throw new Error('bad'); return t.slice(4) }
}
export const net = { request: (o) => globalThis.__net.request(o) }`,
  crypto: `import * as real from 'node:crypto'
export const createHmac = real.createHmac
export const createHash = real.createHash
export function randomUUID() {
  if ((new Error().stack ?? '').includes('writeJsonFile')) return real.randomUUID()
  globalThis.__ids += 1
  return '00000000-0000-4000-8000-' + String(globalThis.__ids).padStart(12, '0')
}
export function randomBytes(n) { globalThis.__bytes += 1; return Buffer.alloc(n, globalThis.__bytes) }`,
  './sftp': none('sftpAdapter'), './ftp': none('ftpAdapter'), './rsync': none('rsyncAdapter'), './webhook': none('webhookAdapter'),
  './gitBranch': none('gitBranchAdapter'), './document': none('documentAdapter')
}
const forms = await loadQuartzControl(control, 'electron/main/services/formsService.ts', stubs, {
  replace: [['const CHECK_RELAY_TIMEOUT_MS = 10_000', 'const CHECK_RELAY_TIMEOUT_MS = 2_000'], ['const RELAY_ASK_AGAIN_MS = 3000', 'const RELAY_ASK_AGAIN_MS = 500']]
})
const connections = await loadQuartzControl(control, 'electron/main/services/connectionsService.ts', stubs)
const targets = await loadQuartzControl(control, 'electron/main/services/publishTargetsService.ts', stubs)

const RealDate = Date
const now = RealDate.parse('2026-11-07T09:30:00.000Z')
globalThis.Date = class extends RealDate {
  constructor(...args) { if (args.length === 0) super(now); else super(...args) }
  static now() { return now }
}

const temp = tmpdir()
const W = (p) => p.split('@W@').join(work).split('@PORT@').join(String(port)).split('@CLOSED@').join(String(closedPort))
const mask = (text) => text.split(work).join('@W@').split(`:${port}`).join(':@PORT@').split(`:${closedPort}`).join(':@CLOSED@')
  .replace(new RegExp(`${temp.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}/qc-relay-[A-Za-z0-9]{6}`, 'g'), '@TMP@')
const source = 'github:boxi-os/quartz-forms'
const projectId = 'p-1'

function tree(root) {
  if (!existsSync(root)) return null
  const found = {}
  const walk = (dir, rel) => {
    for (const name of readdirSync(dir).sort()) {
      const full = join(dir, name), r = rel ? `${rel}/${name}` : name
      const info = lstatSync(full)
      const mode = (info.mode & 0o7777).toString(8)
      if (info.isDirectory()) { found[`${r}/`] = mode; walk(full, r) } else found[r] = `${mode} ${mask(readFileSync(full, 'utf-8'))}`
    }
  }
  walk(root, '')
  return found
}
const read = (file) => (existsSync(file) ? mask(readFileSync(file, 'utf-8')) : null)

const steps = []
async function step(name, op, args, setup = []) {
  for (const a of setup) {
    if (a.write) { mkdirSync(dirname(W(a.write[0])), { recursive: true }); writeFileSync(W(a.write[0]), W(a.write[1])) }
    if (a.mkdir) mkdirSync(W(a.mkdir), { recursive: true })
    if (a.rm) rmSync(W(a.rm), { recursive: true, force: true })
    if (a.chmod) chmodSync(W(a.chmod[0]), parseInt(a.chmod[1], 8))
    if (a.scenario) writeFileSync(join(project, 'fake-cli.json'), W(JSON.stringify(a.scenario)))
    if (a.connection) await connections.saveConnection(a.connection)
    if (a.deleteConnection) await connections.deleteConnection(a.deleteConnection)
    if (a.target) await targets.saveTarget(project, JSON.parse(W(JSON.stringify(a.target))))
    if (a.secrets) await connections.saveRelaySecrets(projectId, a.secrets)
  }
  rmSync(join(project, 'fake-cli.log'), { force: true })
  await fetch(`http://127.0.0.1:${port}/__reset`)
  let result
  try {
    let value
    switch (op) {
      case 'state': value = await forms.relayState(projectId, project, source); break
      case 'settings': value = await forms.saveRelaySettings(project, args[0]); break
      case 'upload': value = await forms.relayUpload(projectId, project, source, args[0] === null ? undefined : W(args[0]), args[1] ?? undefined); break
      case 'export': value = await forms.relayExport(projectId, project, source, W(args[0])); break
      case 'remove': value = await forms.relayRemove(project); break
      case 'exclude': value = await forms.excludeFromSite(project, args[0], args[1]); break
    }
    result = { ok: JSON.parse(mask(JSON.stringify(value ?? null))) }
  } catch (err) {
    result = { error: mask(String(err.message ?? err)) }
  }
  const logFile = join(project, 'fake-cli.log')
  const log = existsSync(logFile) ? readFileSync(logFile, 'utf-8').trim().split('\n').map((l) => JSON.parse(mask(l))) : []
  const requests = await (await fetch(`http://127.0.0.1:${port}/__log`)).json()
  requests.sort((a, b) => (a.path < b.path ? -1 : a.path > b.path ? 1 : 0))
  steps.push({ name, op, args, setup, result, log, requests, relayFile: read(join(project, '.quartz-gui', 'forms-relay.json')),
    targetsFile: read(join(project, '.quartz-gui', 'publish-targets.json')), web: tree(join(work, 'Web')), export: tree(join(work, 'Export')) })
}
const id = (n) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0')

// The command line's answer to `relay`, and the files it writes.
const relayFiles = (generation) => ({
  'send.php': '<?php // send',
  'config.php': "<?php return ['secret' => getenv('x')];",
  'config.generated.php': `<?php\nreturn [\n  'generation' => '${generation}',\n];\n`,
  'counters/.htaccess': '# quartz-forms relay: counters\nDeny from all\n',
  'counters/qf-probe.count': 'quartz-forms relay probe 0'
})
const relayAnswer = (extra = {}, generation = 'a1b2c3d4e5f60001') => ({
  relay: {
    stdout: JSON.stringify({ ok: true, hash: 'h-1', generation, siteOrigin: 'https://garten.example', forms: ['kontakt', 'umfrage'], recipients: ['TestKontakt'],
      missingRecipients: [], warnings: ['Hinweis: Captcha fehlt.'], written: ['send.php', 'config.php'], ...extra }),
    files: relayFiles(generation)
  }
})
const settings = (extra = {}) => ({ subdir: 'forms', from: 'formular@garten.example', allowedOrigins: ['https://Garten.example/'], subjectPrefix: '[Garten] ',
  mailer: 'mail', sendmailPath: '/usr/sbin/sendmail -t -i', counterDir: '', configReadable: false, envelopeSender: true, ...extra })

mkdirSync(join(plugin, 'dist'), { recursive: true })
copyFileSync(join(fixtures, 'fake-cli.mjs'), join(plugin, 'dist', 'cli.js'))
writeFileSync(join(plugin, 'package.json'), JSON.stringify({ name: 'quartz-forms', type: 'module', version: '0.6.0' }))

// A: nothing yet
await step('state of a new project', 'state', [], [{ scenario: relayAnswer() }])
await step('state when the command line refuses', 'state', [], [{ scenario: { relay: { stdout: JSON.stringify({ ok: false, error: 'Kein Formular sendet über das Relay.', warnings: ['w1', 3] }) } } }])
await step('upload without a target', 'upload', [null, null], [{ scenario: relayAnswer() }])
await step('remove what was never uploaded', 'remove', [])
await step('settings with a missing target', 'settings', [settings({ targetId: 'nope' })])
await step('upload to a missing target', 'upload', [null, null])

// B: targets and connections
const ssh = { kind: 'ssh', name: 'Hoster', host: '  Host.Example ', port: 22, username: 'web1', authMethod: 'agent' }
await step('state with targets', 'state', [], [
  { connection: ssh },
  { target: { name: 'Web', destination: { type: 'folder', path: '@W@/Web', deleteRemoved: false } } },
  { target: { name: 'Site rsync', connectionId: id(1), destination: { type: 'sftp', remotePath: '/srv/www/', transfer: 'rsync', deleteRemoved: true } } },
  { target: { name: 'Relay SFTP', connectionId: id(1), destination: { type: 'sftp', remotePath: '/srv/www', transfer: 'sftp', deleteRemoved: false } } },
  { target: { name: 'Hook', destination: { type: 'webhook' } } },
  { target: { name: 'FTP', connectionId: id(1), destination: { type: 'ftp', remotePath: 'htdocs', deleteRemoved: false } } }
])
await step('settings on the SFTP target', 'settings', [settings({ targetId: id(4) })])
await step('state names the rsync conflict', 'state', [])
await step('upload refused over it', 'upload', [null, null])
await step('exclude the folder from the site', 'exclude', [id(3), 'forms'])
await step('exclude it again', 'exclude', [id(3), 'forms'])
await step('exclude from no target', 'exclude', ['nope', 'forms'])
await step('excluding keeps nothing but what it knows', 'exclude', [id(3), 'andere'], [{ target: { id: id(3), name: 'Site rsync', connectionId: id(1), destination: { type: 'sftp', remotePath: '/srv/www/', transfer: 'rsync', deleteRemoved: true }, excludes: ['forms'], withDocuments: [id(2)] } }])
await step('state without the conflict', 'state', [])
await step('a subfolder below the relay is no conflict', 'state', [], [{ target: { id: id(3), name: 'Site rsync', connectionId: id(1), destination: { type: 'sftp', remotePath: '/srv/www/forms/x', transfer: 'rsync', deleteRemoved: true }, excludes: [] } }])
await step('excluded with a slash', 'state', [], [{ target: { id: id(3), name: 'Site rsync', connectionId: id(1), destination: { type: 'sftp', remotePath: '/srv', transfer: 'rsync', deleteRemoved: true }, excludes: ['www/forms/'] } }])

// C: uploads to the folder target
await step('settings on the folder', 'settings', [settings({ targetId: id(2) })])
await step('the command line names problems', 'upload', [null, null], [{ scenario: { relay: { stdout: JSON.stringify({ ok: false, error: 'Probleme', problems: ['Formular „kontakt“: kein Empfänger', 'zwei'] }) } } }])
await step('the command line says an error and warnings', 'upload', [null, null], [{ scenario: { relay: { stdout: JSON.stringify({ ok: false, error: 'kaputt', warnings: ['w1'] }) } } }])
await step('the command line says nothing', 'upload', [null, null], [{ scenario: { relay: { stderr: 'Absturz\n', exit: 1 } } }])
await step('recipients without an address', 'upload', [null, null], [{ scenario: relayAnswer({ missingRecipients: ['TestKontakt', 'Zwei'] }) }])
await step('the first upload', 'upload', [null, null], [{ scenario: relayAnswer() }])
await step('state after it', 'state', [])
await step('a new sender and readable config', 'settings', [settings({ targetId: id(2), from: 'neu@garten.example', configReadable: true })])
await step('state says both changed', 'state', [])
await step('an address stored', 'state', [], [{ secrets: { recipients: { TestKontakt: 'kontakt@garten.example' }, captchaSecret: 'cap' } }])
await step('settings with sendmail', 'settings', [settings({ targetId: id(2), mailer: 'sendmail', counterDir: ' /srv/counts ', envelopeSender: false, allowedOrigins: [] })])
await step('upload with sendmail, a counter folder and no envelope sender', 'upload', [null, null], [
  { write: ['@W@/Web/forms/counters/limit-1.count', '3'] }, { scenario: relayAnswer({}, 'a1b2c3d4e5f60002') }])
await step('state is current', 'state', [])
await step('a hash without one', 'upload', [null, null], [{ scenario: relayAnswer({ hash: 7, generation: 5, warnings: [] }) }])
await step('state keeps the last upload with a hash', 'state', [])
await step('another subfolder moves it', 'settings', [settings({ targetId: id(2), subdir: 'kontakt/relay' })])
await step('state says moved', 'state', [])
await step('a subfolder that is not one', 'settings', [settings({ targetId: id(2), subdir: '../x' })])
await step('upload into it', 'upload', [null, null], [{ scenario: relayAnswer() }])

// D: the probe after an upload
await step('back to forms', 'settings', [settings({ targetId: id(2) })])
await step('probe ok', 'upload', ['http://relay.test/ok/send.php', 'kontakt'], [{ scenario: relayAnswer() }])
await step('probe asks the form given', 'upload', ['http://relay.test/ok/send.php', 'umfrage'])
await step('probe takes the first form for an unknown one', 'upload', ['http://relay.test/ok/send.php', 'fremd'])
await step('probe of an old relay', 'upload', ['http://relay.test/ok-old/send.php', 'kontakt'])
await step('probe finds the counters', 'upload', ['http://relay.test/cnt-probe/send.php', null])
await step('origin refused, listed', 'upload', ['http://relay.test/origin/send.php', null])
await step('origin refused, not listed', 'upload', ['http://relay.test/origin/send.php', null], [{ scenario: relayAnswer({ siteOrigin: 'https://andere.example' }) }])
await step('origin refused, no site origin', 'upload', ['http://relay.test/origin/send.php', null], [{ scenario: relayAnswer({ siteOrigin: null }) }])
await step('origin list empty', 'settings', [settings({ targetId: id(2), allowedOrigins: [] })])
await step('origin refused, any', 'upload', ['http://relay.test/origin/send.php', null], [{ scenario: relayAnswer() }])
await step('settings with a counter folder', 'settings', [settings({ targetId: id(2), counterDir: '/srv/counts' })])
await step('no counters asked with it', 'upload', ['http://relay.test/cnt-probe/send.php', null])
await step('back to none', 'settings', [settings({ targetId: id(2) })])
await step('unreachable asks no counters', 'upload', ['http://127.0.0.1:@CLOSED@/send.php', null])
await step('a probe with no forms', 'upload', ['http://relay.test/ok/send.php', null], [{ scenario: relayAnswer({ forms: [] }) }])
await step('a failed upload probes nothing', 'upload', ['http://relay.test/ok/send.php', null], [{ scenario: relayAnswer() }, { rm: '@W@/Web/forms' }, { chmod: ['@W@/Web', '555'] }])

// E: export
await step('export with the stored secrets', 'export', ['@W@/Export'], [{ chmod: ['@W@/Web', '755'] }])
await step('export over an earlier export', 'export', ['@W@/Export'])
await step('settings without a sender', 'settings', [settings({ targetId: id(2), from: '  ' })])
await step('export with placeholders', 'export', ['@W@/Export'], [{ rm: '@W@/Export' }])
await step('export refused', 'export', ['@W@/Export'], [{ scenario: { relay: { stdout: JSON.stringify({ ok: false, error: 'nein', warnings: ['w'] }) } } }])

// F: removing
await step('back to a sender', 'settings', [settings({ targetId: id(2) })])
await step('upload before removing', 'upload', [null, null], [{ scenario: relayAnswer() }])
await step('the folder target moved', 'remove', [], [{ target: { id: id(2), name: 'Web', destination: { type: 'folder', path: '@W@/Web2', deleteRemoved: false } } }])
await step('remove our own', 'remove', [], [{ target: { id: id(2), name: 'Web', destination: { type: 'folder', path: '@W@/Web', deleteRemoved: false } } }])
await step('state after removing', 'state', [])
await step('remove again', 'remove', [])
await step('upload, then the server keeps the counters', 'upload', [null, null])
await step('remove with counters left', 'remove', [], [{ chmod: ['@W@/Web/forms/counters', '555'] }])
await step('remove with a counter folder named', 'remove', [], [{ chmod: ['@W@/Web/forms/counters', '755'] },
  { write: ['@W@/Gärten-Ü/.quartz-gui/forms-relay.json', JSON.stringify({ settings: settings({ targetId: id(2) }), lastUpload: { at: '2026-11-01T00:00:00.000Z', hash: 'h', targetId: id(2), location: `folder||@W@/Web|forms`, counterDir: '/srv/counts' } })] },
  { write: ['@W@/Web/forms/send.php', 'x'] }, { chmod: ['@W@/Web/forms/counters', '555'] }])
const lastUpload = (targetId, location, extra = {}) => ({ write: ['@W@/Gärten-Ü/.quartz-gui/forms-relay.json', JSON.stringify({ settings: settings({ targetId }), lastUpload: { at: '2026-11-01T00:00:00.000Z', hash: 'h', targetId, location, ...extra } })] })
await step('remove from a target that is gone', 'remove', [], [{ chmod: ['@W@/Web/forms/counters', '755'] }, lastUpload('nope', 'folder||@W@/Web|forms')])
await step('remove after the SFTP folder changed', 'remove', [], [lastUpload(id(4), `sftp|${id(1)}|/srv/alt|forms/x`)])
await step('remove after the login changed', 'remove', [], [{ connection: { kind: 'ssh', name: 'Alter Zugang', host: 'old.example', port: 22, username: 'u', authMethod: 'agent' } },
  lastUpload(id(4), `sftp|${id(7)}|/srv/www|forms`)])
await step('remove after the login went elsewhere', 'remove', [], [lastUpload(id(4), `sftp|${id(1)}|/srv/www|forms`, { server: 'web1@old.example' })])
await step('remove with the login deleted', 'remove', [], [{ deleteConnection: id(1) }, lastUpload(id(4), `sftp|${id(1)}|/srv/www|forms`, { server: 'web1@host.example' })])
await step('state of an FTP upload with another operator', 'state', [], [lastUpload(id(6), `ftp|${id(1)}|htdocs|forms`, { configReadable: false, operator: 'x' })])

// G: what the steps above leave open (at the end, so the ids above stay)
await step('a GitHub login names no server', 'remove', [], [{ connection: { kind: 'github', name: 'GH', secret: 't' } },
  { target: { name: 'FTP über GitHub', connectionId: id(8), destination: { type: 'ftp', remotePath: 'h', deleteRemoved: false } } },
  lastUpload(id(9), `ftp|${id(8)}|h|forms`, { server: 'web1@host.example' })])
await step('state with the server changed', 'state', [], [lastUpload(id(4), `sftp|${id(1)}|/srv/www|forms`, { server: 'web1@old.example' })])
await step('state hides removedAt beside an upload', 'state', [], [{ write: ['@W@/Gärten-Ü/.quartz-gui/forms-relay.json', JSON.stringify({ settings: settings({ targetId: id(2) }), lastUpload: { at: '2026-11-01T00:00:00.000Z', hash: 'h', targetId: id(2), location: 'folder||@W@/Web|forms' }, removedAt: '2026-11-02T00:00:00.000Z' })] }])
await step('no conflict over SFTP or another login', 'state', [], [{ connection: { kind: 'ssh', name: 'Zweiter', host: 'zwei.example', port: 22, username: 'z', authMethod: 'agent' } },
  { target: { name: 'Relay 2', connectionId: id(10), destination: { type: 'sftp', remotePath: '/srv/x', transfer: 'sftp', deleteRemoved: false } } },
  { target: { name: 'Site SFTP', connectionId: id(10), destination: { type: 'sftp', remotePath: '/srv', transfer: 'sftp', deleteRemoved: true } } },
  { target: { name: 'Site rsync anderer Zugang', connectionId: id(7), destination: { type: 'sftp', remotePath: '/srv', transfer: 'rsync', deleteRemoved: true } } },
  { write: ['@W@/Gärten-Ü/.quartz-gui/forms-relay.json', JSON.stringify({ settings: settings({ targetId: id(11) }) })] }])
await step('the folder again', 'settings', [settings({ targetId: id(2) })])
await step('unreachable, the counters not asked', 'upload', ['http://relay.test/half/send.php', null], [{ scenario: relayAnswer() }])
await step('remove with nothing left', 'remove', [], [{ rm: '@W@/Web/forms/send.php' }, { rm: '@W@/Web/forms/config.php' }, { rm: '@W@/Web/forms/config.generated.php' }])
await step('upload for a foreign relay', 'upload', [null, null])
await step('remove a foreign relay', 'remove', [], [{ write: ['@W@/Web/forms/config.generated.php', "<?php\nreturn [\n  'generation' => 'ffffffffffffffff',\n];\n"] }])

server.kill()
mkdirSync(fixtures, { recursive: true })
writeFileSync(join(fixtures, 'relay-steps.json'), JSON.stringify({ temp, steps }, null, 1) + '\n')
rmSync(work, { recursive: true, force: true })
console.log(`${steps.length} Schritte`)
process.exit(0)
