#!/usr/bin/env node
// Golden file for VariableResolve, made by QuartzControl's own src/routes/Styles/variableGraph.ts
// and swatch.ts running in Google Chrome (headless, through QuartzControl's playwright-core):
// isColorVariable and isDisplayableColor ask the canvas, everything else is plain functions.
//
// The contexts are the variable graphs of Fixtures/variable-graph (gui-test, gui-test with the
// theme minimal, minimal alone, the made-up edges) with the palettes of gui-test and Example and
// with overrides of every kind: a changed colour, a light-only one, one of the user's own keys, an
// alias, a cycle, an embedded reference, an emptied pair. Per key and mode: effectiveValue,
// baseValue, resolveChain, resolvedValue, originOf, baseOriginOf, groupOf, isColorVariable (both
// questions); per context pageGround; and pureAlias, referencedVariables, resolveValueLiteral,
// normalizeVarQuery and paletteGround on made-up values.
//
//   Runtime/node/bin/node scripts/variable-resolve-golden.mjs [../QuartzControl] [~/Documents/QuartzProjekte]
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
const out = join(fixtures, 'variable-resolve')
const require = createRequire(join(control, 'package.json'))
const { chromium } = require('playwright-core')
const yaml = require('yaml')

const entry = `
  export * from ${JSON.stringify(join(control, 'src/routes/Styles/variableGraph.ts'))}
  export { pageGround, paletteGround } from ${JSON.stringify(join(control, 'src/routes/Styles/swatch.ts'))}
`
const bundle = await build({
  stdin: { contents: entry, resolveDir: control, loader: 'ts' },
  bundle: true, write: false, format: 'iife', globalName: 'VG', logLevel: 'error',
  alias: { '@shared': join(control, 'shared') }
})

const graphs = JSON.parse(readFileSync(join(fixtures, 'variable-graph', 'graphs.json'), 'utf8'))
  .filter((g) => Object.keys(g.graph.vars).length > 0)
  .map((g) => ({ name: g.name, graph: { vars: g.graph.vars } }))
const palettes = ['gui-test', 'Example'].map((name) => {
  const config = yaml.parse(readFileSync(join(projects, name, 'quartz.config.yaml'), 'utf8'))
  const theme = config.configuration?.theme ?? config.theme ?? {}
  return { name, colors: theme.colors ?? {}, typography: theme.typography }
})

// Overrides as the page holds them: an empty dark is "no dark declaration".
const overrideSets = {
  none: {},
  mixed: {
    secondary: { light: '#ff0000', dark: '' },
    light: { light: 'hsl(40, 30%, 96%)', dark: '#111111' },
    'text-accent': { light: 'var(--tertiary)', dark: 'var(--secondary)' },
    'background-primary': { light: 'oklch(70% 0.1 200)', dark: '', lightOnly: true },
    'tpl-space-lg': { light: '2rem', dark: '' },
    'tpl-accent': { light: 'color-mix(in srgb, var(--secondary) 30%, transparent)', dark: '' },
    'own-alias': { light: 'var(--secondary, #000)', dark: 'var(--nowhere, rgb(1 2 3))' },
    'cycle-a': { light: 'var(--cycle-b)', dark: '' },
    'cycle-b': { light: 'var(--cycle-a)', dark: '' },
    'emptied': { light: '', dark: '' },
    'size-as-colour': { light: '#00ff00', dark: '' },
    bodyFont: { light: '"Inter", sans-serif', dark: '' },
    'color-accent': { light: 'hsl(var(--accent-h), calc(var(--accent-s) * 1.01), calc(var(--accent-l) * 1.075))', dark: '' },
    'accent-h': { light: '200', dark: '' },
    'only-dark': { light: '', dark: '#333' },
    // a theme's or a build's non-colour value, overridden with a colour
    'lightningcss-light': { light: '#ff00ff', dark: '' },
    'anim-duration-fast': { light: 'rgb(0 128 0)', dark: '' },
    a: { light: 'red', dark: '' },
    // embedded references nine deep, past the depth cap
    'deep-1': { light: 'calc(var(--deep-2) + 1px)', dark: '' },
    'deep-2': { light: 'calc(var(--deep-3) + 1px)', dark: '' },
    'deep-3': { light: 'calc(var(--deep-4) + 1px)', dark: '' },
    'deep-4': { light: 'calc(var(--deep-5) + 1px)', dark: '' },
    'deep-5': { light: 'calc(var(--deep-6) + 1px)', dark: '' },
    'deep-6': { light: 'calc(var(--deep-7) + 1px)', dark: '' },
    'deep-7': { light: 'calc(var(--deep-8) + 1px)', dark: '' },
    'deep-8': { light: 'calc(var(--deep-9) + 1px)', dark: '' },
    'deep-9': { light: '1px', dark: '' },
    'shallow-1': { light: 'calc(var(--deep-8) * 2)', dark: '' },
    'embedded-fallback': { light: 'rgb(var(--nowhere, 10) 20 30)', dark: 'hsl(var(--nowhere, var(--accent-h)) 50% 50%)' }
  }
}

