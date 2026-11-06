#!/usr/bin/env node
// Golden file for Connections, made by QuartzControl's own connectionsService.ts with its real
// jsonStore. Stand-ins: Electron's `app.getPath('userData')` answers a scratch profile, and
// `safeStorage` "encrypts" as `enc:<text>`, so the golden can say which secret is stored; ids,
// random bytes and the clock count up. Each step is one call, its answer, and the state: the two
// files as QuartzHub writes them (QuartzControl's text with `encryptedSecret`/`encrypted` exchanged
// for `secretInKeychain: true` in the same place) and the secrets by Keychain account
// (`connection:<id>`, `relay:<projectId>`). A file QuartzControl wrote only because a read found
// none is marked `writtenOnRead`: QuartzHub's reads write nothing.
//
// Also the input rules: QuartzControl's `saveConnectionInput` zod schema over a list of inputs.
//
//   Runtime/node/bin/node scripts/connections-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'connections')
const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-connections-golden-')))
const profile = join(work, 'Gärten-Ü profile')
globalThis.__profile = profile
globalThis.__ids = 0
globalThis.__bytes = 0

const stubs = {
  ...commonStubs,
  electron: `export const app = { getPath: () => globalThis.__profile }
export const safeStorage = {
  isEncryptionAvailable: () => true,
  encryptString: (s) => Buffer.from('enc:' + s, 'utf8'),
  decryptString: (b) => { const t = b.toString('utf8'); if (!t.startsWith('enc:')) throw new Error('bad'); return t.slice(4) }
}`,
  // jsonStore names its temp files with randomUUID too; only the service's own calls count.
  crypto: `import * as real from 'node:crypto'
export const createHmac = real.createHmac
export function randomUUID() {
  if ((new Error().stack ?? '').includes('writeJsonFile')) return real.randomUUID()
  globalThis.__ids += 1
  return '00000000-0000-4000-8000-' + String(globalThis.__ids).padStart(12, '0')
}
export function randomBytes(n) { globalThis.__bytes += 1; return Buffer.alloc(n, globalThis.__bytes) }`
}
const service = await loadQuartzControl(control, 'electron/main/services/connectionsService.ts', stubs)
const schemas = await loadQuartzControl(control, 'electron/main/ipc/schemas.ts', {})

const RealDate = Date
let now = RealDate.parse('2026-11-06T10:00:00.000Z')
globalThis.Date = class extends RealDate {
  constructor(...args) { if (args.length === 0) super(now); else super(...args) }
  static now() { return now }
}

const connectionsFile = join(profile, 'connections.json')
const relayFile = join(profile, 'relay-secrets.json')
const decode = (b64) => Buffer.from(b64, 'base64').toString('utf8').replace(/^enc:/, '')

// QuartzHub's form of a QuartzControl file, and the secrets it holds.
function hubForm(value, field) {
  const secrets = {}
  const swap = (entry, account) => {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) return entry
    const copy = {}
    for (const [key, v] of Object.entries(entry)) {
      if (key === field) {
        if (v) { copy.secretInKeychain = true; secrets[account(entry)] = decode(v) }
      } else copy[key] = v
    }
    return copy
  }
  if (Array.isArray(value)) return { value: value.map((e) => swap(e, (x) => `connection:${x.id}`)), secrets }
  if (value && typeof value === 'object') {
    return { value: Object.fromEntries(Object.entries(value).map(([id, e]) => [id, swap(e, () => `relay:${id}`)])), secrets }
  }
  return { value, secrets }
}

function state() {
  const read = (file, field) => {
    if (!existsSync(file)) return { text: null, secrets: {} }
    const text = readFileSync(file, 'utf-8')
    let parsed
    try { parsed = JSON.parse(text) } catch { return { text, secrets: {} } }
    // A file the store did not write (a seed) stays as it is.
    if (JSON.stringify(parsed, null, 2) !== text) return { text, secrets: {} }
    const { value, secrets } = hubForm(parsed, field)
    return { text: JSON.stringify(value, null, 2), secrets }
  }
  const c = read(connectionsFile, 'encryptedSecret')
  const r = read(relayFile, 'encrypted')
  return { connections: c.text, relaySecrets: r.text, secrets: { ...c.secrets, ...r.secrets } }
}

