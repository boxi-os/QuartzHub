#!/usr/bin/env node
// A copy of a built site whose Mermaid and KaTeX stylesheet come from the copy itself, for
// measuring the export offline (`export-pages-golden.mjs` in Chrome, `qh-check export-pages` in
// WebKit). Quartz 5 loads Mermaid with `import("https://cdnjs.cloudflare.com/ajax/libs/mermaid/…")`
// and KaTeX's stylesheet from jsdelivr; the export lets both through from outside. WebKit cannot
// answer an https request in its place (a scheme handler takes no http/https, a proxy would need
// TLS), so the copy is rewritten instead of the request: those two addresses become
// `/__cdn/<package>@<version>/…`, served from the npm package of the same version. What the
// export refuses stays as it is (copy-tex.js, d3, pixi, the preconnect), so it is refused in the
// measurement too.
//
// The packages are fetched once from the npm registry into .tools/cdn/, pinned with SHA-256 here
// (cross-checked on 2026-11-08 against the registry's sha512 integrity). cdnjs mirrors the npm
// package's dist/, so the files are Mermaid's own.
//
//   Runtime/node/bin/node scripts/cdn-build.mjs <build> <out>
//
// <out> must not exist. Ends with 1 when the build names another version than the ones pinned.
import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync } from 'node:fs'
import { spawnSync } from 'node:child_process'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const PACKAGES = [
  {
    name: 'mermaid', version: '11.4.0',
    sha256: '26f7d5d5498cd889b32f911349b3772d517d99cb7c021f6a9cadca0d19f20e12',
    // What the build writes → the folder of the package it stands for.
    from: 'https://cdnjs.cloudflare.com/ajax/libs/mermaid/11.4.0/', dist: 'package/dist',
    other: /https:\/\/cdnjs\.cloudflare\.com\/ajax\/libs\/mermaid\/([^/"'`]+)\//g
  },
  {
    name: 'katex', version: '0.16.11',
    sha256: '8c5494c5f7d8e8bf73ff3fe64d4bd09a340e4878b7eec9bbd9ef8d8f3e24193f',
    // Only the stylesheet: copy-tex.min.js is a script from outside and stays refused.
    from: 'https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css', file: 'katex.min.css', dist: 'package/dist',
    other: /https:\/\/cdn\.jsdelivr\.net\/npm\/katex@([^/"'`]+)\/dist\/katex\.min\.css/g
  }
]

const here = dirname(fileURLToPath(import.meta.url))
const root = resolve(here, '..')
const [buildArg, outArg] = process.argv.slice(2)
if (!buildArg || !outArg) {
  console.error('Aufruf: cdn-build.mjs <build> <out>')
  process.exit(2)
}
const build = resolve(buildArg)
const out = resolve(outArg)
if (!existsSync(join(build, 'index.html'))) {
  console.error(`Kein Build (index.html fehlt): ${build}`)
  process.exit(2)
}
if (existsSync(out)) {
  console.error(`Ziel gibt es schon: ${out}`)
  process.exit(2)
}

/// The package's dist/ under .tools/cdn/<name>@<version>, fetched and checked once.
async function fetchPackage(p) {
  const dir = join(root, '.tools', 'cdn', `${p.name}@${p.version}`)
  if (existsSync(join(dir, '.complete'))) return dir
  const url = `https://registry.npmjs.org/${p.name}/-/${p.name}-${p.version}.tgz`
  console.error(`[cdn] lade ${url}`)
  const response = await fetch(url)
  if (!response.ok) throw new Error(`${url}: HTTP ${response.status}`)
  const bytes = Buffer.from(await response.arrayBuffer())
  const actual = createHash('sha256').update(bytes).digest('hex')
  if (actual !== p.sha256) throw new Error(`${p.name}@${p.version}: Prüfsumme stimmt nicht: erwartet ${p.sha256}, gelesen ${actual}`)
  const unpack = `${dir}.unpack`
  rmSync(unpack, { recursive: true, force: true })
  rmSync(dir, { recursive: true, force: true })
  mkdirSync(unpack, { recursive: true })
  writeFileSync(join(unpack, 'package.tgz'), bytes)
  const tar = spawnSync('/usr/bin/tar', ['-xzf', join(unpack, 'package.tgz'), '-C', unpack, '--', p.dist], { stdio: 'inherit', timeout: 120_000 })
  if (tar.status !== 0) throw new Error(`${p.name}: tar endete mit ${tar.status ?? tar.signal}`)
  renameSync(join(unpack, p.dist), dir)
  rmSync(unpack, { recursive: true, force: true })
  writeFileSync(join(dir, '.complete'), `${p.name}@${p.version} ${p.sha256}\n`)
  return dir
}

const dirs = []
for (const p of PACKAGES) dirs.push(await fetchPackage(p))

const copy = spawnSync('/bin/cp', ['-cR', '--', build, out], { stdio: 'inherit', timeout: 300_000 })
if (copy.status !== 0) {
  console.error(`Kopie gescheitert (${copy.status ?? copy.signal})`)
  process.exit(2)
}

// Rewrite byte for byte (latin1 keeps every byte; the addresses are ASCII).
const counts = Object.fromEntries(PACKAGES.map((p) => [p.name, 0]))
const foreign = new Set()
function walk(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) { walk(path); continue }
    if (!entry.isFile() || !/\.(html|js|mjs|css)$/.test(entry.name)) continue
    let text = readFileSync(path).toString('latin1')
    let changed = false
    for (const p of PACKAGES) {
      for (const m of text.matchAll(p.other)) if (m[1] !== p.version) foreign.add(`${p.name}@${m[1]}`)
      if (!text.includes(p.from)) continue
      const to = `/__cdn/${p.name}@${p.version}/` + (p.file ?? '')
      const parts = text.split(p.from)
      counts[p.name] += parts.length - 1
      text = parts.join(to)
      changed = true
    }
    if (changed) writeFileSync(path, Buffer.from(text, 'latin1'))
  }
}
walk(out)
if (foreign.size) {
  console.error(`Der Build nennt andere Fassungen als die gepinnten: ${[...foreign].join(', ')}`)
  rmSync(out, { recursive: true, force: true })
  process.exit(1)
}
mkdirSync(join(out, '__cdn'))
PACKAGES.forEach((p, i) => {
  const c = spawnSync('/bin/cp', ['-cR', '--', dirs[i], join(out, '__cdn', `${p.name}@${p.version}`)], { stdio: 'inherit', timeout: 120_000 })
  if (c.status !== 0) { console.error(`Kopie von ${p.name} gescheitert`); process.exit(2) }
})
console.log(PACKAGES.map((p) => `${p.name}@${p.version}: ${counts[p.name]} Adressen`).join(', '))
