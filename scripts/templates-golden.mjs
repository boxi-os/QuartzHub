#!/usr/bin/env node
// Golden file for TemplatePackage, made by QuartzControl's own templatePackage/ (index.ts,
// parts.ts, shared.ts) with the real services underneath (config, styles, fonts, frames, locales,
// presets, icon, content). Projects in a temporary folder, built here and recorded as trees; then
// steps: inspect, export (the package's entries unpacked), dry run and import with both strategies
// of four packages (the source's own export, QuartzControl's qc-basic.qtpl, a folder of the format
// before 1, one built to be hostile), and after each the answer, the files it changed in that
// project, the commands (npm, `quartz plugin add`) and the snapshots it asked for.
//
// npm and the Quartz CLI are scripted: `npm install` writes node_modules/<name>/package.json, the
// CLI succeeds without touching the config. git is real (export asks `rev-parse`).
//
//   Runtime/node/bin/node scripts/templates-golden.mjs [../QuartzControl] [~/Documents/QuartzProjekte]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { spawnSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const projects = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte'))
const fixtures = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures')
const out = join(fixtures, 'templates')

globalThis.__commands = []
globalThis.__snapshots = []
const runCommand = `
const { spawnSync } = require('node:child_process')
const { mkdirSync, writeFileSync } = require('node:fs')
const { join } = require('node:path')
export async function runCommand(command, args, cwd) {
  if (command === 'npm') {
    globalThis.__commands.push(['npm', ...args])
    for (const name of args.slice(1)) {
      mkdirSync(join(cwd, 'node_modules', name), { recursive: true })
      writeFileSync(join(cwd, 'node_modules', name, 'package.json'), JSON.stringify({ name, version: '0.0.0-stub' }) + '\\n')
    }
    return { success: true, output: 'added ' + (args.length - 1) + ' packages', stdout: '' }
  }
  const r = spawnSync(command, args, { cwd, encoding: 'utf-8' })
  return { success: r.status === 0, output: (r.stdout ?? '') + (r.stderr ?? ''), stdout: r.stdout ?? '' }
}`
const pluginService = `
export async function installPluginSource(project, source) {
  globalThis.__commands.push(['quartz', 'plugin', 'add', source])
  // The real CLI appends a bare entry of its own; a frame's (an absolute path) is left without one.
  if (!source.startsWith('/')) await globalThis.__cliAppends(project, source)
  return { success: true, output: '' }
}
export async function addPlugin(project, source) { globalThis.__commands.push(['quartz', 'plugin', 'add', source]); return { success: true, output: '' } }
export async function removePlugin(project, name) { globalThis.__commands.push(['quartz', 'plugin', 'remove', name]); return { success: true, output: '' } }`
const snapshot = `export async function createSnapshot(project, kind, label) { globalThis.__snapshots.push([kind, label ?? null]); return null }`
const stubs = {
  ...commonStubs,
  '../../i18n': commonStubs['../i18n'],
  './snapshotService': snapshot,
  '../snapshotService': snapshot,
  './runCommand': runCommand,
  '../runCommand': runCommand,
  './pluginService': pluginService,
  '../pluginService': pluginService,
  './backupService': 'export async function snapshotContent() {}',
  './projectDependencies': 'export function halfUnpackedModule() { return null }\nexport async function missingDependencies() { return [] }',
  electron: `export const app = { getVersion: () => '1.3.0', getPath: () => globalThis.__userData, getAppPath: () => '/nonexistent', isPackaged: false }
export const net = { fetch: async () => { throw new Error('no network here') } }
export const nativeImage = { createFromBuffer: () => ({ isEmpty: () => true, getSize: () => ({ width: 0, height: 0 }) }), createFromPath: () => ({ isEmpty: () => true }) }`
}
const tp = await loadQuartzControl(control, 'electron/main/services/templatePackage/index.ts', stubs)
const style = await loadQuartzControl(control, 'electron/main/services/styleService.ts', stubs)
const frames = await loadQuartzControl(control, 'electron/main/services/layoutFrameService.ts', stubs)
const locales = await loadQuartzControl(control, 'electron/main/services/localizationService.ts', stubs)
const presets = await loadQuartzControl(control, 'electron/main/services/themePresetsService.ts', stubs)
const configService = await loadQuartzControl(control, 'electron/main/services/configService.ts', stubs)
globalThis.__cliAppends = async (project, source) => {
  const config = await configService.readConfig(project)
  await configService.writeConfig(project, { ...config, plugins: [...config.plugins, { source, enabled: true }] }, { snapshot: false })
}

