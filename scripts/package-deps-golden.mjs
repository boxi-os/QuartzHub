#!/usr/bin/env node
// Golden file for PackageJsonDeps, made by QuartzControl's own shared/packageJsonDeps.ts: each
// case is one call with its arguments and the answer. The arguments are parsed package.json
// values; `{"$unreadable": true}` stands for UNREADABLE, which JSON cannot carry. The cases come
// from the plan's own edges (removed, re-pinned, upstream wins, outside the sections, a package in
// two sections, a line npm wrote at another range) and from gui-test's real package.json.
//
//   Runtime/node/bin/node scripts/package-deps-golden.mjs [../QuartzControl]
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'package-deps')
const deps = await loadQuartzControl(control, 'shared/packageJsonDeps.ts', {})

const UN = { $unreadable: true }
const arg = (value) => (value && value.$unreadable ? deps.UNREADABLE : value)
const real = JSON.parse(readFileSync(join(homedir(), 'Documents/QuartzProjekte/gui-test/package.json'), 'utf-8'))
const realOurs = { ...real, dependencies: { ...real.dependencies, '@quartz-themes/default': '^2.0.0', 'is-odd': '^3.0.0' } }
const realTheirs = { ...real, dependencies: { ...real.dependencies, '@quartz-themes/core': '^9.0.0' } }
delete realTheirs.dependencies[Object.keys(real.dependencies)[0]]

const base = { name: 'q', version: '1.0.0', scripts: { build: 'x' }, dependencies: { a: '^1.0.0', core: '^1.0.0' }, devDependencies: { t: '^1.0.0' } }
const add = (pkg, section, name, range) => ({ ...pkg, [section]: { ...(pkg[section] ?? {}), [name]: range } })
const drop = (pkg, section, name) => {
  const copy = { ...pkg, [section]: { ...pkg[section] } }
  delete copy[section][name]
  return copy
}

const plans = [
  ['identical', base, base, base],
  ['added locally', base, add(base, 'dependencies', 'theme', '^2.0.0'), base],
  ['added in every section', base,
    add(add(add(add(base, 'dependencies', 'p', '1'), 'devDependencies', 'd', '2'), 'optionalDependencies', 'o', '3'), 'peerDependencies', 'e', '4'), base],
  ['re-pinned locally', base, add(base, 'dependencies', 'a', '^1.5.0'), base],
  ['re-pinned on both sides', base, add(base, 'dependencies', 'core', '^1.1.0'), add(base, 'dependencies', 'core', '^2.0.0')],
  ['re-pinned here, removed upstream', base, add(base, 'dependencies', 'core', '^1.1.0'), drop(base, 'dependencies', 'core')],
  ['added on both sides, other ranges', base, add(base, 'dependencies', 'n', '^1.0.0'), add(base, 'dependencies', 'n', '^2.0.0')],
  ['added on both sides, same range', base, add(base, 'dependencies', 'n', '^1.0.0'), add(base, 'dependencies', 'n', '^1.0.0')],
  ['removed locally', base, drop(base, 'dependencies', 'a'), base],
  ['moved to another section', base, add(drop(base, 'dependencies', 'a'), 'devDependencies', 'a', '^1.0.0'), base],
  ['removed, re-pinned and added at once', { dependencies: { a: '1', b: '1' } }, { dependencies: { c: '1', b: '2' } }, {}],
  ['a script changed', base, { ...base, scripts: { build: 'y' } }, base],
  ['a key added', base, { ...base, type: 'module' }, base],
  ['a key removed', base, (({ version, ...rest }) => rest)(base), base],
  ['key order only', base, { version: '1.0.0', name: 'q', scripts: { build: 'x' }, dependencies: base.dependencies, devDependencies: base.devDependencies }, base],
  ['nested key order', base, { ...base, scripts: { build: 'x', a: 'b' } }, { ...base }],
  ['non-string ranges are ignored', { dependencies: { a: 1, b: '^1' } }, { dependencies: { a: 2, b: '^1', c: null, d: '^2' } }, {}],
  ['section not an object', { dependencies: ['a'] }, { dependencies: 'a' }, { dependencies: null }],
  ['base null', null, base, base],
  ['ours an array', base, [1, 2], base],
  ['theirs a string', base, add(base, 'dependencies', 'x', '1'), 'nope'],
  ['all empty', {}, {}, {}],
  ['numeric names first', { dependencies: { b: '1' } }, { dependencies: { b: '1', 2: '1', 10: '1', a: '1' } }, {}],
  ['scoped names', base, add(add(base, 'dependencies', '@s/z', '1'), 'dependencies', '@s/a', '1'), base],
  ['empty range', base, add(base, 'dependencies', 'e', ''), base],
  ['undefined-like keys', { x: null }, { x: null, y: false }, {}],
  ['gui-test with own themes', real, realOurs, realTheirs],
  ['gui-test against itself', real, real, real]
]

