#!/usr/bin/env node
// Golden file for DocumentHTML, made by QuartzControl's own export/documentHtml.ts and the parts
// of export/exportService.ts that work on collected pages without the export window:
// - `printWidthPx` and `printCss` for every paper size, both orientations and titles a CSS string
//   has to survive (quotes, backslashes, line breaks);
// - `documentHtml` over books with and without a cover picture, subtitle, author, date line, table
//   of contents, interposed headings, pages on three levels, a page item nothing was collected for,
//   and text an HTML attribute or element has to survive;
// - `addBacklinksAndRegister` (the "Links to this page" box and the register as one more page),
//   `bookKeywords`, `bookIdentifier` and `coverPicture` against files in a project folder.
// mainTIn answers `@@<lang>:<key>@@` (a mark HTML leaves alone), so the test fills in the catalog's
// text in the document's language.
//
//   Runtime/node/bin/node scripts/document-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { createHash } from 'node:crypto'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'document')
const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-document-golden-')))

const i18n = `export function mainT(key, args) { return JSON.stringify({ key, args: args ?? {} }) }
export function mainTIn(lang, key, args) { return args ? JSON.stringify({ key, args, in: lang }) : '@@' + lang + ':' + key + '@@' }`
const stubs = {
  ...commonStubs,
  '../../i18n': i18n,
  './pageScripts': ['settlePage', 'readNavigation', 'extractArticle', 'findDocumentProblems', 'imagesSettled', 'fillPageNumbers', 'epubChapters']
    .map((name) => `export function ${name}() {}`).join('\n'),
  './exportWindow': 'export function openExportWindow() { throw new Error("no window here") }',
  '../../appWindows': 'export function appWindows() { return [] }'
}
const doc = await loadQuartzControl(control, 'electron/main/services/export/documentHtml.ts', stubs)
const service = await loadQuartzControl(control, 'electron/main/services/export/exportService.ts', stubs, {
  expose: ['bookKeywords', 'addBacklinksAndRegister', 'coverPicture', 'mb']
})

const widths = []
for (const size of ['A4', 'A5', 'Letter']) for (const landscape of [false, true]) widths.push({ size, landscape, result: doc.printWidthPx(size, landscape) })

const css = []
for (const title of ['Handbuch', 'Ein "Zitat"', 'a\\b', 'Zeile\nzwei\r\ndrei', 'Ü & <b>', '']) {
  for (const [pageSize, landscape] of [['A4', false], ['A5', true], ['Letter', false]]) css.push({ title, pageSize, landscape, result: doc.printCss({ title, pageSize, landscape }) })
}

const counts = { outsideLinks: 0, textLinks: 0, forms: 0, frames: 0, media: 0, canvases: 0, unrenderedDiagrams: 0 }
const collected = (slug, title, level, html, lang = 'de') => ({ slug, title, lang, html, images: [], level, counts })
const pages = [
  collected('index', 'Start & "Ziel"', 1, '<p>Willkommen <b>hier</b></p>'),
  collected('a/index', 'Kapitel <A>', 1, '<p>A</p>'),
  collected('a/x', "X's Seite", 2, '<h3 id="p-a_2f_x--k">Kopf</h3>'),
  collected('a/b/c', 'Tief', 3, '<p>c</p>'),
  collected('anhang/z', 'Z', 2, '<p>z</p>')
]
const items = [
  { kind: 'page', slug: 'index', level: 1 }, { kind: 'page', slug: 'a/index', level: 1 }, { kind: 'page', slug: 'a/x', level: 2 },
  { kind: 'page', slug: 'a/b/c', level: 3 }, { kind: 'heading', text: 'Anhang <&>', level: 1 }, { kind: 'page', slug: 'anhang/z', level: 2 },
  { kind: 'page', slug: 'fehlt', level: 2 }
]
const base = {
  lang: 'de', title: 'Handbuch "Q" & <C>', subtitle: 'Für alle', author: 'Boxi', meta: 'Stand 7. November 2026', coverImage: 'data:image/png;base64,AAAA',
  stylesheets: ['http://127.0.0.1:1/index.css', 'http://127.0.0.1:1/a b.css?x="1"&y=2'], items, pages, toc: true, pageSize: 'A4', landscape: false
}
const variants = [
  {}, { toc: false }, { coverImage: null }, { subtitle: '' }, { author: '', meta: '' }, { author: '' }, { meta: '' }, { lang: 'en-US' }, { lang: 'EN' },
  { lang: '', title: '' }, { pageSize: 'Letter', landscape: true }, { stylesheets: [] }, { items: [] }, { items: [{ kind: 'heading', text: 'Nur', level: 1 }] },
  { items: items.slice(0, 3), pages: pages.slice(0, 1) },
  { pages: [...pages, collected('a/index', 'Zweiter Titel', 1, '<p>Zwei</p>')] }
]
const documents = variants.map((patch) => ({ patch, result: doc.documentHtml({ ...base, ...patch }) }))
const constants = { PAGE_MM: doc.PAGE_MM, MARGIN_MM: doc.MARGIN_MM, PAGE_PLACEHOLDER: doc.PAGE_PLACEHOLDER, headingAnchors: [0, 4, 12].map(doc.headingAnchor) }

