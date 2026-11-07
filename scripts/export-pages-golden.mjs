#!/usr/bin/env node
// The export's page scripts in Chrome, as QuartzControl's export window runs them, on a built site:
// QuartzControl's own siteServer serves a copy of the build, Chrome renders it at the print width of
// A4 (658 px) in light (prefers-color-scheme and Quartz's localStorage theme), and the page scripts
// of export/pageScripts.ts run with the three exportModel helpers handed in as source, exactly as
// exportWindow.ts's `run` hands them. Recorded per page: settlePage, readNavigation on the start
// page, extractArticle; then epubChapters over every collected page. `qh-check export-pages` runs
// the same scripts in WebKit on the same build and compares.
//
// Nothing goes to the network: every request from outside the copy is refused (QuartzHub's run
// does the same), so both engines render alike without KaTeX's fonts from jsdelivr. The rule that
// lets such requests through is measured on its own (`qh-check export-window`).
//
// The texts that replace a form, a frame, a video or a canvas are marks (`@@form@@` …), so both
// sides put in the same thing.
//
//   Runtime/node/bin/node scripts/export-pages-golden.mjs <build> <out.json> [../QuartzControl] [--limit N]
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { mkdirSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const [build, outFile, controlArg] = process.argv.slice(2).filter((a, i, all) => !a.startsWith('--') && all[i - 1] !== '--limit')
if (!build || !outFile) {
  console.error('Aufruf: export-pages-golden.mjs <build> <out.json> [QuartzControl] [--limit N]')
  process.exit(2)
}
const limitAt = process.argv.indexOf('--limit')
const limit = limitAt > 0 ? Number(process.argv[limitAt + 1]) : Infinity
const control = resolve(controlArg ?? join(here, '..', '..', 'QuartzControl'))
const { chromium } = createRequire(join(control, 'package.json'))('playwright-core')

const scripts = await loadQuartzControl(control, 'electron/main/services/export/pageScripts.ts', {})
const model = await loadQuartzControl(control, 'shared/exportModel.ts', {})
const siteServer = await loadQuartzControl(control, 'electron/main/services/export/siteServer.ts', {})

const server = await siteServer.serveSiteCopy(resolve(build))
const browser = await chromium.launch({ channel: 'chrome', headless: true })
const context = await browser.newContext({ viewport: { width: 658, height: 1000 }, colorScheme: 'light', deviceScaleFactor: 1 })
await context.addInitScript(`try { localStorage.setItem('theme', 'light') } catch {}`)
await context.route('**/*', (route) => {
  const url = route.request().url()
  if (url.startsWith(server.origin + '/') || url.startsWith('data:') || url.startsWith('blob:')) return route.continue()
  return route.abort()
})
const page = await context.newPage()
// What exportWindow.ts's run does: the function and its helpers as source, the arguments as JSON.
const run = (fn, args, helpers = []) =>
  page.evaluate(`(async () => { try { return { ok: true, value: await (${fn.toString()})(${[...args.map((a) => JSON.stringify(a)), ...helpers.map((h) => `(${h.toString()})`)].join(', ')}) } } catch (e) { return { ok: false, error: String((e && e.message) || e) } } })()`)

const texts = { form: '@@form {{url}}@@', frame: '@@frame {{url}}@@', media: '@@media {{url}}@@', canvas: '@@canvas {{url}}@@',
  noUrl: { form: '@@form@@', frame: '@@frame@@', media: '@@media@@', canvas: '@@canvas@@' } }

await page.goto(`${server.origin}/index`)
const homeSettled = await run(scripts.settlePage, [{ navigation: true, timeoutMs: 15000 }])
const navigation = await run(scripts.readNavigation, [])
const slugs = []
for (const href of navigation.value.hrefs) {
  const slug = model.slugFromPathname(new URL(href).pathname)
  if (!slugs.includes(slug)) slugs.push(slug)
}
if (!slugs.includes('index')) slugs.unshift('index')
const inBook = slugs.slice(0, limit)

const pages = []
for (const slug of inBook) {
  await page.goto(`${server.origin}/${slug}`)
  const settled = await run(scripts.settlePage, [{ navigation: false, timeoutMs: 15000 }])
  const level = slug === 'index' ? 1 : Math.min(6, Math.max(1, model.pageDepth(slug, '')))
  const args = { slug, level, signpost: level === 1 && (slug === 'index' || slug.endsWith('/index')), inBook, outsideLinks: 'site', baseUrl: 'quartzmac.example', texts }
  const extracted = await run(scripts.extractArticle, [args], [model.slugFromPathname, model.anchorFor, model.outsideUrl])
  pages.push({ slug, args, settled, extracted })
  process.stderr.write('.')
}
process.stderr.write('\n')

// epubChapters over the collected pages, in a page of the copy (relative addresses resolve there).
const inputs = pages.filter((p) => p.extracted.ok).map((p, i) => ({
  file: `text/c${String(i + 1).padStart(4, '0')}.xhtml`, slug: p.slug, anchor: model.anchorFor(p.slug), level: p.args.level, title: p.extracted.value.title, html: p.extracted.value.html
}))
await page.goto(server.setDocument('epub.html', '<!doctype html><html><head><meta charset="utf-8"></head><body></body></html>'))
const chapters = await run(scripts.epubChapters, [{ chapters: inputs, imageNames: {}, imageExtensions: ['png', 'jpg', 'jpeg', 'gif', 'svg', 'webp'], formulaAlt: '@@formula@@', diagramAlt: '@@diagram@@' }])

await browser.close()
await server.close()
mkdirSync(dirname(resolve(outFile)), { recursive: true })
writeFileSync(resolve(outFile), JSON.stringify({ engine: 'chrome', origin: server.origin, homeSettled, navigation, pages, inputs, chapters }, null, 1) + '\n')
console.log(`${pages.length} pages, ${pages.filter((p) => !p.extracted.ok).length} without an article, ${chapters.ok ? chapters.value.chapters.length : 'no'} chapters`)
