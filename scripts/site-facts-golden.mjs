#!/usr/bin/env node
// Golden file for SiteFacts, made by QuartzControl's own export/collect.ts and the tail of
// export/exportService.ts (`readSitePages`), with its real siteServer, projectDirs and
// projectPrefsService. The export window and the page scripts are stand-ins: what QuartzControl
// read from the rendered navigation (9b ports that) is handed in per case, so what is measured
// here is everything around it - the site's own files (static/contentIndex.json and
// static/multilanguage.json, broken, missing, of the wrong shape), the languages, the root a book
// counts from, the navigation's addresses as slugs, the Explorer's order when there is no
// navigation, and the editor's list of pages.
//
// Each site is recorded with its files, so the test builds the same folder.
//
//   Runtime/node/bin/node scripts/site-facts-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'site-facts')
const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-site-facts-golden-')))

const i18n = `export function mainT(key, args) { return JSON.stringify({ key, args: args ?? {} }) }
export function mainTIn(lang, key, args) { return JSON.stringify({ key, args: args ?? {}, in: lang }) }`
const pageScripts = ['settlePage', 'readNavigation', 'extractArticle', 'findDocumentProblems', 'imagesSettled', 'fillPageNumbers', 'epubChapters']
  .map((name) => `export function ${name}() {}\n${name}.tag = '${name}'`).join('\n')
const windowStub = `export function openExportWindow(origin) {
  globalThis.__origin = origin
  return {
    win: {}, refused: new Map(), fetched: new Map(), unfinished: [],
    async load(url) { globalThis.__loads.push(url.slice(origin.length)); return true },
    async run(fn) {
      const nav = globalThis.__nav
      if (fn.tag === 'settlePage') return { navigation: nav.complete ?? true, unrenderedDiagrams: 0 }
      if (fn.tag === 'readNavigation') return { source: nav.source, hrefs: (nav.hrefs ?? []).map((h) => new URL(h, origin + '/').href) }
      throw new Error('unexpected page script ' + fn.tag)
    },
    close() {}
  }
}`
const stubs = {
  ...commonStubs,
  '../../i18n': i18n,
  './pageScripts': pageScripts,
  './exportWindow': windowStub,
  '../../appWindows': 'export function appWindows() { return [] }'
}
const collect = await loadQuartzControl(control, 'electron/main/services/export/collect.ts', stubs)
const service = await loadQuartzControl(control, 'electron/main/services/export/exportService.ts', stubs)

const page = (title, extra = {}) => ({ title, ...extra })
const html = (...slugs) => Object.fromEntries(slugs.map((s) => [`${s}.html`, `<html>${s}</html>`]))
const sites = {
  plain: {
    'static/contentIndex.json': JSON.stringify({
      index: page('Start', { filePath: 'index.md', tags: ['a', 5, 'b'], links: ['a/', 'b', 7] }),
      'a/index': page('Ordner A', { filePath: 'a/index.md' }), 'a/x': page('X', { filePath: 'A Ordner/x.md', tags: 'nein' }),
      'a/y': page(7, { filePath: 3, links: 'b' }), b: page('B'), 'tags/foo': page('Tag foo'), tags: page('Tags'), ghost: page('Ohne HTML'),
      'Gärten/über uns': page('Über uns'), '2': page('Zwei'), '10': page('Zehn'), 'z/tags': page('Tags-Seite'), c: null, d: 'text'
    }),
    ...html('index', 'a/index', 'a/x', 'a/y', 'b', 'tags/foo', 'tags', 'Gärten/über uns', '2', '10', 'z/tags', 'c', 'd')
  },
  languages: {
    'static/contentIndex.json': JSON.stringify({
      index: page('Start'), 'neu': page('Neu'), 'en/index': page('Home'), 'en/new': page('New'), 'fr/index': page('Accueil'), 'fr/x': page('X'), lost: page('Ohne Sprache')
    }),
    'static/multilanguage.json': JSON.stringify({
      defaultLanguage: 'de',
      languages: [{ code: 'de', home: 'index', native: 'Deutsch', label: 'German', locale: 'de-DE' }, { code: 'en', home: 'en/index', label: 'English' },
        { code: 'fr', home: 7 }, { home: 'x/index' }, { code: 5 }],
      pages: { index: { lang: 'de' }, neu: { lang: 'de' }, 'en/index': { lang: 'en' }, 'en/new': { lang: 'en' }, 'fr/index': { lang: 'fr' }, 'fr/x': { lang: 3 }, gone: { lang: 'en' } }
    }),
    ...html('index', 'neu', 'en/index', 'en/new', 'fr/index', 'fr/x', 'lost')
  },
  noDefault: {
    'static/contentIndex.json': JSON.stringify({ index: page('Start'), 'en/index': page('Home') }),
    'static/multilanguage.json': JSON.stringify({ languages: [{ code: 'en', home: 'en/index' }, { code: 'de' }], pages: { 'en/index': { lang: 'en' } } }),
    ...html('index', 'en/index')
  },
  emptyLanguages: {
    'static/contentIndex.json': JSON.stringify({ index: page('Start') }),
    'static/multilanguage.json': JSON.stringify({ defaultLanguage: 'de', languages: [] }),
    ...html('index')
  },
  brokenLanguages: { 'static/contentIndex.json': JSON.stringify({ index: page('Start') }), 'static/multilanguage.json': '{"languages":', ...html('index') },
  languagesNotList: { 'static/contentIndex.json': JSON.stringify({ index: page('Start') }), 'static/multilanguage.json': '{"languages":{"de":1},"defaultLanguage":5}', ...html('index') },
  pagesNotObject: {
    'static/contentIndex.json': JSON.stringify({ index: page('Start') }),
    'static/multilanguage.json': JSON.stringify({ defaultLanguage: 'en', languages: [{ code: 'en' }], pages: [{ lang: 'x' }] }), ...html('index')
  },
  nullLanguage: {
    'static/contentIndex.json': JSON.stringify({ index: page('Start'), 'en/index': page('Home') }),
    'static/multilanguage.json': JSON.stringify({ defaultLanguage: 'en', languages: [{ code: 'en', home: 'en/index' }, null], pages: { 'en/index': { lang: 'en' } } }),
    ...html('index', 'en/index')
  },
  noIndex: { 'index.html': '<html></html>' },
  brokenIndex: { 'static/contentIndex.json': '{"index":', ...html('index') },
  arrayIndex: { 'static/contentIndex.json': '[]', ...html('index') },
  nullIndex: { 'static/contentIndex.json': 'null', ...html('index') },
  numberIndex: { 'static/contentIndex.json': '4', ...html('index') },
  folderIndex: { 'static/contentIndex.json/x': '', ...html('index') },
  emptySite: { 'static/contentIndex.json': '{}' }
}

