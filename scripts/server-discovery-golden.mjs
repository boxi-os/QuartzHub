#!/usr/bin/env node
// Golden file for ServerScan, made by QuartzControl's own serverDiscovery.ts: each scenario hands
// it a process table (`ps`), lsof answers per pid (working directory, listening ports), which TCP
// ports answer and what each HTTP port serves, the projects and the pids the app started, and
// records what discoverServers answered; then killServer for a few pids, and what that signalled.
//
//   Runtime/node/bin/node scripts/server-discovery-golden.mjs [../QuartzControl]
//
// Stand-ins: child_process.execFile (ps, lsof), net, http, tree-kill, projectStore, buildService,
// Date.now. Nothing is started, nothing is signalled.
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'server-discovery')

// globalThis.__world is the scenario; __calls what was asked of it.
const discovery = await loadQuartzControl(control, 'electron/main/services/serverDiscovery.ts', {
  child_process: `export function execFile(file, args, options, callback) {
    const w = globalThis.__world
    globalThis.__calls.push([file, ...args])
    const answer = file === 'ps' ? w.ps
      : args.includes('cwd') ? (w.cwd ?? {})[args[args.indexOf('-p') + 1]]
      : (w.lsof ?? {})[args[args.indexOf('-p') + 1]]
    setTimeout(() => {
      if (answer === undefined) return callback(Object.assign(new Error('Command failed: ' + [file, ...args].join(' ') + '\\n'), { code: 1 }), '', '')
      if (answer.enoent) return callback(Object.assign(new Error('spawn ' + file + ' ENOENT'), { code: 'ENOENT' }), '', '')
      if (answer.code !== undefined) {
        const message = 'Command failed: ' + [file, ...args].join(' ') + '\\n' + (answer.stderr ?? '')
        return callback(Object.assign(new Error(message), { code: answer.code }), answer.stdout ?? '', answer.stderr ?? '')
      }
      callback(null, answer.stdout ?? '', '')
    }, 1)
  }`,
  net: `import { EventEmitter } from 'node:events'
  export function createConnection({ port }) {
    const socket = new EventEmitter()
    socket.setTimeout = () => {}
    socket.destroy = () => {}
    setTimeout(() => socket.emit((globalThis.__world.tcp ?? []).includes(port) ? 'connect' : 'error', new Error('ECONNREFUSED')), 1)
    return socket
  }`,
  http: `import { EventEmitter } from 'node:events'
  export function get({ port }, onResponse) {
    const request = new EventEmitter()
    request.destroy = () => { request.destroyed = true }
    const page = (globalThis.__world.http ?? {})[port]
    setTimeout(() => {
      if (page === undefined) return request.emit('error', new Error('ECONNREFUSED'))
      if (page.timeout) return request.emit('timeout')
      const response = new EventEmitter()
      response.setEncoding = () => {}
      response.destroy = () => { response.destroyed = true }
      onResponse(response)
      const body = page.body ?? ''
      // In pieces of 16 KiB, as a socket delivers them.
      for (let i = 0; i < body.length && !response.destroyed; i += 16384) response.emit('data', body.slice(i, i + 16384))
      if (response.destroyed) return
      if (page.breaks) return response.emit('error', new Error('socket hang up'))
      response.emit('end')
    }, 1)
    return request
  }`,
  'fs/promises': 'export async function readdir() { throw new Error("no /proc") }; export const readFile = readdir; export const readlink = readdir',
  'tree-kill': `export default function treeKill(pid, signal, callback) {
    globalThis.__calls.push(['treeKill', pid, signal])
    const error = (globalThis.__world.killFails ?? []).includes(pid) ? Object.assign(new Error('kill EPERM'), { code: 'EPERM' }) : undefined
    setTimeout(() => callback(error), 1)
  }`,
  './projectStore': 'export async function listProjects() { return globalThis.__world.projects ?? [] }',
  './buildService': `export function ownedServerPids() { return new Map(Object.entries(globalThis.__world.owned ?? {}).map(([pid, id]) => [Number(pid), id])) }
  export async function stopServer(id) { globalThis.__calls.push(['stopServer', id]) }`
})

const NOW = Date.UTC(2026, 10, 6, 12, 0, 0)
Date.now = () => NOW

const page = (title, generator = true) =>
  `<!doctype html><html><head><title>${title}</title>${generator ? '<meta name="generator" content="Quartz"/>' : ''}</head><body></body></html>`
const ps = (...rows) => ({ stdout: rows.map((r) => r.join(' ')).join('\n') + '\n' })
const npx = (pid, ppid, etime, args) => [[pid, ppid, etime, `npm exec quartz build --serve ${args}`],
  [pid + 1, pid, etime, `node --no-deprecation /Users/x/proj/node_modules/.bin/quartz build --serve ${args}`]]
const cwd = (path) => ({ stdout: `p1\nfcwd\nn${path}\n` })
const listens = (...ports) => ({ stdout: `p1\nf20\nn*:${ports[0]}\n` + ports.slice(1).map((p) => `f21\nn127.0.0.1:${p}\n`).join('') })
const projects = [{ id: 'p1', name: 'Garten', path: '/Users/x/proj' }, { id: 'p2', name: 'Mit Leerzeichen', path: '/Users/x/Mein Projekt/' }]

