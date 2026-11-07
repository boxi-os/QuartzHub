#!/usr/bin/env node
// Golden file for Books, made by QuartzControl's own shared/bookDefinition.ts and
// services/bookService.ts with their real jsonStore and writableTarget:
// - `normalizeBook` over raw values a person, a merge or a newer version may leave in a file
//   (wrong types, unknown keys, duplicates, arrays where objects belong, lengths past the caps);
// - `serializeBook`, `emptyBook` and `bookIdFromTitle` (umlauts, accents, length, counters);
// - the input rules: QuartzControl's `bookSaveArgs` zod schema over a list of books;
// - steps in a project folder with umlauts: list, read, save and delete, each with its answer and
//   every file under quartz-books/ afterwards (or what stands there instead of a folder).
//
// A reason QuartzControl took from V8's JSON.parse is kept as it came out; the test compares such
// a reason only up to its parenthesis, since QuartzHub's parser words its errors itself.
//
//   Runtime/node/bin/node scripts/books-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'books')
const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-books-golden-')))
const project = join(work, 'Gärten-Ü')
mkdirSync(project, { recursive: true })

const definition = await loadQuartzControl(control, 'shared/bookDefinition.ts', {})
const service = await loadQuartzControl(control, 'electron/main/services/bookService.ts', commonStubs)
const schemas = await loadQuartzControl(control, 'electron/main/ipc/schemas.ts', {})

// ── the normaliser ──────────────────────────────────────────────────────────────────────────
const long = (n, c = 'x') => c.repeat(n)
const raws = [
  {}, { title: 'Handbuch' }, null, [], [1, 2], 'text', 7, true,
  { title: 5, subtitle: null, author: ['a'], language: 'de', root: '/handbuch/', order: 'nav', excluded: 'x', coverImage: 1, toc: 'yes', tagIndex: 1, backlinks: null, outsideLinks: 'none', pdf: 'A5' },
  { root: '///a/b///', title: long(600), subtitle: long(499) + 'äö', author: long(500, 'ü') + 'z', language: 'en' },
  { root: long(1030, 'r') }, { root: 7 }, { root: '' }, { root: '/' },
  { order: [] }, { order: null }, { order: {} },
  { order: [{ slug: 'a' }, { slug: 'a' }, { heading: 'Anhang' }, { heading: '   ' }, { heading: '' }, { slug: '' }, { slug: 5 }, null, 'b', [], { slug: 'b', heading: 'H' }, { heading: 'H', x: 1 }, { slug: long(1025) }, { slug: long(1024) }, { heading: long(510) }, { slug: 'c', extra: true }, { heading: '　' }, { heading: '﻿' }, { heading: ' x' }] },
  { order: Array.from({ length: 10005 }, (_, i) => ({ slug: `p${i % 10002}` })) },
  { excluded: ['a', 'a', '', 5, null, 'b', long(1025), long(1024, 'e')] },
  { excluded: Array.from({ length: 10003 }, (_, i) => `e${i}`) },
  { pdf: { pageSize: 'A5', landscape: true, margin: 3 } }, { pdf: { pageSize: 'a4', landscape: 'yes' } }, { pdf: null }, { pdf: [1, 2] }, { pdf: { pageSize: 'Letter' } },
  { later: { x: 1 }, title: 'T', id: 'other', version: 3, 2: 'two', 1: 'one' },
  { outsideLinks: 'text' }, { outsideLinks: 'site' }, { outsideLinks: 'TEXT' },
  { toc: false, tagIndex: true, backlinks: true },
  { coverImage: 'static/cover.png', language: long(501, 'l') }
]
const normalized = raws.map((raw) => ({ raw: Array.isArray(raw?.order) && raw.order.length > 100 ? { ...raw, order: { generated: raw.order.length } } : raw, result: definition.normalizeBook('buch', raw) }))
// The long order is described rather than stored: its result is checked by its length and ends.
for (const n of normalized) {
  if (n.raw?.order?.generated) n.result = { ...n.result, order: { length: n.result.order.length, first: n.result.order.slice(0, 3), last: n.result.order.slice(-3) } }
  if (Array.isArray(n.raw?.excluded) && n.raw.excluded.length > 100) {
    n.raw = { ...n.raw, excluded: { generated: n.raw.excluded.length } }
    n.result = { ...n.result, excluded: { length: n.result.excluded.length, first: n.result.excluded.slice(0, 3), last: n.result.excluded.slice(-3) } }
  }
}

const serialized = [
  { id: 'a', title: 'T' }, { title: 'T', id: 'a', version: 9, x: 1 }, definition.emptyBook('Neu'), { ...definition.emptyBook(), version: 0, later: [1] }
].map((book) => ({ book, result: definition.serializeBook(book) }))

