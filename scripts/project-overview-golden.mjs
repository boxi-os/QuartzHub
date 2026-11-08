#!/usr/bin/env node
// Golden file for ProjectOverviews.sorted and .filter: the order and the search of QuartzControl's
// start page (src/routes/Home.tsx), run here in Node on a list of rows. The two expressions are
// copied from Home.tsx; the script checks that Home.tsx still holds them word for word.
//
// QuartzControl's renderer ran `localeCompare` in Chromium's default locale, the system's (de-DE
// on the measured Mac); this script names 'de', as JS.localeCompare in Swift does.
//
//   Runtime/node/bin/node scripts/project-overview-golden.mjs [../QuartzControl]
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const qc = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'project-overview')

// ── copied from src/routes/Home.tsx (the sort and the filter) ──
const home = readFileSync(join(qc, 'src', 'routes', 'Home.tsx'), 'utf-8')
for (const line of [
  "const at = a.lastOpenedAt ? Date.parse(a.lastOpenedAt) : 0",
  "const bt = b.lastOpenedAt ? Date.parse(b.lastOpenedAt) : 0",
  "return bt - at || a.name.localeCompare(b.name)",
  "const needle = query.trim().toLowerCase()",
  "p.name.toLowerCase().includes(needle) ||",
  "p.path.toLowerCase().includes(needle) ||",
  "(p.siteTitle ?? '').toLowerCase().includes(needle)",
]) {
  if (!home.includes(line)) throw new Error(`Home.tsx no longer holds: ${line}`)
}
function sorted(projects) {
  const list = [...projects]
  list.sort((a, b) => {
    const at = a.lastOpenedAt ? Date.parse(a.lastOpenedAt) : 0
    const bt = b.lastOpenedAt ? Date.parse(b.lastOpenedAt) : 0
    return bt - at || a.name.localeCompare(b.name, 'de')
  })
  return list
}
function filtered(list, query) {
  const needle = query.trim().toLowerCase()
  if (!needle) return list
  return list.filter(
    (p) =>
      p.name.toLowerCase().includes(needle) ||
      p.path.toLowerCase().includes(needle) ||
      (p.siteTitle ?? '').toLowerCase().includes(needle)
  )
}
// ── end copied ──

const rows = [
  { id: '1', name: 'Zettel', path: '/Users/x/Zettel', lastOpenedAt: '2026-11-01T10:00:00.000Z', siteTitle: 'Mein Zettelkasten' },
  { id: '2', name: 'äpfel', path: '/Users/x/äpfel', lastOpenedAt: '2026-11-01T10:00:00.000Z' },
  { id: '3', name: 'Apfel', path: '/Users/x/Apfel', lastOpenedAt: '2026-11-01T10:00:00.000Z' },
  { id: '4', name: 'apfel', path: '/Users/x/apfel2' },
  { id: '5', name: 'Beta', path: '/Users/x/Beta' },
  { id: '6', name: 'Alpha', path: '/Users/x/Alpha' },
  { id: '7', name: 'Neu', path: '/Users/x/Neu', lastOpenedAt: '2026-11-08T09:00:00Z' },
  { id: '8', name: 'Kaputt', path: '/Users/x/Kaputt', lastOpenedAt: 'gestern' },
  { id: '9', name: 'Gärten-Ü', path: '/Volumes/Gärten-Ü/site', lastOpenedAt: '2026-11-08T09:00:00.001Z', siteTitle: 'Über Gärten' },
  { id: '10', name: 'Projekt 10', path: '/Users/x/p10', lastOpenedAt: '2026-10-01T00:00:00.000Z' },
  { id: '11', name: 'Projekt 9', path: '/Users/x/p9', lastOpenedAt: '2026-10-01T00:00:00.000Z' },
  { id: '12', name: 'Handbuch', path: '/Users/x/Handbuch', lastOpenedAt: '' , siteTitle: 'QuartzHub Handbuch' },
  { id: '13', name: 'Älter', path: '/Users/x/Aelter', lastOpenedAt: '1999-12-31T23:59:59.999Z' },
]
const queries = ['', '   ', 'apfel', 'APFEL', ' zettel ', 'gärten', 'ÜBER', 'handbuch', '/users/x/p', 'x/p1', 'nichts', 'ä', 'ß']

const order = sorted(rows).map((p) => p.id)
const search = queries.map((query) => ({ query, ids: filtered(sorted(rows), query).map((p) => p.id) }))
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'golden.json'), JSON.stringify({ rows, order, search }, null, 2) + '\n')
console.log(`order: ${order.join(' ')}`)
for (const s of search) console.log(`"${s.query}": ${s.ids.join(' ')}`)
