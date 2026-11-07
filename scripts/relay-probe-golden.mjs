#!/usr/bin/env node
// Golden file for RelayProbe, made by QuartzControl's own formsService.ts: checkRelay and
// countersServed (exposed for this), phpMessage and localHost. Electron's `net.request` is a
// stand-in over Node's http that behaves as Chromium was measured to (formsService.ts): redirects
// followed with a 'redirect' event per hop, `Origin: null` once a hop changed the origin, errors as
// net::ERR_* codes. Names ending in .test go to Fixtures/forms/relay-server.mjs as an HTTP proxy;
// 127.0.0.1 and other literals go there directly. The deadlines are shortened (10 s → 2 s,
// 3 s → 0.5 s) the same way QuartzHub's test shortens them. Each case is the call, its answer
// and the requests the server saw.
//
//   Runtime/node/bin/node scripts/relay-probe-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { spawn } from 'node:child_process'
import { request as httpRequest } from 'node:http'
import { createServer } from 'node:net'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { createInterface } from 'node:readline'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { EventEmitter } from 'node:events'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const fixtures = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'forms')

const server = spawn(process.execPath, [join(fixtures, 'relay-server.mjs')], { stdio: ['ignore', 'pipe', 'inherit'] })
const port = await new Promise((resolve) => createInterface({ input: server.stdout }).once('line', (l) => resolve(JSON.parse(l).port)))
const closedPort = await new Promise((resolve) => { const s = createServer().listen(0, '127.0.0.1', () => { const p = s.address().port; s.close(() => resolve(p)) }) })

