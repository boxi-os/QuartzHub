// Reads and edits Quartz's locale files (quartz/i18n/locales/*.ts) with the TypeScript compiler,
// as QuartzControl's localizationService.ts did in its main process: the same version (5.9.3), the
// same walk, the same splice, so both apps read the same entries and write the same bytes.
//
// Nothing about files here: QuartzHub (LocaleFiles.swift) reads and writes them, takes the
// baseline, asks git. The helper parses what it is given.
//
// Request: { calls: Call[] }
//   Call = { kind: 'entries', text, fileName }
//        | { kind: 'splice', text, fileName, path: string[], replacement: string }
// Answer:  { results: Result[] }
//   entries → { entries: { path, kind: 'string' | 'template', value }[] } | { noRoot: true }
//   splice  → { text } | { noRoot: true } | { notFound: true } | { syntax: string }
import ts from 'typescript'
import { runHelper } from './protocol'

interface Call {
  kind: 'entries' | 'splice'
  text: string
  fileName: string
  path?: string[]
  replacement?: string
}

// `export default { ... } as const satisfies Translation`: the `as`/`satisfies`/parentheses peeled.
function unwrapToObjectLiteral(expr: ts.Expression): ts.ObjectLiteralExpression | null {
  let node: ts.Expression = expr
  while (true) {
    if (ts.isParenthesizedExpression(node)) node = node.expression
    else if (ts.isAsExpression(node) || ts.isSatisfiesExpression(node)) node = node.expression
    else break
  }
  return ts.isObjectLiteralExpression(node) ? node : null
}

function findDefaultExportObject(source: ts.SourceFile): ts.ObjectLiteralExpression | null {
  let result: ts.ObjectLiteralExpression | null = null
  ts.forEachChild(source, (node) => {
    if (result || !ts.isExportAssignment(node) || node.isExportEquals) return
    result = unwrapToObjectLiteral(node.expression)
  })
  return result
}

function propName(prop: ts.ObjectLiteralElementLike): string | null {
  if (!ts.isPropertyAssignment(prop)) return null
  if (ts.isIdentifier(prop.name) || ts.isStringLiteral(prop.name)) return prop.name.text
  return null
}

interface Entry {
  path: string[]
  kind: 'string' | 'template'
  value: string
}

function walkEntries(obj: ts.ObjectLiteralExpression, source: ts.SourceFile, prefix: string[], out: Entry[]): void {
  for (const prop of obj.properties) {
    const name = propName(prop)
    if (!name || !ts.isPropertyAssignment(prop)) continue
    const path = [...prefix, name]
    const init = prop.initializer
    if (ts.isObjectLiteralExpression(init)) walkEntries(init, source, path, out)
    else if (ts.isStringLiteral(init) || ts.isNoSubstitutionTemplateLiteral(init)) out.push({ path, kind: 'string', value: init.text })
    else out.push({ path, kind: 'template', value: init.getText(source) })
  }
}

function findInitializer(obj: ts.ObjectLiteralExpression, path: string[]): ts.Expression | null {
  let current: ts.ObjectLiteralExpression = obj
  for (let i = 0; i < path.length; i++) {
    const prop = current.properties.find((p) => propName(p) === path[i])
    if (!prop || !ts.isPropertyAssignment(prop)) return null
    if (i === path.length - 1) return prop.initializer
    if (!ts.isObjectLiteralExpression(prop.initializer)) return null
    current = prop.initializer
  }
  return null
}

function entries(call: Call): Record<string, unknown> {
  const source = ts.createSourceFile(call.fileName, call.text, ts.ScriptTarget.Latest, true)
  const root = findDefaultExportObject(source)
  if (!root) return { noRoot: true }
  const out: Entry[] = []
  walkEntries(root, source, [], out)
  return { entries: out }
}

// Only the initializer's own span is replaced; everything else stays byte for byte. The result is
// parsed whole before it is handed back, so a malformed template value never reaches the file.
function splice(call: Call): Record<string, unknown> {
  const source = ts.createSourceFile(call.fileName, call.text, ts.ScriptTarget.Latest, true)
  const root = findDefaultExportObject(source)
  if (!root) return { noRoot: true }
  const target = findInitializer(root, call.path ?? [])
  if (!target) return { notFound: true }
  const text = call.text.slice(0, target.getStart(source)) + call.replacement + call.text.slice(target.getEnd())
  const diagnostics = ts.transpileModule(text, {
    reportDiagnostics: true,
    compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.Latest }
  }).diagnostics
  const errors = (diagnostics ?? []).filter((d) => d.category === ts.DiagnosticCategory.Error)
  if (errors.length > 0) return { syntax: errors.map((d) => ts.flattenDiagnosticMessageText(d.messageText, ' ')).join('; ') }
  return { text }
}

runHelper((raw) => {
  const request = raw as { calls: Call[] }
  return { results: request.calls.map((call) => (call.kind === 'splice' ? splice(call) : entries(call))) }
})