const steps = []
let pendingReset = false
async function step(name, op, args, fn, setup) {
  if (setup) setup()
  // What the Swift test has to set up before the same call: a fresh profile, a seeded file, the clock.
  const before = { reset: pendingReset, now: new RealDate(now).toISOString() }
  if (setup && existsSync(connectionsFile)) before.seed = readFileSync(connectionsFile, 'utf-8')
  pendingReset = false
  const existedBefore = existsSync(connectionsFile)
  let result
  try {
    result = { ok: (await fn()) ?? null }
  } catch (err) {
    result = { error: JSON.parse(err.message) }
  }
  const s = state()
  steps.push({ name, op, args, before, result, ...s, writtenOnRead: !existedBefore && existsSync(connectionsFile) && op.startsWith('read') })
}
const id = (n) => '00000000-0000-4000-8000-' + String(n).padStart(12, '0')
const reset = () => { rmSync(profile, { recursive: true, force: true }); globalThis.__ids = 0; globalThis.__bytes = 0; pendingReset = true }

// ── connections ──────────────────────────────────────────────────────────────────────────────
reset()
await step('list without a file', 'read:list', [], () => service.listConnections())
await step('new ssh with a password', 'save', [{ kind: 'ssh', name: 'Server Ü', host: '  DEBIAN.LOCAL ', port: 22, username: 'qchost', authMethod: 'password', secret: 'pässwort' }],
  () => service.saveConnection({ kind: 'ssh', name: 'Server Ü', host: '  DEBIAN.LOCAL ', port: 22, username: 'qchost', authMethod: 'password', secret: 'pässwort' }))
await step('new ftp without a secret', 'save', [{ kind: 'ftp', name: 'FTP', host: 'ftp.example.com', port: 21, username: 'u', secure: true }],
  () => service.saveConnection({ kind: 'ftp', name: 'FTP', host: 'ftp.example.com', port: 21, username: 'u', secure: true }))
await step('new github without a token', 'save', [{ kind: 'github', name: 'GitHub leer' }], () => service.saveConnection({ kind: 'github', name: 'GitHub leer' }))
await step('new github with a token', 'save', [{ kind: 'github', name: 'GitHub', login: 'boxi-os', secret: 'ghp_token' }],
  () => service.saveConnection({ kind: 'github', name: 'GitHub', login: 'boxi-os', secret: 'ghp_token' }))
await step('new webhook', 'save', [{ kind: 'webhook', name: 'Netlify', secret: 'https://API.Netlify.com:443/build_hooks/5f1a2b3c4d5e6f7a?x=1' }],
  () => service.saveConnection({ kind: 'webhook', name: 'Netlify', secret: 'https://API.Netlify.com:443/build_hooks/5f1a2b3c4d5e6f7a?x=1' }))
await step('list', 'read:list', [], () => service.listConnections())
await step('get one', 'read:get', [id(1)], () => service.getConnection(id(1)))
await step('get none', 'read:get', [id(99)], () => service.getConnection(id(99)))
await step('secret of ssh', 'read:secret', [id(1)], () => service.getSecret(id(1)))
await step('secret of ftp (none)', 'read:secret', [id(2)], () => service.getSecret(id(2)))
await step('secret of unknown', 'read:secret', [id(99)], () => service.getSecret(id(99)))
await step('github token skips the one without', 'read:githubToken', [], () => service.getGithubToken())
const sshEdit = (extra) => ({ id: id(1), kind: 'ssh', name: 'Server Ü', host: 'debian.local', port: 2222, username: 'qchost', authMethod: 'password', ...extra })
await step('edit ssh, secret empty keeps', 'save', [sshEdit({ secret: '' })], () => service.saveConnection(sshEdit({ secret: '' })))
await step('edit ssh, secret absent keeps', 'save', [sshEdit({})], () => service.saveConnection(sshEdit({})))
await step('edit ssh, new password', 'save', [sshEdit({ secret: 'neu' })], () => service.saveConnection(sshEdit({ secret: 'neu' })))
await step('remember host key', 'save:hostKey', [id(1), { fingerprint: 'SHA256:abc', blob: 'AAAA', type: 'ssh-ed25519' }],
  () => service.rememberHostKey(id(1), { fingerprint: 'SHA256:abc', blob: 'AAAA', type: 'ssh-ed25519' }))
