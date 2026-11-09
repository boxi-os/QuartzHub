#!/usr/bin/env node
// Golden file for CssColor, made by QuartzControl's own src/routes/Styles/variableGraph.ts running
// in Google Chrome (headless, through QuartzControl's playwright-core): QuartzControl asked the
// canvas' fillStyle what a value is as a colour, so Chrome's colour parser is what CssColor has to
// agree with. Per value: what canvas makes of it, `cssColorToHexAlpha`, `isDisplayableColor`, and
// the pixel Chrome paints for it over white and over black (the swatch).
//
// The values are every light and dark value of the variable graphs in Fixtures/variable-graph
// (gui-test, gui-test with the theme minimal, minimal alone, the made-up edges), each one also as
// QuartzControl resolves it (`resolvedValue`, which substitutes var() into hsl() and calc()), the
// palettes of gui-test and Example, and made-up edges of the colour syntax.
//
//   Runtime/node/bin/node scripts/css-color-golden.mjs [../QuartzControl] [~/Documents/QuartzProjekte]
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { build } from '../Helpers/node_modules/esbuild/lib/main.js'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const projects = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte'))
const fixtures = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures')
const out = join(fixtures, 'css-color')
const require = createRequire(join(control, 'package.json'))
const { chromium } = require('playwright-core')
const yaml = require('yaml')

const entry = `
  export * from ${JSON.stringify(join(control, 'src/routes/Styles/variableGraph.ts'))}
`
const bundle = await build({
  stdin: { contents: entry, resolveDir: control, loader: 'ts' },
  bundle: true, write: false, format: 'iife', globalName: 'VG', logLevel: 'error',
  alias: { '@shared': join(control, 'shared') }
})

const graphs = JSON.parse(readFileSync(join(fixtures, 'variable-graph', 'graphs.json'), 'utf8'))
const palettes = ['gui-test', 'Example'].map((name) => {
  const config = yaml.parse(readFileSync(join(projects, name, 'quartz.config.yaml'), 'utf8'))
  return { colors: config.configuration?.theme?.colors ?? config.theme?.colors ?? {}, typography: config.configuration?.theme?.typography ?? config.theme?.typography }
})

const edges = [
  // hex in every length and case, and what is not hex
  '#fff', '#FFF', '#ffff', '#fff8', '#ffffff', '#FFFFFF80', '#12345678', '#1234567', '#12', '#ggg', '#', '# fff', ' #abc ', '#010203',
  // names
  'red', 'RED', 'Red', 'rebeccapurple', 'transparent', 'TRANSPARENT', 'currentColor', 'currentcolor', 'inherit', 'initial', 'none', 'notacolor',
  'grey', 'gray', 'darkslategrey', 'lightgoldenrodyellow', 'Canvas', 'CanvasText', 'ButtonText',
  // rgb, legacy and modern
  'rgb(255, 0, 0)', 'rgb(255,0,0)', 'rgba(255, 0, 0, 0.5)', 'rgba(255,0,0,.5)', 'rgb(255 0 0)', 'rgb(255 0 0 / 50%)', 'rgb(255 0 0 / .25)',
  'rgb(100%, 0%, 0%)', 'rgb(50% 25% 0%)', 'rgb(300, -20, 0)', 'rgba(0, 0, 0, 0)', 'rgba(0,0,0,1)', 'rgba(0, 0, 0, 2)', 'rgba(0, 0, 0, -1)',
  'rgb(10.5, 20.4, 30.6)', 'rgb(127.5 127.5 127.5)', 'rgb(255, 0%, 0)', 'rgb(255 0 0, 0.5)', 'rgb(none 0 0)', 'rgb(255, 0, 0, 0.5)', 'rgba(255 0 0)',
  'RGB(1, 2, 3)', 'rgb( 1 , 2 , 3 )', 'rgb(1,2)', 'rgb()', 'rgb(1e2, 0, 0)', 'rgba(255, 255, 255, 0.502)', 'rgba(255, 255, 255, 0.333)',
  'rgba(12, 34, 56, 0.1)', 'rgba(12, 34, 56, 0.07)', 'rgba(12, 34, 56, 0.004)', 'rgba(12, 34, 56, 0.999)', 'rgb(0 0 0 / 0.6667)',
  // hsl and hwb
  'hsl(0, 100%, 50%)', 'hsl(120deg 100% 25%)', 'hsl(240 100% 50% / 0.5)', 'hsla(200, 50%, 50%, 0.3)', 'hsl(0.5turn 50% 50%)',
  'hsl(3.14159rad 50% 50%)', 'hsl(400grad 50% 50%)', 'hsl(-120, 100%, 50%)', 'hsl(480, 100%, 50%)', 'hsl(0, 0%, 100%)', 'hsl(200 50 50)',
  'hsl(254, 80%, 68%)', 'hsl(254, 80.8%, 73.1%)', 'hsl(var(--x))', 'hsl(none 50% 50%)', 'hsl(0, 120%, 50%)', 'hsl(0, 100%, 150%)',
  'hwb(0 0% 0%)', 'hwb(120 30% 30%)', 'hwb(0 60% 60%)', 'hwb(200 10% 20% / 0.5)',
  // calc in channels, the way themes write them once var() is substituted
  'hsl(254, calc(80% * 1.01), calc(68% * 1.075))', 'hsl(calc(254 - 10), 80%, 68%)', 'rgb(calc(255 / 2) 0 0)', 'hsl(254 calc(80% * 1.01) calc(68% * 1.075))',
  'hsl(calc(254deg + 10deg) 80% 68%)', 'rgba(calc(10 + 5), 0, 0, calc(0.5 * 2))', 'hsl(254, calc(80% - 5%), 50%)', 'hsl(254, calc((80% + 5%) / 2), 50%)',
  // the colour functions canvas keeps as they are
  'color(srgb 1 0 0)', 'color(srgb 1 0 0 / 0.5)', 'color(srgb 0.5 0.25 0)', 'color(srgb-linear 0.5 0.25 0)', 'color(display-p3 1 0 0)',
  'color(display-p3 0.5 0.5 0.5 / 50%)', 'color(rec2020 0.5 0.5 0.5)', 'color(xyz 0.2 0.3 0.4)', 'color(a98-rgb 0.5 0.5 0.5)', 'color(prophoto-rgb 0.5 0.5 0.5)',
  'lab(50% 40 59.5)', 'lab(50 40 59.5 / 0.5)', 'lch(52.2% 72.2 50)', 'oklab(59% 0.1 0.1)', 'oklch(70% 0.1 200)', 'oklch(70% .1 200 / .5)',
  'oklch(0.7 0.1 200)', 'oklch(60% 0.15 50deg)', 'lch(80 30 120 / 25%)',
  // color-mix
  'color-mix(in srgb, red 50%, blue)', 'color-mix(in srgb, red, blue)', 'color-mix(in srgb, #284b63 10%, transparent)', 'color-mix(in srgb, white 30%, black)',
  'color-mix(in srgb, red 20%, blue 20%)', 'color-mix(in srgb, rgba(255, 0, 0, 0.5), blue)', 'color-mix(in oklch, red, blue)', 'color-mix(in oklab, red 30%, white)',
  'color-mix(in srgb-linear, red, blue)', 'color-mix(in hsl, red, blue)', 'color-mix(in srgb, red 0%, blue 0%)', 'color-mix(in srgb, red 150%, blue)',
  'color-mix(in srgb, var(--a), blue)', 'color-mix(in lch longer hue, red, blue)', 'color-mix(red, blue)', 'color-mix(in srgb, currentColor, blue)',
  'color-mix(in oklch longer hue, red, orange)', 'color-mix(in oklch increasing hue, blue, red)', 'color-mix(in oklch decreasing hue, red, blue)',
  'color-mix(in hsl longer hue, red 30%, yellow)', 'color-mix(in hwb, red, lime)', 'color-mix(in lab, red, blue)', 'color-mix(in display-p3, red, blue)',
  'oklch(70% 0.1 200 / 1.5)', 'color(srgb 1 0 0 / -0.5)', 'lab(50 40 59.5 / 150%)', 'color(srgb 1.2 -0.1 0.5)', 'color(srgb 0.0000001 0 0)',
  // relative colours and the rest
  'rgb(from red r g b)', 'light-dark(red, blue)', 'linear-gradient(red, blue)', 'url(#x)', '0', '1px', 'calc(1px + 2px)', '', '   ', 'red blue', 'red;',
  '/* c */ red', 'red /* c */', 'rgb(255/**/0 0)', '#ff0000 !important', 'var(--x)', 'var(--x, red)'
]