const titles = [
  'Handbuch für Einsteiger', 'Übersicht', 'ÄÖÜ äöü ß', 'Straße', 'Crème brûlée', 'Ångström', 'Ærø', 'Œuvre', 'İstanbul', 'ǅemal',
  '東京', '   ', '', '---', 'a--b', '-a-', 'Kapitel 1: Start!', 'x'.repeat(60), 'a'.repeat(47) + ' b', 'a'.repeat(47) + '-b',
  'ﬁnal', '①②', 'Ⅻ', 'ﬀ', 'é', 'Ãó', 'Ǆ', 'ı', 'ẞ', 'São Paulo', 'naïve café', 'Dokument', 'dokument',
  'A'.repeat(48), 'Ä'.repeat(30), '1 2 3', 'Ŀ', 'ǈ', 'ﬆ', 'ʼn', 'İ̇'
]
const ids = []
for (const title of titles) ids.push({ title, taken: [], result: definition.bookIdFromTitle(title, new Set()) })
const takenSets = [['handbuch'], ['handbuch', 'handbuch-2'], ['handbuch', 'handbuch-3'], ['dokument'], ['dokument', 'dokument-2', 'dokument-3']]
for (const taken of takenSets) for (const title of ['Handbuch', '']) ids.push({ title, taken, result: definition.bookIdFromTitle(title, new Set(taken)) })

const bookIdCases = ['a', '0', 'a-b', '-a', 'A', 'a_b', 'ä', '', 'a'.repeat(63), 'a'.repeat(64), 'a\n', 'a b', '1-'].map((id) => ({ id, valid: definition.BOOK_ID.test(id) }))

// ── the input rules ─────────────────────────────────────────────────────────────────────────
const base = definition.emptyBook('T')
const variants = [
  {}, { id: 'buch' }, { id: 'Buch' }, { id: '' }, { id: 5 }, { title: long(500) }, { title: long(501) }, { title: 5 }, { subtitle: undefined },
  { root: long(1024) }, { root: long(1025) }, { order: null }, { order: [] }, { order: [{ slug: 'a' }, { heading: 'H' }] }, { order: [{ slug: '' }] },
  { order: [{ heading: '' }] }, { order: [{ heading: long(501) }] }, { order: [{ slug: long(1025) }] }, { order: [{ slug: 'a', heading: '' }] }, { order: [{}] },
  { order: [5] }, { order: 'nav' }, { order: Array(10001).fill({ slug: 'a' }) }, { order: Array(10000).fill({ slug: 'a' }) }, { excluded: [''] },
  { excluded: Array(10001).fill('a') }, { excluded: null }, { coverImage: long(501) }, { toc: 'yes' }, { tagIndex: undefined }, { backlinks: 1 },
  { outsideLinks: 'none' }, { outsideLinks: 'text' }, { pdf: { pageSize: 'A5', landscape: true } }, { pdf: { pageSize: 'A3', landscape: false } },
  { pdf: { pageSize: 'A4' } }, { pdf: { pageSize: 'A4', landscape: false, x: 1 } }, { pdf: null }, { later: 1 }, { language: long(501) },
  { title: 'ä'.repeat(500) }, { title: '😀'.repeat(250) }, { title: '😀'.repeat(251) }
]
const rules = variants.map((patch) => {
  const book = { ...base, ...patch }
  for (const key of Object.keys(patch)) if (patch[key] === undefined) delete book[key]
  const shown = Array.isArray(book.order) && book.order.length > 100 ? { ...book, order: { generated: book.order.length, entry: book.order[0] } }
    : Array.isArray(book.excluded) && book.excluded.length > 100 ? { ...book, excluded: { generated: book.excluded.length, entry: book.excluded[0] } } : book
  return { book: shown, valid: schemas.bookSaveArgs.safeParse({ projectPath: '/p', book }).success }
})

// ── steps ───────────────────────────────────────────────────────────────────────────────────
const books = join(project, 'quartz-books')
function files() {
  const found = {}
  const describe = (full, rel) => {
    let info
    try { info = lstatSync(full) } catch { return }
    if (info.isSymbolicLink()) { found[rel] = { link: readlinkSync(full).split(work).join('@W@') }; return }
    if (info.isDirectory()) {
      let names
      try { names = readdirSync(full).sort() } catch { found[rel] = { unreadableFolder: true }; return }
      if (names.length === 0) found[rel] = { folder: true }
      for (const name of names) describe(join(full, name), `${rel}/${name}`)
      return
    }
    try { found[rel.replace(/\.tmp-\d+-[0-9a-f]{8}$/, '.tmp-*')] = readFileSync(full, 'utf-8') } catch { found[rel] = { unreadableFile: true } }
  }
  describe(books, 'quartz-books')
  return found
}