function build(name) {
  const root = join(work, name)
  for (const [path, content] of Object.entries(sites[name])) {
    mkdirSync(dirname(join(root, path)), { recursive: true })
    writeFileSync(join(root, path), content)
  }
  return root
}
const factsJson = (f) => ({
  pages: [...f.pages].map(([slug, p]) => [slug, p]), languages: f.languages, defaultLanguage: f.defaultLanguage, langOf: [...f.langOf]
})
const outcome = async (fn) => {
  try {
    return { ok: (await fn()) ?? null }
  } catch (err) {
    return { error: String(err.message ?? err).split(work).join('@W@') }
  }
}

const facts = []
for (const name of Object.keys(sites)) {
  const root = build(name)
  const result = await outcome(async () => factsJson(await collect.readSiteFacts(root)))
  const entry = { site: name, result, calls: [] }
  if (result.ok) {
    const f = await collect.readSiteFacts(root)
    for (const language of ['', 'de', 'en', 'fr', 'xx']) {
      entry.calls.push({ fn: 'pagesInLanguage', language, result: [...collect.pagesInLanguage(f, language)] })
      entry.calls.push({ fn: 'languageHome', language, result: collect.languageHome(f, language) })
      for (const bookRoot of ['', 'a', 'en']) entry.calls.push({ fn: 'effectiveRoot', language, root: bookRoot, result: collect.effectiveRoot(f, bookRoot, language) })
    }
  }
  facts.push(entry)
}

// The navigation as the stand-in window hands it over, and what QuartzControl made of it.
const navigations = [
  { source: 'explorer', hrefs: ['/a/', '/a/x', '/a/x.html', '/b', '/ghost', '/tags/foo', 'https://example.com/b', '/Gärten/über%20uns', '/%C3%BCber', '/a/y#k', '/a/y?q=1', '/', '/10', '/2'] },
  { source: 'quartz-navigations', hrefs: ['/b', '/a/'], complete: false },
  { source: 'links', hrefs: [] },
  { source: 'none' },
  { source: 'explorer', hrefs: ['/en/new', '/en/', '/neu', '/fr/x', '/lost'] }
]
const orders = []
for (const site of ['plain', 'languages', 'emptySite']) {
  const root = join(work, site)
  const f = await collect.readSiteFacts(root)
  for (const nav of navigations) {
    for (const language of ['', 'en']) {
      globalThis.__nav = nav
      globalThis.__loads = []
      const result = await outcome(() => collect.readNavigationOrder(openWindow(), globalThis.__origin, f, language))
      orders.push({ site, nav, language, loads: globalThis.__loads, result })
    }
  }
}
function openWindow() {
  // collect.readNavigationOrder takes the window as an argument; the stand-in records the origin.
  const stub = { load: async (url) => { globalThis.__loads.push(url.slice(globalThis.__origin.length)); return true } }
  globalThis.__origin = 'http://127.0.0.1:1'
  return {
    ...stub,
    async run(fn) {
      const nav = globalThis.__nav
      if (fn.tag === 'settlePage') return { navigation: nav.complete ?? true, unrenderedDiagrams: 0 }
      if (fn.tag === 'readNavigation') return { source: nav.source, hrefs: (nav.hrefs ?? []).map((h) => new URL(h, globalThis.__origin + '/').href) }
      throw new Error('unexpected page script ' + fn.tag)
    }
  }
}

// readSitePages: the project's build folder (public/, or what project prefs say), a copy served,
// the stand-in window, the editor's list.
const sitePages = []
const project = join(work, 'Projekt Ü')
for (const site of ['plain', 'languages', 'emptySite']) {
  rmSync(project, { recursive: true, force: true })
  for (const [path, content] of Object.entries(sites[site])) {
    mkdirSync(dirname(join(project, 'public', path)), { recursive: true })
    writeFileSync(join(project, 'public', path), content)
  }
  for (const nav of navigations) {
    for (const [root, language] of [['', ''], ['a', ''], ['', 'en'], ['en', 'en'], ['fr', 'fr'], ['nichts', '']]) {
      globalThis.__nav = nav
      globalThis.__loads = []
      const result = await outcome(() => service.readSitePages(project, root, language))
      sitePages.push({ site, nav, root, language, loads: globalThis.__loads, result })
    }
  }
}
rmSync(join(project, 'public'), { recursive: true, force: true })
const noBuild = await outcome(() => service.readSitePages(project, '', ''))

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'golden.json'), JSON.stringify({ sites, facts, orders, sitePages, noBuild }, null, 1).split(project).join('@P@') + '\n')
rmSync(work, { recursive: true, force: true })
console.log(`${facts.length} sites, ${orders.length} navigation orders, ${sitePages.length} page lists`)
