#!/usr/bin/env node
// Golden files for ConfigFile, made by QuartzControl's own configService.ts: each case reads an
// input with readConfig, applies a few edits to what it read, and writes it back with writeConfig.
// The Swift test (ConfigFileTests) does the same edits through ConfigFile and compares the bytes.
//
//   Runtime/node/bin/node scripts/config-golden.mjs [../QuartzControl] [~/Documents/QuartzProjekte]
//
// Loaded, not copied (the rule "ein Prüfskript lädt die Logik, statt sie abzuschreiben"): esbuild
// bundles configService.ts with QuartzControl's own node_modules (yaml 2.9.0, the version the
// helper pins), and only two neighbours are stand-ins: the snapshot store (writeConfig is called
// with snapshot: false) and mainT, which answers the key and its arguments as JSON so the test can
// compare the sentence without its wording.
//
// Inputs: the configs of gui-test and Example with the home folder masked, and small files for
// the edges. Only these two projects are read (never the real profile, never a private project).
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync, existsSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const projects = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'config')

const work = mkdtempSync(join(tmpdir(), 'qh-config-golden-'))
const { readConfig, writeConfig } = await loadQuartzControl(control, 'electron/main/services/configService.ts')

const masked = (name) =>
  readFileSync(join(projects, name, 'quartz.config.yaml'), 'utf-8').replaceAll(homedir(), '/Users/example')

const special = `# Kopf der Datei
configuration:
  pageTitle: Garten # der Titel
  ratio: .inf
  minus: -0
  hex: 0x1F
  quoted: 'einfach'
  long: "${'Ein langer Satz, der weit über die Breite hinausgeht, '.repeat(3)}"
  theme:
    colors:
      lightMode:
        light: "#fff" # hell
plugins:
  # ein Kommentar in der Liste
  - source: github:quartz-community/explorer#v1
    name: alter-name
    options:
      depth: .nan
  - source:
      repo: https://github.com/a/b.git
    enabled: yes
  - source:
      repo: x
      name: Benannt
    enabled: 0
  - source: git+https://example.org/c/d.git#main
    enabled: true
    order: 30
`

const noTheme = `configuration:
  pageTitle: Ohne Thema
plugins: []
`

const anchors = `configuration:
  pageTitle: Anker
  sizes: [1, .inf, -0]
  shared: &s
    a: 1
    b: [x, y]
  again: *s
  list: &l [1, 2]
  listAgain: *l
plugins:
  - source: a
    enabled: true
    options: &o
      deep: { n: .nan }
  - source: b
    enabled: true
    options: *o
`

const syntax = `configuration:
  pageTitle: "abc
  baseUrl: example.org
plugins: []
`

