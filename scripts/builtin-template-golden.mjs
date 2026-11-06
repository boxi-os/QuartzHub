#!/usr/bin/env node
// Golden file for BuiltinTemplate, made by QuartzControl's own builtinTemplateService.ts: which
// package a new project gets (the download of a day, cached in userData, or the copy inside the
// app; the newer `createdAt` wins, a tie goes to the copy), with a scripted network (`net.fetch`
// replaced), cache files aged by their mtime, and damaged caches and copies. Each step records the
// answer, the requests and the cache file afterwards.
//
//   Runtime/node/bin/node scripts/builtin-template-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, utimesSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'builtin-template')

const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-builtin-golden-')))
const userData = join(work, 'userData')
const resources = join(work, 'resources')
globalThis.__requests = []
globalThis.__answer = null
process.resourcesPath = resources
const service = await loadQuartzControl(control, 'electron/main/services/builtinTemplateService.ts', {
  ...commonStubs,
  electron: `export const app = { getPath: () => ${JSON.stringify(userData)}, getAppPath: () => ${JSON.stringify(join(work, 'app'))} }
export const net = { fetch: async (url, options) => {
  globalThis.__requests.push(url)
  const answer = globalThis.__answer
  if (!answer || answer.fail) throw new Error('offline')
  const body = answer.package !== undefined ? globalThis.__packages[answer.package] : Buffer.from(answer.base64, 'base64')
  return { ok: answer.status >= 200 && answer.status < 300, status: answer.status, arrayBuffer: async () => body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength) }
} }`
})
const { createZip } = await loadQuartzControl(control, 'electron/main/services/zipArchive.ts', commonStubs)

const sha = (data) => createHash('sha256').update(data).digest('hex')
const pkg = (manifest, content) => createZip([
  { name: 'manifest.json', data: Buffer.from(typeof manifest === 'string' ? manifest : JSON.stringify(manifest)) },
  ...(content === undefined ? [] : [{ name: 'parts/content.json', data: Buffer.from(typeof content === 'string' ? content : JSON.stringify(content)) }])
], new Date(2026, 10, 6))
const packages = {
  bundled: readFileSync(join(control, 'resources', 'templates', 'qc-basic.qtpl')),
  newer: pkg({ formatVersion: 1, name: 'Neuer', createdAt: '2026-12-01T00:00:00.000Z' }, { files: ['a.md', 'b/B.MD', 'bild.png', 7, 'c.md'] }),
  older: pkg({ formatVersion: 1, name: 'Älter', createdAt: '2026-01-01T00:00:00.000Z' }, { files: ['x.md'] }),
  same: pkg({ formatVersion: 1, name: 'Gleich', createdAt: '2026-11-05T22:34:29.737Z' }),
  undated: pkg({ formatVersion: 1, name: 'Ohne Datum' }, { files: 'kein Array' }),
  badDate: pkg({ formatVersion: 1, name: 'Datum kaputt', createdAt: 'gestern' }, '{ kaputt'),
  badManifest: pkg('{ kaputt'),
  noManifest: createZip([{ name: 'parts/theme.json', data: Buffer.from('{}') }]),
  portal: Buffer.from('<html><body>Bitte anmelden</body></html>'),
  truncated: null
}
packages.truncated = packages.newer.subarray(0, packages.newer.length - 30)
// A real package of exactly the ceiling and one byte more: a stored filler grows the file byte for
// byte. Built here and in the Swift test alike (25 MB is no fixture).
const sized = (target) => {
  const make = (n) => createZip([{ name: 'manifest.json', data: Buffer.from(JSON.stringify({ formatVersion: 1, name: 'Groß', createdAt: '2026-12-02T00:00:00.000Z' })), store: true },
    { name: 'filler.bin', data: Buffer.alloc(n, 7), store: true }], new Date(2026, 10, 6))
  return make(target - make(0).length)
}
packages.atCeiling = sized(25 * 1024 * 1024)
globalThis.__packages = packages
packages.overCeiling = sized(25 * 1024 * 1024 + 1)

