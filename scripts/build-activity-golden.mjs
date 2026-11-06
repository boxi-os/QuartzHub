#!/usr/bin/env node
// Golden file for BuildActivityTracker, made by QuartzControl's own buildService.ts: its
// `followQuartzOutput` and `setActivity` (exposed at bundle time, the file stays as it is) are
// driven through sequences of steps - an activity set or cleared, a chunk of output from the build
// or from the server - and after each step the script records the activity and the activity
// events it emitted. A `startedAt` set by the step itself reads "new", one carried over "kept".
//
//   Runtime/node/bin/node scripts/build-activity-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'build-activity')

const nothing = 'export {}'
const service = await loadQuartzControl(control, 'electron/main/services/buildService.ts', {
  ...commonStubs,
  './layoutFrameService': nothing, './fontService': nothing, './styleService': nothing,
  './projectPaths': 'export async function repointAuthoredFrames() {}',
  './runningServersStore': 'export async function record() {}; export async function remove() {}; export async function takeAll() { return {} }',
  './serverDiscovery': 'export async function discoverServers() { return { servers: [] } }',
  './projectDependencies': 'export async function missingDependencies() { return [] }',
  './runCommand': 'export function needsShell() { return false }',
  './buildOutputGuard': 'export async function looksLikeQuartzBuild() { return false }',
  'tree-kill': 'export default function treeKill() {}'
}, { expose: ['followQuartzOutput', 'setActivity'] })

const ESC = '\u001b'
const scenarios = [
  { name: 'one-off-build', steps: [
    { feed: 'build', text: 'Parsing input files\n' },
    { set: { kind: 'build', phase: 'preparing' } },
    { feed: 'build', text: 'Quartz v5.0.0\n\nCleaned output directory `public` in 12ms\n' },
    { feed: 'build', text: 'Parsing input files using 8 threads\n' },
    { feed: 'server', text: 'Detected change, rebuilding...\n' },
    { feed: 'build', text: 'Parsed 40 Markdown files in 1s\nFiltered out 2 files\n' },
    { feed: 'build', text: `${ESC}[32mEmitting files${ESC}[39m\n` },
    { feed: 'build', text: 'Done processing 40 files in 3s\n' },
    { clear: true }
  ] },
  { name: 'soft-rebuild', steps: [
    { feed: 'server', text: 'Parsing input files\n' },
    { feed: 'server', text: 'Detected change, rebuilding...\n' },
    { feed: 'server', text: 'Filtered out 3 files\n' },
    { feed: 'server', text: 'Emitted 40 files to `public` in 20ms\n' },
    { feed: 'server', text: 'Done rebuilding in 312ms\n' },
    { feed: 'server', text: 'Done rebuilding in 312ms\n' }
  ] },
  { name: 'hard-rebuild', steps: [
    { feed: 'server', text: 'Detected a source code change, doing a hard rebuild...\n' },
    { feed: 'server', text: 'Transpiled `quartz.ts` in 300ms\nParsing input files\n' },
    { feed: 'server', text: 'Emitting files\n' },
    { feed: 'server', text: 'Done processing 12 files in 2s\n' }
  ] },
  { name: 'failed-rebuild', steps: [
    { feed: 'server', text: 'Rebuild failed: nothing to fail\n' },
    { feed: 'server', text: 'Detected change, rebuilding...\n' },
    { feed: 'server', text: `${ESC}[31mRebuild failed:${ESC}[39m SyntaxError\n` }
  ] },
  { name: 'first-build-of-the-server', steps: [
    { set: { kind: 'serve', phase: 'preparing' } },
    { feed: 'build', text: 'Parsing input files\n' },
    { feed: 'server', text: 'Parsing input files\n' },
    { feed: 'server', text: 'Done rebuilding in 1ms\n' },
    { feed: 'server', text: 'Emitting files\n' },
    { feed: 'server', text: 'Done processing 40 files\n' }
  ] },
  { name: 'one-chunk-many-lines', steps: [
    { feed: 'server', text: 'Detected change, rebuilding...\nFiltered out 2 files\nDone rebuilding in 5ms\nDetected a source code change\nParsing input files\n' }
  ] },
  { name: 'a-new-rebuild-replaces-one', steps: [
    { set: { kind: 'rebuild', phase: 'emitting' } },
    { feed: 'server', text: 'Detected change, rebuilding...\n' }
  ] },
  { name: 'a-rebuild-beside-a-build', steps: [
    { set: { kind: 'build', phase: 'parsing' } },
    { feed: 'server', text: 'Detected change, rebuilding...\nDone rebuilding in 2ms\nDone processing\n' },
    { feed: 'build', text: 'Emitting files\n' }
  ] },
  { name: 'same-phase-again', steps: [
    { set: { kind: 'build', phase: 'parsing' } },
    { feed: 'build', text: 'Parsing input files\nParsing input files\n' }
  ] },
  { name: 'filtered-out-needs-a-number', steps: [
    { set: { kind: 'rebuild', phase: 'parsing' } },
    { feed: 'server', text: 'Filtered out files\n' },
    { feed: 'server', text: 'Filtered out 0 files\n' }
  ] },
  // A line cut by a read boundary. QuartzControl matched each chunk on its own; QuartzHub keeps
  // the start of a line until its end arrives (BuildActivityTrackerTests, `deviations`).
  { name: 'a-line-in-two-chunks', steps: [
    { set: { kind: 'build', phase: 'parsing' } },
    { feed: 'build', text: 'Parsed 40 files\nEmitting fi' },
    { feed: 'build', text: 'les\nDone' }
  ] },
  { name: 'a-colour-code-in-two-chunks', steps: [
    { feed: 'server', text: `${ESC}[33mDetected change, rebu` },
    { feed: 'server', text: `ilding...${ESC}[39m\n` }
  ] }
]

const show = (activity) => activity === null || activity === undefined ? null
  : { kind: activity.kind, phase: activity.phase, startedAt: activity.startedAt === 'T0' ? 'kept' : 'new' }

const recorded = []
for (const s of scenarios) {
  const id = `p-${s.name}`
  const steps = []
  for (const step of s.steps) {
    const events = []
    const listener = (projectId, activity) => { if (projectId === id) events.push(show(activity)) }
    service.serverEvents.on('activity', listener)
    if (step.set) service.setActivity(id, { kind: step.set.kind, startedAt: 'T0', phase: step.set.phase })
    else if (step.clear) service.setActivity(id, null)
    else service.followQuartzOutput(id, step.text, step.feed)
    service.serverEvents.off('activity', listener)
    steps.push({ ...step, expected: { activity: show(service.getBuildActivity(id)), events } })
  }
  recorded.push({ name: s.name, steps })
}

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'scenarios.json'), JSON.stringify(recorded, null, 2) + '\n')
console.log(`${recorded.length} Szenarien nach ${out}`)
