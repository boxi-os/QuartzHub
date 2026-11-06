#!/usr/bin/env node
// Golden file for RunningServersStore, made by QuartzControl's own runningServersStore.ts: each
// scenario starts from a file (or none), runs record/remove/takeAll and records, after every step,
// what the call answered, the file's text and whether something was moved aside.
//
//   Runtime/node/bin/node scripts/running-servers-golden.mjs [../QuartzControl]
//
// Stand-in: electron's app.getPath('userData'), a fresh directory per scenario.
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'running-servers')

const store = await loadQuartzControl(control, 'electron/main/services/runningServersStore.ts', {
  electron: 'export const app = { getPath: () => globalThis.__userData }'
})

const server = (pid, port = 8080) => ({ pid, port, startedAt: `2026-11-06T10:00:0${pid % 10}.000Z` })
const scenarios = [
  { name: 'record-remove-take', steps: [
    { op: 'record', id: 'a', server: server(101) },
    { op: 'record', id: 'b', server: server(202, 8081) },
    { op: 'record', id: 'a', server: server(103, 8082) },
    { op: 'remove', id: 'b' },
    { op: 'remove', id: 'unknown' },
    { op: 'takeAll' },
    { op: 'takeAll' }
  ] },
  { name: 'no-file', steps: [{ op: 'remove', id: 'a' }, { op: 'takeAll' }] },
  { name: 'others-kept-as-they-are', file: '{"z":{"pid":1,"port":2,"startedAt":"x","extra":[true]},"y":"not an object"}', steps: [
    { op: 'record', id: 'a', server: server(101) },
    { op: 'remove', id: 'z' },
    { op: 'takeAll' }
  ] },
  { name: 'not-json', file: '{"a":', steps: [{ op: 'record', id: 'a', server: server(101) }] },
  { name: 'empty-file', file: '', steps: [{ op: 'takeAll' }] },
  { name: 'null', file: 'null', steps: [{ op: 'record', id: 'a', server: server(101) }] },
  // A list where the object belongs is moved aside like broken JSON (readJsonFileOr's shape check).
  { name: 'a-list', file: '[{"pid":1}]', steps: [{ op: 'record', id: 'a', server: server(101) }, { op: 'takeAll' }] }
]

const recorded = []
for (const s of scenarios) {
  const dir = mkdtempSync(join(tmpdir(), 'qh-running-'))
  globalThis.__userData = join(dir, 'Profile')
  const file = join(globalThis.__userData, 'running-servers.json')
  if (s.file !== undefined) {
    mkdirSync(globalThis.__userData, { recursive: true })
    writeFileSync(file, s.file)
  }
  const steps = []
  for (const step of s.steps) {
    let answer = null
    if (step.op === 'record') await store.record(step.id, step.server)
    else if (step.op === 'remove') await store.remove(step.id)
    else answer = await store.takeAll()
    const names = existsSync(globalThis.__userData) ? readdirSync(globalThis.__userData) : []
    steps.push({
      ...step,
      expected: {
        answer,
        file: existsSync(file) ? readFileSync(file, 'utf8') : null,
        quarantined: names.filter((n) => n.includes('.corrupt-')).length
      }
    })
  }
  rmSync(dir, { recursive: true, force: true })
  recorded.push({ name: s.name, file: s.file ?? null, steps })
}

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'scenarios.json'), JSON.stringify(recorded, null, 2) + '\n')
console.log(`${recorded.length} Szenarien nach ${out}`)