const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-templates-golden-')))
globalThis.__userData = join(work, 'userData')
const mask = (text) => text.replaceAll(work, '@W@')
const sha = (data) => createHash('sha256').update(data).digest('hex')

// A tree as the Swift test rebuilds it: text where the bytes are UTF-8 and short, else a blob
// (base64, kept once in blobs.json by its sha256: the same fonts and pictures lie in many projects).
const blobs = {}
let keepBlobs = false
function describeFile(data) {
  const text = data.toString('utf-8')
  if (Buffer.from(text, 'utf-8').equals(data) && !text.includes('\0') && data.length <= 200_000) return { text: mask(text) }
  const id = sha(data)
  if (keepBlobs) blobs[id] = data.toString('base64')
  return { blob: id, length: data.length }
}
function tree(root) {
  const files = {}
  const walk = (dir) => {
    for (const name of readdirSync(dir).sort()) {
      if (name === '.git') continue
      const full = join(dir, name)
      const rel = relative(root, full)
      const info = lstatSync(full)
      if (info.isSymbolicLink()) files[rel] = { link: mask(readlinkSync(full)) }
      else if (info.isDirectory()) { files[rel] = { dir: true }; walk(full) }
      else files[rel] = describeFile(readFileSync(full))
    }
  }
  if (existsSync(root)) walk(root)
  return files
}
// What a step changed, a file as its sha256 and length when it is not short text.
function brief(entry) {
  if (!entry) return null
  if (entry.blob !== undefined) return { sha256: entry.blob, length: entry.length }
  if (entry.text !== undefined && entry.text.length > 4000) return { sha256: sha(Buffer.from(entry.text, 'utf-8')), length: Buffer.byteLength(entry.text) }
  return entry
}

function put(root, files) {
  for (const [path, data] of Object.entries(files)) {
    const full = join(root, path)
    mkdirSync(dirname(full), { recursive: true })
    writeFileSync(full, data)
  }
}

// ── the material ─────────────────────────────────────────────────────────────────────────────
const fontFiles = join(fixtures, 'font-file', 'files')
const woff2 = readdirSync(fontFiles).filter((n) => n.endsWith('.woff2') && !n.includes('bomb')).sort()
const fontA = readFileSync(join(fontFiles, woff2[0]))
const fontB = readFileSync(join(fontFiles, woff2[1]))
const quartzIcon = readFileSync(join(projects, 'gui-test', 'quartz', 'static', 'icon.png'))
const ownIcon = Buffer.concat([quartzIcon.subarray(0, 64), Buffer.from('eigenes Bild')])
const deDE = readFileSync(join(projects, 'gui-test', 'quartz', 'i18n', 'locales', 'de-DE.ts'))
const enUS = readFileSync(join(projects, 'gui-test', 'quartz', 'i18n', 'locales', 'en-US.ts'))
const definition = readFileSync(join(projects, 'gui-test', 'quartz', 'i18n', 'locales', 'definition.ts'))

