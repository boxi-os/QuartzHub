#!/usr/bin/env node
// Golden file for GitHubAPI, made by QuartzControl's own githubService.ts with its real runCommand
// (git for the origin) and `fetch` replaced by a script: each step names the token (a string, none,
// or one that cannot be read), the answers GitHub gives in order (status and body, or a failure on
// the way), the call and its arguments; it records the answer, every request (method, URL, the
// four headers, body) and the project's origin afterwards.
//
//   Runtime/node/bin/node scripts/github-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { spawnSync } from 'node:child_process'
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'github')
const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-github-golden-')))
writeFileSync(join(work, 'gitconfig'), '')
for (const key of Object.keys(process.env)) if (key.startsWith('GIT_')) delete process.env[key]
Object.assign(process.env, { PATH: '/usr/bin:/bin', GIT_CONFIG_GLOBAL: join(work, 'gitconfig'), GIT_CONFIG_NOSYSTEM: '1' })

globalThis.__token = { value: 'ghp_token' }
const stubs = {
  ...commonStubs,
  './connectionsService': `export async function getGithubToken() {
  const t = globalThis.__token
  if (t.unreadable) throw new Error(JSON.stringify({ key: 'secretStorageUnreadableMac', args: {} }))
  return t.value
}`
}
const github = await loadQuartzControl(control, 'electron/main/services/githubService.ts', stubs)

let answers = []
let requests = []
globalThis.fetch = async (url, init) => {
  const h = init.headers
  requests.push({ method: init.method, url: String(url), accept: h.accept, version: h['x-github-api-version'], authorization: h.authorization,
    contentType: h['content-type'] ?? null, body: init.body ?? null })
  const a = answers.shift()
  if (!a) throw new Error('no answer scripted')
  if (a.timeout) { const e = new Error('The operation was aborted due to timeout'); e.name = 'TimeoutError'; throw e }
  if (a.network) throw new TypeError('fetch failed')
  return new Response(a.body ?? null, { status: a.status })
}

const git = (args, cwd) => spawnSync('/usr/bin/git', args, { cwd, encoding: 'utf-8' })
const projects = { none: join(work, 'ohne Origin'), github: join(work, 'Gärten-Ü'), gitlab: join(work, 'gitlab') }
for (const p of Object.values(projects)) { mkdirSync(p, { recursive: true }); git(['init', '-q'], p) }
git(['remote', 'add', 'origin', 'https://github.com/boxi-os/site.git'], projects.github)
git(['remote', 'add', 'origin', 'git@gitlab.com:boxi/site.git'], projects.gitlab)

const steps = []
async function step(name, call, args, scripted = [], token = { value: 'ghp_token' }) {
  globalThis.__token = token
  answers = [...scripted]
  requests = []
  const project = projects[args[0]]
  let result
  try {
    let value
    switch (call) {
      case 'viewer': value = await github.getViewer(); break
      case 'originRepo': value = await github.getOriginRepo(project); break
      case 'createRepo': value = await github.createRepo(project, args[1]); break
      case 'pagesInfo': value = await github.getPagesInfo(project); break
      case 'configurePages': value = await github.configurePages(project, args[1]); break
    }
    result = { ok: value ?? null }
  } catch (err) {
    result = { error: String(err.message ?? err) }
  }
  const origins = Object.fromEntries(Object.entries(projects).map(([k, p]) => [k, git(['remote', 'get-url', 'origin'], p).stdout.trim() || null]))
  steps.push({ name, call, args, token, scripted, result, requests, origins, unused: answers.length })
}

