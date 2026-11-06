// dts-schema: the options of a Quartz plugin, read from its .d.ts files, as JSON Schema.
//
// Request on stdin:  { "distDir": "<plugin>/dist" }
// Answer on stdout:  { "ok": true, "schema": {…} | null }   (null: no .d.ts or no options type)
//                    { "ok": false, "error": "…" }           (could not read; never "no options")
//
// The code below `── copied ──` is QuartzControl 1.3.0, electron/main/services/pluginSchemaService.ts
// (indexDts … membersOf), unchanged: the measurements behind it (docs/decisions/plugins-and-config.md
// in QuartzControl) stay valid only as long as it is the same code. The normalizer
// (shared/pluginOptionSchema.ts) moves to Swift in Phase 3; this helper only translates.
import { readdirSync, readFileSync, statSync, existsSync } from 'fs'
import { join } from 'path'
import ts from 'typescript'
import { runHelper } from './protocol'

const MAX_DTS_FILES = 200
const MAX_DTS_BYTES = 4 * 1024 * 1024
const isPlainObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)

function walkFiles(dir: string, extension: string): string[] {
  const results: string[] = []
  for (const entry of readdirSync(dir)) {
    if (entry === 'node_modules') continue
    const full = join(dir, entry)
    const stat = statSync(full)
    if (stat.isDirectory()) results.push(...walkFiles(full, extension))
    else if (entry.endsWith(extension)) results.push(full)
  }
  return results
}

runHelper((request) => {
  const distDir = (request as { distDir?: unknown }).distDir
  if (typeof distDir !== 'string' || distDir === '') throw new Error('distDir missing')
  return { schema: optionsJsonSchemaFromDts(distDir) }
})

// ── copied ──
type Decl = ts.InterfaceDeclaration | ts.TypeAliasDeclaration
type JsonSchema = Record<string, unknown>

interface DtsIndex {
  decls: Map<string, Decl[]>
  order: Decl[]
  /** Type names the plugin's own constructors are parameterised with, and how often. */
  votes: Map<string, number>
}

function indexDts(distDir: string): DtsIndex | null {
  if (!existsSync(distDir)) return null
  const files = walkFiles(distDir, '.d.ts').slice(0, MAX_DTS_FILES)
  const decls = new Map<string, Decl[]>()
  const order: Decl[] = []
  const votes = new Map<string, number>()
  let total = 0
  for (const file of files) {
    let text: string
    try {
      total += statSync(file).size
      if (total > MAX_DTS_BYTES) break
      text = readFileSync(file, 'utf-8')
    } catch {
      continue
    }
    const source = ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true)
    ts.forEachChild(source, (node) => {
      if (ts.isInterfaceDeclaration(node) || ts.isTypeAliasDeclaration(node)) {
        const list = decls.get(node.name.text) ?? []
        list.push(node)
        decls.set(node.name.text, list)
        order.push(node)
      }
      if (ts.isVariableStatement(node)) {
        for (const d of node.declarationList.declarations) {
          const name = constructorOptionsType(d.type)
          if (name) votes.set(name, (votes.get(name) ?? 0) + 1)
        }
      }
    })
  }
  return decls.size > 0 ? { decls, order, votes } : null
}

// `declare const X: QuartzTransformerPlugin<MultilanguageOptions>` - the type quartz hands the
// options to, as the plugin itself declares it. `Partial<Options>` counts as `Options`
// (alias-redirects writes it that way).
function constructorOptionsType(type: ts.TypeNode | undefined): string | null {
  if (!type || !ts.isTypeReferenceNode(type) || !ts.isIdentifier(type.typeName)) return null
  if (!/^Quartz\w*(Plugin|Constructor)$/.test(type.typeName.text)) return null
  let arg = type.typeArguments?.[0]
  while (arg && ts.isTypeReferenceNode(arg) && ts.isIdentifier(arg.typeName) && /^(Partial|Required|Readonly)$/.test(arg.typeName.text)) {
    arg = arg.typeArguments?.[0]
  }
  return arg && ts.isTypeReferenceNode(arg) && ts.isIdentifier(arg.typeName) ? arg.typeName.text : null
}