const codes = { ECONNREFUSED: 'net::ERR_CONNECTION_REFUSED', ECONNRESET: 'net::ERR_CONNECTION_RESET', ENOTFOUND: 'net::ERR_NAME_NOT_RESOLVED', EHOSTUNREACH: 'net::ERR_ADDRESS_UNREACHABLE', ENETUNREACH: 'net::ERR_ADDRESS_UNREACHABLE' }
// Chromium's ClientRequest as formsService.ts uses it: url, method GET, redirect 'follow'.
globalThis.__net = {
  request({ url }) {
    const req = new EventEmitter()
    const headers = {}
    let current = null
    let aborted = false
    let hops = 0
    const go = (target, tainted) => {
      if (aborted) return
      const u = new URL(target)
      const viaProxy = u.hostname.endsWith('.test')
      const h = { ...headers, host: u.host }
      if (tainted && 'Origin' in headers) h.Origin = 'null'
      const host = u.hostname.replace(/^\[|\]$/g, '')
      current = httpRequest(viaProxy
        ? { host: '127.0.0.1', port, path: u.href, method: 'GET', headers: h }
        : { host, port: u.port || 80, path: u.pathname + u.search, method: 'GET', headers: h, family: host.includes(':') ? 6 : 4 })
      current.on('response', (res) => {
        if ([301, 302, 303, 307, 308].includes(res.statusCode) && res.headers.location && hops < 20) {
          hops += 1
          res.resume()
          // Chromium reads the header's bytes as UTF-8; Node hands them over as latin1.
          const next = new URL(Buffer.from(res.headers.location, 'latin1').toString('utf8'), u).href
          req.emit('redirect', res.statusCode, 'GET', next, res.headers)
          if (!aborted) go(next, tainted || new URL(next).origin !== u.origin)
          return
        }
        const out = new EventEmitter()
        out.statusCode = res.statusCode
        res.on('data', (c) => out.emit('data', c))
        res.on('end', () => out.emit('end'))
        res.on('error', (e) => out.emit('error', e))
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

const stubs = {
  ...commonStubs,
  '../i18n': `${commonStubs['../i18n']}\nexport function mainLanguage() { return 'de' }`,
  electron: 'export const net = { request: (o) => globalThis.__net.request(o) }',
  './connectionsService': 'export async function claimLegacyTargets() { return [] }',
  './deploy': 'export async function runDirectoryUpload() { throw new Error("no deploy here") }'
}
const forms = await loadQuartzControl(control, 'electron/main/services/formsService.ts', stubs, {
  expose: ['checkRelay', 'countersServed', 'phpMessage', 'localHost'],
  replace: [['const CHECK_RELAY_TIMEOUT_MS = 10_000', 'const CHECK_RELAY_TIMEOUT_MS = 2_000'], ['const RELAY_ASK_AGAIN_MS = 3000', 'const RELAY_ASK_AGAIN_MS = 1500']]
})

const P = (s) => s.split('@PORT@').join(String(port)).split('@CLOSED@').join(String(closedPort))
const mask = (s) => s.split(`:${port}`).join(':@PORT@').split(`:${closedPort}`).join(':@CLOSED@')
const serverLog = async () => (await (await fetch(`http://127.0.0.1:${port}/__log`)).json())
await fetch(`http://127.0.0.1:${port}/__reset`)

const cases = []
async function probe(name, url, origin, form, generation) {
  await serverLog()
  await fetch(`http://127.0.0.1:${port}/__reset`)
  const started = Date.now()
  const answer = await forms.checkRelay(url === null ? undefined : P(url), origin, form ?? undefined, generation ?? undefined)
  const ms = Date.now() - started
  cases.push({ name, op: 'check', args: [url, origin, form, generation], answer: JSON.parse(mask(JSON.stringify(answer))), requests: await serverLog(), slow: ms > 1000 })
}
async function counters(name, url) {
  await serverLog()
  const answer = await forms.countersServed(P(url))
  const requests = (await serverLog()).sort((a, b) => (a.path < b.path ? -1 : 1))
  cases.push({ name, op: 'counters', args: [url], answer: answer === null ? null : mask(answer), requests })
}

const G = '0123456789abcdef'
const site = 'https://garten.example'
const relay = (kind) => `http://relay.test/${kind}/send.php`
await probe('no address', null, site, 'kontakt', G)
await probe('ftp', 'ftp://relay.test/send.php', site, 'kontakt', G)
await probe('no form', relay('ok'), site, null, G)
await probe('not a URL', 'http://', site, 'kontakt', G)
await probe('upper-case scheme', 'HTTP://relay.test/ok/send.php', site, 'kontakt', G)
await probe('ok', relay('ok'), site, 'kontakt', G)
await probe('ok with a query of its own', 'http://relay.test/ok/send.php?a=b%20c&challenge=alt&x', site, 'kontakt-2', G)
await probe('ok, no origin', relay('ok'), null, 'kontakt', G)
await probe('ok, no generation', relay('ok'), site, 'kontakt', null)
await probe('counters not a boolean', relay('ok-nocounters'), site, 'kontakt', G)
await probe('ok without a stamp', relay('ok-nostamp'), site, 'kontakt', G)
await probe('another generation, twice', relay('ok-old'), site, 'kontakt', G)
await probe('another generation, then this one', relay('ok-late'), site, 'kontakt', G)
await probe('ok with 201', relay('ok-status'), site, 'kontakt', G)
await probe('unknown form', relay('unknown'), site, 'kontakt', G)
await probe('origin refused', relay('origin'), site, 'kontakt', G)
await probe('a long error', relay('longerr'), site, 'kontakt', G)
await probe('mbstring', relay('mbstring'), site, 'kontakt', G)
await probe('PHP stopped', relay('php500'), site, 'kontakt', G)
await probe('the host\'s 500', relay('host500'), site, 'kontakt', G)
await probe('no PHP, config served', relay('nophp'), site, 'kontakt', G)
await probe('no PHP, config closed', relay('nophp-closed'), site, 'kontakt', G)
await probe('fatal error as HTML', relay('fatal-html'), site, 'kontakt', G)
await probe('warning as HTML', relay('warn-html'), site, 'kontakt', G)
await probe('deprecated as text', relay('warn-text'), site, 'kontakt', G)
await probe('fatal as long text', relay('fatal-text'), site, 'kontakt', G)
await probe('a host page with Warning', relay('host404-warning'), site, 'kontakt', G)
await probe('a text 404 with Warning', relay('text404-warning'), site, 'kontakt', G)
await probe('PHP-FPM cannot read', relay('fpm'), site, 'kontakt', G)
await probe('not found', relay('notfound'), site, 'kontakt', G)
await probe('a big body', relay('big'), site, 'kontakt', G)
await probe('a big relay answer', relay('bigjson'), site, 'kontakt', G)
await probe('a body that never ends', relay('slowbody'), site, 'kontakt', G)
await probe('a JSON body that never ends', relay('slowjson'), site, 'kontakt', G)
await probe('an HTML body that never ends', relay('slowhtml'), site, 'kontakt', G)
await probe('a server that never answers', relay('silent'), site, 'kontakt', G)
await probe('a server that hangs up', relay('drop'), site, 'kontakt', G)
await probe('refused', 'http://127.0.0.1:@CLOSED@/send.php', site, 'kontakt', G)
await probe('301 within the origin', relay('r301-same'), site, 'kontakt', G)
await probe('303 within the origin', relay('r303-same'), site, 'kontakt', G)
await probe('307 within the origin', relay('r307-same'), site, 'kontakt', G)
await probe('308 home', relay('r308-same-home'), site, 'kontakt', G)
await probe('307 home', relay('r307-same-home'), site, 'kontakt', G)
await probe('301 home', relay('r301-same-home'), site, 'kontakt', G)
await probe('302 to a relay elsewhere', relay('r302-cross-relay'), site, 'kontakt', G)
await probe('308 to a relay elsewhere', relay('r308-cross-relay'), site, 'kontakt', G)
await probe('302 to a home elsewhere', relay('r302-cross-home'), site, 'kontakt', G)
await probe('302 to an API elsewhere', relay('r302-cross-api'), site, 'kontakt', G)
await probe('302 to a refusal elsewhere', relay('r302-cross-origin-refusal'), site, 'kontakt', G)
await probe('301 to this machine', relay('r301-to-local'), site, 'kontakt', G)
await probe('301 to this machine in hex', relay('r301-to-hex'), site, 'kontakt', G)
await probe('301 to this machine over IPv6', relay('r301-to-v6'), site, 'kontakt', G)
await probe('301 into the LAN', relay('r301-to-lan'), site, 'kontakt', G)
await probe('a local address may go local', 'http://127.0.0.1:@PORT@/r301-to-local/send.php', site, 'kontakt', G)
await probe('a chain back home', relay('r302-chain'), site, 'kontakt', G)
await probe('a long place', relay('r302-long'), site, 'kontakt', G)
await probe('elsewhere ok without a stamp', relay('r302-cross-nostamp'), site, 'kontakt', G)
await probe('away and back without a generation', relay('r302-away-and-back'), site, 'kontakt', null)
await probe('303, then 301', relay('r303-then-301'), site, 'kontakt', G)
await probe('a body that grows without end', relay('endless'), site, 'kontakt', G)
await counters('the probe file served', relay('cnt-probe'))
await counters('the .htaccess served', relay('cnt-ht'))
await counters('nothing served', relay('ok'))
await counters('every path answers', relay('cnt-all200'))

// The two pure judgements, over many inputs.
const php = [
  '', '{"ok":true}', '<b>Warning</b>:  x in <b>/a.php</b> on line <b>1</b>',
  '<br />\n<b>Fatal error</b>:  Uncaught Error: nope in /srv/a.php:3\nStack trace:',
  '<br />\n<b>Parse error</b>:  syntax error, unexpected end of file',
  '<br />\n<b>Notice</b>:  Undefined index: a in <b>/x/y.php</b> on line <b>2</b><br />\n<b>Fatal error</b>: boom in <b>/x/z.php</b> on line <b>9</b>',
  'PHP Warning:  file_get_contents(x): Failed to open stream in /var/www/a.php on line 5',
  'Warning: something without a place',
  'Deprecated: thing in /a.php on line 1\nWarning: second in /b.php on line 2',
  '  Fatal error: Allowed memory size exhausted in /srv/a.php on line 44   ',
  '<html><body>Fatal error: in /x.php on line 1</body></html>',
  '<!DOCTYPE html>\n<b>Warning</b>: in html in /x.php on line 1',
  'Notice: ' + 'ü'.repeat(310) + ' in /x.php on line 1',
  'Warning: a\tb in /x.php:12',
  'PHP Fatal error:  Uncaught TypeError in /x.php:7',
  'Fatal error:x in /x.php on line 1',
  'Warning: two  spaces in  /x.php on line 1',
  '<p>Warning: tagged in /x.php on line 1</p>',
  'Error: not a PHP kind in /x.php on line 1'
]
const hosts = [
  'http://localhost/', 'http://LOCALHOST./', 'http://a.localhost/', 'http://localhost.example/', 'http://127.0.0.1/', 'http://127.1/',
  'http://0x7f000001/', 'http://2130706433/', 'http://0177.0.0.1/', 'http://0.0.0.0/', 'http://10.1.2.3/', 'http://172.15.0.1/',
  'http://172.16.0.1/', 'http://172.31.255.255/', 'http://172.32.0.1/', 'http://192.168.0.1/', 'http://192.169.0.1/', 'http://169.254.1.1/',
  'http://169.255.1.1/', 'http://8.8.8.8/', 'http://[::1]/', 'http://[::]/', 'http://[::ffff:127.0.0.1]/', 'http://[::ffff:8.8.8.8]/',
  'http://[fc00::1]/', 'http://[fd12:3456::1]/', 'http://[fe80::1]/', 'http://[febf::1]/', 'http://[fec0::1]/', 'http://[2001:db8::1]/',
  'http://[0:0:0:0:0:0:0:1]/', 'http://[FC00::]/', 'http://[fc0::1]/', 'http://example.com/', 'http://garten.example:8080/x',
  'http://xn--grten-gra.example/', 'http://1.2.3.4.5/', 'http://256.0.0.1/',
  'http://[1:0:0:2:0:0:0:3]/', 'http://[1:0:0:0:2:0:0:3]/', 'http://[::ffff:1.2.3.4]:8080/', 'http://[1:2:3:4:5:6:7:8]/', 'http://[::1.2.3.4]/',
  'http://[1::]/', 'http://[1:2]/', 'http://[::1:2:3:4:5:6:7:8]/', 'http://[::01.2.3.4]/', 'http://[::1.2.3]/', 'http://[0000:00::0]/',
  'http://[fe80::1%25en0]/', 'http://[::1]x/', 'http://0x/', 'http://0x100000000/', 'http://0.0x300/', 'http://4294967295/',
  'http://4294967296/', 'http://1.2.3./', 'http://08/', 'http://0x7f.1/', 'http://1.2.0x10000/', 'http://0xffffffffffffffffffffff/',
  'http://1.256.3.4/', 'http://a.0x1/', 'http://1.2.3.09/', 'http://0X7F.0.0.1/',
  'http://[1:0:2:3:4:5:6:7]/', 'http://[1:0:0:2:3:4:5:6]/'
]
const pure = {
  phpMessage: php.map((body) => ({ body, message: forms.phpMessage(body) })),
  localHost: hosts.map((url) => {
    let hostname = null
    try { hostname = new URL(url).hostname } catch { /* invalid */ }
    return { url, hostname, local: hostname === null ? null : forms.localHost(hostname) }
  })
}

server.kill()
mkdirSync(fixtures, { recursive: true })
writeFileSync(join(fixtures, 'probe-cases.json'), JSON.stringify({ cases, ...pure }, null, 1) + '\n')
console.log(`${cases.length} Abfragen, ${php.length} PHP-Texte, ${hosts.length} Adressen`)
process.exit(0)
