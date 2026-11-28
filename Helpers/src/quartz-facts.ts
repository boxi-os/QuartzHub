// quartz-facts: what a project's Quartz says about itself, read from its source with TypeScript's
// parser, never running it. QuartzHub used to carry these as its own constants, and each Quartz
// release that changed one made QuartzHub show something wrong (Quartz 5.3: links'
// `disableBrokenWikilinks` became true, two layout conditions and `not-<any>` came; plan
// "Quartz-Updates ohne ständiges Nachziehen", 2026-11-28).
//
//   builtins    `BUILTINS` in quartz/plugins/builtins/index.ts: per entry its configKey, order,
//               absorbs and the option defaults, followed through the import to the object literal
//               (`defaults: linksDefaults` → `export const linksDefaults = { … }` in ./links.ts)
//   conditions  the keys of `builtinConditions` in quartz/plugins/loader/conditions.ts, and whether
//               `getCondition` turns `not-<name>` into the negation of any condition (Quartz 5.3)
//
// Request on stdin:  { "project": "<path>" }
// Answer on stdout:  { "ok": true,
//                      "builtins":   { "state": "read", "entries": [Entry, …] }
//                                  | { "state": "missing" } | { "state": "unknown", "reason": "…" },
//                      "conditions": { "state": "read", "names": ["…"], "negation": bool }
//                                  | { "state": "missing" } | { "state": "unknown", "reason": "…" } }
//   Entry: { configKey, order?, absorbs?, defaults?, absorbedDefaults?, undefinedKeys: [], unresolved: [] }
//   A default whose value is `undefined` is left out and named in undefinedKeys (fonts' title … h6);
//   one that is no literal (a call, a reference) is left out and named in unresolved, so the caller
//   keeps its own value for that key. `missing`: the file is not there (an older Quartz);
//   `unknown`: it is there in a shape this reader does not know, which the caller reports.
import { existsSync, readFileSync } from 'fs'
import { dirname, join } from 'path'
import ts from 'typescript'
import { runHelper } from './protocol'

type Json = null | boolean | number | string | Json[] | { [key: string]: Json }
const isPlainObject = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)
const MAX_BYTES = 2 * 1024 * 1024

class Unknown extends Error {}

function parse(file: string): ts.SourceFile {
  const text = readFileSync(file, 'utf-8')
  if (text.length > MAX_BYTES) throw new Unknown(`${file} is larger than ${MAX_BYTES} bytes`)
  return ts.createSourceFile(file, text, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS)
}

function propName(name: ts.PropertyName): string | null {
  if (ts.isIdentifier(name) || ts.isStringLiteral(name) || ts.isNumericLiteral(name) || ts.isNoSubstitutionTemplateLiteral(name)) return name.text
  return null
}

/** `x as T`, `x satisfies T`, `<T>x`, `(x)`, `x!` are x. */
function bare(node: ts.Expression): ts.Expression {
  for (;;) {
    if (ts.isAsExpression(node) || ts.isSatisfiesExpression(node) || ts.isTypeAssertionExpression(node) ||
        ts.isParenthesizedExpression(node) || ts.isNonNullExpression(node)) node = node.expression
    else return node
  }
}

/** The initializer of a top-level `const name = …` in the file. */
function constInitializer(source: ts.SourceFile, name: string): ts.Expression | undefined {
  for (const statement of source.statements) {
    if (!ts.isVariableStatement(statement)) continue
    for (const decl of statement.declarationList.declarations) {
      if (ts.isIdentifier(decl.name) && decl.name.text === name && decl.initializer) return decl.initializer
    }
  }
  return undefined
}

/** Where an imported name is declared: `import { linksDefaults } from "./links"` → ./links.ts. */
function importedFrom(source: ts.SourceFile, name: string): { file: string; name: string } | undefined {
  for (const statement of source.statements) {
    if (!ts.isImportDeclaration(statement) || !ts.isStringLiteral(statement.moduleSpecifier)) continue
    const bindings = statement.importClause?.namedBindings
    if (!bindings || !ts.isNamedImports(bindings)) continue
    for (const element of bindings.elements) {
      if (element.name.text !== name) continue
      const specifier = statement.moduleSpecifier.text
      if (!specifier.startsWith('.')) return undefined
      const base = join(dirname(source.fileName), specifier).replace(/\.js$/, '')
      for (const candidate of [`${base}.ts`, `${base}.tsx`, join(base, 'index.ts')]) {
        if (existsSync(candidate)) return { file: candidate, name: element.propertyName?.text ?? name }
      }
      return undefined
    }
  }
  return undefined
}

/** An identifier followed to its object literal, in this file or the one it is imported from. */
function resolveObject(source: ts.SourceFile, node: ts.Expression): ts.ObjectLiteralExpression | undefined {
  node = bare(node)
  if (ts.isObjectLiteralExpression(node)) return node
  if (!ts.isIdentifier(node)) return undefined
  const local = constInitializer(source, node.text)
  if (local) return resolveObject(source, local)
  const from = importedFrom(source, node.text)
  if (!from) return undefined
  const other = parse(from.file)
  const init = constInitializer(other, from.name)
  return init ? resolveObject(other, init) : undefined
}

const NOT_LITERAL = Symbol('not a literal')
const UNDEFINED = Symbol('undefined')