const cache = join(userData, 'templates', 'qc-basic.qtpl')
const bundledFile = join(resources, 'templates', 'qc-basic.qtpl')
const DAY = 24 * 60 * 60 * 1000
const steps = []
const setFile = (path, name, ageMs) => {
  if (name === null) { rmSync(path, { force: true }); return }
  mkdirSync(dirname(path), { recursive: true })
  writeFileSync(path, packages[name])
  const when = new Date(Date.now() - ageMs)
  utimesSync(path, when, when)
}
const which = (data) => Object.entries(packages).find(([, value]) => value && Buffer.compare(value, data) === 0)?.[0] ?? sha(data)

async function step(name, { bundled = 'bundled', cached = null, age = 0, answer = null }) {
  setFile(bundledFile, bundled, 0)
  setFile(cache, cached, age)
  globalThis.__requests = []
  globalThis.__answer = answer
  const result = await service.getBuiltinTemplate()
  const leftovers = existsSync(dirname(cache)) ? readdirSync(dirname(cache)).filter((n) => n !== 'qc-basic.qtpl') : []
  steps.push({
    name, setup: { bundled, cached, ageHours: age / 3600000, answer },
    result: result && { path: result.path.replace(work, '@W@'), source: result.source, pages: result.pages },
    requests: globalThis.__requests, cacheAfter: existsSync(cache) ? which(readFileSync(cache)) : null, leftovers
  })
}

const net = (name, status = 200) => ({ status, base64: packages[name].toString('base64') })
try {
  await step('first run offline', { answer: { fail: true } })
  await step('first run 404', { answer: { ...net('newer'), status: 404 } })
  await step('first run, newer online', { answer: net('newer') })
  await step('fresh cache is not asked again', { cached: 'newer', age: 2 * 3600000, answer: net('older') })
  await step('day-old cache, older online, the copy wins', { cached: 'newer', age: DAY + 60000, answer: net('older') })
  await step('day-old cache, offline, it stays', { cached: 'newer', age: DAY + 60000, answer: { fail: true } })
  await step('just under a day', { cached: 'older', age: DAY - 60000, answer: net('newer') })
  await step('torn cache is deleted and fetched again', { cached: 'truncated', age: 60000, answer: net('newer') })
  await step('torn cache, offline', { cached: 'truncated', age: 60000, answer: { fail: true } })
  await step('a captive portal', { answer: net('portal') })
  await step('a zip without a manifest', { answer: net('noManifest') })
  await step('an unreadable manifest is still a package', { answer: net('badManifest') })
  await step('an empty answer', { answer: { status: 200, base64: '' } })
  await step('larger than 25 MB', { answer: { status: 200, package: 'overCeiling' } })
  await step('exactly 25 MB', { answer: { status: 200, package: 'atCeiling' } })
  await step('same date: the copy', { cached: 'same', age: 60000 })
  await step('undated cache against the copy', { cached: 'undated', age: 60000 })
  await step('bad date against the copy', { cached: 'badDate', age: 60000 })
  await step('undated cache, no copy', { bundled: null, cached: 'undated', age: 60000 })
  await step('no copy, offline', { bundled: null, answer: { fail: true } })
  await step('damaged copy, newer cache', { bundled: 'truncated', cached: 'newer', age: 60000 })
  await step('damaged copy, nothing else', { bundled: 'truncated', answer: { fail: true } })
  await step('copy without manifest, older cache', { bundled: 'noManifest', cached: 'older', age: 60000 })
  await step('copy without manifest, nothing else', { bundled: 'noManifest', answer: { fail: true } })
  await step('cache without manifest, offline', { cached: 'noManifest', age: 60000, answer: { fail: true } })
} finally {
  rmSync(work, { recursive: true, force: true })
}

rmSync(out, { recursive: true, force: true })
mkdirSync(out, { recursive: true })
const keep = Object.fromEntries(Object.entries(packages).filter(([name]) => !['bundled', 'atCeiling', 'overCeiling'].includes(name)).map(([name, data]) => [name, data.toString('base64')]))
writeFileSync(join(out, 'packages.json'), JSON.stringify(keep) + '\n')
writeFileSync(join(out, 'steps.json'), JSON.stringify(steps, null, 1) + '\n')
console.log(`${steps.length} steps → ${out}`)
