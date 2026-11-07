#!/usr/bin/env node
// Golden file for SiteCopy, made by QuartzControl's own export/siteServer.ts: the copy of a build
// (links left out, whatever they point at; folders, umlauts, a file and a folder of one name), how
// a URL path resolves to a file there (`/a` is `a.html`, `/a/` is `a/index.html`, escapes good and
// broken, `..` that must not leave the copy), what the server answers for each (status and content
// type, the own documents under `/__quartzcontrol/` before any file), and which old copies the
// sweep at startup removes (an hour old, the prefix, folders only). The server's answers are for
// 9b, which decides how QuartzHub serves the copy.
//
//   Runtime/node/bin/node scripts/site-copy-golden.mjs [../QuartzControl]
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { lstatSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, readlinkSync, realpathSync, rmSync, symlinkSync, utimesSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'site-copy')
const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-site-copy-golden-')))
const temp = join(work, 'tmp')
mkdirSync(temp)
// os.tmpdir() reads TMPDIR on every call: the copies and the sweep stay inside this folder.
process.env.TMPDIR = temp
const server = await loadQuartzControl(control, 'electron/main/services/export/siteServer.ts', {}, { expose: ['resolveFile', 'TYPES', 'TEMP_PREFIX'] })

const build = join(work, 'public')
const files = {
  'index.html': '<h1>Start</h1>', 'a.html': 'a-datei', 'a/index.html': 'a-ordner', 'b/index.html': 'b', 'c.html': 'c', 'c': 'c-ohne',
  'Gärten/über uns.html': 'über', 'static/contentIndex.json': '{}', 'static/icon.png': 'png', 'x.CSS': 'css', 'y.woff2': 'w', 'z.unknown': 'u',
  'noext': 'n', 'd/e/f.svg': '<svg/>', 'd/e/.html': 'versteckt', '__quartzcontrol/epub.html': 'fremd', 'leer/.keep': '', '%41.html': 'prozent', 'a b.mjs': 'm'
}
for (const [path, content] of Object.entries(files)) {
  mkdirSync(dirname(join(build, path)), { recursive: true })
  writeFileSync(join(build, path), content)
}
writeFileSync(join(work, 'geheim.txt'), 'geheim')
// Next to the copy itself: what `..` out of the copy would reach.
writeFileSync(join(temp, 'neben-der-kopie.txt'), 'neben')
mkdirSync(join(work, 'draussen'))
writeFileSync(join(work, 'draussen', 'x.html'), 'draussen')
symlinkSync(join(work, 'geheim.txt'), join(build, 'static', 'geheim.txt'))
symlinkSync(join(work, 'draussen'), join(build, 'draussen'))
symlinkSync('fehlt', join(build, 'kaputt.html'))
symlinkSync('a.html', join(build, 'neben.html'))

function tree(root) {
  const found = {}
  const walk = (dir, rel) => {
    for (const name of readdirSync(dir).sort()) {
      const full = join(dir, name), r = rel ? `${rel}/${name}` : name
      const info = lstatSync(full)
      if (info.isSymbolicLink()) found[r] = { link: readlinkSync(full) }
      else if (info.isDirectory()) { found[r] = { folder: true }; walk(full, r) }
      else found[r] = readFileSync(full, 'utf-8')
    }
  }
  walk(root, '')
  return found
}

const site = await server.serveSiteCopy(build)
const copy = tree(site.root)
const copyName = site.root.slice(temp.length + 1).replace(/[^-]*$/, '*')
const own = [site.setDocument('epub.html', '<p>eigen</p>'), site.setDocument('drawing.html', 'zeichnen'), site.setDocument('a b.html', 'leer')].map((u) => u.slice(site.origin.length))
const paths = ['/', '/index', '/index.html', '/a', '/a/', '/a.html', '/a/index.html', '/b', '/b/', '/c', '/c.html', '/Gärten/über uns', '/G%C3%A4rten/%C3%BCber%20uns',
  '/G%C3%A4rten/%C3%BCber%20uns.html', '/static/contentIndex.json', '/static/icon.png', '/static/geheim.txt', '/draussen/x', '/kaputt', '/neben', '/x.CSS', '/y.woff2',
  '/z.unknown', '/noext', '/d/e/f.svg', '/d/e/', '/d', '/leer/', '/leer', '/../geheim.txt', '/%2e%2e/geheim.txt', '/a/../c', '/%E0%A4%A', '/%41', '/%2541',
  '/__quartzcontrol/epub.html', '/__quartzcontrol/drawing.html', '/__quartzcontrol/fehlt.html', '/__quartzcontrol/', '/__quartzcontrol/a%20b.html',
  '/../neben-der-kopie.txt', '/%2e%2e/neben-der-kopie.txt', '/..%2fneben-der-kopie.txt', '/d/e/.html', '/a b.mjs', '/a%20b.mjs', '/fehlt', '//index.html', '/a?x=1', '/a#k']
const resolved = []
for (const p of paths) {
  const file = await server.resolveFile(site.root, p)
  resolved.push({ path: p, file: file === null ? null : file.slice(site.root.length) })
}
const answers = []
for (const p of paths) {
  const res = await fetch(site.origin + p.replace(/ /g, '%20'))
  const body = await res.text()
  answers.push({ path: p, status: res.status, type: res.headers.get('content-type'), body: body.slice(0, 40) })
}
await site.close()
const removedAfterClose = !readdirSync(temp).some((n) => n.startsWith(server.TEMP_PREFIX))

// ── the sweep ───────────────────────────────────────────────────────────────────────────────
// Two hours after this run: a link's target keeps the time it was made, and that is now.
const now = Date.now() + 2 * 3600_000
const make = (name, minutes, folder = true) => {
  const path = join(temp, name)
  if (folder) { mkdirSync(path); writeFileSync(join(path, 'index.html'), 'x') } else writeFileSync(path, 'x')
  const t = new Date(now - minutes * 60_000)
  utimesSync(path, t, t)
}
make(`${server.TEMP_PREFIX}alt`, 61)
make(`${server.TEMP_PREFIX}genau`, 60)
make(`${server.TEMP_PREFIX}knapp`, 59)
make(`${server.TEMP_PREFIX}neu`, 1)
make(`${server.TEMP_PREFIX}datei`, 120, false)
make('quartzcontrol-anders-alt', 120)
make('qh-relay-alt', 120)
symlinkSync(join(work, 'draussen'), join(temp, `${server.TEMP_PREFIX}link`))
const swept = (await server.sweepExportTempDirs(now)).map((p) => p.slice(temp.length + 1)).sort()
const left = readdirSync(temp).sort()

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'golden.json'), JSON.stringify({
  files, links: { 'static/geheim.txt': '@W@/geheim.txt', draussen: '@W@/draussen', 'kaputt.html': 'fehlt', 'neben.html': 'a.html' },
  copy, copyName, ownPrefix: server.OWN_PREFIX, tempPrefix: server.TEMP_PREFIX, types: server.TYPES, own, resolved, answers, removedAfterClose, swept, left
}, null, 1) + '\n')
rmSync(work, { recursive: true, force: true })
console.log(`${Object.keys(copy).length} entries copied, ${resolved.length} paths, swept ${swept.join(' ')}`)
