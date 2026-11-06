// yaml-edit: read and write quartz.config.yaml without losing comments, layout or key order.
//
// Requests on stdin (one per call):
//   { "op": "read", "text": "…" }
//       → { errors: [{ message, line, col }] } when it does not parse, else
//         { errors: [], kind: "empty" | "mapping" | "other", value }
//   { "op": "write", "text": "…", "configuration": {…}, "theme": {…}, "plugins": [{…}], "layout"?: {…} }
//       → { text } — or { errors } / { notAMapping: true } when the file on disk cannot take it
//
// `write` is writeConfigNow from QuartzControl's configService.ts, operation for operation (same
// library, same calls, lineWidth 120), so a file written by either app reads the same in the other
// and a save changes in the file exactly what it changed there. What configService does around it
// moves to Swift (ConfigFile): the file itself, the lock, the frame paths, the sentences.
import { parseDocument, Document, isMap } from 'yaml'
import { runHelper } from './protocol'

function errorsOf(doc: Document): { message: string; line?: number; col?: number }[] {
  return doc.errors.map((e) => {
    const pos = e.linePos?.[0]
    return { message: e.message, ...(pos ? { line: pos.line, col: pos.col } : {}) }
  })
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && Object.getPrototypeOf(value) === Object.prototype
}

// What JSON does not carry. QuartzControl handed the config through Electron's structured clone,
// which keeps what JSON loses:
//   - `.inf`, `.nan` and `-0` (and, under `%YAML 1.1`, dates, sets and binary), which JSON turns
//     into null, a string or {};
//   - shared objects. `toJS()` gives an alias the very object of its anchor, the clone keeps the
//     sharing, and yaml writes a repeated object as anchor and alias again. Measured on Example's
//     config (`breakpoints: &a1` … `*a1`): through JSON the alias came back as a copy.
// So wherever the incoming value is exactly what JSON made of the value the document holds there,
// the document's own value goes back in: an unchanged part is written as QuartzControl wrote it,
// and a changed one is taken as it comes.
function revive(incoming: unknown, existing: unknown): unknown {
  if (existing === undefined) return incoming
  if (JSON.stringify(existing) === JSON.stringify(incoming)) return existing
  if (Array.isArray(incoming) && Array.isArray(existing)) {
    return incoming.map((item, index) => revive(item, existing[index]))
  }
  if (isPlainObject(incoming) && isPlainObject(existing)) {
    const out: Record<string, unknown> = {}
    for (const [key, value] of Object.entries(incoming)) out[key] = revive(value, existing[key])
    return out
  }
  return incoming
}

// setIn alone can only add or update, so a key the user removed in the editor would survive every
// save forever. This reconciles a mapping node with the incoming object: keys absent from `next`
// are deleted, the rest are set field-by-field so surrounding YAML comments stay intact.
// `keep` exempts keys that live under the same node but are managed elsewhere. (configService.ts)
function syncMapping(doc: Document, nodePath: string[], next: Record<string, unknown>, keep: string[] = []): void {
  const node = doc.getIn(nodePath)
  if (isMap(node)) {
    const exempt = new Set(keep)
    const stale = node.items
      .map((item) => String(item.key))
      .filter((key) => !exempt.has(key) && !(key in next))
    for (const key of stale) doc.deleteIn([...nodePath, key])
  }
  for (const [key, value] of Object.entries(next)) {
    doc.setIn([...nodePath, key], value)
  }
}

function object(raw: unknown, name: string): Record<string, unknown> {
  if (!isPlainObject(raw)) throw new Error(`${name} must be an object`)
  return raw
}

function read(text: string): Record<string, unknown> {
  const doc = parseDocument(text)
  const errors = errorsOf(doc)
  if (errors.length > 0) return { errors }
  // readConfig's shape test, on the value rather than the node.
  const value = doc.toJS() as unknown
  const kind =
    value === null || value === undefined ? 'empty' : typeof value === 'object' && !Array.isArray(value) ? 'mapping' : 'other'
  return { errors, kind, value: value ?? null }
}

function write(r: Record<string, unknown>, text: string): Record<string, unknown> {
  const doc = text ? parseDocument(text) : new Document({})
  if (doc.errors.length > 0) return { errors: errorsOf(doc) }
  if (doc.contents !== null && doc.contents !== undefined && !isMap(doc.contents)) return { notAMapping: true }

  const held = (doc.toJS() ?? {}) as Record<string, unknown>
  const heldConfiguration = isPlainObject(held.configuration) ? held.configuration : {}
  const configuration = revive(object(r.configuration, 'configuration'), heldConfiguration) as Record<string, unknown>
  const theme = revive(object(r.theme, 'theme'), heldConfiguration.theme) as Record<string, unknown>
  if (!Array.isArray(r.plugins)) throw new Error('plugins must be a list')
  const plugins = revive(r.plugins, held.plugins) as unknown[]

  // `theme` is exempt: readConfig splits it out of `configuration` into its own field.
  syncMapping(doc, ['configuration'], configuration, ['theme'])
  // Only reconcile the theme block if it already exists or the config actually carries one, so an
  // empty theme never creates a bare `theme:` node on a project that never had one.
  if (isMap(doc.getIn(['configuration', 'theme'])) || Object.keys(theme).length > 0) {
    syncMapping(doc, ['configuration', 'theme'], theme)
  }
  // Names are gone and frame paths are this project's: both done in Swift before the call.
  doc.set('plugins', plugins)
  // Only when the config carries a layout: every save round-trips what it loaded.
  if (r.layout !== undefined && r.layout !== null) {
    const layout = revive(object(r.layout, 'layout'), held.layout) as Record<string, unknown>
    doc.setIn(['layout', 'groups'], layout.groups ?? {})
    doc.setIn(['layout', 'byPageType'], layout.byPageType ?? {})
  }

  // The Quartz CLI writes this file with lineWidth 120 (writeDataToFile in
  // quartz/cli/plugin-data.js); with yaml's default of 80 every switch between the app and a CLI
  // plugin action folded the same long strings the other way.
  const serialized = doc.toString({ lineWidth: 120 })
  // configService's atomicWrite checks the result before it touches the file. Nothing here is
  // meant to produce invalid YAML, so this is a broken helper, not an input.
  const check = parseDocument(serialized)
  if (check.errors.length > 0) throw new Error(`result does not parse: ${check.errors[0].message.split('\n')[0]}`)
  return { text: serialized }
}

runHelper((request) => {
  const r = object(request, 'request')
  if (typeof r.text !== 'string') throw new Error('text missing')
  switch (r.op) {
    case 'read':
      return read(r.text)
    case 'write':
      return write(r, r.text)
    default:
      throw new Error(`unknown op ${String(r.op)}`)
  }
})