// The declaration the options object is typed as.
//
// It used to be the first interface whose name ends in "Options", in file order. For
// quartz-multilanguage that is `SeoOptions`, a nested part of the real one - the page offered
// `hreflang`, `ogLocale` and `xDefault` as top-level options, and a switch written there landed at
// `options.hreflang`, where the plugin never looks; the 15 keys gui-test actually sets were
// invisible. Now, in this order:
//
//   1. what the plugin's constructors are parameterised with (`QuartzTransformerPlugin<T>`,
//      `QuartzComponentConstructor<T>`, ...) - the plugin's own statement, and the most votes win;
//   2. otherwise an `…Options` interface that no other one refers to - the outermost - leaving
//      out `Resolved…`, which is the shape after defaults, not what the user writes. Several left:
//      the one with the most members.
function pickOptionsRoot(index: DtsIndex): Decl | null {
  const voted = [...index.votes].sort((a, b) => b[1] - a[1]).find(([name]) => index.decls.has(name))
  if (voted) return index.decls.get(voted[0])![0]

  const candidates = index.order.filter(
    (d): d is ts.InterfaceDeclaration =>
      ts.isInterfaceDeclaration(d) && /options$/i.test(d.name.text) && !/^Resolved/.test(d.name.text) && d.members.some(ts.isPropertySignature)
  )
  const referenced = new Set<string>()
  const collect = (node: ts.Node): void => {
    if (ts.isTypeReferenceNode(node) && ts.isIdentifier(node.typeName)) referenced.add(node.typeName.text)
    ts.forEachChild(node, collect)
  }
  for (const c of candidates) c.members.forEach(collect)
  const outermost = candidates.filter((c) => !referenced.has(c.name.text))
  const pool = outermost.length > 0 ? outermost : candidates
  return pool.sort((a, b) => b.members.length - a.members.length)[0] ?? null
}

function optionsJsonSchemaFromDts(distDir: string): JsonSchema | null {
  const index = indexDts(distDir)
  if (!index) return null
  const root = pickOptionsRoot(index)
  if (!root) return null
  return declToSchema(root, index, new Set(), 0, null)
}

const note = (reason: string): JsonSchema => ({ 'x-quartz-note': reason })
const MAX_TYPE_DEPTH = 12

function docOf(node: ts.Node): string | undefined {
  for (const doc of ts.getJSDocCommentsAndTags(node)) {
    if (ts.isJSDoc(doc) && doc.comment) return ts.getTextOfJSDocComment(doc.comment)
  }
  return undefined
}

function memberName(name: ts.PropertyName): string | null {
  return ts.isIdentifier(name) || ts.isStringLiteral(name) || ts.isNumericLiteral(name) ? name.text : null
}

// `keep` narrows the members (Pick/Omit): null keeps all, otherwise a predicate on the name.
function membersToSchema(
  members: ts.NodeArray<ts.TypeElement>,
  index: DtsIndex,
  seen: Set<string>,
  depth: number,
  keep: ((name: string) => boolean) | null
): JsonSchema {
  const properties: Record<string, JsonSchema> = {}
  let additional: JsonSchema | undefined
  for (const member of members) {
    if (ts.isPropertySignature(member) || ts.isMethodSignature(member)) {
      const name = memberName(member.name)
      if (name === null || (keep && !keep(name))) continue
      const schema: JsonSchema = ts.isMethodSignature(member)
        ? note('a function cannot be written in YAML')
        : member.type
          ? typeToSchema(member.type, index, seen, depth + 1)
          : note('no type')
      const description = docOf(member)
      properties[name] = description ? { ...schema, description } : schema
    } else if (ts.isIndexSignatureDeclaration(member) && member.type) {
      additional = typeToSchema(member.type, index, seen, depth + 1)
    }
  }
  return { type: 'object', properties, ...(additional ? { additionalProperties: additional } : {}) }
}

function declToSchema(decl: Decl, index: DtsIndex, seen: Set<string>, depth: number, keep: ((name: string) => boolean) | null): JsonSchema {
  if (ts.isTypeAliasDeclaration(decl)) return typeToSchema(decl.type, index, seen, depth + 1, keep)
  let schema = membersToSchema(decl.members, index, seen, depth, keep)
  // `interface A extends B` - B's members first, A's override.
  for (const clause of decl.heritageClauses ?? []) {
    for (const base of clause.types) {
      if (!ts.isIdentifier(base.expression)) continue
      const inherited = typeToSchema(ts.factory.createTypeReferenceNode(base.expression.text), index, seen, depth + 1, keep)
      if (isPlainObject(inherited.properties)) {
        schema = { ...schema, properties: { ...inherited.properties, ...(schema.properties as object) } }
      }
    }
  }
  return schema
}

function literalKeys(node: ts.TypeNode | undefined): string[] | null {
  if (!node) return null
  if (ts.isLiteralTypeNode(node) && ts.isStringLiteral(node.literal)) return [node.literal.text]
  if (ts.isUnionTypeNode(node)) {
    const all = node.types.map(literalKeys)
    return all.every((k): k is string[] => k !== null) ? all.flat() : null
  }
  return null
}

