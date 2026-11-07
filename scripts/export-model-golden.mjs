#!/usr/bin/env node
// Golden file for ExportModel, made by QuartzControl's own shared/exportModel.ts: each case is one
// call with its arguments and the answer. The inputs walk what the comments there name: slugs from
// URL paths (escapes good and broken, folders, `.html`), the injective anchor (every character
// outside [A-Za-z0-9-], UTF-16 halves of a character beyond the BMP), page depth below a root, the
// Explorer's default order (folders first, numeric and case-blind names, a folder named by its
// index page, its folder on disk or its slug, a page of the same name as a folder), the book's
// order against the navigation (own order, headings, excluded, missing, appended, the root's start
// page), links to the published site, backlinks and the tag register in several locales.
//
//   Runtime/node/bin/node scripts/export-model-golden.mjs [../QuartzControl]
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'export-model')
const m = await loadQuartzControl(control, 'shared/exportModel.ts', {})

const cases = []
const call = (fn, ...args) => cases.push({ fn, args, result: m[fn](...args) ?? null })

for (const p of ['/', '', '/index', '/index.html', '/a/', '/a/index.html', '/a.html', '/a', '//a', '///a/', '/%C3%BC', '/%c3%bc/x.html', '/%E0%A4%A',
  '/%ZZ', '/a%2Fb', '/a.html/', '/.html', '/x.HTML', '/a b', '/%F0%9F%98%80', '/%ED%A0%80', '/%C0%AF', '/a/.html', '/1-einstieg/', '/1-einstieg/index.html',
  '/en/', '/Gärten/Über uns', '/%25', '/a%', '/%E2%82', '/%FF', '/a.html.html', '/index.html/', 'a/b']) call('slugFromPathname', p)

const slugs = ['index', 'a', 'a-b', 'a/b', 'a_b', 'A9-z', 'Über', 'ü', '😀', 'a b', 'x.y', '1-einstieg/index', '__quartzcontrol/register', '', '-', '_2f_', 'ǅ', '́', 'é']
for (const s of slugs) {
  call('anchorFor', s)
  for (const id of ['', 'kopf', 'a b', 'h-1', '😀']) call('anchorFor', s, id)
}

for (const s of ['index', 'a', 'a/b', 'a/b/index', 'a/b/c', '', '/', 'a//b']) {
  call('folderOf', s)
  call('isFolderIndex', s)
}
const roots = ['', 'a', 'a/b', 'en', 'x']
for (const s of ['index', 'a/index', 'a', 'a/b', 'a/b/index', 'a/b/c', 'ab/c', 'en/index', 'en/a/b', 'x/index', 'a/index/x']) {
  for (const r of roots) {
    call('insideRoot', s, r)
    if (m.insideRoot(s, r)) call('pageDepth', s, r)
  }
}

const explorerSets = [
  [{ slug: 'index', title: 'Start' }, { slug: '1-einstieg/index', title: '1 Einstieg' }, { slug: '1-einstieg/a', title: 'Zweite' }, { slug: '1-einstieg/b', title: 'erste' },
    { slug: '10-anhang/index', title: '10 Anhang' }, { slug: '2-mitte/index', title: '2 Mitte' }, { slug: '2-mitte/x', title: 'X' }, { slug: 'lose', title: 'Lose Seite' }, { slug: 'Ärger', title: 'Ärger' }],
  [{ slug: 'b/c', title: 'C', filePath: 'B Ordner/c.md' }, { slug: 'b/a', title: 'a' }, { slug: 'a', title: 'Z' }, { slug: 'index', title: 'Home' }],
  [{ slug: 'a/b/c/d', title: 'D', filePath: 'A/B/C/d.md' }, { slug: 'a/b/index', title: 'index' }, { slug: 'a/index', title: 'Ordner A' }],
  [{ slug: 'x', title: 'Seite X' }, { slug: 'x/y', title: 'Y' }, { slug: 'x/index', title: 'Index X' }],
  [{ slug: 'v10', title: 'v10' }, { slug: 'v2', title: 'v2' }, { slug: 'V1', title: 'V1' }, { slug: 'é', title: 'é' }, { slug: 'e', title: 'e' }, { slug: 'f', title: 'f' }],
  [{ slug: 'docs/tags', title: 'Tags-Komponente' }, { slug: 'docs/index', title: 'Docs' }, { slug: 'index', title: 'Home' }],
  [{ slug: 'index', title: 'A' }, { slug: 'index', title: 'B' }, { slug: 'k/index', title: 'K1' }, { slug: 'k/index', title: 'K2' }],
  [{ slug: 'a/x', title: 'X', filePath: '' }, { slug: 'b/x', title: 'X' }, { slug: 'c/x', title: 'X', filePath: 'C/x.md' }],
  [], [{ slug: 'nur', title: 'Nur' }],
  [{ slug: 'a/y', title: 'Y', filePath: 'Zulu/y.md' }, { slug: 'b/x', title: 'X', filePath: 'Alpha/x.md' }],
  [{ slug: 'x/index', title: 'index' }, { slug: 'x/p', title: 'P' }, { slug: 'm/index', title: 'Mitte' }, { slug: 'm/q', title: 'Q' }],
  [{ slug: 'Gärten/über', title: 'über' }, { slug: 'Gärten/Ufer', title: 'Ufer' }, { slug: 'gärten/index', title: 'gärten' }, { slug: 'Zebra', title: 'zebra' }, { slug: 'apfel', title: 'Apfel' }]
]
for (const set of explorerSets) call('explorerOrder', set)

