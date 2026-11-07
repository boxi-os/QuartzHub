#!/usr/bin/env node
// Golden file for EpubPack and HtmlPack, made by QuartzControl's own export/writeEpub.ts
// (`packEpub`, `navList`, `esc`, `STYLE`) and export/writeHtml.ts (`packHtml`) with its real
// zipArchive: book contents as `prepareBookContent` hands them over (chapters as XHTML bodies, the
// navigation on three levels, pictures of the site, drawn formulas and diagrams, a cover or none)
// and the package parts (language, title, subtitle, author, identifier, date). Each ePub is
// recorded as its entries in order (name, stored or deflated, the bytes) and the date it was
// zipped with, so the test can zip the expected entries with ZipArchive (measured byte for byte
// against QuartzControl's createZip in zip-golden.mjs) after filling in the catalog's texts.
// `packHtml`'s ceiling is shrunk to 2 KiB for the refusal.
//
// `@@<lang>:<key>@@` stands for QuartzControl's `mainTIn`, as in document-golden.mjs.
//
//   Runtime/node/bin/node scripts/epub-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'epub')

const i18n = `export function mainT(key, args) { return JSON.stringify({ key, args: args ?? {} }) }
export function mainTIn(lang, key, args) { return args ? JSON.stringify({ key, args, in: lang }) : '@@' + lang + ':' + key + '@@' }`
let zipped = []
const stubs = {
  ...commonStubs,
  '../../i18n': i18n,
  './pageScripts': 'export function epubChapters() {}',
  './exportWindow': 'export function openExportWindow() { throw new Error("no window here") }',
  // QuartzControl's own createZip, wrapped to record what it was handed.
  '../zipArchive': `import * as real from './electron/main/services/zipArchive.ts'
export function createZip(entries, modified) {
  globalThis.__zipped.push({ modified: modified.toISOString(), entries: entries.map((e) => ({ name: e.name, store: !!e.store, data: Buffer.from(e.data).toString('base64') })) })
  return real.createZip(entries, modified)
}
export const readZip = real.readZip`
}
globalThis.__zipped = zipped
const epub = await loadQuartzControl(control, 'electron/main/services/export/writeEpub.ts', stubs)
const html = await loadQuartzControl(control, 'electron/main/services/export/writeHtml.ts', { ...stubs, './writeEpub': `export * from './electron/main/services/export/writeEpub.ts'` })
const small = await loadQuartzControl(control, 'electron/main/services/export/writeHtml.ts', { ...stubs, './writeEpub': `export * from './electron/main/services/export/writeEpub.ts'` },
  { replace: [['200 * 1024 * 1024', '2 * 1024']] })

const png = (text) => Buffer.from(text)
const chapters = [
  { file: 'text/c0001.xhtml', title: 'Start & "Ziel"', body: '<section xmlns="http://www.w3.org/1999/xhtml" id="p-index"><h1>Start &amp; „Ziel“</h1><p><img src="../images/a.png" alt="A"/> <a href="c0002.xhtml#p-a">A</a></p></section>', hasMath: false, hasSvg: false },
  { file: 'text/c0002.xhtml', title: 'A', body: '<section id="p-a"><h2>A</h2><p epub:type="footnote">Fuß</p><img src="../images/f1.png" alt="Formel" style="height:1.250em;vertical-align:middle"/><img src="../images/fehlt.png"/></section>', hasMath: true, hasSvg: false },
  { file: 'text/c0003.xhtml', title: 'Anhang', body: '<h1 id="h-2">Anhang</h1>', hasMath: true, hasSvg: true },
  { file: 'text/c0004.xhtml', title: 'Tief <3>', body: '<section id="p-a_2f_b"><h3>Tief</h3><a href="c0001.xhtml#p-index">zurück</a> <a href="https://example.com/x?a=1&amp;b=2">raus</a></section>', hasMath: false, hasSvg: false }
]
const nav = [
  { href: 'text/c0001.xhtml#p-index', title: 'Start & "Ziel"', level: 1 }, { href: 'text/c0002.xhtml#p-a', title: 'A', level: 2 },
  { href: 'text/c0003.xhtml#h-2', title: 'Anhang', level: 1 }, { href: 'text/c0004.xhtml#p-a_2f_b', title: 'Tief <3>', level: 3 }
]
const assets = [['images/a.png', { data: png('png-a'), type: 'image/png' }], ['images/b c.svg', { data: png('<svg/>'), type: 'image/svg+xml' }], ['images/f1.png', { data: png('formel'), type: 'image/png' }], ['images/a&b"<>.gif', { data: png('gif'), type: 'image/gif' }]]
const counts = { externalImages: 1, unsupportedImages: 2, unresolvedLinks: 0, footnotes: 1, formulas: 1, diagrams: 0 }
const content = (patch = {}) => ({
  chapters, nav, assets: new Map(assets), cover: { name: 'images/cover.png', data: png('cover'), type: 'image/png' }, drawings: { formulas: 1, diagrams: 0 }, counts, ...patch
})
const parts = (patch = {}) => ({
  lang: 'de', title: 'Handbuch "Q" & <C>', subtitle: 'Für alle', author: 'Boxi & Co', identifier: 'urn:uuid:f533875b-8c8b-51fe-b480-cec441903dab',
  modified: new Date('2026-11-07T09:30:15.123Z'), cover: null, stylesheets: [], items: [], pages: [], ...patch
})
const show = (c) => ({
  chapters: c.chapters, nav: c.nav, assets: [...c.assets].map(([name, a]) => [name, { type: a.type, data: a.data.toString('base64') }]),
  cover: c.cover ? { name: c.cover.name, type: c.cover.type, data: c.cover.data.toString('base64') } : null, drawings: c.drawings, counts: c.counts
})
const showParts = (p) => ({ ...p, modified: p.modified.toISOString() })