const layoutOf = (over = {}) => ({ rows: 2, cols: 2, rowGap: '1rem', columnGap: '1rem', placements: {}, ...over })
const frameDef = (over = {}) => ({
  id: 'frame-made', frameName: 'Gemacht',
  areas: [{ id: 'a1', name: 'top', slot: 'header' }, { id: 'a2', name: 'body', slot: 'pageBody' }],
  breakpoints: {
    desktop: layoutOf({ placements: { a1: { row: 1, col: 1, rowSpan: 1, colSpan: 2 }, a2: { row: 2, col: 1, rowSpan: 1, colSpan: 2 } } }),
    tablet: layoutOf({ cols: 1, placements: { a1: { row: 1, col: 1, rowSpan: 1, colSpan: 1 }, a2: { row: 2, col: 1, rowSpan: 1, colSpan: 1 } } }),
    mobile: layoutOf({ cols: 1, placements: { a1: { row: 1, col: 1, rowSpan: 1, colSpan: 1 }, a2: { row: 2, col: 1, rowSpan: 1, colSpan: 1 } } })
  },
  ...over
})

const scaffold = (plugins = '[]', extra = '') => `configuration:
  pageTitle: Ziel
  locale: de-DE
  baseUrl: example.org
  theme:
    fontOrigin: googleFonts
    cdnCaching: true
    typography:
      header: Schibsted Grotesk
      body: Source Sans Pro
      code: IBM Plex Mono
    colors:
      lightMode:
        light: "#faf8f8"
        dark: "#2b2b2b"
      darkMode:
        light: "#161618"
        dark: "#ebebec"
plugins: ${plugins}
${extra}`

function baseProject(dir, { config = scaffold(), icon = quartzIcon, content = true } = {}) {
  put(dir, {
    'quartz.config.yaml': config,
    'package.json': '{ "name": "ziel", "version": "1.0.0" }\n',
    'quartz/styles/custom.scss': '@use "./base.scss";\n\n// put your custom CSS here!\n',
    'quartz/styles/base.scss': '/* Quartz */\n',
    'quartz/static/icon.png': icon,
    'quartz/static/og-image.png': Buffer.from('og'),
    'quartz/i18n/locales/de-DE.ts': deDE,
    'quartz/i18n/locales/en-US.ts': enUS,
    'quartz/i18n/locales/definition.ts': definition
  })
  if (content) mkdirSync(join(dir, 'content'), { recursive: true })
}

const sourceConfig = scaffold(`
  - source: "@quartz-themes/core"
    enabled: true
    options:
      theme: tokyo-night
      styleSettings:
        accent: blue
        width: wide
  - source: "@quartz-community/explorer"
    enabled: true
    layout:
      position: left
      priority: 20
  - source: "@quartz-community/backlinks"
    enabled: false
  - source: "@quartz-community/explorer"
    enabled: false
  - source: github:boxi-os/quartz-layout-box
    enabled: true
    options:
      title: Erste
  - source: github:boxi-os/quartz-layout-box
    enabled: true
    options:
      title: Zweite
  - source: github:boxi-os/quartz-forms
    enabled: true
    options:
      transport:
        kind: none
      forms:
        kontakt:
          fields: [name]
        newsletter:
          fields: [mail]`, `layout:
  groups:
    nav:
      priority: 1
  byPageType:
    tag:
      exclude: [explorer]
`).replace('fontOrigin: googleFonts', 'fontOrigin: local').replace('cdnCaching: true', 'cdnCaching: false').replace('pageTitle: Ziel', 'pageTitle: Quelle')
  .replace('header: Schibsted Grotesk', 'header: Inter').replace('light: "#faf8f8"', 'light: "#ffffff"')

