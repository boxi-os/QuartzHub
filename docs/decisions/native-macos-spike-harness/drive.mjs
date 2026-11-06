// Drives the sidecar like the Swift app would: spawn, invoke channels, answer dialog requests.
import { spawn } from 'child_process'
import { createInterface } from 'readline'
const [node, sidecar, profile, project, ...steps] = process.argv.slice(2)
const child = spawn(node, [sidecar], {
  env: { ...process.env, QC_USER_DATA: profile, QC_APP_PATH: '/Users/boxi/Development/QuartzControl', QC_SAFE_STORAGE_PASSWORD: 'spike-only', QC_LOCALE: 'de' },
  stdio: ['pipe', 'pipe', 'pipe']
})
child.stderr.on('data', (d) => process.stderr.write('  [stderr] ' + d))
let id = 0; const pend = new Map(); const events = []
createInterface({ input: child.stdout }).on('line', (l) => {
  const m = JSON.parse(l)
  if (m.event) { events.push(m); return }
  if (m.rid) { console.log('  <request>', m.request, JSON.stringify(m.params).slice(0, 120)); child.stdin.write(JSON.stringify({ rid: m.rid, result: { response: 0 } }) + '\n'); return }
  const p = pend.get(m.id); pend.delete(m.id); p(m)
})
const invoke = (ch, args = []) => new Promise((r) => { const i = ++id; pend.set(i, r); child.stdin.write(JSON.stringify({ id: i, invoke: ch, args }) + '\n') })
const show = (label, m) => console.log(label, m.error ? 'ERROR ' + m.error : JSON.stringify(m.result).slice(0, 300))
const wait = (ms) => new Promise((r) => setTimeout(r, ms))
const t0 = Date.now()
show('settings:environment', await invoke('settings:environment'))
console.log('  first answer after', Date.now() - t0, 'ms')
const added = await invoke('project:add', [project]); show('project:add', added)
const pid = added.result?.id ?? (await invoke('project:list')).result?.[0]?.id
show('project:list', await invoke('project:list'))
show('project:overview', await invoke('project:overview'))
show('config:get', await invoke('config:get', [project]))
show('bad args', await invoke('project:add', ['relative/path']))
if (steps.includes('server')) {
  show('server:start', await invoke('server:start', [pid, project]))
  for (let i = 0; i < 60; i++) {
    await wait(1000)
    const st = (await invoke('server:status', [pid])).result
    if (st?.state === 'running' || st?.state === 'error') { console.log('  status after', i + 1, 's:', JSON.stringify(st).slice(0, 200)); break }
  }
  const port = (await invoke('server:status', [pid])).result?.options?.port
  try { const r = await fetch(`http://localhost:${port}/`); console.log('  GET / ->', r.status, (await r.text()).length, 'bytes') } catch (e) { console.log('  GET failed', e.message) }
  show('server:stop', await invoke('server:stop', [pid]))
  await wait(1500)
  show('server:status', await invoke('server:status', [pid]))
}
for (const e of events.filter(e => e.event === 'server:log').slice(0, 8)) console.log('  log:', JSON.stringify(e.payload).slice(0, 160))
const byChannel = {}; for (const e of events) byChannel[e.event] = (byChannel[e.event] ?? 0) + 1
console.log('events:', JSON.stringify(byChannel))
child.stdin.end()
