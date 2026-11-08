#!/usr/bin/env node
// Golden file for ProjectPrefs.outputDirProblem, made by QuartzControl's own `projectPrefs` schema
// (electron/main/ipc/schemas.ts): each case is an `outputDir` and whether the schema accepts it.
// The inputs walk its edges: empty, absolute and relative, ".." as a segment and inside a name,
// both separators, the two length limits in UTF-16 units, and "Gärten-Ü".
//
//   Runtime/node/bin/node scripts/output-dir-golden.mjs [../QuartzControl]
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'output-dir')
const schemas = await loadQuartzControl(control, 'electron/main/ipc/schemas.ts', {})

const values = [
  '', ' ', 'dist', 'public', './dist', 'dist/', 'a/b/c', '.', './', '..', '../site', 'a/..', 'a/../b', 'a/..b', '..a', '...',
  'a\\..\\b', 'a\\b', '\\..', '/', '/tmp/export', '/Users/x/Gärten-Ü/site', '/a/../b', '/..', 'Gärten-Ü', '~/site', 'C:\\x',
  'x'.repeat(1024), 'x'.repeat(1025), 'ä'.repeat(1024), 'ä'.repeat(1025), '😀'.repeat(512), '😀'.repeat(513),
  '/' + 'x'.repeat(4095), '/' + 'x'.repeat(4096), '/' + '😀'.repeat(2047) + 'x', '/' + '😀'.repeat(2048)
]
const cases = values.map((outputDir) => ({ outputDir, ok: schemas.projectPrefs.safeParse({ outputDir }).success }))
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify(cases, null, 1) + '\n')
console.log(`${cases.length} cases, ${cases.filter((c) => c.ok).length} accepted`)
