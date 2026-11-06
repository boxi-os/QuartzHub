#!/usr/bin/env node
// Golden file for Marketplace, made by QuartzControl's own marketplaceService.ts: each scenario
// runs a few calls (list, refresh, readme) against a fetch that answers from the scenario's queue
// and a clock the scenario sets, and records the requests each call made and what it answered.
// The Swift test (MarketplaceTests) serves the same answers through a URLProtocol and compares.
// Also the zod rule for a README's owner/repo (ipc/schemas.ts `marketplaceReadmeArgs`), against a
// list of names.
//
//   Runtime/node/bin/node scripts/marketplace-golden.mjs [../QuartzControl]
//
// Stand-ins: fetch, Date.now, connectionsService.getGithubToken. No network.
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { mkdirSync, writeFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'marketplace')

const market = await loadQuartzControl(control, 'electron/main/services/marketplaceService.ts', {
  './connectionsService': `export async function getGithubToken() {
    if (globalThis.__token === 'throws') throw new Error('Keychain access denied')
    return globalThis.__token ?? undefined
  }`
})
const schemas = await loadQuartzControl(control, 'electron/main/ipc/schemas.ts', {})

// A body is text, `{ fill: n, char }` (n times char), or `{ bytes: [..] }` before/after text.
function bytesOf(body) {
  if (body === undefined) return new Uint8Array()
  if (typeof body === 'string') return new TextEncoder().encode(body)
  if (body.fill !== undefined) {
    const head = new TextEncoder().encode(body.before ?? '')
    const fill = new TextEncoder().encode((body.char ?? 'x').repeat(body.fill))
    const tail = new Uint8Array(body.bytes ?? [])
    const after = new TextEncoder().encode(body.after ?? '')
    const all = new Uint8Array(head.length + fill.length + tail.length + after.length)
    all.set(head, 0); all.set(fill, head.length); all.set(tail, head.length + fill.length); all.set(after, head.length + fill.length + tail.length)
    return all
  }
  return new Uint8Array(body.bytes)
}

const NULL_BODY = new Set([101, 103, 204, 205, 304])
let queue = []
let requests = []
let now = 0
Date.now = () => now
globalThis.fetch = async (url, init) => {
  const headers = init?.headers ?? {}
  requests.push({ url: String(url), accept: headers.Accept ?? null, authorization: headers.Authorization ?? null, deadline: init?.signal instanceof AbortSignal })
  const answer = queue.shift()
  if (!answer) throw new Error('no answer queued')
  await new Promise((r) => setTimeout(r, 5))
  if (answer.fails) throw new TypeError('fetch failed')
  const bytes = bytesOf(answer.body)
  // Delivered in pieces of 1000 bytes, as a network would.
  const stream = new ReadableStream({
    start(c) {
      for (let i = 0; i < bytes.length; i += 1000) c.enqueue(bytes.subarray(i, i + 1000))
      c.close()
    }
  })
  return new Response(NULL_BODY.has(answer.status) ? null : stream, { status: answer.status, headers: answer.headers ?? {} })
}

const repo = (name, extra = {}) => ({
  name, full_name: `quartz-community/${name}`, description: `The ${name} plugin.`, stargazers_count: 3,
  html_url: `https://github.com/quartz-community/${name}`, topics: ['quartz-plugin'], archived: false, ...extra
})
const catalog = JSON.stringify([
  repo('explorer', { stargazers_count: 41 }),
  repo('v5', { archived: true, topics: [], description: null }),
  repo('types', { topics: undefined, archived: undefined, stargazers_count: 0 }),
  { name: 'bare', full_name: 'quartz-community/bare', html_url: 'https://github.com/quartz-community/bare' },
  repo('ümlaut', { description: 'Mit „Anführungszeichen“ und 🎉' })
])
const MAX = 256 * 1024
const MIN = 60 * 1000

