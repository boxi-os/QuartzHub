#!/usr/bin/env node
// Golden file for WebhookAdapter, made by QuartzControl's own deploy/webhook.ts with `fetch`
// replaced by a script: each case is the stored URL, what the provider answers (status, status
// text, body) or how the request fails (timeout, network), the request the adapter made, its
// answer and its progress events. One case goes to Node's real fetch, which refuses a URL with
// credentials before anything is sent.
//
//   Runtime/node/bin/node scripts/webhook-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'webhook')
// The blanking text goes into the body before it is cut to 2000 characters, so it has to be the
// real one, not the stand-in's key: QuartzHub's German text from the catalog.
const catalog = JSON.parse(readFileSync(join(here, '..', 'Packages', 'QuartzHubCore', 'Sources', 'QuartzHubCore', 'Resources', 'Localizable.xcstrings'), 'utf-8'))
const redacted = catalog.strings['main.webhookRedacted'].localizations.de.stringUnit.value
const i18n = `export function mainT(key, args) { return key === 'webhookRedacted' ? ${JSON.stringify(redacted)} : JSON.stringify({ key, args: args ?? {} }) }`
const { webhookAdapter } = await loadQuartzControl(control, 'electron/main/services/deploy/webhook.ts', { ...commonStubs, '../../i18n': i18n })

const realFetch = globalThis.fetch
let answer = null
let requests = []
globalThis.fetch = async (url, init) => {
  requests.push({ url: String(url), method: init.method, contentType: init.headers['content-type'], body: init.body })
  if (answer.real) return realFetch(url, init)
  if (answer.timeout) { const e = new Error('The operation was aborted due to timeout'); e.name = 'TimeoutError'; throw e }
  if (answer.network) throw new TypeError('fetch failed')
  return new Response(answer.body === '' ? null : answer.body, { status: answer.status, statusText: answer.statusText })
}

const token = '0b7e6c1a-2f9d-4c3e-9a8b-7d6c5e4f3a2b'
const hook = `https://webhook.site/${token}`
const long = 'x'.repeat(1990) + token + 'y'.repeat(1000)
const cases = [
  { name: 'no URL', secret: null },
  { name: 'empty URL', secret: '' },
  { name: 'not a URL', secret: 'hooks/abc' },
  { name: 'http', secret: 'http://example.com/hook/abcdefghij' },
  { name: 'mailto', secret: 'mailto:hook@example.com' },
  { name: 'created, the token echoed in another shape', secret: hook,
    answer: { status: 201, statusText: 'Created', body: `Change response in <a href="https://webhook.site/#!/edit/${token}">` } },
  { name: 'not found', secret: 'https://api.netlify.com/build_hooks/5f1a2b3c4d5e6f7a8b9c0d1e', answer: { status: 404, statusText: 'Not Found', body: '{"message":"Not Found"}' } },
  { name: 'ok without a body', secret: 'https://API.Example.com:443/hooks/build/AbCdEfGhIjKl', answer: { status: 200, statusText: 'OK', body: '' } },
  { name: 'a long body is cut after the blanking', secret: hook, answer: { status: 500, statusText: 'Internal Server Error', body: long } },
  { name: 'secrets in the query and the fragment', secret: 'https://example.com:8443/h?token=abcdefgh12&x=1&name=zwei+w%C3%B6rter#frag-secret-123',
    answer: { status: 202, statusText: 'Accepted', body: 'abcdefgh12 x=1 frag-secret-123 zwei wörter hooks' } },
  { name: 'a body in UTF-8', secret: hook, answer: { status: 200, statusText: 'OK', body: 'Grüße aus Köln ✓' } },
  { name: 'a timeout', secret: hook, answer: { timeout: true } },
  { name: 'the network fails', secret: hook, answer: { network: true } },
  { name: 'credentials in the URL', secret: 'https://user:passwort-12345@example.com/hook/abcdefghij', answer: { real: true } },
  { name: 'a part of exactly eight characters is blanked', secret: 'https://example.com/abcdefgh/1234567', answer: { status: 200, statusText: 'OK', body: 'abcdefgh 1234567' } },
  { name: 'a redirect that was not followed is no success', secret: hook, answer: { status: 302, statusText: 'Found', body: 'moved' } },
  { name: 'a status with a phrase of its own', secret: hook, answer: { status: 403, statusText: 'Forbidden', body: 'no' } },
]
const results = []
for (const c of cases) {
  answer = c.answer ?? null
  requests = []
  const events = []
  const ctx = { projectPath: '/p', target: { id: 't', name: 'Hook', destination: { type: 'webhook' }, excludes: [] }, buildDir: '/b', secret: c.secret,
    emitProgress: (processed, total, currentFile) => events.push({ processed, total, currentFile }) }
  const result = await webhookAdapter.run(ctx)
  results.push({ ...c, result, requests, events })
}
const preview = await webhookAdapter.preview()

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify({ cases: results, preview }, null, 1) + '\n')
console.log(`${results.length} cases`)