const avail = (...s) => new Set(s)
const site = avail('index', 'a/index', 'a/x', 'a/y', 'b/index', 'b/z', 'c', 'en/index', 'en/a')
const nav = ['a/index', 'a/x', 'a/y', 'b/index', 'b/z', 'c']
const resolveCases = [
  [{ order: null, excluded: [], root: '' }, nav, site],
  [{ order: null, excluded: ['a/x', 'c'], root: '' }, nav, site],
  [{ order: null, excluded: [], root: 'a' }, nav, site],
  [{ order: null, excluded: [], root: 'en' }, ['en/a'], site],
  [{ order: null, excluded: [], root: '' }, ['index', ...nav], site],
  [{ order: null, excluded: [], root: '' }, [...nav, 'gone', 'a/x'], site],
  [{ order: null, excluded: [], root: 'b' }, nav, avail('a/x', 'b/z')],
  [{ order: [{ slug: 'c' }, { heading: 'Anhang' }, { slug: 'a/x' }, { slug: 'gone' }, { slug: 'a/x' }], excluded: [], root: '' }, nav, site],
  [{ order: [{ heading: 'Erst' }, { slug: 'b/z' }], excluded: ['a/y'], root: '' }, nav, site],
  [{ order: [{ slug: 'a/x' }, { slug: 'en/a' }, { slug: 'b/z' }], excluded: [], root: 'a' }, nav, site],
  [{ order: [], excluded: [], root: '' }, nav, site],
  [{ order: [{ heading: 'H' }], excluded: [], root: '' }, [], avail()],
  [{ order: [{ slug: 'gone' }, { slug: 'c' }], excluded: ['c'], root: '' }, nav, site],
  [{ order: null, excluded: [], root: '' }, ['a/b/c/d/e/f/g/h', 'a/b/c/d/e/f/g/index', 'a/b'], avail('a/b/c/d/e/f/g/h', 'a/b/c/d/e/f/g/index', 'a/b', 'index')],
  [{ order: [{ heading: 'Tief' }, { slug: 'a/b/c/d/e/f/g/h' }, { slug: 'a/b/c/d/e/f/g' }], excluded: [], root: '' }, [], avail('a/b/c/d/e/f/g/h', 'a/b/c/d/e/f/g')],
  [{ order: null, excluded: ['index'], root: '' }, nav, site],
  [{ order: [{ slug: 'index' }, { heading: 'A' }, { heading: 'B' }, { slug: 'a/index' }], excluded: [], root: '' }, ['a/index'], site]
]
for (const [book, navigation, available] of resolveCases) cases.push({ fn: 'resolveOrder', args: [book, navigation, [...available]], result: m.resolveOrder(book, navigation, available) })

for (const base of [undefined, '', 'https://example.com', 'https://example.com/', 'example.com', 'http://x.y/sub/', 'https://', '///', 'quartzmac.borkel.net/', ' x ', 'HTTPS://Groß.de']) {
  for (const [slug, hash] of [['index', ''], ['a/index', '#k'], ['a/b', ''], ['a b/ü', '#t%C3%BC'], ['x?y', ''], ['a/index/', ''], ['😀', ''], ["it's(1)!*~", '']]) call('outsideUrl', base, slug, hash)
}

for (const l of ['a', '/a', '//a/', 'a/', '', '/', 'a#k', 'a/#k', '#k', 'a/b#x#y', '/4-gestaltung/']) call('linkSlug', l)

const links = { a: ['b', 'c', '/b', 'b#k', 'a', 'x/'], b: ['a/'], c: ['b', 'nicht'], d: ['a', 'b', 'c', 'x/index'], 'x/index': ['a', 'd'] }
for (const slugs of [['a', 'b', 'c', 'd', 'x/index'], ['d', 'c', 'b', 'a'], ['a'], []]) {
  const result = m.backlinksInBook(slugs, (s) => links[s] ?? [])
  cases.push({ fn: 'backlinksInBook', args: [slugs, links], result: [...result] })
}

const tags = { a: ['Zebra', 'apfel', 'Äpfel', 'zebra'], b: ['v10', 'v2', 'Apfel', 'apfel'], c: ['ö', 'z', 'o', 'é', 'e', 'Z', 'ñ', 'n', 'å', 'ş', 's', 'č', 'c'], d: [], e: ['a', 'a', 'B'] }
for (const locale of ['de', 'en', '', 'sv', 'de-CH', 'tr', 'es', 'cs', 'fi']) {
  for (const slugs of [['a', 'b', 'c', 'd', 'e'], ['e', 'c', 'b', 'a']]) {
    cases.push({ fn: 'tagRegister', args: [slugs, tags, locale], result: m.tagRegister(slugs, (s) => tags[s] ?? [], locale) })
  }
}
cases.push({ fn: 'REGISTER_SLUG', args: [], result: m.REGISTER_SLUG })

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify({ defaultLocale: new Intl.Collator().resolvedOptions().locale, cases }, null, 1) + '\n')
console.log(`${cases.length} cases, default locale ${new Intl.Collator().resolvedOptions().locale}`)
