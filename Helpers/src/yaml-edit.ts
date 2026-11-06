// yaml-edit: read and change quartz.config.yaml without losing comments, layout or key order.
//
// Requests on stdin (one per call):
//   { "op": "read", "text": "…" }
//       → { kind: "empty" | "mapping" | "other", value, errors: [{ message, line, col }] }
//   { "op": "set",  "text": "…", "path": ["plugins", 3, "options", "x"], "value": … }
//   { "op": "delete", "text": "…", "path": [...] }
//       → { text } — or { ok: false, error } when the result would not parse again
//
// Same library and options as QuartzControl's configService.ts (parseDocument, toString with
// lineWidth 120), so a file written by either app reads the same in the other. What configService
// does on top (repoint paths, locks, the empty-file and no-plugins-list sentences) moves to Swift.
import { parseDocument, Document, isMap } from 'yaml'
import { runHelper } from './protocol'

type Path = (string | number)[]

function errorsOf(doc: Document): { message: string; line?: number; col?: number }[] {
  return doc.errors.map((e) => {
    const pos = e.linePos?.[0]
    return { message: e.message, ...(pos ? { line: pos.line, col: pos.col } : {}) }
  })
}

function serialize(doc: Document): string {
  const text = doc.toString({ lineWidth: 120 })
  // configService checks the result before it touches the file; the helper refuses instead.
  const check = parseDocument(text)
  if (check.errors.length > 0) throw new Error(`result does not parse: ${check.errors[0].message}`)
  return text
}

function asPath(raw: unknown): Path {
  if (!Array.isArray(raw) || !raw.every((p) => typeof p === 'string' || typeof p === 'number')) {
    throw new Error('path must be an array of strings and numbers')
  }
  return raw
}

runHelper((request) => {
  const r = request as { op?: unknown; text?: unknown; path?: unknown; value?: unknown }
  if (typeof r.text !== 'string') throw new Error('text missing')
  const doc = parseDocument(r.text)
  switch (r.op) {
    case 'read': {
      const errors = errorsOf(doc)
      const kind = doc.contents === null ? 'empty' : isMap(doc.contents) ? 'mapping' : 'other'
      return { kind, value: errors.length > 0 ? null : doc.toJS(), errors }
    }
    case 'set': {
      if (doc.errors.length > 0) throw new Error(`document has errors: ${doc.errors[0].message}`)
      doc.setIn(asPath(r.path), r.value)
      return { text: serialize(doc) }
    }
    case 'delete': {
      if (doc.errors.length > 0) throw new Error(`document has errors: ${doc.errors[0].message}`)
      doc.deleteIn(asPath(r.path))
      return { text: serialize(doc) }
    }
    default:
      throw new Error(`unknown op ${String(r.op)}`)
  }
})