function typeToSchema(
  node: ts.TypeNode,
  index: DtsIndex,
  seen: Set<string>,
  depth: number,
  keep: ((name: string) => boolean) | null = null
): JsonSchema {
  if (depth > MAX_TYPE_DEPTH) return note('types nested too deeply')
  switch (node.kind) {
    case ts.SyntaxKind.BooleanKeyword:
      return { type: 'boolean' }
    case ts.SyntaxKind.StringKeyword:
      return { type: 'string' }
    case ts.SyntaxKind.NumberKeyword:
      return { type: 'number' }
    case ts.SyntaxKind.AnyKeyword:
    case ts.SyntaxKind.UnknownKeyword:
      return {}
  }
  if (ts.isParenthesizedTypeNode(node)) return typeToSchema(node.type, index, seen, depth, keep)
  if (ts.isTypeOperatorNode(node)) return typeToSchema(node.type, index, seen, depth, keep)
  if (ts.isLiteralTypeNode(node)) {
    const lit = node.literal
    if (ts.isStringLiteral(lit)) return { const: lit.text }
    if (ts.isNumericLiteral(lit)) return { const: Number(lit.text) }
    if (lit.kind === ts.SyntaxKind.TrueKeyword) return { const: true }
    if (lit.kind === ts.SyntaxKind.FalseKeyword) return { const: false }
    return note('a null literal')
  }
  if (ts.isUnionTypeNode(node)) {
    const members = node.types.filter(
      (t) => t.kind !== ts.SyntaxKind.UndefinedKeyword && !(ts.isLiteralTypeNode(t) && t.literal.kind === ts.SyntaxKind.NullKeyword)
    )
    const schemas = members.map((t) => typeToSchema(t, index, seen, depth + 1))
    if (schemas.length === 1) return schemas[0]
    if (schemas.every((s) => 'const' in s)) return { enum: schemas.map((s) => s.const) }
    return { anyOf: schemas }
  }
  if (ts.isArrayTypeNode(node)) return { type: 'array', items: typeToSchema(node.elementType, index, seen, depth + 1) }
  if (ts.isTypeLiteralNode(node)) return membersToSchema(node.members, index, seen, depth, keep)
  if (ts.isFunctionTypeNode(node)) return note('a function cannot be written in YAML')
  if (ts.isIntersectionTypeNode(node)) {
    const parts = node.types.map((t) => typeToSchema(t, index, seen, depth + 1, keep))
    if (parts.every((p) => p.type === 'object' && isPlainObject(p.properties))) {
      return { type: 'object', properties: Object.assign({}, ...parts.map((p) => p.properties)) }
    }
    return note('an intersection of non-object types')
  }
  if (ts.isTypeReferenceNode(node)) {
    const name = ts.isIdentifier(node.typeName) ? node.typeName.text : node.typeName.right.text
    const args = node.typeArguments ?? []
    switch (name) {
      case 'Array':
      case 'ReadonlyArray':
        return { type: 'array', items: args[0] ? typeToSchema(args[0], index, seen, depth + 1) : {} }
      case 'Record':
        return { type: 'object', additionalProperties: args[1] ? typeToSchema(args[1], index, seen, depth + 1) : {} }
      case 'Partial':
      case 'Required':
      case 'Readonly':
        return args[0] ? typeToSchema(args[0], index, seen, depth + 1, keep) : note(`${name} without an argument`)
      case 'Omit':
      case 'Pick': {
        const keys = literalKeys(args[1])
        if (!args[0] || !keys) return note(`${name} with keys that are not string literals`)
        const narrowed = name === 'Omit' ? (k: string) => !keys.includes(k) : (k: string) => keys.includes(k)
        const combined = keep ? (k: string) => keep(k) && narrowed(k) : narrowed
        return typeToSchema(args[0], index, seen, depth + 1, combined)
      }
    }
    const decls = index.decls.get(name)
    if (!decls) return note(`type ${name} is not declared in the package`)
    // Seen per shape, not per name: `Omit<LayoutBoxOptions, "byLang">` inside LayoutBoxOptions is
    // not a cycle, because the member that would recurse is the one it leaves out.
    const shape = keep ? `${name}|${[...membersOf(decls[0])].filter(keep).join(',')}` : name
    if (seen.has(shape)) return note(`type ${name} refers to itself`)
    seen.add(shape)
    try {
      return declToSchema(decls[0], index, seen, depth + 1, keep)
    } finally {
      seen.delete(shape)
    }
  }
  return note(`type syntax ${ts.SyntaxKind[node.kind]} is not supported`)
}

function membersOf(decl: Decl): string[] {
  if (!ts.isInterfaceDeclaration(decl)) return []
  return decl.members.map((m) => (m.name ? memberName(m.name) : null)).filter((n): n is string => n !== null)
}