// ── backlinks and register ──────────────────────────────────────────────────────────────────
const factsPages = new Map([
  ['index', { title: 'Start', tags: ['Einstieg', 'v10', 'Äpfel'], links: ['a/', 'a/x', 'nicht/da'] }],
  ['a/index', { title: 'A', tags: ['Einstieg'], links: ['a/x', 'index', 'a/'] }],
  ['a/x', { title: 'X', tags: ['v2', 'apfel', 'Einstieg'], links: ['/index#k', 'a/b/c'] }],
  ['a/b/c', { title: 'C', tags: [], links: ['a/x'] }],
  ['anhang/z', { title: 'Z', tags: ['Zebra', 'zebra'], links: [] }]
])
const books = [
  { backlinks: false, tagIndex: false }, { backlinks: true, tagIndex: false }, { backlinks: false, tagIndex: true }, { backlinks: true, tagIndex: true }
]
const extras = []
for (const book of books) {
  for (const lang of ['de', 'en', 'sv']) {
    const p = structuredClone(pages)
    const it = structuredClone(items)
    const result = service.addBacklinksAndRegister(p, it, book, { pages: factsPages }, lang)
    extras.push({ book, lang, result, pages: p, items: it })
  }
}
const noTags = structuredClone(pages)
const noTagsItems = structuredClone(items)
extras.push({ book: { backlinks: true, tagIndex: true }, lang: 'de', facts: 'empty', result: service.addBacklinksAndRegister(noTags, noTagsItems, { backlinks: true, tagIndex: true }, { pages: new Map() }, 'de'), pages: noTags, items: noTagsItems })

const keywordFacts = new Map([
  ['a', { tags: ['x', 'y', 'z'] }], ['b', { tags: ['y', 'z'] }], ['c', { tags: ['z', 'B', 'b', 'ä', 'a'] }],
  ['d', { tags: Array.from({ length: 40 }, (_, i) => `t${String(i).padStart(2, '0')}`) }]
])
const keywordItems = [{ kind: 'page', slug: 'a' }, { kind: 'page', slug: 'b' }, { kind: 'heading', text: 'H' }, { kind: 'page', slug: 'c' }, { kind: 'page', slug: 'gone' }]
const keywords = [
  { items: keywordItems, result: service.bookKeywords(keywordItems, { pages: keywordFacts }) },
  { items: [...keywordItems, { kind: 'page', slug: 'd' }], result: service.bookKeywords([...keywordItems, { kind: 'page', slug: 'd' }], { pages: keywordFacts }) },
  { items: [], result: service.bookKeywords([], { pages: keywordFacts }) }
]

const identifiers = []
for (const site of ['https://quartzmac.example.net', '/Users/x/Projekt', '', 'ü']) for (const id of ['handbuch', 'a', '']) identifiers.push({ site, id, result: service.bookIdentifier(site, id) })
const megabytes = [0, 1, 1048575, 1048576, 1572864, 123456789, 52428, 262144, 786432, 1310720, 52429, 157286].map((bytes) => ({ bytes, result: service.mb(bytes) }))

// ── the cover picture ───────────────────────────────────────────────────────────────────────
const project = join(work, 'Gärten-Ü')
const buildRoot = join(work, 'kopie')
const write = (path, content) => { mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, content) }
write(join(project, 'static/cover.png'), 'png-bytes')
write(join(project, 'static/cover.JPG'), 'jpg-bytes')
write(join(project, 'static/cover.bmp'), 'bmp-bytes')
write(join(project, 'static/vektor.svg'), '<svg/>')
mkdirSync(join(project, 'static/ordner.png'), { recursive: true })
write(join(work, 'draussen.png'), 'outside')
symlinkSync(join(work, 'draussen.png'), join(project, 'static/link.png'))
write(join(buildRoot, 'static/icon.png'), 'icon-bytes')
const covers = []
const describe = (r) => ({ ownMissing: r.ownMissing, picture: r.picture ? { type: r.picture.type, text: r.picture.data.toString('utf-8') } : null })
const cover = async (coverImage) => {
  try {
    return describe(await service.coverPicture(project, buildRoot, { coverImage }))
  } catch (err) {
    return { error: String(err.message ?? err).split(work).join('@W@') }
  }
}
for (const coverImage of ['', 'static/cover.png', 'static/cover.JPG', 'static/cover.bmp', 'static/vektor.svg', 'static/fehlt.png', '../draussen.png', '/etc/hosts',
  join(project, 'static/cover.png'), 'static/link.png', 'static/ordner.png', 'static/../static/cover.png', '.']) {
  covers.push({ coverImage: coverImage.split(work).join('@W@'), withIcon: true, result: await cover(coverImage) })
}
rmSync(join(buildRoot, 'static/icon.png'))
for (const coverImage of ['', 'static/fehlt.png', 'static/cover.png']) {
  covers.push({ coverImage, withIcon: false, result: await cover(coverImage) })
}

mkdirSync(out, { recursive: true })
const golden = { widths, css, documents: { base, variants: documents }, constants, factsPages: [...factsPages], extras, keywordFacts: [...keywordFacts], keywords, identifiers, megabytes, covers }
writeFileSync(join(out, 'golden.json'), JSON.stringify(golden, null, 1) + '\n')
rmSync(work, { recursive: true, force: true })
console.log(`${widths.length} widths, ${css.length} css, ${documents.length} documents, ${extras.length} extras, ${identifiers.length} ids, ${covers.length} covers`,
  createHash('sha256').update(JSON.stringify(golden)).digest('hex').slice(0, 8))