// edits: { set: path, value } | { delete: path } | { move: [from, to] } on readConfig's object.
const cases = [
  { name: 'gui-test-unchanged', input: masked('gui-test'), edits: [] },
  {
    name: 'gui-test-edited', input: masked('gui-test'), edits: [
      { set: ['configuration', 'pageTitle'], value: 'Neuer Titel' },
      { delete: ['configuration', 'locale'] },
      { set: ['theme', 'cdnCaching'], value: false },
      { set: ['plugins', 3, 'enabled'], value: false },
      { set: ['plugins', 5, 'options', 'neu'], value: { a: [1, 2.5, 'drei'] } },
      { move: [10, 2] }
    ]
  },
  { name: 'example-unchanged', input: masked('Example'), edits: [] },
  {
    name: 'example-layout', input: masked('Example'), edits: [
      { set: ['layout', 'groups', 'neu'], value: { priority: 5 } },
      { set: ['theme', 'typography', 'header'], value: 'Inter' }
    ]
  },
  { name: 'special-unchanged', input: special, edits: [] },
  {
    name: 'special-edited', input: special, edits: [
      { set: ['configuration', 'pageTitle'], value: 'Wiese' },
      { delete: ['theme', 'colors'] },
      { set: ['plugins', 1, 'enabled'], value: false }
    ]
  },
  { name: 'anchors-unchanged', input: anchors, edits: [] },
  {
    name: 'anchors-edited', input: anchors, edits: [
      { set: ['configuration', 'pageTitle'], value: 'Kette' },
      { set: ['configuration', 'again', 'a'], value: 2 },
      { set: ['plugins', 1, 'enabled'], value: false }
    ]
  },
  { name: 'no-theme', input: noTheme, edits: [{ set: ['configuration', 'baseUrl'], value: 'example.org' }] },
  { name: 'empty', input: '', edits: [{ set: ['configuration', 'pageTitle'], value: 'Neu' }] },
  { name: 'comment-only', input: '# nur ein Kommentar\n', edits: [{ set: ['configuration', 'pageTitle'], value: 'Neu' }] },
  { name: 'syntax-error', input: syntax, edits: [] },
  { name: 'a-list', input: '- a\n- b\n', edits: [] },
  { name: 'a-string', input: 'abc\n', edits: [] },
  { name: 'plugins-not-a-list', input: 'configuration:\n  pageTitle: x\nplugins: 5\n', edits: [] },
  // Changed on disk between the read and the save: the write asks again.
  { name: 'broken-before-save', input: noTheme, edits: [], replaceBeforeWrite: syntax },
  { name: 'list-before-save', input: noTheme, edits: [], replaceBeforeWrite: '- a\n' }
]

// Edits copy along their path and share everything else, as the renderer's state updates do
// (`{ ...config, configuration: { ...config.configuration, pageTitle } }`): an alias the edit does
// not pass through stays the anchor's object, one it passes through becomes a copy.
function apply(config, edit) {
  if (edit.move) {
    const [from, to] = edit.move
    const plugins = [...config.plugins]
    const [entry] = plugins.splice(from, 1)
    plugins.splice(to, 0, entry)
    return { ...config, plugins }
  }
  const path = edit.set ?? edit.delete
  const step = (node, depth) => {
    const copy = Array.isArray(node) ? [...node] : { ...(node ?? {}) }
    const key = path[depth]
    if (depth === path.length - 1) {
      if (edit.set) copy[key] = edit.value
      else if (Array.isArray(copy)) copy.splice(key, 1)
      else delete copy[key]
    } else {
      copy[key] = step(copy[key], depth + 1)
    }
    return copy
  }
  return step(config, 0)
}

const caught = (error) => {
  try { return JSON.parse(error.message) } catch { throw error }
}

rmSync(out, { recursive: true, force: true })
for (const c of cases) {
  const dir = join(out, c.name)
  mkdirSync(dir, { recursive: true })
  const project = mkdtempSync(join(work, 'project-'))
  const file = join(project, 'quartz.config.yaml')
  writeFileSync(file, c.input)
  writeFileSync(join(dir, 'input.yaml'), c.input)
  writeFileSync(join(dir, 'edits.json'), JSON.stringify({ edits: c.edits, replaceBeforeWrite: c.replaceBeforeWrite ?? null }, null, 2) + '\n')
  let config
  try {
    config = await readConfig(project)
  } catch (error) {
    writeFileSync(join(dir, 'error.json'), JSON.stringify({ during: 'read', ...caught(error) }, null, 2) + '\n')
    continue
  }
  writeFileSync(join(dir, 'read.json'), JSON.stringify(config, null, 2) + '\n')
  for (const edit of c.edits) config = apply(config, edit)
  if (c.replaceBeforeWrite !== undefined) writeFileSync(file, c.replaceBeforeWrite)
  try {
    await writeConfig(project, config, { snapshot: false })
    writeFileSync(join(dir, 'expected.yaml'), readFileSync(file))
  } catch (error) {
    writeFileSync(join(dir, 'error.json'), JSON.stringify({ during: 'write', ...caught(error) }, null, 2) + '\n')
  }
}
rmSync(work, { recursive: true, force: true })
console.log(`${cases.length} Fälle nach ${out}`)
if (!existsSync(join(out, 'gui-test-unchanged', 'expected.yaml'))) process.exit(1)
