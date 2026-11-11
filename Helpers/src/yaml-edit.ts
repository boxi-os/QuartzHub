// yaml-edit: read and write quartz.config.yaml without losing comments, layout or key order.
//
// Requests on stdin (one per call):
//   { "op": "read", "text": "…" }
//       → { errors: [{ message, line, col }] } when it does not parse, else
//         { errors: [], kind: "empty" | "mapping" | "other", value }
//   { "op": "write", "text": "…", "configuration": {…}, "theme": {…}, "plugins": [{…}], "layout"?: {…} }
//       → { text } — or { errors } / { notAMapping: true } when the file on disk cannot take it
//
// `write` is writeConfigNow from QuartzControl's configService.ts (same library, lineWidth 120), so
// a file written by either app reads the same in the other. One deviation: an unchanged value
// keeps its node, so a save no longer takes comments, flow style or anchors out of what it did not
// change (`syncMapping`; Review 2026-11-11 (2), nebenbei 1). What configService does around it
// moves to Swift (ConfigFile): the file itself, the lock, the frame paths, the sentences.
import { parseDocument, Document, isAlias, isMap } from 'yaml'
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
//
// Deviation from configService: a value that has not changed is left alone, and a mapping goes
// down key by key. setIn replaces a collection node and the comments inside it, so every save
// took the comments out of `configuration.links`, `.contentIndex` and `.drafts`, the blocks
// `plugin doctor --fix` writes with "comments are kept" (Review 2026-11-11 (2), nebenbei 1). The
// values written are the same.
//
// `ordered`: the keys end in `next`'s order, as when QuartzControl replaced the whole value (every
// level below `configuration`'s own keys, and `layout.groups`/`byPageType`); the pairs move with
// their comments.
function syncMapping(doc: Document, nodePath: string[], next: Record<string, unknown>, keep: string[] = [], ordered = false): void {
  const node = doc.getIn(nodePath)
  if (isMap(node)) {
    const exempt = new Set(keep)
    const stale = node.items
      .map((item) => String(item.key))
      .filter((key) => !exempt.has(key) && !(key in next))
    for (const key of stale) doc.deleteIn([...nodePath, key])
  }
  for (const [key, value] of Object.entries(next)) {
    const path = [...nodePath, key]
    const current = doc.getIn(path)
    if (isPlainObject(value) && isMap(current) && !isAlias(current)) {
      syncMapping(doc, path, value, [], true)
    } else if (!(doc.hasIn(path) && same(current, value))) {
      doc.setIn(path, value)
    }
  }
  const synced = doc.getIn(nodePath)
  if (ordered && isMap(synced)) {
    const order = Object.keys(next)
    synced.items.sort((a, b) => order.indexOf(String(a.key)) - order.indexOf(String(b.key)))
  }
}

// The node already holds this value: the same scalar or the same collection, as JSON sees it. An
// alias never counts: its anchor may just have been changed, and the alias would follow it.
function same(node: unknown, value: unknown): boolean {
  if (isAlias(node)) return false
  const held = node !== null && typeof node === 'object' && 'toJSON' in node ? (node as { toJSON(): unknown }).toJSON() : node
  return JSON.stringify(held) === JSON.stringify(value)
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
    // Key by key, as `configuration`: a comment inside a page type's entry survived no save.
    for (const key of ['groups', 'byPageType']) {
      const value = layout[key] ?? {}
      if (isPlainObject(value) && isMap(doc.getIn(['layout', key]))) syncMapping(doc, ['layout', key], value, [], true)
      else doc.setIn(['layout', key], value)
    }
    // Quartz 5.1's `layout.sidebars` ({ left, right }: fit | scroll | static). Not in
    // QuartzControl's writeConfigNow, which knew only the two keys above: written when the layout
    // carries it, removed when a layout read with it comes back without (decisions/phase-5-gleichstand.md).
    const heldSidebars = isPlainObject(held.layout) ? held.layout.sidebars : undefined
    if (layout.sidebars === undefined) {
      if (doc.hasIn(['layout', 'sidebars'])) doc.deleteIn(['layout', 'sidebars'])
    } else if (JSON.stringify(layout.sidebars) !== JSON.stringify(heldSidebars)) {
      // Only a change is written: setIn replaces the node, and with it the comments inside.
      doc.setIn(['layout', 'sidebars'], layout.sidebars)
    }
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
