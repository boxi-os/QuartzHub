#!/usr/bin/env node
// Golden files for ThemePresets, StyleSettingsSchema and ThemeMarketplace, made by QuartzControl's
// own themePresetsService.ts, styleSettingsSchemaService.ts and themeMarketplaceService.ts, with
// the network scripted (global fetch replaced: the Obsidian theme registry, theme.css files on
// raw.githubusercontent.com, GitHub's org listing, jsDelivr), `npm search` and `npm install`
// replaced, and Electron's userData in a temporary folder. Each step records its answer, the
// requests it made and the files it left (presets, the theme-docs cache).
//
//   Runtime/node/bin/node scripts/themes-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'themes')
const work = mkdtempSync(join(tmpdir(), 'qh-themes-golden-'))
const userData = join(work, 'userData')
mkdirSync(userData, { recursive: true })

const electron = `export const app = { getPath: () => ${JSON.stringify(userData)} }`
const presets = await loadQuartzControl(control, 'electron/main/services/themePresetsService.ts', commonStubs)
const settings = await loadQuartzControl(control, 'electron/main/services/styleSettingsSchemaService.ts', { ...commonStubs, electron })
const market = await loadQuartzControl(control, 'electron/main/services/themeMarketplaceService.ts', {
  ...commonStubs, electron,
  child_process: `import { EventEmitter } from 'events'
    export function spawn(cmd, args) {
      globalThis.__commands.push([cmd, ...args])
      const child = new EventEmitter()
      child.stdout = new EventEmitter()
      child.kill = () => {}
      const answer = globalThis.__npmSearch
      setTimeout(() => {
        if (answer.error) { child.emit('error', new Error('spawn npm ENOENT')); return }
        child.stdout.emit('data', Buffer.from(answer.stdout))
        child.emit('close', answer.code ?? 0)
      }, 1)
      return child
    }`,
  './connectionsService': 'export async function getGithubToken() { return undefined }',
  './runCommand': `export function needsShell() { return false }
    export async function runCommand(cmd, args, cwd) { globalThis.__commands.push([cmd, ...args]); return { success: true, output: 'added 2 packages' } }`
})

// ── the scripted network ─────────────────────────────────────────────────────────────────────
const REGISTRY = 'https://raw.githubusercontent.com/obsidianmd/obsidian-releases/master/community-css-themes.json'
const raw = (repo, file) => `https://raw.githubusercontent.com/${repo}/HEAD/${file}`
const tokyoCss = `/* @settings
name: Appearance
id: tokyo-night-appearance
settings:
  - id: heading-a
    title: Colours
    type: heading
    level: 2
    collapsed: true
  - id: accent
    title: Accent
    description: The colour of links
    type: variable-themed-color
    format: hex
    default-light: '#3d59a1'
    default-dark: '#7aa2f7'
  - id: width
    title: Line width
    type: variable-number-slider
    default: 700
    min: '400'
    max: 1200
    step: 10
  - id: font
    type: variable-select
    default: Inter
    options:
      - Inter
      - label: Serif
        value: Georgia
      - { label: Broken }
      - 42
  - id: toggle
    title: Toggle
    type: class-toggle
    default: true
  - id: weird
    type: something-new
  - title: no id
    type: info-text
  - id: 12
    type: variable-number
    level: x
    default: 3
*/
body { color: red; }
/* @settings
id: tokyo-night-editor
settings:
  - id: editor-a
    title: Editor
    type: class-select
    allowEmpty: false
    options: [a, b]
*/
/* @settings
id: broken
settings:
  - id: [unclosed
*/
/* @settings
name: no-settings-list
settings: nope
*/`
const registry = [
  { name: 'Tokyo Night', author: 'tcmmichaelb139', repo: 'tcmmichaelb139/obsidian-tokyonight', screenshot: 'images/shot.png' },
  { name: "80's Neon", author: 'someone', repo: 'someone/neon' },
  { name: 'Café Élégant', author: 'x', repo: 'x/cafe' },
  { name: 'Evil', author: 'e', repo: '../../evil' },
  { name: 'No Settings', author: 'n', repo: 'n/none' },
  { name: 'Obsidian Only', author: 'o', repo: 'o/only' },
  { name: 'Huge', author: 'h', repo: 'h/huge' },
  { name: 'Anon', repo: 'a/anon' }
]
const net = {
  [REGISTRY]: { status: 200, json: registry },
  [raw('tcmmichaelb139/obsidian-tokyonight', 'theme.css')]: { status: 200, text: tokyoCss },
  [raw('someone/neon', 'theme.css')]: { status: 200, text: '/* @settings\nid: neon\nsettings:\n  - id: glow\n    type: class-toggle\n*/' },
  [raw('x/cafe', 'theme.css')]: { status: 404, text: 'no' },
  [raw('x/cafe', 'obsidian.css')]: { status: 200, text: '/*@settings\nid: cafe\nsettings: []\n*/' },
  [raw('n/none', 'theme.css')]: { status: 200, text: 'body {}' },
  [raw('o/only', 'theme.css')]: { fail: true },
  [raw('o/only', 'obsidian.css')]: { status: 200, text: '/* @settings\nid: only\nsettings:\n  - id: x\n    type: heading\n*/' },
  [raw('a/anon', 'theme.css')]: { status: 200, text: '/* @settings\nid: anon\nsettings:\n  - id: t\n    type: class-toggle\n*/' },
  [raw('h/huge', 'theme.css')]: { status: 200, headers: { 'content-length': String(17 * 1024 * 1024) }, text: '/* @settings\nid: huge\nsettings: []\n*/' },
  'https://api.github.com/orgs/quartz-themes/repos?per_page=100&page=1': { status: 200, json: [
    { name: 'tokyo-night', stargazers_count: 3, topics: ['obsidian', 'dark'], description: 'Tokyo Night for Quartz' },
    { name: 'minimal', stargazers_count: 0, topics: [], description: null },
    { name: 'unlisted', stargazers_count: 9, topics: ['x'], description: 'not on npm' }] },
  'https://cdn.jsdelivr.net/npm/@quartz-themes/catppuccin/theme.json': { status: 200, json: { meta: { styleSettingsId: 'catppuccin-style', modes: ['dark', 'light'], variations: ['frappe', 'latte'], fonts: ['Inter'] } } },
  'https://cdn.jsdelivr.net/npm/@quartz-themes/plain/theme.json': { status: 200, json: { meta: {} } },
  'https://cdn.jsdelivr.net/npm/@quartz-themes/listid/theme.json': { status: 200, json: { meta: { styleSettingsId: ['a', 'b'] } } },
  'https://cdn.jsdelivr.net/npm/@quartz-themes/gone/theme.json': { status: 404, text: 'nope' },
  'https://cdn.jsdelivr.net/npm/@quartz-themes/down/theme.json': { fail: true },
  'https://cdn.jsdelivr.net/npm/@quartz-themes/nullbody/theme.json': { status: 200, json: null }
}
let requests = []
globalThis.fetch = async (input, init = {}) => {
  const url = String(input)
  requests.push({ url, authorization: init.headers?.Authorization ?? null, accept: init.headers?.Accept ?? null })
  const answer = net[url]
  if (!answer || answer.fail) throw new TypeError('fetch failed')
  const body = answer.json !== undefined ? JSON.stringify(answer.json) : answer.text ?? ''
  const headers = new Map(Object.entries(answer.headers ?? {}))
  return { ok: answer.status >= 200 && answer.status < 300, status: answer.status, headers: { get: (n) => headers.get(n.toLowerCase()) ?? null },
    text: async () => body, json: async () => JSON.parse(body) }
}