function literal(node: ts.Expression): Json | typeof NOT_LITERAL | typeof UNDEFINED {
  node = bare(node)
  if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) return node.text
  if (ts.isNumericLiteral(node)) return Number(node.text)
  if (ts.isPrefixUnaryExpression(node) && node.operator === ts.SyntaxKind.MinusToken && ts.isNumericLiteral(node.operand)) return -Number(node.operand.text)
  if (node.kind === ts.SyntaxKind.TrueKeyword) return true
  if (node.kind === ts.SyntaxKind.FalseKeyword) return false
  if (node.kind === ts.SyntaxKind.NullKeyword) return null
  if (ts.isIdentifier(node) && node.text === 'undefined') return UNDEFINED
  if (ts.isArrayLiteralExpression(node)) {
    const out: Json[] = []
    for (const element of node.elements) {
      const value = ts.isSpreadElement(element) ? NOT_LITERAL : literal(element)
      if (value === NOT_LITERAL || value === UNDEFINED) return NOT_LITERAL
      out.push(value)
    }
    return out
  }
  if (ts.isObjectLiteralExpression(node)) {
    const read = readObject(node)
    return read.unresolved.length || read.undefinedKeys.length ? NOT_LITERAL : read.values
  }
  return NOT_LITERAL
}

function readObject(node: ts.ObjectLiteralExpression): { values: { [key: string]: Json }; undefinedKeys: string[]; unresolved: string[] } {
  const values: { [key: string]: Json } = {}
  const undefinedKeys: string[] = []
  const unresolved: string[] = []
  for (const prop of node.properties) {
    if (!ts.isPropertyAssignment(prop)) {
      // A spread or a shorthand: what it brings is not in this literal.
      unresolved.push(prop.name && ts.isIdentifier(prop.name) ? prop.name.text : '…')
      continue
    }
    const key = propName(prop.name)
    if (key === null) {
      unresolved.push('…')
      continue
    }
    const value = literal(prop.initializer)
    if (value === UNDEFINED) undefinedKeys.push(key)
    else if (value === NOT_LITERAL) unresolved.push(key)
    else values[key] = value
  }
  return { values, undefinedKeys, unresolved }
}

function builtins(project: string): Record<string, unknown> {
  const file = join(project, 'quartz', 'plugins', 'builtins', 'index.ts')
  if (!existsSync(file)) return { state: 'missing' }
  const source = parse(file)
  const list = constInitializer(source, 'BUILTINS')
  if (!list || !ts.isArrayLiteralExpression(bare(list))) throw new Unknown('no array literal BUILTINS in quartz/plugins/builtins/index.ts')
  const entries: Record<string, unknown>[] = []
  for (const element of (bare(list) as ts.ArrayLiteralExpression).elements) {
    const spec = ts.isSpreadElement(element) ? undefined : bare(element)
    if (!spec || !ts.isObjectLiteralExpression(spec)) throw new Unknown('a BUILTINS entry is no object literal')
    const entry: Record<string, unknown> = { undefinedKeys: [], unresolved: [] }
    for (const prop of spec.properties) {
      if (!ts.isPropertyAssignment(prop)) continue
      const key = propName(prop.name)
      if (key === 'configKey' || key === 'order' || key === 'absorbs') {
        const value = literal(prop.initializer)
        if (value !== NOT_LITERAL && value !== UNDEFINED) entry[key] = value
      } else if (key === 'defaults' || key === 'absorbedDefaults') {
        const object = resolveObject(source, prop.initializer)
        if (!object) {
          ;(entry.unresolved as string[]).push(key === 'defaults' ? '*' : 'absorbedDefaults')
          continue
        }
        const read = readObject(object)
        entry[key] = read.values
        if (key === 'defaults') {
          entry.undefinedKeys = read.undefinedKeys
          entry.unresolved = [...(entry.unresolved as string[]), ...read.unresolved]
        }
      }
    }
    if (typeof entry.configKey !== 'string') throw new Unknown('a BUILTINS entry has no literal configKey')
    entries.push(entry)
  }
  return { state: 'read', entries }
}

function conditions(project: string): Record<string, unknown> {
  const file = join(project, 'quartz', 'plugins', 'loader', 'conditions.ts')
  if (!existsSync(file)) return { state: 'missing' }
  const source = parse(file)
  const table = constInitializer(source, 'builtinConditions')
  if (!table || !ts.isObjectLiteralExpression(bare(table))) throw new Unknown('no object literal builtinConditions in quartz/plugins/loader/conditions.ts')
  const names: string[] = []
  for (const prop of (bare(table) as ts.ObjectLiteralExpression).properties) {
    const name = prop.name ? propName(prop.name) : null
    if (name === null) throw new Unknown('a condition without a literal name')
    names.push(name)
  }
  // Quartz 5.3: `getCondition` strips "not-" (a literal, or a top-level const holding it) and
  // negates what is left. Read as that call, not as a version.
  let negation = false
  const visit = (node: ts.Node): void => {
    if (negation) return
    if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression) && node.expression.name.text === 'startsWith' && node.arguments.length === 1) {
      const arg = bare(node.arguments[0])
      const value = ts.isIdentifier(arg) ? constInitializer(source, arg.text) : arg
      if (value && literal(value) === 'not-') negation = true
    }
    ts.forEachChild(node, visit)
  }
  for (const statement of source.statements) {
    if (ts.isFunctionDeclaration(statement) && statement.name?.text === 'getCondition' && statement.body) visit(statement.body)
  }
  return { state: 'read', names, negation }
}

function section(read: () => Record<string, unknown>): Record<string, unknown> {
  try {
    return read()
  } catch (error) {
    return { state: 'unknown', reason: error instanceof Error ? error.message : String(error) }
  }
}

runHelper((request) => {
  if (!isPlainObject(request) || typeof request.project !== 'string' || request.project === '') throw new Error('request has no project')
  const project = request.project
  return { builtins: section(() => builtins(project)), conditions: section(() => conditions(project)) }
})