const browser = await chromium.launch({ channel: 'chrome' })
try {
  const page = await browser.newPage()
  await page.setContent('<!doctype html><title>t</title>')
  await page.addScriptTag({ content: bundle.outputFiles[0].text })
  const result = await page.evaluate(([graphs, palettes, edges]) => {
    const values = new Set(edges)
    for (const { colors, typography } of palettes) {
      for (const mode of Object.values(colors)) for (const v of Object.values(mode ?? {})) if (typeof v === 'string') values.add(v)
      for (const g of graphs) {
        const ctx = { graph: g.graph, overrides: {}, colors, typography }
        for (const key of VG.allKnownKeys(ctx)) {
          for (const mode of ['light', 'dark']) {
            const base = VG.baseValue(key, mode, ctx)
            if (base !== undefined) values.add(base)
            const resolved = VG.resolvedValue(key, mode, ctx)
            if (resolved !== undefined) values.add(resolved)
          }
        }
      }
    }
    const canvas = document.createElement('canvas')
    canvas.width = 1
    canvas.height = 1
    const c = canvas.getContext('2d', { willReadFrequently: true })
    const probe = (v) => {
      c.fillStyle = '#010203'
      c.fillStyle = v
      const raw = c.fillStyle
      return typeof raw !== 'string' || (raw === '#010203' && v.trim().toLowerCase() !== '#010203') ? null : raw
    }
    const paint = (v, ground) => {
      c.clearRect(0, 0, 1, 1)
      c.fillStyle = ground
      c.fillRect(0, 0, 1, 1)
      c.fillStyle = v
      c.fillRect(0, 0, 1, 1)
      return Array.from(c.getImageData(0, 0, 1, 1).data.slice(0, 3))
    }
    return [...values].sort().map((value) => {
      const raw = value.trim() && !value.includes('var(') ? probe(value.trim()) : null
      const displayable = VG.isDisplayableColor(value)
      return {
        value,
        canvas: raw,
        hexAlpha: VG.cssColorToHexAlpha(value),
        displayable,
        overWhite: raw === null ? null : paint(value.trim(), '#ffffff'),
        overBlack: raw === null ? null : paint(value.trim(), '#000000')
      }
    })
  }, [graphs, palettes, edges])
  mkdirSync(out, { recursive: true })
  writeFileSync(join(out, 'colors.json'), JSON.stringify(result, null, 1) + '\n')
  console.log(`${result.length} values, ${result.filter((r) => r.displayable).length} displayable, ${result.filter((r) => r.hexAlpha).length} with a hex`)
} finally {
  await browser.close()
}