const values = [
  'var(--a)', 'var(--a, var(--b))', 'var( --a , red )', 'var(--a) var(--b)', 'var(--a))', 'var(--a', 'calc(var(--a) * 2)', 'rgba(var(--bg), .8)',
  'hsl(var(--x))', 'var(--)', 'var(-- a)', 'var(--a,)', ' var(--light) ', 'var(--a,var(--b,var(--c)))', 'var(--a, (red))', 'red', '', '   ',
  'var(--secondary)', 'var(--nowhere, #123456)', 'var(--nowhere)', 'hsl(var(--accent-h), 50%, 50%)', 'color-mix(in srgb, var(--light) 50%, var(--dark))',
  'var(--ünicode)', 'var(--a_b-c9)', 'VAR(--a)', 'var(--a, red) var(--b)', 'var(--light,#fff) var(--dark)', 'hsl(var(--nowhere, 120), 50%, 50%)',
  'rgb(var(--nowhere, var(--also-nowhere, 9)) 0 0)', 'var(--n1, var(--n2, var(--n3, var(--n4, var(--color-accent)))))',
  'var(--n1, var(--n2, var(--n3, var(--color-accent))))', 'var(--n1, var(--n2, var(--n3, var(--n4, var(--n5, var(--n6, red))))))'
]
const queries = ['--tpl-space-lg', '  ---Light ', 'TEXT', '', '-', 'tpl-', 'Ä']
const paletteValues = [{ light: '#ffffff' }, { light: 'rgba(0,0,0,.5)' }, { light: 'var(--x)' }, { light: 12 }, {}, undefined]

const browser = await chromium.launch({ channel: 'chrome' })
try {
  const page = await browser.newPage()
  await page.setContent('<!doctype html><title>t</title>')
  await page.addScriptTag({ content: bundle.outputFiles[0].text })
  const result = await page.evaluate(([graphs, palettes, overrideSets, values, queries, paletteValues]) => {
    const contexts = []
    const plans = [
      ['gui-test', 'gui-test', 'none'], ['gui-test', 'gui-test', 'mixed'], ['gui-test with minimal', 'gui-test', 'none'],
      ['gui-test with minimal', 'Example', 'mixed'], ['minimal alone', 'Example', 'none'], ['edges', 'gui-test', 'mixed'],
      ['edges in an own output folder', 'Example', 'none'], ['many build files', 'gui-test', 'none'], [null, 'gui-test', 'mixed'], [null, 'Example', 'none']
    ]
    for (const [graphName, paletteName, overridesName] of plans) {
      const g = graphs.find((x) => x.name === graphName)
      const p = palettes.find((x) => x.name === paletteName)
      const ctx = { graph: g ? g.graph : null, overrides: overrideSets[overridesName], colors: p.colors, typography: p.typography }
      const keys = VG.allKnownKeys(ctx)
      const rows = keys.map((key) => {
        const perMode = (mode) => ({
          effective: VG.effectiveValue(key, mode, ctx) ?? null,
          base: VG.baseValue(key, mode, ctx) ?? null,
          chain: VG.resolveChain(key, mode, ctx),
          resolved: VG.resolvedValue(key, mode, ctx) ?? null
        })
        return {
          key,
          light: perMode('light'),
          dark: perMode('dark'),
          origin: VG.originOf(key, ctx),
          baseOrigin: VG.baseOriginOf(key, ctx),
          group: VG.groupOf(key),
          colorBase: VG.isColorVariable(key, ctx, 'base'),
          colorShown: VG.isColorVariable(key, ctx, 'shown')
        }
      })
      const literals = values.map((value) => ({
        value,
        light: VG.resolveValueLiteral(value, 'light', ctx) ?? null,
        dark: VG.resolveValueLiteral(value, 'dark', ctx) ?? null
      }))
      contexts.push({
        graph: graphName, palette: paletteName, overrides: overridesName,
        keys, rows, literals,
        pageGround: { light: VG.pageGround('light', ctx), dark: VG.pageGround('dark', ctx) }
      })
    }
    return {
      contexts,
      pureAlias: values.map((value) => ({ value, alias: VG.pureAlias(value) ?? null })),
      referenced: values.map((value) => ({ value, names: VG.referencedVariables(value) })),
      queries: queries.map((query) => ({ query, normalized: VG.normalizeVarQuery(query) })),
      paletteGrounds: paletteValues.map((palette) => ({ palette: palette ?? null, light: VG.paletteGround('light', palette), dark: VG.paletteGround('dark', palette) }))
    }
  }, [graphs, palettes, overrideSets, values, queries, paletteValues])
  mkdirSync(out, { recursive: true })
  // The contexts point at a graph by name; the graphs themselves are Fixtures/variable-graph's.
  writeFileSync(join(out, 'cases.json'), JSON.stringify({ palettes, overrideSets, ...result }) + '\n')
  console.log(`${result.contexts.length} contexts, ${result.contexts.reduce((n, c) => n + c.rows.length, 0)} rows`)
} finally {
  await browser.close()
}