const json = (status, body) => ({ status, body: JSON.stringify(body) })
await step('viewer', 'viewer', [null], [json(200, { login: 'boxi-os', name: 'Boxi Ö', id: 1 })])
await step('viewer without a name', 'viewer', [null], [json(200, { login: 'boxi-os', name: null })])
await step('viewer refused', 'viewer', [null], [json(401, { message: 'Bad credentials' })])
await step('viewer without a token', 'viewer', [null], [], { value: undefined })
await step('viewer with an empty token', 'viewer', [null], [], { value: '' })
await step('viewer with a token that cannot be read', 'viewer', [null], [], { unreadable: true })
await step('viewer, network down', 'viewer', [null], [{ network: true }])
await step('viewer, timeout', 'viewer', [null], [{ timeout: true }])
await step('origin on github', 'originRepo', ['github'])
await step('origin elsewhere', 'originRepo', ['gitlab'])
await step('no origin', 'originRepo', ['none'])
await step('create where there is an origin', 'createRepo', ['github', { name: 'site', private: true }])
await step('create without a token', 'createRepo', ['none', { name: 'site', private: false }], [], { value: undefined })
await step('create refused', 'createRepo', ['none', { name: 'site', private: false, description: 'Meine Seite' }],
  [json(422, { message: 'Repository creation failed.', errors: [{ message: 'name already exists on this account' }] })])
await step('create, an error page', 'createRepo', ['none', { name: 'site', private: false }], [{ status: 502, body: '<html>Bad gateway</html>' }])
await step('create, a 200 is not a 201', 'createRepo', ['none', { name: 'site', private: false }], [json(200, { full_name: 'boxi-os/site' })])
await step('create', 'createRepo', ['none', { name: 'site-ü', private: true, description: 'Gärten' }],
  [json(201, { full_name: 'boxi-os/site-ü', clone_url: 'https://github.com/boxi-os/site-ü.git', html_url: 'https://github.com/boxi-os/site-ü' })])
await step('pages elsewhere', 'pagesInfo', ['gitlab'])
await step('pages none yet', 'pagesInfo', ['github'], [json(404, { message: 'Not Found' })])
await step('pages', 'pagesInfo', ['github'], [json(200, { status: 'built', html_url: 'https://boxi-os.github.io/site/', cname: null, https_enforced: true,
  source: { branch: 'gh-pages', path: '/' }, public: true })])
await step('pages without a status', 'pagesInfo', ['github'], [json(200, { html_url: 'https://x/', cname: 'blog.example.org', https_enforced: false })])
await step('pages forbidden', 'pagesInfo', ['github'], [json(403, { message: 'Resource not accessible by personal access token' })])
await step('pages, an error page', 'pagesInfo', ['github'], [{ status: 500, body: 'oops' }])
await step('pages without a token', 'pagesInfo', ['github'], [], { value: undefined })
await step('configure elsewhere', 'configurePages', ['gitlab', { branch: 'gh-pages' }])
await step('configure a new site with https', 'configurePages', ['github', { branch: 'gh-pages', httpsEnforced: true }],
  [json(404, { message: 'Not Found' }), json(201, { status: null }), { status: 204 }])
await step('configure, creation refused', 'configurePages', ['github', { branch: 'gh-pages' }],
  [json(404, {}), json(422, { message: 'Your current plan does not support GitHub Pages for this repository.' })])
await step('configure a domain, https not yet', 'configurePages', ['github', { branch: 'gh-pages', cname: 'blog.example.org', httpsEnforced: true }],
  [json(200, {}), { status: 204 }, json(404, { message: 'The certificate does not exist yet' })])
await step('configure, clear the domain', 'configurePages', ['github', { branch: 'pages', cname: '' }], [json(200, {}), { status: 204 }])
await step('configure, domain null', 'configurePages', ['github', { branch: 'pages', cname: null, httpsEnforced: false }],
  [json(200, {}), { status: 204 }, { status: 204 }])
await step('configure, saving refused', 'configurePages', ['github', { branch: 'gh-pages' }], [json(200, {}), { status: 409, body: '' }])
await step('configure, a 200 is not the 204 it means', 'configurePages', ['github', { branch: 'gh-pages' }], [json(200, {}), json(200, {})])
await step('configure without a token', 'configurePages', ['github', { branch: 'gh-pages' }], [], { value: undefined })

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'steps.json'), JSON.stringify({ steps }, null, 1) + '\n')
rmSync(work, { recursive: true, force: true })
console.log(`${steps.length} steps`)