const scenarios = [
  { name: 'list-ok-then-cached', token: 'ghp_token', steps: [
    { op: 'list', answers: [{ status: 200, body: catalog }] },
    { op: 'list', at: 14 * MIN },
    { op: 'list', at: 15 * MIN },
    { op: 'list', at: 15 * MIN + 1, answers: [{ status: 200, body: JSON.stringify([repo('explorer')]) }] }
  ] },
  { name: 'list-empty', steps: [{ op: 'list', answers: [{ status: 200, body: '[]' }] }] },
  { name: 'list-rate-limited-not-cached', steps: [
    { op: 'list', answers: [{ status: 403, body: '{"message":"API rate limit exceeded"}' }] },
    { op: 'list', answers: [{ status: 200, body: catalog }] },
    { op: 'list' }
  ] },
  { name: 'list-server-error', steps: [{ op: 'list', answers: [{ status: 502, body: 'Bad Gateway' }] }] },
  { name: 'list-no-network', steps: [{ op: 'list', answers: [{ fails: true }] }] },
  { name: 'list-not-json', steps: [{ op: 'list', answers: [{ status: 200, body: '<html>' }] }] },
  { name: 'list-not-an-array', steps: [{ op: 'list', answers: [{ status: 200, body: '{"message":"Moved"}' }] }] },
  { name: 'list-no-content', steps: [{ op: 'list', answers: [{ status: 204 }] }] },
  { name: 'list-token-unreadable', token: 'throws', steps: [{ op: 'list', answers: [{ status: 200, body: catalog }] }] },
  { name: 'list-coalesced', steps: [{ op: 'list', parallel: 2, answers: [{ status: 200, body: catalog }] }] },
  { name: 'refresh-refetches-both', steps: [
    { op: 'list', answers: [{ status: 200, body: catalog }] },
    { op: 'readme', fullName: 'quartz-community/explorer', answers: [{ status: 200, body: '# Explorer\n' }] },
    { op: 'refresh' },
    { op: 'list', answers: [{ status: 200, body: '[]' }] },
    { op: 'readme', fullName: 'quartz-community/explorer', answers: [{ status: 404, body: '{}' }] }
  ] },
  { name: 'readme-ok-cached', token: 'ghp_token', steps: [
    { op: 'readme', fullName: 'quartz-community/explorer', answers: [{ status: 200, body: '# Explorer\n\nÄpfel 🎉\n' }] },
    { op: 'readme', fullName: 'quartz-community/explorer', at: 15 * MIN },
    { op: 'readme', fullName: 'quartz-community/explorer', at: 15 * MIN + 1, answers: [{ status: 200, body: 'neu' }] },
    { op: 'readme', fullName: 'quartz-community/other', at: 15 * MIN + 1, answers: [{ status: 200, body: 'other' }] }
  ] },
  { name: 'readme-missing-cached', steps: [
    { op: 'readme', fullName: 'quartz-community/none', answers: [{ status: 404, body: '{"message":"Not Found"}' }] },
    { op: 'readme', fullName: 'quartz-community/none' }
  ] },
  { name: 'readme-unavailable-not-cached', steps: [
    { op: 'readme', fullName: 'quartz-community/x', answers: [{ status: 403, body: 'rate' }] },
    { op: 'readme', fullName: 'quartz-community/x', answers: [{ fails: true }] },
    { op: 'readme', fullName: 'quartz-community/x', answers: [{ status: 500, body: '' }] },
    { op: 'readme', fullName: 'quartz-community/x', answers: [{ status: 204 }] },
    { op: 'readme', fullName: 'quartz-community/x', answers: [{ status: 200, body: '' }] },
    { op: 'readme', fullName: 'quartz-community/x' }
  ] },
  { name: 'readme-exactly-the-cap', steps: [{ op: 'readme', fullName: 'a/b', answers: [{ status: 200, body: { fill: MAX } }] }] },
  { name: 'readme-one-over-the-cap', steps: [{ op: 'readme', fullName: 'a/b', answers: [{ status: 200, body: { fill: MAX + 1 } }] }] },
  { name: 'readme-far-over-the-cap', steps: [{ op: 'readme', fullName: 'a/b', answers: [{ status: 200, body: { fill: 3 * MAX } }] }] },
  // The cap falls inside "ä" (two bytes) and inside "🎉" (four).
  { name: 'readme-cap-splits-a-character', steps: [
    { op: 'readme', fullName: 'a/b', answers: [{ status: 200, body: { fill: MAX - 1, after: 'äää' } }] },
    { op: 'readme', fullName: 'a/c', answers: [{ status: 200, body: { fill: MAX - 2, after: '🎉🎉' } }] }
  ] },
  { name: 'readme-invalid-utf8', steps: [
    { op: 'readme', fullName: 'a/b', answers: [{ status: 200, body: { fill: 3, bytes: [0xff, 0x41, 0xf0, 0x9f, 0x41, 0xe4, 0xb8, 0xc0, 0x80, 0xed, 0xa0, 0x80], after: 'z' } }] }
  ] }
]

const names = [
  'quartz-community/explorer', 'a/b', 'A-1/b.c_d-e', '-a/b', 'a-/b', 'a/b.', 'a/.git', 'a/.', 'a/..', 'a/..b', 'a/b..',
  '../b', 'a/b/c', 'a', 'a/', '/b', '', 'a b/c', 'a/b c', 'a_b/c', 'a.b/c', 'ä/b', 'a/ä', 'a/b\n', '\na/b', 'a/b\u0000',
  'a/' + 'x'.repeat(198), 'a/' + 'x'.repeat(199), 'a/' + 'x'.repeat(250), 'a//b', 'a/b%2F..', 'a/.b'
]

const recorded = []
for (const s of scenarios) {
  market.invalidateCache()
  globalThis.__token = s.token
  now = 0
  const steps = []
  for (const step of s.steps) {
    if (step.at !== undefined) now = step.at
    queue = [...(step.answers ?? [])]
    requests = []
    let results
    if (step.op === 'refresh') { market.invalidateCache(); results = [null] }
    else if (step.op === 'list') results = await Promise.all(Array.from({ length: step.parallel ?? 1 }, () => market.listPlugins()))
    else results = [await market.readme(step.fullName)]
    if (queue.length) throw new Error(`${s.name}: ${queue.length} answers left over`)
    // A long text is kept as its length, digest and ends: the fixture stays small.
    results = results.map((r) => r?.text?.length > 200
      ? { ...r, text: { length: r.text.length, sha256: createHash("sha256").update(r.text).digest('hex'), head: r.text.slice(0, 20), tail: r.text.slice(-20) } }
      : r)
    steps.push({ ...step, expected: { requests, results } })
  }
  recorded.push({ name: s.name, token: s.token ?? null, steps })
}

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'scenarios.json'), JSON.stringify(recorded, null, 2) + '\n')
writeFileSync(join(out, 'names.json'), JSON.stringify(names.map((name) => ({
  name, accepted: schemas.marketplaceReadmeArgs.safeParse({ fullName: name }).success
})), null, 2) + '\n')
console.log(`${recorded.length} Szenarien, ${names.length} Namen nach ${out}`)