await step('edit ssh keeps the host key', 'save', [sshEdit({ secret: '' })], () => service.saveConnection(sshEdit({ secret: '' })))
await step('edit ssh, method changed, empty clears', 'save', [sshEdit({ authMethod: 'privateKey', secret: '' })],
  () => service.saveConnection(sshEdit({ authMethod: 'privateKey', secret: '' })))
await step('edit ssh, pasted key', 'save', [sshEdit({ authMethod: 'privateKey', secret: '-----BEGIN KEY-----' })],
  () => service.saveConnection(sshEdit({ authMethod: 'privateKey', secret: '-----BEGIN KEY-----' })))
await step('edit ssh, key file without secret clears', 'save', [sshEdit({ authMethod: 'privateKey', keyPath: '/Users/x/.ssh/id_ed25519' })],
  () => service.saveConnection(sshEdit({ authMethod: 'privateKey', keyPath: '/Users/x/.ssh/id_ed25519' })))
await step('edit ssh, key file with passphrase', 'save', [sshEdit({ authMethod: 'privateKey', keyPath: '/Users/x/.ssh/id_ed25519', secret: 'phrase' })],
  () => service.saveConnection(sshEdit({ authMethod: 'privateKey', keyPath: '/Users/x/.ssh/id_ed25519', secret: 'phrase' })))
await step('edit ssh, agent keeps nothing', 'save', [sshEdit({ authMethod: 'agent', secret: '' })],
  () => service.saveConnection(sshEdit({ authMethod: 'agent', secret: '' })))
await step('edit ssh, agent with a secret', 'save', [sshEdit({ authMethod: 'agent', secret: 'x' })],
  () => service.saveConnection(sshEdit({ authMethod: 'agent', secret: 'x' })))
await step('edit ssh, password again, absent fields', 'save', [{ id: id(1), kind: 'ssh', name: 'Kurz', host: 'h', authMethod: 'password', secret: 'pw' }],
  () => service.saveConnection({ id: id(1), kind: 'ssh', name: 'Kurz', host: 'h', authMethod: 'password', secret: 'pw' }))
await step('forget host key', 'save:forget', [id(1)], () => service.forgetHostKey(id(1)))
await step('forget host key again (none)', 'save:forget', [id(1)], () => service.forgetHostKey(id(1)))
await step('remember on unknown', 'save:hostKey', [id(99), { fingerprint: 'x', blob: '', type: '' }], () => service.rememberHostKey(id(99), { fingerprint: 'x', blob: '', type: '' }))
const hook = (extra) => ({ id: id(5), kind: 'webhook', name: 'Netlify', ...extra })
await step('edit webhook, empty keeps url and origin', 'save', [hook({ secret: '' })], () => service.saveConnection(hook({ secret: '' })))
await step('edit webhook, new url', 'save', [hook({ secret: 'https://hooks.example.org/x/y/zzzzzzzzzz' })],
  () => service.saveConnection(hook({ secret: 'https://hooks.example.org/x/y/zzzzzzzzzz' })))
await step('edit ftp, unknown id saves new', 'save', [{ id: id(77), kind: 'ftp', name: 'Neu', host: 'f', port: 990, username: '', secure: false, secret: 'p' }],
  () => service.saveConnection({ id: id(77), kind: 'ftp', name: 'Neu', host: 'f', port: 990, username: '', secure: false, secret: 'p' }))
await step('edit github to another kind of name', 'save', [{ id: id(4), kind: 'github', name: 'GitHub 2' }],
  () => service.saveConnection({ id: id(4), kind: 'github', name: 'GitHub 2' }))