// ── steps ────────────────────────────────────────────────────────────────────────────────────
const project = join(work, 'project')
mkdirSync(join(project, 'node_modules', '@quartz-themes', 'tokyo-night'), { recursive: true })
writeFileSync(join(project, 'node_modules', '@quartz-themes', 'tokyo-night', 'theme.json'), JSON.stringify({ meta: { styleSettingsId: 'tokyo-night-appearance', modes: ['dark'], variations: [], fonts: ['Inter'] }, classSettings: {} }))
const npmOutput = JSON.stringify([
  { name: '@quartz-themes/core', description: 'the transformer' }, { name: '@quartz-themes/tokyo-night', description: 'Tokyo Night' },
  { name: '@quartz-themes/minimal' }, { name: 'quartz-themes-fake', description: 'not ours' }, { name: '@quartz-themes/catppuccin', description: 'Catppuccin' }])
const step = (service, call, ...args) => ({ service, call, args })
const steps = [
  step('presets', 'listPresets'),
  step('presets', 'savePreset', { id: 'p1', name: 'Dunkel', createdAt: '2026-11-06T10:00:00.000Z', baseThemeId: 'tokyo-night', options: { a: 1 } }),
  step('presets', 'savePreset', { id: 'p2', name: 'Hell', createdAt: '2026-11-06T11:00:00.000Z', options: {} }),
  step('presets', 'savePreset', { id: 'p1', name: 'Dunkel neu', createdAt: '2026-11-06T12:00:00.000Z', options: { b: [1, 2] } }),
  step('presets', 'deletePreset', 'p2'), step('presets', 'deletePreset', 'nie-da'), step('presets', 'listPresets'),
  step('presets', 'writeRaw', '{ kaputt'), step('presets', 'listPresets'), step('presets', 'savePreset', { id: 'p3', name: 'Nach dem Bruch', options: {} }),
  step('settings', 'getStyleSettingsSchema', 'tokyo-night'), step('settings', 'getStyleSettingsSchema', 'tokyo-night'),
  step('settings', 'getStyleSettingsSchema', '80s-neon.variant'), step('settings', 'getStyleSettingsSchema', 'cafe-elegant'),
  step('settings', 'getStyleSettingsSchema', 'evil'), step('settings', 'getStyleSettingsSchema', 'no-settings'),
  step('settings', 'getStyleSettingsSchema', 'obsidian-only'), step('settings', 'getStyleSettingsSchema', 'huge'),
  step('settings', 'getStyleSettingsSchema', 'not-in-registry'), step('settings', 'getStyleSettingsSchema', 'anon'),
  step('settings', 'themeDocsCacheStats'), step('settings', 'clearStyleSettingsSchemaCache', 'tokyo-night'), step('settings', 'themeDocsCacheStats'),
  step('settings', 'getStyleSettingsSchema', 'tokyo-night'),
  step('settings', 'registryDown'),
  // The registry from the copy on disk: the memo is gone with the cleared entry, the network is down.
  step('settings', 'clearStyleSettingsSchemaCache', 'tokyo-night'), step('settings', 'getStyleSettingsSchema', 'tokyo-night'),
  step('settings', 'clearThemeDocsCache'), step('settings', 'themeDocsCacheStats'),
  step('settings', 'getStyleSettingsSchema', 'tokyo-night'),
  step('market', 'npm', { stdout: npmOutput }), step('market', 'listThemes'), step('market', 'listThemes'),
  step('market', 'getThemeDetail', 'tokyo-night'), step('market', 'getThemeDetail', 'catppuccin'), step('market', 'getThemeDetail', 'catppuccin'),
  step('market', 'getThemeDetail', 'plain'), step('market', 'getThemeDetail', 'listid'), step('market', 'getThemeDetail', 'gone'), step('market', 'getThemeDetail', 'gone'),
  step('market', 'getThemeDetail', 'nullbody'), step('market', 'getThemeDetail', 'nullbody'),
  step('market', 'getThemeDetail', 'down'), step('market', 'getThemeDetail', 'down'),
  step('market', 'installTheme', 'catppuccin'),
  step('market', 'invalidateCache'), step('market', 'npm', { stdout: 'not json' }), step('market', 'listThemes'),
  step('market', 'npm', { stdout: '[]' }), step('market', 'listThemes'),
  step('market', 'npm', { error: true }), step('market', 'listThemes'),
  step('market', 'npm', { stdout: JSON.stringify([{ name: '@quartz-themes/core' }]) }), step('market', 'listThemes'),
  // One entry without a name costs the whole answer: `p.name.startsWith` throws.
  step('market', 'npm', { stdout: JSON.stringify([{ description: 'no name' }, { name: '@quartz-themes/kept' }]) }), step('market', 'listThemes')
]
const filesOf = () => {
  const result = {}
  const walk = (dir, prefix) => {
    if (!existsSync(dir)) return
    for (const name of readdirSync(dir).sort()) {
      const full = join(dir, name)
      try { result[prefix + name] = readFileSync(full, 'utf8') } catch { walk(full, `${prefix}${name}/`) }
    }
  }
  walk(join(project, '.quartz-gui'), 'project/.quartz-gui/')
  walk(join(userData, 'theme-docs'), 'theme-docs/')
  return result
}
const results = []
let before = filesOf()
for (const s of steps) {
  requests = []
  globalThis.__commands = []
  let result = null
  if (s.call === 'writeRaw') { mkdirSync(join(project, '.quartz-gui'), { recursive: true }); writeFileSync(join(project, '.quartz-gui', 'theme-presets.json'), s.args[0]) }
  else if (s.call === 'npm') globalThis.__npmSearch = s.args[0]
  else if (s.call === 'registryDown') net[REGISTRY].fail = true
  else {
    const service = { presets, settings, market }[s.service]
    const takesProject = s.service === 'presets' || ['getThemeDetail', 'installTheme'].includes(s.call)
    try { result = (await service[s.call](...(takesProject ? [project, ...s.args] : s.args))) ?? null } catch (error) { result = { threw: String(error) } }
  }
  const after = filesOf()
  const changed = {}
  for (const p of new Set([...Object.keys(before), ...Object.keys(after)])) {
    if (before[p] !== after[p]) changed[p.replace(/corrupt-[^/]*$/, 'corrupt-*')] = after[p] ?? null
  }
  results.push({ ...s, result: JSON.parse(JSON.stringify(result).replaceAll(project, '@P@')), requests, commands: globalThis.__commands, changed })
  before = after
}
rmSync(work, { recursive: true, force: true })
rmSync(out, { recursive: true, force: true })
mkdirSync(out, { recursive: true })
// The scripted network, for the Swift test to answer from.
writeFileSync(join(out, 'net.json'), JSON.stringify({ net: Object.fromEntries(Object.entries(net).map(([k, v]) => [k, k === REGISTRY ? { ...v, fail: false } : v])), registry: REGISTRY, npmOutput }, null, 2) + '\n')
writeFileSync(join(out, 'steps.json'), JSON.stringify(results, null, 2) + '\n')
console.log(`themes: ${results.length} steps`)
for (const r of results) console.log(`  ${r.service}.${r.call} ${JSON.stringify(r.args).slice(0, 40)}: ${JSON.stringify(r.result).slice(0, 110)} | ${r.requests.length} req ${Object.keys(r.changed).join(',')}`)
