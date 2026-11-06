// The canonical form of QuartzControl's normalized option schema, for the golden files: the keys
// of a node, a field and a result in one fixed order, which Swift's encoder writes as well. The
// order QuartzControl builds them in depends on the path a field took (fieldFromSchema and
// inferredField differ, a spread appends `default` at the end) and nothing reads it. Values that
// come from the plugin or the config (`default`, `when`, enum labels) are left as they are.

export function canonNode(node) {
  const out = { kind: node.kind }
  switch (node.kind) {
    case 'number':
      if (node.integer !== undefined) out.integer = node.integer
      if (node.minimum !== undefined) out.minimum = node.minimum
      if (node.maximum !== undefined) out.maximum = node.maximum
      break
    case 'enum':
      out.values = node.values
      break
    case 'union':
      out.variants = node.variants.map(canonNode)
      break
    case 'object':
      out.fields = node.fields.map(canonField)
      if (node.rest !== undefined) out.rest = canonNode(node.rest)
      break
    case 'record':
      out.value = canonNode(node.value)
      if (node.keys !== undefined) out.keys = node.keys
      break
    case 'array':
      out.items = canonNode(node.items)
      break
  }
  return out
}

export function canonField(field) {
  const out = { key: field.key, node: canonNode(field.node) }
  if (field.title !== undefined) out.title = field.title
  if (field.description !== undefined) out.description = field.description
  out.hasDefault = field.hasDefault
  if (field.hasDefault) out.default = field.default
  if (field.when !== undefined) out.when = field.when
  if (field.group !== undefined) out.group = field.group
  if (field.order !== undefined) out.order = field.order
  if (field.advanced !== undefined) out.advanced = field.advanced
  if (field.widget !== undefined) {
    out.widget = { kind: field.widget.kind }
    if (field.widget.dirOption !== undefined) out.widget.dirOption = field.widget.dirOption
  }
  if (field.l10n !== undefined) {
    out.l10n = Object.fromEntries(Object.entries(field.l10n).map(([lang, t]) => {
      const text = {}
      if (t.title !== undefined) text.title = t.title
      if (t.description !== undefined) text.description = t.description
      if (t.group !== undefined) text.group = t.group
      if (t.enum !== undefined) text.enum = t.enum
      return [lang, text]
    }))
  }
  out.origin = field.origin
  return out
}

export function canonSchema(schema) {
  if (schema === null) return null
  return { source: schema.source, fields: schema.fields.map(canonField), notes: schema.notes.map((n) => ({ path: n.path, reason: n.reason })) }
}

export function canonResult(result) {
  const out = { schema: canonSchema(result.schema) }
  if (result.packageVersion !== undefined) out.packageVersion = result.packageVersion
  if (result.unreadable !== undefined) out.unreadable = result.unreadable
  if (result.categories !== undefined) out.categories = result.categories
  return out
}