await step('delete ftp', 'save:delete', [id(2)], () => service.deleteConnection(id(2)))
await step('delete one with a secret', 'save:delete', [id(6)], () => service.deleteConnection(id(6)))
await step('delete unknown', 'save:delete', [id(99)], () => service.deleteConnection(id(99)))
await step('list at the end', 'read:list', [], () => service.listConnections())

// Files that are not a list.
reset()
await step('an object instead of a list', 'read:list', [], () => service.listConnections(), () => {
  mkdirSync(profile, { recursive: true }); writeFileSync(connectionsFile, '{"a":1}')
})
await step('save over the object', 'save', [{ kind: 'github', name: 'G', secret: 't' }], () => service.saveConnection({ kind: 'github', name: 'G', secret: 't' }))
reset()
await step('unreadable store', 'read:list', [], () => service.listConnections(), () => {
  mkdirSync(profile, { recursive: true }); writeFileSync(connectionsFile, '[{"id":')
})
reset()
await step('entries with fields this version does not know', 'read:list', [], () => service.listConnections(), () => {
  mkdirSync(profile, { recursive: true })
  writeFileSync(connectionsFile, JSON.stringify([{ id: id(1), kind: 'ssh', name: 'S', extra: 1, host: 'h' }, { id: id(2), kind: 'ftp', name: 'F' }, { id: id(3), kind: 'webhook', name: 'W', login: 'https://x' }], null, 2))
})
await step('a save drops what it does not know', 'save', [{ id: id(1), kind: 'ssh', name: 'S', host: 'h', authMethod: 'agent' }],
  () => service.saveConnection({ id: id(1), kind: 'ssh', name: 'S', host: 'h', authMethod: 'agent' }))

// ── relay secrets ────────────────────────────────────────────────────────────────────────────
reset()
const P = 'project-ä', Q = 'project-q'
await step('relay info without a file', 'read:relayInfo', [P], () => service.getRelaySecretInfo(P).then(({ storage, ...rest }) => rest))
await step('relay save recipients', 'relay', [P, { recipients: { kontakt: ' a@example.org ', leer: '   ', '2': 'zwei@example.org' } }],
  () => service.saveRelaySecrets(P, { recipients: { kontakt: ' a@example.org ', leer: '   ', '2': 'zwei@example.org' } }))
await step('relay save captcha secret', 'relay', [P, { captchaSecret: ' cap ' }], () => service.saveRelaySecrets(P, { captchaSecret: ' cap ' }))
await step('relay blank captcha secret leaves it', 'relay', [P, { captchaSecret: '  ' }], () => service.saveRelaySecrets(P, { captchaSecret: '  ' }))
await step('relay form captcha secrets', 'relay', [P, { captchaSecrets: { plain: 's1', other: 's2', gone: null } }],
  () => service.saveRelaySecrets(P, { captchaSecrets: { plain: 's1', other: 's2', gone: null } }))
await step('relay move a form secret', 'relay', [P, { moveCaptchaSecret: { from: 'plain', to: 'plainx' } }],
  () => service.saveRelaySecrets(P, { moveCaptchaSecret: { from: 'plain', to: 'plainx' } }))
await step('relay move without a secret writes nothing', 'relay', [P, { moveCaptchaSecret: { from: 'nobody', to: 'x' } }],
  () => service.saveRelaySecrets(P, { moveCaptchaSecret: { from: 'nobody', to: 'x' } }), () => { now += 60_000 })
await step('relay move onto its own name', 'relay', [P, { moveCaptchaSecret: { from: 'plainx', to: 'plainx' } }],
  () => service.saveRelaySecrets(P, { moveCaptchaSecret: { from: 'plainx', to: 'plainx' } }))
await step('relay move onto an existing name', 'relay', [P, { moveCaptchaSecret: { from: 'other', to: 'plainx' }, recipients: { b: 'b@example.org' } }],
  () => service.saveRelaySecrets(P, { moveCaptchaSecret: { from: 'other', to: 'plainx' }, recipients: { b: 'b@example.org' } }))
await step('relay remove a recipient and the captcha secret', 'relay', [P, { recipients: { kontakt: null }, captchaSecret: null }],
  () => service.saveRelaySecrets(P, { recipients: { kontakt: null }, captchaSecret: null }))