async function makeSource(dir) {
  baseProject(dir, { config: sourceConfig })
  put(dir, {
    'quartz/styles/custom.scss': '@use "./base.scss";\n@use "./quelle.scss";\n\n// put your custom CSS here!\n.quelle { color: red; }\n',
    'quartz/styles/quelle.scss': '.q {}\n',
    'quartz/styles/custom/a.scss': '.a { color: var(--tpl-accent); }\n',
    'quartz/styles/custom/b.scss': ':root { --tpl-accent: red; }\n.b { margin: var(--tpl-gap); }\n',
    'quartz/styles/custom/unloaded.scss': '.u {}\n',
    [`quartz/static/fonts/${woff2[0]}`]: fontA,
    [`quartz/static/fonts/${woff2[1]}`]: fontB,
    'quartz/static/notes/sidebar.md': 'Eine Notiz für die Box.\n',
    'quartz/static/.hidden': 'nie',
    'content/index.md': '# Start\n\nWillkommen.\n',
    'content/kontakt.md': '# Kontakt\n\n```quartz-form\nkontakt\n```\n\n```quartz-form\numfrage\n```\n',
    'content/bilder/bild.png': ownIcon,
    'content/.obsidian/app.json': '{}',
    'content-extra/verwiesen.md': '# Über einen Link\n',
    'node_modules/@quartz-themes/core/package.json': '{ "name": "@quartz-themes/core", "version": "2.0.0" }\n',
    'node_modules/@quartz-themes/tokyo-night/package.json': '{ "name": "@quartz-themes/tokyo-night", "version": "1.4.0" }\n',
    'node_modules/@quartz-community/explorer/package.json': '{ "name": "@quartz-community/explorer", "version": "1.0.3" }\n',
    '.quartz/plugins/quartz-layout-box/package.json': '{}\n'
  })
  // The managed blocks as the app writes them (moved, i.e. _quartzcontrol.scss): the load order,
  // the variables (one of them light only), the @font-face rules and a Google block.
  await style.setImportOrder(dir, ['custom/a.scss', 'custom/b.scss'])
  await style.saveVariableOverrides(dir, [
    { key: 'secondary', light: '#284b63', dark: '#7b97aa' },
    { key: 'tertiary', light: '#84a59d', lightOnly: true },
    { key: 'tpl-gap', light: '2rem' }
  ])
  const face = (family, file) => `@font-face {\n  font-family: "${family}";\n  src: url("../static/fonts/${file}") format("woff2");\n}`
  await style.writeManagedBlocks(dir, { fonts: `${face('Eins', woff2[0])}\n\n${face('Zwei', woff2[1])}` })
  await style.writeManagedBlocks(dir, { 'google-fonts': '/* https://fonts.googleapis.com/css2?family=Inter */\n@font-face {\n  font-family: "Inter";\n  src: url("../static/fonts/inter-latin.woff2") format("woff2");\n}' })
  await frames.saveFrame(dir, frameDef(), { snapshot: false })
  // The entry the real `quartz plugin add` writes (the scripted one writes none).
  const config = readFileSync(join(dir, 'quartz.config.yaml'), 'utf-8')
  writeFileSync(join(dir, 'quartz.config.yaml'), config.replace('\nlayout:', `\n  - source: ${join(dir, '.quartz-gui', 'authored-frames', 'frame-made')}\n    enabled: true\nlayout:`))
  await frames.saveBreakpointWidths(dir, { tablet: 1100, mobile: 700 })
  await locales.saveLocaleEntry(dir, 'de-DE', ['propertyDefaults', 'title'], 'string', 'Ohne Titel')
  await locales.saveLocaleEntry(dir, 'de-DE', ['components', 'recentNotes', 'seeRemainingMore'], 'template', '({ remaining }) => `noch ${remaining}`')
  await presets.savePreset(dir, { id: 'p-hell', name: 'Hell', themeId: 'tokyo-night', mode: 'light', styleSettings: { accent: 'blue' } })
  await presets.savePreset(dir, { id: 'p-dunkel', name: 'Dunkel', themeId: 'tokyo-night', mode: 'dark', styleSettings: {} })
  // A link to a folder is followed, a link back to an ancestor is not walked twice.
  symlinkSync(join(dir, 'content-extra'), join(dir, 'content', 'verweis'))
  symlinkSync(join(dir, 'content'), join(dir, 'content', 'schleife'))
  // quartz/static to a total with a remainder of .5 KB and more: Math.round, not floor.
  const staticBytes = (d) => readdirSync(d, { withFileTypes: true }).reduce((sum, e) => sum + (e.name.startsWith('.') ? 0 :
    e.isDirectory() ? (e.name === 'fonts' ? 0 : staticBytes(join(d, e.name))) : readFileSync(join(d, e.name)).length), 0)
  const total = staticBytes(join(dir, 'quartz', 'static'))
  writeFileSync(join(dir, 'quartz', 'static', 'pad.bin'), Buffer.alloc((Math.ceil(total / 1024) + 1) * 1024 + 700 - total, 1))
}