const steps = []
async function step(name, op, args, fn, setup = []) {
  for (const action of setup) {
    if (action.write) { mkdirSync(dirname(join(project, action.write[0])), { recursive: true }); writeFileSync(join(project, action.write[0]), action.write[1]) }
    if (action.bytes) { mkdirSync(dirname(join(project, action.bytes[0])), { recursive: true }); writeFileSync(join(project, action.bytes[0]), Buffer.from(action.bytes[1], 'base64')) }
    if (action.mkdir) mkdirSync(join(project, action.mkdir), { recursive: true })
    if (action.rm) rmSync(join(project, action.rm), { recursive: true, force: true })
    if (action.link) { mkdirSync(dirname(join(project, action.link[1])), { recursive: true }); symlinkSync(action.link[0].replace('@W@', work), join(project, action.link[1])) }
    if (action.chmod) chmodSync(join(project, action.chmod[0]), action.chmod[1])
  }
  let result
  try {
    const ok = (await fn()) ?? null
    result = { ok: JSON.parse(JSON.stringify(ok).split(project).join('@P@').split(work).join('@W@')) }
  } catch (err) {
    result = { error: String(err.message ?? err).split(project).join('@P@').split(work).join('@W@').replace(/\.tmp-\d+-[0-9a-f]{8}/g, '.tmp-*') }
  }
  steps.push({ name, op, args, setup, result, files: files() })
}
const book = (patch = {}) => ({ ...definition.emptyBook(), ...patch })

await step('list without a folder', 'list', [], () => service.listBooks(project))
await step('read without a folder', 'read', ['buch'], () => service.readBook(project, 'buch'))
await step('delete without a folder', 'delete', ['buch'], () => service.deleteBook(project, 'buch'))
await step('save a new book', 'save', [book({ title: 'Handbuch für Einsteiger', author: 'Boxi' })],
  () => service.saveBook(project, book({ title: 'Handbuch für Einsteiger', author: 'Boxi' })))