const cases = [
  ['full', content(), parts()],
  ['no cover', content({ cover: null }), parts()],
  ['no subtitle and author', content(), parts({ subtitle: '', author: '' })],
  ['english', content(), parts({ lang: 'en-GB' })],
  ['no pictures', content({ assets: new Map(), cover: null, drawings: { formulas: 0, diagrams: 0 }, chapters: chapters.map((c) => ({ ...c, hasMath: false, hasSvg: false })) }), parts()],
  ['svg only', content({ assets: new Map(), cover: null, drawings: { formulas: 0, diagrams: 0 } }), parts()],
  ['empty', content({ chapters: [], nav: [], assets: new Map(), cover: null, drawings: { formulas: 0, diagrams: 0 } }), parts({ lang: '', title: '' })],
  ['diagrams', content({ drawings: { formulas: 1, diagrams: 1 }, assets: new Map([...assets, ['images/d1.png', { data: png('diagramm'), type: 'image/png' }]]) }), parts({ modified: new Date('1979-06-01T00:00:00.000Z') })]
]
const results = []
for (const [name, c, p] of cases) {
  zipped.length = 0
  const e = epub.packEpub(c, p)
  const zip = zipped[0]
  const h = html.packHtml(c, p)
  results.push({
    name, content: show(c), parts: showParts(p),
    epub: { chapters: e.chapters, images: e.images, counts: e.counts, zip, bytes: e.bytes.toString('base64') },
    html: { chapters: h.chapters, pictures: h.pictures, text: h.bytes.toString('utf-8') }
  })
}

const navLists = []
for (const entries of [nav, [], [{ href: 'a', title: 'A', level: 2 }, { href: 'b', title: 'B', level: 1 }], [{ href: 'a', title: 'A', level: 1 }, { href: 'b', title: 'B', level: 4 }, { href: 'c', title: 'C', level: 2 }, { href: 'd', title: 'D', level: 1 }],
  [{ href: 'x"y', title: '<&>', level: 1 }, { href: 'z', title: 'Z', level: 1 }, { href: 'w', title: 'W', level: 3 }, { href: 'v', title: 'V', level: 3 }, { href: 'u', title: 'U', level: 2 }]]) {
  navLists.push({ entries, result: epub.navList(entries) })
}

let tooLarge
try {
  small.packHtml(content({ assets: new Map([['images/big.png', { data: Buffer.alloc(3000, 1), type: 'image/png' }]]) }), parts())
  tooLarge = { ok: true }
} catch (err) {
  tooLarge = { error: err.message }
}
let justFits
try {
  const r = small.packHtml(content({ chapters: [], nav: [], assets: new Map([['images/x.png', { data: Buffer.alloc(1500, 2), type: 'image/png' }]]), cover: null }), parts())
  justFits = { ok: r.bytes.toString('utf-8') }
} catch (err) {
  justFits = { error: err.message }
}

// The ceiling, shrunk to 2 KiB, at its edges: exactly at it, a third of a byte rounded up, the
// cover and the chapters' text counted.
const bytes = (n, fill = 1) => Buffer.alloc(n, fill)
const chapter = (length) => ({ file: 'text/c0001.xhtml', title: 'T', body: 'x'.repeat(length), hasMath: false, hasSvg: false })
const limit = (name, patch) => {
  const c = content({ chapters: [], nav: [], assets: new Map(), cover: null, ...patch })
  let result
  try {
    small.packHtml(c, parts())
    result = { ok: true }
  } catch (err) {
    result = { error: err.message }
  }
  return { name, content: show(c), result }
}
const limits = [
  limit('exactly at the ceiling', { assets: new Map([['images/x.png', { data: bytes(1536), type: 'image/png' }]]) }),
  limit('one byte over', { assets: new Map([['images/x.png', { data: bytes(1537), type: 'image/png' }]]) }),
  limit('a third rounded up', { assets: new Map([['images/x.png', { data: bytes(1), type: 'image/png' }]]), chapters: [chapter(2047)] }),
  limit('the cover counts', { cover: { name: 'images/cover.png', data: bytes(1600), type: 'image/png' } }),
  limit('the chapters count', { chapters: [chapter(2100)] }),
  limit('UTF-16 units of the text', { chapters: [{ ...chapter(0), body: 'ü'.repeat(2048) }] }),
  limit('one unit over', { chapters: [{ ...chapter(0), body: '😀'.repeat(1024) + 'x' }] })
]

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'golden.json'), JSON.stringify({ style: epub.STYLE, results, navLists, tooLarge, justFits, limits, maxBytes: html.HTML_MAX_BYTES }, null, 1) + '\n')
console.log(`${results.length} books, ${navLists.length} navigation lists`, JSON.stringify(tooLarge), JSON.stringify(justFits))