// A project with its own of everything: what 'projectWins' keeps and 'packageWins' replaces.
async function makeOwn(dir) {
  baseProject(dir, {
    icon: ownIcon,
    config: scaffold(`
  - source: "@quartz-themes/core"
    enabled: true
    order: 5
    options:
      theme: minimal
  - source: "@quartz-community/explorer"
    enabled: false
  - source: github:boxi-os/quartz-layout-box
    enabled: true
    options:
      title: Eigene
  - source: github:boxi-os/quartz-forms
    enabled: true
    options:
      transport:
        kind: relay
        url: https://example.org/relay.php
      forms:
        kontakt:
          fields: [eigenes]`)
  })
  put(dir, {
    'quartz/styles/custom/a.scss': '.a { color: green; }\n',
    'quartz/styles/custom/eigen.scss': '.eigen {}\n',
    [`quartz/static/fonts/${woff2[0]}`]: fontA,
    [`quartz/static/fonts/${woff2[1]}`]: Buffer.concat([fontB, Buffer.from('anders')]),
    'quartz/static/fonts/eigen.woff2': Buffer.concat([fontA, Buffer.from('eigen')]),
    'quartz/static/notes/sidebar.md': 'Meine eigene Notiz.\n',
    'content/index.md': '# Mein Start\n',
    '.quartz-gui/project-icon.json': '{ "custom": true, "hasOriginal": false }\n',
    'node_modules/@quartz-themes/core/package.json': '{ "name": "@quartz-themes/core", "version": "2.0.0" }\n',
    '.quartz/plugins/quartz-layout-box/package.json': '{}\n'
  })
  await style.setImportOrder(dir, ['custom/eigen.scss', 'custom/a.scss'])
  // Delivered locally like the source, but cached differently: one half of the switch differs.
  writeFileSync(join(dir, 'quartz.config.yaml'), readFileSync(join(dir, 'quartz.config.yaml'), 'utf-8').replace('fontOrigin: googleFonts', 'fontOrigin: local'))
  await style.saveVariableOverrides(dir, [{ key: 'secondary', light: '#000000', dark: '#ffffff' }, { key: 'eigen', light: '1px' }, { key: 'tpl-gap', light: '2rem', dark: '3rem' }])
  await style.writeManagedBlocks(dir, { fonts: `@font-face {\n  font-family: "Zwei";\n  src: url("../static/fonts/${woff2[1]}") format("woff2");\n}\n\n@font-face {\n  font-family: "Eigen";\n  src: url("../static/fonts/eigen.woff2") format("woff2");\n}` })
  await style.writeManagedBlocks(dir, { 'google-fonts': '/* https://fonts.googleapis.com/css2?family=Lora */\n@font-face {\n  font-family: "Lora";\n  src: url("../static/fonts/lora-latin.woff2") format("woff2");\n}' })
  await frames.saveFrame(dir, frameDef({ frameName: 'Mein Frame' }), { snapshot: false })
  await locales.saveLocaleEntry(dir, 'de-DE', ['propertyDefaults', 'title'], 'string', 'Mein Titel')
  await presets.savePreset(dir, { id: 'p-hell', name: 'Mein Hell', themeId: 'minimal', mode: 'light', styleSettings: {} })
}