await step('the same title again', 'save', [book({ title: 'Handbuch für Einsteiger' })], () => service.saveBook(project, book({ title: 'Handbuch für Einsteiger' })))
await step('an empty title', 'save', [book()], () => service.saveBook(project, book()))
const edited = { id: 'handbuch-fuer-einsteiger', ...book({ title: 'Neu', order: [{ slug: 'a' }, { heading: 'Anhang' }, { slug: 'a' }], excluded: ['x', 'x'], later: { kept: true } }) }
await step('save by id with an own order and an unknown key', 'save', [edited], () => service.saveBook(project, edited))
const keyOrder = { later: 1, title: 'Zuerst', id: 'reihenfolge', ...book({ title: 'Zuerst' }), version: 0 }
await step('save by an id that has no file yet', 'save', [keyOrder], () => service.saveBook(project, keyOrder))
await step('list', 'list', [], () => service.listBooks(project))
await step('read', 'read', ['handbuch-fuer-einsteiger'], () => service.readBook(project, 'handbuch-fuer-einsteiger'))
await step('read one that is not there', 'read', ['fehlt'], () => service.readBook(project, 'fehlt'))
await step('files that are not books', 'list', [], () => service.listBooks(project), [
  { write: ['quartz-books/Notizen.json', '{}'] }, { write: ['quartz-books/a.json.corrupt-1', '{}'] }, { write: ['quartz-books/.json', '{}'] },
  { write: ['quartz-books/a_b.json', '{}'] }, { write: ['quartz-books/notiz.txt', 'x'] }, { write: ['quartz-books/-a.json', '{}'] }, { mkdir: 'quartz-books/sub.json' }
])
await step('a merge conflict', 'list', [], () => service.listBooks(project), [{ rm: 'quartz-books/sub.json' }, { write: ['quartz-books/konflikt.json', '<<<<<<< HEAD\n{"title":"A"}\n=======\n{"title":"B"}\n>>>>>>> x\n'] }])
await step('read the conflict', 'read', ['konflikt'], () => service.readBook(project, 'konflikt'))
await step('save over the conflict', 'save', [{ id: 'konflikt', ...book({ title: 'X' }) }], () => service.saveBook(project, { id: 'konflikt', ...book({ title: 'X' }) }))
await step('delete the conflict', 'delete', ['konflikt'], () => service.deleteBook(project, 'konflikt'))
await step('not an object', 'list', [], () => service.listBooks(project), [
  { write: ['quartz-books/liste.json', '[1,2]'] }, { write: ['quartz-books/null.json', 'null'] }, { write: ['quartz-books/text.json', '"x"'] }, { write: ['quartz-books/zahl.json', '42'] }
])
await step('save over one that is not an object', 'save', [{ id: 'liste', ...book({ title: 'L' }) }], () => service.saveBook(project, { id: 'liste', ...book({ title: 'L' }) }))
await step('empty, truncated and with a byte order mark', 'list', [], () => service.listBooks(project), [
  { rm: 'quartz-books/liste.json' }, { rm: 'quartz-books/null.json' }, { rm: 'quartz-books/text.json' }, { rm: 'quartz-books/zahl.json' },
  { write: ['quartz-books/leer.json', ''] }, { write: ['quartz-books/halb.json', '{"title":'] }, { write: ['quartz-books/bom.json', '﻿{"title":"B"}'] }
])
await step('invalid UTF-8 in a title', 'list', [], () => service.listBooks(project), [
  { rm: 'quartz-books/leer.json' }, { rm: 'quartz-books/halb.json' }, { rm: 'quartz-books/bom.json' },
  { bytes: ['quartz-books/bytes.json', Buffer.from('{"title":"a\xff\xfeb"}', 'latin1').toString('base64')] }
])
await step('a folder where a book file belongs', 'list', [], () => service.listBooks(project), [{ rm: 'quartz-books/bytes.json' }, { mkdir: 'quartz-books/ordner.json' }])
await step('read the folder', 'read', ['ordner'], () => service.readBook(project, 'ordner'))
await step('delete the folder', 'delete', ['ordner'], () => service.deleteBook(project, 'ordner'))
await step('a file that cannot be opened', 'list', [], () => service.listBooks(project), [
  { rm: 'quartz-books/ordner.json' }, { write: ['quartz-books/gesperrt.json', '{}'] }, { chmod: ['quartz-books/gesperrt.json', 0o000] }
])
await step('save over the file that cannot be opened', 'save', [{ id: 'gesperrt', ...book() }], () => service.saveBook(project, { id: 'gesperrt', ...book() }))
await step('a book file that is a link', 'save', [{ id: 'link', ...book({ title: 'L' }) }], () => service.saveBook(project, { id: 'link', ...book({ title: 'L' }) }), [
  { chmod: ['quartz-books/gesperrt.json', 0o644] }, { rm: 'quartz-books/gesperrt.json' }, { write: ['../elsewhere.json', '{"title":"Fremd"}'] },
  { link: ['@W@/elsewhere.json', 'quartz-books/link.json'] }
])
await step('list reads through it', 'list', [], () => service.listBooks(project))
await step('delete through it', 'delete', ['link'], () => service.deleteBook(project, 'link'))
await step('quartz-books as a link', 'save', [book({ title: 'Fremd' })], () => service.saveBook(project, book({ title: 'Fremd' })), [
  { rm: 'quartz-books' }, { mkdir: '../other-books' }, { write: ['../other-books/fremd.json', '{"title":"Fremd"}'] }, { link: ['@W@/other-books', 'quartz-books'] }
])
await step('list through the linked folder', 'list', [], () => service.listBooks(project))
await step('delete in the linked folder', 'delete', ['fremd'], () => service.deleteBook(project, 'fremd'))
await step('quartz-books as a file', 'list', [], () => service.listBooks(project), [{ rm: 'quartz-books' }, { write: ['quartz-books', 'kein Ordner'] }])
await step('save with a file in the way', 'save', [book({ title: 'Datei' })], () => service.saveBook(project, book({ title: 'Datei' })))
await step('read with a file in the way', 'read', ['datei'], () => service.readBook(project, 'datei'))
await step('a folder that cannot be listed', 'list', [], () => service.listBooks(project), [
  { rm: 'quartz-books' }, { mkdir: 'quartz-books' }, { write: ['quartz-books/a.json', '{}'] }, { chmod: ['quartz-books', 0o300] }
])
await step('a folder that cannot be written', 'save', [book({ title: 'Schreibschutz' })], () => service.saveBook(project, book({ title: 'Schreibschutz' })), [
  { chmod: ['quartz-books', 0o555] }
])
await step('delete in a folder that cannot be written', 'delete', ['a'], () => service.deleteBook(project, 'a'))
chmodSync(books, 0o755)

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'golden.json'), JSON.stringify({ normalized, serialized, ids, bookIdCases, rules, steps }, null, 1) + '\n')
rmSync(work, { recursive: true, force: true })
console.log(`${normalized.length} raws, ${serialized.length} serialized, ${ids.length} ids, ${rules.length} rules, ${steps.length} steps`)