const scenarios = [
  { name: 'started-by-the-app', world: {
    ps: ps([1, 0, '10-00:00:00', '/sbin/launchd'], ...npx(500, 1, '01:05', '--port 8099 --wsPort 3099'), [700, 1, '2:00:00', '/usr/libexec/appleeventsd --server']),
    cwd: { 501: cwd('/Users/x/proj') }, http: { 8099: { body: page('  Mein Garten  ') } }, tcp: [8099, 3099],
    projects, owned: { 500: 'p1' } }, ports: [8099, 3099],
    kills: [500, 501, 700, 4242] },
  { name: 'from-a-terminal-without-flags', world: {
    ps: ps(...npx(800, 1, '1:02:03', '').map((r) => [...r.slice(0, 3), r[3].trimEnd()])),
    cwd: { 801: cwd('/Users/x/Mein Projekt') }, lsof: { 801: listens(8080, 3001) }, http: { 8080: { body: page('Zweit') } }, projects },
    kills: [800] },
  { name: 'without-flags-holding-another-port', world: {
    ps: ps([900, 1, '00:10', 'node /Users/x/quartz/x.js --serve']), lsof: { 900: listens(4000) }, projects } },
  { name: 'without-flags-holding-none', world: {
    ps: ps([900, 1, '00:10', 'node /Users/x/quartz/x.js --serve']), lsof: { 900: { code: 1 } }, projects } },
  { name: 'lsof-missing', world: {
    ps: ps([900, 1, '00:10', 'node /Users/x/quartz/x.js --serve'], [950, 1, '00:10', 'node quartz build --serve --port 8100']),
    lsof: { 900: { enoent: true } }, http: { 8100: { body: page('Da') } }, projects } },
  { name: 'lsof-refuses', world: {
    ps: ps([900, 1, '00:10', 'node /Users/x/quartz/x.js --serve']), lsof: { 900: { code: 1, stderr: 'lsof: WARNING: can\'t stat() fuse\n' } }, projects } },
  { name: 'needles', world: {
    ps: ps([10, 1, '00:01', '/Users/x/QuartzProjekte/a/node_modules/.bin/q build --serve --port 8131'],
      [11, 1, '00:01', 'node quartz build --serve=yes --port 8132'],
      [12, 1, '00:01', 'node quartz build --serves --port 8133'],
      [13, 1, '00:01', 'node quartz build --SERVE --PORT 8134'],
      [14, 1, '00:01', 'node /x/serve build --port 8135'],
      [15, 1, '00:01', 'node quartz build --serve --port=8136 --wsPort=3136'],
      [16, 1, '00:01', 'node quartz build --serve --port 70000'],
      [17, 1, '00:01', 'node quartz build --serve --port 0'],
      [18, 1, '00:01', 'node quartz build --serve --port 81370'],
      [19, 1, '00:01', 'node quartz build --serve --wsPort 3138 --port  8138']),
    lsof: { 16: { code: 1 }, 17: { code: 1 }, 18: { code: 1 } }, projects } },
  { name: 'elapsed-and-odd-rows', world: {
    ps: { stdout: '  20     1 05:03 node quartz build --serve --port 8201\n' +
      '21 1 1:02:03 node quartz build --serve --port 8202\n' +
      '22 1 2-01:02:03 node quartz build --serve --port 8203\n' +
      '23 1 x node quartz build --serve --port 8204\n' +
      'not a row\n\n' +
      '24 24 00:01 node quartz build --serve --port 8205\n' +
      '25 26 00:01 node quartz build --serve --port 8206\n26 25 00:01 node quartz build --serve --port 8206\n' },
    projects } },
  { name: 'probes', world: {
    ps: ps([30, 1, '00:01', 'node quartz build --serve --port 8301'], [31, 1, '00:01', 'node quartz build --serve --port 8302'],
      [32, 1, '00:01', 'node quartz build --serve --port 8303'], [33, 1, '00:01', 'node quartz build --serve --port 8304'],
      [34, 1, '00:01', 'node quartz build --serve --port 8305'], [35, 1, '00:01', 'node quartz build --serve --port 8306'],
      [36, 1, '00:01', 'node quartz build --serve --port 8307']),
    http: {
      8301: { body: '<TITLE>Groß</TITLE><META NAME="generator" CONTENT="Quartz">' },
      8302: { body: page('', false) },
      8303: { timeout: true },
      8304: { body: page('Abgebrochen'), breaks: true },
      8305: { body: 'x'.repeat(70000) + page('Zu spät') },
      8306: { body: '<title>Ohne Ende' },
      8307: { body: '<meta name="generator"  content="Quartz"><title>a<b</title>' }
    }, projects } },
  { name: 'occupied-ports', world: {
    ps: ps(...npx(40, 1, '00:01', '--port 8401 --wsPort 3401')), tcp: [8401, 3401, 8500, 9000], projects },
    ports: [8401, 3401, 8500, 8500, 8600, 9000] },
  { name: 'ps-fails', world: { ps: { enoent: true } }, ports: [8080], kills: [500] },
  { name: 'kill-fails', world: { ps: ps([60, 1, '00:01', 'node quartz build --serve --port 8601']), killFails: [60], projects }, kills: [60] }
]

const recorded = []
for (const s of scenarios) {
  globalThis.__world = s.world
  globalThis.__calls = []
  const answer = await discovery.discoverServers(s.ports ?? [])
  const scanCalls = globalThis.__calls
  const kills = []
  for (const pid of s.kills ?? []) {
    globalThis.__calls = []
    const result = await discovery.killServer(pid)
    kills.push({ pid, expected: result, actions: globalThis.__calls.filter((c) => c[0] === 'treeKill' || c[0] === 'stopServer') })
  }
  recorded.push({ name: s.name, world: s.world, ports: s.ports ?? [], expected: answer, lsofAsked: scanCalls.filter((c) => c[0] === 'lsof').length, kills })
}

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'scenarios.json'), JSON.stringify({ now: new Date(NOW).toISOString(), scenarios: recorded }, null, 2) + '\n')
console.log(`${recorded.length} Szenarien nach ${out}`)