// The format before 1: a folder.
function makeLegacy(dir) {
  put(dir, {
    'manifest.json': JSON.stringify({ name: 'Alte Vorlage', createdAt: '2026-08-01T10:00:00.000Z', categories: ['layout', 'colors', 'plugins', 'styles', 'fonts', 'frames'] }),
    'layout.json': JSON.stringify({ groups: { alt: { priority: 3 } } }),
    'colors.json': JSON.stringify({ colors: { lightMode: { light: '#ffffff' } }, typography: { header: 'Alt' }, fontOrigin: 'local',
      cssVariableOverrides: [{ key: 'secondary', light: '#111111', dark: '#eeeeee' }] }),
    'frames.json': JSON.stringify([frameDef({ id: 'frame-alt', frameName: 'Alt' })]),
    'plugins.json': JSON.stringify([
      { name: 'core', source: '@quartz-themes/core', enabled: true, options: { theme: 'alt-theme' } },
      { name: 'frame-alt', source: '/Users/someone/project/.quartz-gui/authored-frames/frame-alt', enabled: true },
      { name: 'explorer', source: '@quartz-community/explorer', enabled: true }
    ]),
    'custom.scss': '.alt { color: red; }\n',
    'imported/x.scss': '.x {}\n',
    'fonts/alt.woff2': fontA
  })
}

// Every name a package can use against the project, and parts this version cannot read.
function hostilePackage() {
  const parts = {
    styles: { customScss: '.h {}', order: ['../../escape.scss', 'custom/ok.scss'], files: ['../../escape.scss', 'custom/ok.scss', 'custom/linked/x.scss'] },
    fonts: { fontFaceCss: null, googleFontsCss: null, files: ['../evil.woff2', 'ok.woff2'] },
    static: { files: ['../../../outside.txt', 'notes/ok.md', 'link/through.md'] },
    content: { files: ['../PROOF.md', 'ok.md'] },
    frames: { frames: [{ id: '../escape', frameName: 'Böse' }, { frameName: 42 }, frameDef({ id: 'frame-ok', frameName: 'Gut' })] },
    translations: { scope: 'changed', locales: [{ code: 'de-DE', entries: [{ path: ['fehlt', 'ganz'], kind: 'string', value: 'x' },
      { path: ['propertyDefaults', 'title'], kind: 'template', value: '({ kaputt' }] }, { code: 'xx-YY', entries: [{ path: ['a'], kind: 'string', value: 'b' }] }] },
    presets: { presets: [{ id: 'p-neu', name: 'Neu', themeId: 'x', mode: 'light', styleSettings: {} }] }
  }
  const entries = [
    { name: 'manifest.json', data: Buffer.from(JSON.stringify({ formatVersion: 2, name: 'Böse', createdAt: 'gestern', createdBy: { app: 'Fremd', appVersion: '9' }, source: {},
      parts: [...Object.keys(parts), 'future', 'theme', 'appearance'].map((id) => ({ id, stats: {}, requires: [] })) })) },
    ...Object.entries(parts).map(([id, payload]) => ({ name: `parts/${id}.json`, data: Buffer.from(JSON.stringify(payload)) })),
    { name: 'parts/future.json', data: Buffer.from('{}') },
    { name: 'parts/appearance.json', data: Buffer.from('{ nicht json') },
    { name: 'files/styles/custom/ok.scss', data: Buffer.from('.ok {}') },
    { name: 'files/styles/custom/linked/x.scss', data: Buffer.from('.x {}') },
    { name: 'files/fonts/ok.woff2', data: fontA },
    { name: 'files/fonts/../evil.woff2', data: fontA }
  ].filter((e) => !e.name.includes('..'))
  return entries
}

// ── the run ──────────────────────────────────────────────────────────────────────────────────
const steps = []
const initial = {}
const roots = {}
let before = {}
const { createZip, readZip } = await loadQuartzControl(control, 'electron/main/services/zipArchive.ts', commonStubs)

