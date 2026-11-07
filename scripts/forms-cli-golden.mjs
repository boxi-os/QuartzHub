#!/usr/bin/env node
// Golden file for FormsCLI, made by QuartzControl's own formsService.ts (check, texts, inspectKey,
// importKeyFile) with its real runCommand, pluginSchemaService and templatePackage/shared. The
// plugin's command line is Fixtures/forms/fake-cli.mjs, which answers per step what the step's
// scenario says and logs its arguments and QF_* variables. Stand-ins: mainT (key and arguments),
// mainLanguage ("@LANG@", the app's language in QuartzHub), electron. Each step is its setup, one
// call, its answer (or the thrown error as String(err)), the log lines of that call, and the key
// folder afterwards.
//
//   Runtime/node/bin/node scripts/forms-cli-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { chmodSync, copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, symlinkSync, writeFileSync, appendFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const fixtures = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'forms')
const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-forms-golden-')))
const W = (p) => p.split('@W@').join(work)
const mask = (text) => text.split(work).join('@W@').split(`.tmp-${process.pid}`).join('.tmp-@PID@')
const project = join(work, 'Gärten-Ü')
process.env.PATH = `${dirname(process.execPath)}:${process.env.PATH}`

const stubs = {
  ...commonStubs,
  '../i18n': `${commonStubs['../i18n']}\nexport function mainLanguage() { return '@LANG@' }`,
  electron: 'export const net = {}',
  './connectionsService': 'export async function claimLegacyTargets() { return [] }',
  './deploy': 'export async function runDirectoryUpload() { throw new Error("no deploy here") }'
}
const forms = await loadQuartzControl(control, 'electron/main/services/formsService.ts', stubs)
const source = 'github:boxi-os/quartz-forms'
const plugin = join(project, '.quartz', 'plugins', 'quartz-forms')

function keys() {
  const dir = join(project, 'quartz-forms', 'keys')
  if (!existsSync(dir)) return null
  const found = {}
  for (const name of readdirSync(dir).sort()) {
    const info = lstatSync(join(dir, name))
    const text = info.isFile() ? readFileSync(join(dir, name), 'utf-8') : null
    found[name] = text === null ? (info.isSymbolicLink() ? 'link' : 'folder') : text.length > 2000 ? `${text.length}: ${text.slice(0, 60)}` : text
  }
  return found
}

const steps = []
async function step(name, op, args, setup = []) {
  for (const a of setup) {
    if (a.write) { mkdirSync(dirname(W(a.write[0])), { recursive: true }); writeFileSync(W(a.write[0]), a.write[1]) }
    if (a.fill) writeFileSync(W(a.fill[0]), a.fill[1].padEnd(a.fill[2], 'x'))
    if (a.mkdir) mkdirSync(W(a.mkdir), { recursive: true })
    if (a.rm) rmSync(W(a.rm), { recursive: true, force: true })
    if (a.chmod) chmodSync(W(a.chmod[0]), parseInt(a.chmod[1], 8))
    if (a.symlink) { mkdirSync(dirname(W(a.symlink[1])), { recursive: true }); symlinkSync(W(a.symlink[0]), W(a.symlink[1])) }
    if (a.cli !== undefined) {
      mkdirSync(join(plugin, 'dist'), { recursive: true })
      copyFileSync(join(fixtures, 'fake-cli.mjs'), join(plugin, 'dist', 'cli.js'))
      if (a.cli) appendFileSync(join(plugin, 'dist', 'cli.js'), a.cli)
    }
    if (a.version !== undefined) mkdirSync(plugin, { recursive: true })
    if (a.version !== undefined) writeFileSync(join(plugin, 'package.json'), JSON.stringify({ name: 'quartz-forms', type: 'module', version: a.version }))
    if (a.scenario) writeFileSync(join(project, 'fake-cli.json'), JSON.stringify(a.scenario))
  }
  rmSync(join(project, 'fake-cli.log'), { force: true })
  let result
  try {
    let value
    switch (op) {
      case 'check': value = await forms.check(project, source); break
      case 'texts': value = await forms.texts(project, source); break
      case 'inspectKey': value = await forms.inspectKey(project, source, args[0]); break
      case 'importKey': value = await forms.importKeyFile(project, W(args[0]), args[1], args[2]); break
    }
    result = { ok: JSON.parse(mask(JSON.stringify(value ?? null))) }
  } catch (err) {
    result = { error: mask(String(err)) }
  }
  const logFile = join(project, 'fake-cli.log')
  const log = existsSync(logFile) ? readFileSync(logFile, 'utf-8').trim().split('\n').map((l) => JSON.parse(mask(l))) : []
  steps.push({ name, op, args, setup, result, log, keys: JSON.parse(mask(JSON.stringify(keys()))) })
}

