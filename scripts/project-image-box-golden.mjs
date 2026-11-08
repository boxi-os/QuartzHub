#!/usr/bin/env node
// Golden file for ProjectImageBox, made by QuartzControl's own shared/projectImageBox.ts: the
// header picture as one quartz-layout-box instance. Each case is a plugin list as readConfig hands
// it out (with `name` and `enabled`), and the answers of every function for it; the lists come out
// as JSON.stringify writes them, so key order is part of the comparison.
//
//   Runtime/node/bin/node scripts/project-image-box-golden.mjs [../QuartzControl]
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'project-image-box')
const box = await loadQuartzControl(control, 'shared/projectImageBox.ts', {})

const explorer = { source: 'github:quartz-community/explorer', name: 'explorer', enabled: true }
const favicon = { source: '@quartz-community/favicon', options: {}, name: 'favicon', enabled: false }
// What `quartz plugin add` writes, as readConfig hands it out.
const fresh = { source: 'github:boxi-os/quartz-layout-box', enabled: true, options: { position: 'left' }, layout: { position: 'left', priority: 50 }, name: 'quartz-layout-box' }
const freshNoOptions = { source: 'github:boxi-os/quartz-layout-box#v2', name: 'quartz-layout-box', enabled: false }
const freshStringOptions = { source: 'github:boxi-os/quartz-layout-box', options: 'x', name: 'quartz-layout-box', enabled: true }
const own = (html) => ({ source: 'github:boxi-os/quartz-layout-box', enabled: true, options: { html, className: 'layout-box-project-image', placeholders: true, extra: 1 }, layout: { position: 'header', priority: 10 }, name: 'quartz-layout-box' })
const mark = (html, enabled = true) => ({ source: 'github:boxi-os/quartz-layout-box', enabled, options: { html, className: 'layout-box-mark' }, name: 'quartz-layout-box' })
const objectSource = { source: { name: 'quartz-layout-box', repo: 'github:x/quartz-layout-box' }, name: 'quartz-layout-box', enabled: true }
const otherBox = { source: 'github:me/quartz-layout-box-fork', options: { html: '<b>x</b>' }, name: 'quartz-layout-box-fork', enabled: true }

const lists = {
  empty: [],
  noBox: [explorer, favicon],
  fresh: [explorer, fresh],
  freshNoOptions: [freshNoOptions, explorer],
  freshStringOptions: [explorer, freshStringOptions],
  ownLight: [explorer, own(box.projectImageHtml(false))],
  ownDark: [own(box.projectImageHtml(true)), explorer],
  ownAndFresh: [fresh, own('old')],
  markDouble: [mark('<img src="{{root}}/static/icon.png">'), explorer],
  markSingle: [mark("<img src='{{root}}/static/icon.png'>")],
  markDark: [mark('<img src="{{root}}/static/icon.png"><img src="{{root}}/static/icon-dark.png">')],
  markOff: [mark('<img src="{{root}}/static/icon.png">', false)],
  markOtherFile: [mark('<img src="{{root}}/static/icon.png.bak">'), mark('<img src="/static/icon.pngx">')],
  markAndOwn: [mark('<img src="{{root}}/static/icon.png">'), own('x')],
  objectSource: [objectSource],
  forkAndFresh: [otherBox, fresh],
  numberHtml: [{ source: 'github:boxi-os/quartz-layout-box', options: { html: 5 }, name: 'quartz-layout-box', enabled: true }],
  nullOptions: [{ source: 'github:boxi-os/quartz-layout-box', options: null, name: 'quartz-layout-box', enabled: true }],
}

const cases = Object.entries(lists).map(([id, plugins]) => {
  const copy = () => JSON.parse(JSON.stringify(plugins))
  const indices = [undefined, -1, 0, 1, 2]
  return {
    id,
    plugins: JSON.stringify(plugins),
    isLayoutBox: plugins.map(box.isLayoutBox),
    isFresh: plugins.map(box.isFreshLayoutBoxEntry),
    findOwn: box.findProjectImageEntry(plugins),
    findOther: box.findOtherProjectImage(plugins),
    without: JSON.stringify(box.withoutProjectImage(copy())),
    with: [false, true].flatMap((hasDark) => indices.map((replaceIndex) => ({
      hasDark, replaceIndex: replaceIndex ?? null,
      result: JSON.stringify(box.withProjectImage(copy(), hasDark, replaceIndex))
    })))
  }
})
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify({
  source: box.LAYOUT_BOX_SOURCE, className: box.PROJECT_IMAGE_CLASS,
  html: { light: box.projectImageHtml(false), dark: box.projectImageHtml(true) }, cases
}, null, 1) + '\n')
console.log(`${cases.length} lists`)