function unpacked(path) {
  const files = readZip(readFileSync(path))
  const out = {}
  for (const [name, data] of files) {
    if (name.endsWith('.json')) {
      const value = JSON.parse(data.toString('utf-8'))
      if (name === 'manifest.json') { value.createdAt = '@DATE@'; value.createdBy = '@APP@' }
      out[name] = name === 'manifest.json' ? { json: value } : { json: value, raw: brief({ text: data.toString('utf-8') }) }
    } else out[name] = brief(describeFile(data))
  }
  return { names: [...files.keys()], files: out }
}

async function step(on, call, args, run) {
  globalThis.__commands = []
  globalThis.__snapshots = []
  let result
  try {
    result = (await run()) ?? null
  } catch (error) {
    result = { threw: mask(error.message) }
  }
  const after = tree(roots[on])
  const changed = {}
  for (const path of new Set([...Object.keys(before[on]), ...Object.keys(after)])) {
    if (JSON.stringify(before[on][path]) !== JSON.stringify(after[path])) {
      // A package QuartzHub writes is deflated by another encoder: its entries are compared, not its bytes.
      changed[path] = path.endsWith('.qtpl') && after[path] ? { package: true } : brief(after[path])
    }
  }
  before[on] = after
  steps.push({ on, call, args, result: JSON.parse(mask(JSON.stringify(result))), changed, commands: globalThis.__commands.map((c) => c.map(mask)), snapshots: globalThis.__snapshots })
}

async function project(name, make) {
  const dir = join(work, name)
  mkdirSync(dir, { recursive: true })
  await make(dir)
  roots[name] = dir
  keepBlobs = true
  initial[name] = tree(dir)
  keepBlobs = false
  before[name] = initial[name]
  return dir
}