const ok = (o) => JSON.stringify({ ok: true, ...o })
const longOutput = `Zeile mit Ümlauten ${'ä'.repeat(420)}`

// check
mkdirSync(project, { recursive: true })
await step('no plugin at all', 'check', [])
await step('a plugin without the command line', 'check', [], [{ version: '0.1.2' }])
await step('0.2.0: no --lang', 'check', [], [{ cli: '' }, { version: '0.2.0' },
  { scenario: { check: { stdout: ok({ problems: ['Formular „a“ fehlt', 3, null], hints: ['h1'], keys: [{ name: 'k', fingerprint: 'AB12', userIds: ['A <a@b>', 7], expires: '2027-01-01', problem: 'p', notice: 'n', extra: 1 }, 'kein Objekt', null, { name: 5, problem: false }] }) } } }])
await step('0.3.0: --lang', 'check', [], [{ version: '0.3.0' }])
await step('0.3.0-beta.1 is older than 0.3.0', 'check', [], [{ version: '0.3.0-beta.1' }])
await step('0.10.0 is newer', 'check', [], [{ version: '0.10.0' }])
await step('a version that is not one', 'check', [], [{ version: 'v0.6' }])
await step('a version that is no string', 'check', [], [{ write: ['@W@/Gärten-Ü/.quartz/plugins/quartz-forms/package.json', '{"version":6}'] }])
await step('a package.json that cannot be read', 'check', [], [{ rm: '@W@/Gärten-Ü/.quartz/plugins/quartz-forms/package.json' }, { mkdir: '@W@/Gärten-Ü/.quartz/plugins/quartz-forms/package.json' }])
await step('lists missing', 'check', [], [{ rm: '@W@/Gärten-Ü/.quartz/plugins/quartz-forms/package.json' }, { version: '0.6.0' }, { scenario: { check: { stdout: ok({ problems: 'x' }) } } }])
await step('several lines, the last one counts', 'check', [], [{ scenario: { check: { stdout: `Hinweis\n${ok({ problems: ['p'] })}\n\n  ` } } }])
await step('a line before the JSON on stdout only', 'check', [], [{ scenario: { check: { stdout: `${ok({ problems: ['früh'] })}\nnoch eine Zeile` } } }])
await step('not JSON, with stderr', 'check', [], [{ scenario: { check: { stderr: 'Warnung: veraltet\n', stdout: 'kein JSON\n', exit: 1 } } }])
await step('not JSON, long', 'check', [], [{ scenario: { check: { stdout: longOutput } } }])
await step('nothing at all', 'check', [], [{ scenario: { check: { exit: 2 } } }])
await step('ok false with an error', 'check', [], [{ scenario: { check: { stdout: JSON.stringify({ ok: false, error: 'Die Konfiguration ist kaputt.' }), exit: 1 } } }])
await step('ok false without one', 'check', [], [{ scenario: { check: { stdout: JSON.stringify({ ok: false, error: 3 }), stderr: 'E' } } }])
await step('ok as a string', 'check', [], [{ scenario: { check: { stdout: JSON.stringify({ ok: 'true' }) } } }])
await step('JSON that is no object', 'check', [], [{ scenario: { check: { stdout: '[1,2]' } } }])
await step('JSON null', 'check', [], [{ scenario: { check: { stdout: 'null' } } }])
await step('a failed exit with ok true', 'check', [], [{ scenario: { check: { stdout: ok({ hints: ['trotzdem'] }), exit: 3 } } }])

// texts
await step('texts', 'texts', [], [{ scenario: { texts: { stdout: ok({ locales: { de: { a: 'Ä', b: 2, c: 'C' }, en: { a: 'A' }, fr: { x: 1 }, nl: 'nein', it: null } }) } } }])
await step('texts again from the cache', 'texts', [], [{ scenario: { texts: { stdout: ok({ locales: { de: { a: 'neu' } } }) } } }])
await step('a new command line asks again', 'texts', [], [{ cli: '// 2\n' }])
await step('no locale with a string', 'texts', [], [{ cli: '// 3\n' }, { scenario: { texts: { stdout: ok({ locales: { de: { a: 1 } }, extra: 'ü' }) } } }])
await step('unavailable is not kept', 'texts', [], [{ scenario: { texts: { stdout: ok({ locales: { de: { a: 'wieder da' } } }) } } }])
await step('locales not an object', 'texts', [], [{ cli: '// 4\n' }, { scenario: { texts: { stdout: ok({ locales: 'de' }) } } }])
await step('texts refused', 'texts', [], [{ cli: '// 5\n' }, { scenario: { texts: { stdout: JSON.stringify({ ok: false, error: 'unknown command "texts"' }) } } }])