await step('relay renew the secret', 'relay', [P, { renewSecret: true }], () => service.saveRelaySecrets(P, { renewSecret: true }), () => { now += 60_000 })
await step('relay info', 'read:relayInfo', [P], () => service.getRelaySecretInfo(P).then(({ storage, ...rest }) => rest))
await step('relay secrets', 'read:relaySecrets', [P], () => service.getRelaySecrets(P))
await step('relay second project, renew on first save', 'relay', [Q, { renewSecret: true }], () => service.saveRelaySecrets(Q, { renewSecret: true }))
await step('projects with relay secrets', 'read:relayProjects', [], () => service.projectsWithRelaySecrets().then((s) => [...s].sort()))
await step('relay delete', 'relay:delete', [P], () => service.deleteRelaySecrets(P))
await step('relay delete unknown', 'relay:delete', ['nobody'], () => service.deleteRelaySecrets('nobody'))
await step('relay secrets of none', 'read:relaySecrets', [P], () => service.getRelaySecrets(P))

// ── the input rules ──────────────────────────────────────────────────────────────────────────
const long = (n) => 'x'.repeat(n)
const inputs = [
  { kind: 'ssh', name: 'S', host: 'h' }, { kind: 'ssh', name: '', host: 'h' }, { kind: 'ssh', name: long(200), host: 'h' },
  { kind: 'ssh', name: long(201), host: 'h' }, { kind: 'ssh', name: 'Ü'.repeat(200), host: 'h' }, { kind: 'ssh', name: '😀'.repeat(100), host: 'h' },
  { kind: 'ssh', name: '😀'.repeat(101), host: 'h' }, { kind: 'ssh', name: 'S', host: '   ' }, { kind: 'ssh', name: 'S', host: ` ${long(255)} ` },
  { kind: 'ssh', name: 'S', host: long(256) }, { kind: 'ssh', name: 'S', host: 'h', port: 0 }, { kind: 'ssh', name: 'S', host: 'h', port: 65535 },
  { kind: 'ssh', name: 'S', host: 'h', port: 65536 }, { kind: 'ssh', name: 'S', host: 'h', username: long(255) }, { kind: 'ssh', name: 'S', host: 'h', username: long(256) },
  { kind: 'ssh', name: 'S', host: 'h', keyPath: '/a/b' }, { kind: 'ssh', name: 'S', host: 'h', keyPath: 'a/b' }, { kind: 'ssh', name: 'S', host: 'h', keyPath: '' },
  { kind: 'ssh', name: 'S', host: 'h', keyPath: '/' + long(4095) }, { kind: 'ssh', name: 'S', host: 'h', keyPath: '/' + long(4096) },
  { kind: 'github', name: 'G', login: long(255) }, { kind: 'github', name: 'G', login: long(256) }, { kind: 'github', name: 'G', secret: long(100000) },
  { kind: 'github', name: 'G', secret: long(100001) }, { kind: 'webhook', name: 'W' }, { kind: 'webhook', name: 'W', secret: '' },
  { kind: 'webhook', name: 'W', secret: '', id: id(1) }, { kind: 'webhook', name: 'W', secret: 'http://example.com/x' },
  { kind: 'webhook', name: 'W', secret: 'https://example.com/x' }, { kind: 'webhook', name: 'W', secret: 'HTTPS://example.com' },
  { kind: 'webhook', name: 'W', secret: 'example.com/hook' }, { kind: 'webhook', name: 'W', secret: 'mailto:x@example.com' },
  { kind: 'webhook', name: 'W', secret: 'https://' }, { kind: 'webhook', name: 'W', secret: ' https://example.com ' },
  { kind: 'ftp', name: 'F', host: 'f', secure: true }, { kind: 'ftp', name: 'F', host: 'f', port: 21 }
]
const rules = inputs.map((input) => ({ input, valid: schemas.saveConnectionInput.safeParse(input).success }))

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'steps.json'), JSON.stringify({ steps, rules }, null, 1) + '\n')
rmSync(work, { recursive: true, force: true })
console.log(`${steps.length} steps, ${rules.length} rules`)
