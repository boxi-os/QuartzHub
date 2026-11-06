#!/usr/bin/env node
// Copies the JSON files QuartzControl wrote into two test projects to the golden-file fixtures of
// QuartzHubCore, with every address, host, path and hash replaced by a fixed stand-in.
//
//   Runtime/node/bin/node scripts/golden-fixtures.mjs [~/Documents/QuartzProjekte]
//
// Why masked and re-serialised: the fixtures are versioned, and the real files carry mail
// addresses, server paths and origins. Masking replaces string values only and writes the result
// with JSON.stringify(value, null, 2) - the very call QuartzControl writes with - so the bytes stay
// in QuartzControl's form and key order and nesting are the originals. The script refuses a file
// that is not already in that form, so a fixture never claims a form the source did not have.
//
// Only gui-test and Example are read (docs/conventions.md: never the real profile, never
// hinterland-history). Deploy manifests are skipped except the small relay one: the site
// manifests hold hundreds of paths and add nothing the relay one does not show.
import { readFileSync, writeFileSync, mkdirSync, readdirSync, rmSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { homedir } from 'node:os'
import { fileURLToPath } from 'node:url'

const root = process.argv[2] ?? join(homedir(), 'Documents', 'QuartzProjekte')
const out = join(dirname(fileURLToPath(import.meta.url)), '..', 'Packages', 'QuartzHubCore', 'Tests',
  'QuartzHubCoreTests', 'Fixtures', 'quartz-gui')
const projects = ['gui-test', 'Example']

// key -> stand-in. Applied wherever the key appears, at any depth; arrays of strings are masked
// element by element.
const MASK = {
  from: 'relay@example.org',
  allowedOrigins: 'https://example.org',
  location: 'sftp|00000000-0000-4000-8000-000000000000|/srv/www/example|forms',
  operator: 'operator@host',
  server: 'deploy@example.org',
  hash: '0'.repeat(64),
  remotePath: '/srv/www/example/',
  path: '/Users/example/Export',
  outputDir: ''
}

function mask(value, key) {
  if (Array.isArray(value)) return value.map((item) => mask(item, key))
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, mask(v, k)]))
  }
  if (typeof value === 'string' && key in MASK && value !== '') return MASK[key]
  return value
}

function maskManifest(value) {
  // Paths of the relay are the relay's own file names, not the user's; only the hashes are masked.
  return Object.fromEntries(Object.keys(value).map((k, i) => [k, String(i).padStart(64, 'a')]))
}

rmSync(out, { recursive: true, force: true })
let count = 0
for (const project of projects) {
  const dir = join(root, project, '.quartz-gui')
  const target = join(out, project)
  mkdirSync(target, { recursive: true })
  for (const name of readdirSync(dir).sort()) {
    if (!name.endsWith('.json')) continue
    const isManifest = name.startsWith('deploy-manifest-')
    if (isManifest && !name.startsWith('deploy-manifest-relay-')) continue
    const text = readFileSync(join(dir, name), 'utf8')
    const value = JSON.parse(text)
    if (JSON.stringify(value, null, 2) !== text) {
      console.error(`${project}/${name}: not in JSON.stringify(…, null, 2) form, refusing`)
      process.exit(1)
    }
    let masked = isManifest ? maskManifest(value) : mask(value, '')
    // Target names are what the user typed, often a domain.
    if (name === 'publish-targets.json') masked = masked.map((t, i) => ({ ...t, name: `Ziel ${i + 1}` }))
    // Target ids are UUIDs and say nothing; the file name keeps the shape, not the real id.
    const outName = isManifest ? 'deploy-manifest-relay-00000000-0000-4000-8000-000000000001.json' : name
    writeFileSync(join(target, outName), JSON.stringify(masked, null, 2))
    count++
  }
}
console.log(`${count} fixtures in ${out}`)