// inspectKey
const armored = '-----BEGIN PGP PUBLIC KEY BLOCK-----\n\nxsDN\n-----END PGP PUBLIC KEY BLOCK-----'
await step('a key', 'inspectKey', [`Vorher\n${armored}\nNachher`], [{ scenario: { key: { stdout: ok({ key: { name: '', fingerprint: 'DDFD 7A73', userIds: ['Boxi <b@x>'] }, armored }) } } }])
await step('a key without armored', 'inspectKey', ['x'], [{ scenario: { key: { stdout: ok({ key: { fingerprint: '', userIds: [], problem: 'Kein öffentlicher Schlüssel.' }, armored: 5 }) } } }])
await step('a key answer without key', 'inspectKey', ['x'], [{ scenario: { key: { stdout: ok({}) } } }])
await step('a key refused', 'inspectKey', ['x'], [{ scenario: { key: { stdout: JSON.stringify({ ok: false, error: 'kaputt' }) } } }])
await step('a key with no command line', 'inspectKey', ['x'], [{ rm: '@W@/Gärten-Ü/.quartz/plugins/quartz-forms/dist/cli.js' }])

// importKeyFile
const pub = `${armored}\n`
await step('a name that is not one', 'importKey', ['@W@/k.asc', 'a b', false])
await step('a name too long', 'importKey', ['@W@/k.asc', 'x'.repeat(65), false])
await step('a name of 64', 'importKey', ['@W@/k64.asc', 'y'.repeat(64), false], [{ write: ['@W@/k64.asc', `${armored}\n`] }])
await step('a name with an umlaut', 'importKey', ['@W@/k.asc', 'schlüssel', false])
await step('no such file', 'importKey', ['@W@/fehlt.asc', 'k', false])
await step('a folder', 'importKey', ['@W@/ordner', 'k', false], [{ mkdir: '@W@/ordner' }])
await step('too large', 'importKey', ['@W@/gross.asc', 'k', false], [{ fill: ['@W@/gross.asc', '', 256 * 1024 + 1] }])
await step('exactly the limit', 'importKey', ['@W@/grenze.asc', 'k', false], [{ fill: ['@W@/grenze.asc', pub, 256 * 1024] }])
await step('a private key', 'importKey', ['@W@/privat.asc', 'k', false], [{ write: ['@W@/privat.asc', `${pub}-----BEGIN PGP PRIVATE KEY BLOCK-----\n`] }])
await step('no public block', 'importKey', ['@W@/leer.asc', 'k', false], [{ write: ['@W@/leer.asc', 'nur Text'] }])
await step('a key file', 'importKey', ['@W@/Schlüssel Ö.asc', 'kontakt_1-A', false], [{ write: ['@W@/Schlüssel Ö.asc', `Kommentar ä\n${pub}`] }])
await step('it exists', 'importKey', ['@W@/Schlüssel Ö.asc', 'kontakt_1-A', false], [{ write: ['@W@/Schlüssel Ö.asc', `neu\n${pub}`] }])
await step('overwritten', 'importKey', ['@W@/Schlüssel Ö.asc', 'kontakt_1-A', true])
await step('through a link to the source', 'importKey', ['@W@/link.asc', 'verlinkt', false], [{ symlink: ['@W@/Schlüssel Ö.asc', '@W@/link.asc'] }])
await step('the target is a link', 'importKey', ['@W@/Schlüssel Ö.asc', 'ziel', false], [{ write: ['@W@/anderswo.asc', 'alt'] }, { symlink: ['@W@/anderswo.asc', '@W@/Gärten-Ü/quartz-forms/keys/ziel.asc'] }])
await step('a folder with the name', 'importKey', ['@W@/Schlüssel Ö.asc', 'ordner', true], [{ mkdir: '@W@/Gärten-Ü/quartz-forms/keys/ordner.asc' }])
await step('the key folder is a link', 'importKey', ['@W@/Schlüssel Ö.asc', 'k2', false], [
  { rm: '@W@/Gärten-Ü/quartz-forms' }, { mkdir: '@W@/fremd/keys' }, { symlink: ['@W@/fremd', '@W@/Gärten-Ü/quartz-forms'] }])
await step('a file where the folder goes', 'importKey', ['@W@/Schlüssel Ö.asc', 'k3', false], [
  { rm: '@W@/Gärten-Ü/quartz-forms' }, { write: ['@W@/Gärten-Ü/quartz-forms', 'datei'] }])
await step('an unreadable source', 'importKey', ['@W@/gesperrt.asc', 'k4', false], [{ rm: '@W@/Gärten-Ü/quartz-forms' }, { write: ['@W@/gesperrt.asc', pub] }, { chmod: ['@W@/gesperrt.asc', '000'] }])
chmodSync(join(work, 'gesperrt.asc'), 0o644)

mkdirSync(fixtures, { recursive: true })
writeFileSync(join(fixtures, 'cli-steps.json'), JSON.stringify({ steps }, null, 1) + '\n')
rmSync(work, { recursive: true, force: true })
console.log(`${steps.length} Schritte`)