const cases = []
for (const [name, b, o, t] of plans) cases.push({ name, fn: 'localPackageChanges', args: [b, o, t], result: deps.localPackageChanges(b, o, t) })

const entries = [
  { name: 'is-odd', section: 'dependencies', range: '^3.0.0' },
  { name: 'kind-of', section: 'devDependencies', range: '^6.0.0' },
  { name: 'kind-of', section: 'peerDependencies', range: '^6.0.0' },
  { name: 'left-pad', section: 'optionalDependencies', range: '1.3.0' },
  { name: '@quartz-themes/default', section: 'dependencies', range: '^2.0.0' }
]
cases.push({ name: 'commands for every section', fn: 'reinstallCommands', args: [entries], result: deps.reinstallCommands(entries) })
cases.push({ name: 'commands for none', fn: 'reinstallCommands', args: [[]], result: deps.reinstallCommands([]) })
cases.push({ name: 'commands keep order', fn: 'reinstallCommands', args: [[entries[4], entries[0]]], result: deps.reinstallCommands([entries[4], entries[0]]) })

const pkgs = [
  ['all there', { dependencies: { 'is-odd': '^3.0.0', '@quartz-themes/default': '^2.0.0' }, devDependencies: { 'kind-of': '^6.0.0' }, peerDependencies: { 'kind-of': '^6.0.0' }, optionalDependencies: { 'left-pad': '1.3.0' } }],
  ['npm wrote its range', { dependencies: { 'is-odd': '^3.0.1', '@quartz-themes/default': '^2.0.0' }, devDependencies: { 'kind-of': '^6.0.3' } }],
  ['none there', { dependencies: {} }],
  ['moved to dev', { devDependencies: { 'is-odd': '^3.0.0', 'kind-of': '^6.0.0' } }],
  ['dev there, peer gone', { devDependencies: { 'kind-of': '^6.0.0' }, optionalDependencies: { 'left-pad': '1.3.0' } }],
  ['kind-of moved to dependencies twice over', { dependencies: { 'kind-of': '^6.0.0' } }],
  ['not an object', 'x'],
  ['null', null],
  ['unreadable', UN]
]
for (const [name, pkg] of pkgs) {
  cases.push({ name: `missingFrom: ${name}`, fn: 'missingFrom', args: [pkg, entries], result: deps.missingFrom(arg(pkg), entries) })
  cases.push({ name: `absentFrom: ${name}`, fn: 'absentFrom', args: [pkg, entries], result: deps.absentFrom(arg(pkg), entries) })
  for (const putBack of [[], ['is-odd', 'kind-of'], ['kind-of', 'left-pad', 'nobody']]) {
    cases.push({ name: `outstandingPackages: ${name} ${putBack.join('+')}`, fn: 'outstandingPackages', args: [pkg, entries, putBack], result: deps.outstandingPackages(arg(pkg), entries, putBack) })
  }
}
const twice = [entries[1], { ...entries[1] }, entries[0]]
for (const [name, pkg] of [['twice, one moved', { dependencies: { 'kind-of': '^6.0.0' } }], ['twice, none', {}]]) {
  cases.push({ name: `absentFrom: ${name}`, fn: 'absentFrom', args: [pkg, twice], result: deps.absentFrom(pkg, twice) })
  cases.push({ name: `outstandingPackages: ${name}`, fn: 'outstandingPackages', args: [pkg, twice, ['kind-of']], result: deps.outstandingPackages(pkg, twice, ['kind-of']) })
}
cases.push({ name: 'dependencyRange: present', fn: 'dependencyRange', args: [pkgs[0][1], 'dependencies', 'is-odd'], result: deps.dependencyRange(pkgs[0][1], 'dependencies', 'is-odd') ?? null })
cases.push({ name: 'dependencyRange: absent', fn: 'dependencyRange', args: [pkgs[0][1], 'devDependencies', 'is-odd'], result: deps.dependencyRange(pkgs[0][1], 'devDependencies', 'is-odd') ?? null })
cases.push({ name: 'dependencyRange: not a string', fn: 'dependencyRange', args: [{ dependencies: { a: 1 } }, 'dependencies', 'a'], result: deps.dependencyRange({ dependencies: { a: 1 } }, 'dependencies', 'a') ?? null })

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify(cases, null, 1) + '\n')
console.log(`${cases.length} cases`)