try {
  const source = await project('source', makeSource)
  const fresh = await project('fresh', (d) => baseProject(d))
  const own = await project('own', makeOwn)
  const ownPackage = await project('own-package', makeOwn)
  const basic = await project('basic', (d) => baseProject(d))
  const old = await project('old', (d) => baseProject(d))
  await project('elsewhere', () => {})
  await project('vault', () => {})
  const hostile = await project('hostile', (d) => {
    baseProject(d)
    // A link inside quartz/static that leads out: writing through it is writing elsewhere.
    symlinkSync(join(work, 'elsewhere'), join(d, 'quartz', 'static', 'link'))
    mkdirSync(join(d, 'quartz', 'styles', 'custom'), { recursive: true })
    symlinkSync(join(work, 'elsewhere'), join(d, 'quartz', 'styles', 'custom', 'linked'))
  })
  await project('linked', (d) => {
    baseProject(d, { content: false, icon: ownIcon })
    symlinkSync(join(work, 'vault'), join(d, 'content'))
  })
  await project('legacy', makeLegacy)
  const packages = await project('packages', (d) => {
    writeFileSync(join(d, 'hostile.qtpl'), createZip(hostilePackage(), new Date(2026, 10, 6)))
    writeFileSync(join(d, 'kein-paket.qtpl'), 'Das ist kein Archiv.')
    writeFileSync(join(d, 'ohne-manifest.qtpl'), createZip([{ name: 'parts/theme.json', data: Buffer.from('{}') }]))
    writeFileSync(join(d, 'manifest-kaputt.qtpl'), createZip([{ name: 'manifest.json', data: Buffer.from('{ kaputt') }]))
  })
  const basicPath = join(control, 'resources', 'templates', 'qc-basic.qtpl')
  const P = (name) => join(packages, name)
  const all = ['frames', 'theme', 'plugins', 'appearance', 'layout', 'presets', 'translations', 'styles', 'fonts', 'static', 'cssVariables', 'content']

  await step('source', 'inspectProject', [], () => tp.inspectProject(source))
  await step('fresh', 'inspectProject', [], () => tp.inspectProject(fresh))
  await step('elsewhere', 'inspectProject', [], () => tp.inspectProject(roots.elsewhere))
  await step('packages', 'exportPackage', ['source', 'quelle.qtpl', { name: 'Quelle', description: 'Alles', parts: all, translationScope: 'changed' }], async () => {
    const result = await tp.exportPackage(source, P('quelle.qtpl'), { name: 'Quelle', description: 'Alles', parts: all, translationScope: 'changed' })
    return { parts: result.parts, unpacked: unpacked(P('quelle.qtpl')) }
  })
  await step('packages', 'exportPackage', ['source', 'teil.qtpl', { name: 'Teil', parts: ['translations', 'presets', 'theme', 'nicht-da'], translationScope: 'all' }], async () => {
    const result = await tp.exportPackage(source, P('teil.qtpl'), { name: 'Teil', parts: ['translations', 'presets', 'theme', 'nicht-da'], translationScope: 'all' })
    return { parts: result.parts, unpacked: unpacked(P('teil.qtpl')) }
  })
  await step('packages', 'exportPackage', ['fresh', 'leer.qtpl', { name: '  Leer  ', parts: ['frames', 'presets', 'cssVariables'], translationScope: 'changed' }], async () => {
    const result = await tp.exportPackage(fresh, P('leer.qtpl'), { name: '  Leer  ', parts: ['frames', 'presets', 'cssVariables'], translationScope: 'changed' })
    return { parts: result.parts, unpacked: unpacked(P('leer.qtpl')) }
  })

  const imports = [
    ['fresh', 'quelle.qtpl', 'packageWins', all],
    ['fresh', 'quelle.qtpl', 'packageWins', all],
    ['own', 'quelle.qtpl', 'projectWins', all],
    ['own-package', 'quelle.qtpl', 'packageWins', all],
    ['basic', basicPath, 'packageWins', all],
    ['old', join(work, 'legacy'), 'packageWins', all],
    ['hostile', 'hostile.qtpl', 'packageWins', all],
    ['linked', 'quelle.qtpl', 'packageWins', ['content', 'presets']]
  ]
  for (const [on, pkg, strategy, parts] of imports) {
    const path = pkg.startsWith('/') ? pkg : P(pkg)
    const label = pkg === basicPath ? '@BASIC@' : pkg.startsWith('/') ? mask(pkg) : pkg
    await step(on, 'planImport', [label], async () => {
      const plan = await tp.planImport(roots[on], path)
      // A package written in this run says when and by whom; QuartzHub's says it differently.
      if (plan && !pkg.startsWith('/') && ['Quelle', 'Teil', 'Leer'].includes(plan.manifest.name)) { plan.manifest.createdAt = '@DATE@'; plan.manifest.createdBy = '@APP@' }
      return plan
    })
    await step(on, 'importPackage', [label, parts, strategy], () => tp.importPackage(roots[on], path, parts, strategy))
  }
  for (const name of ['kein-paket.qtpl', 'ohne-manifest.qtpl', 'manifest-kaputt.qtpl', 'fehlt.qtpl']) {
    await step('fresh', 'planImport', [name], () => tp.planImport(fresh, P(name)))
    await step('fresh', 'importPackage', [name, all, 'packageWins'], () => tp.importPackage(fresh, P(name), all, 'packageWins'))
  }
  await step('fresh', 'slugifyFileName', ['  Mein Paket: Ä/ö  '], () => [' Mein Paket: Ä/ö ', '', '---', 'Basis-Template 2', 'ÄÖÜ'].map((n) => tp.slugifyFileName(n)))
} finally {
  rmSync(work, { recursive: true, force: true })
}

rmSync(out, { recursive: true, force: true })
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'initial.json'), JSON.stringify(initial) + '\n')
writeFileSync(join(out, 'blobs.json'), JSON.stringify(blobs) + '\n')
writeFileSync(join(out, 'steps.json'), JSON.stringify(steps, null, 1) + '\n')
console.log(`${steps.length} steps, ${Object.keys(initial).length} projects → ${out}`)
