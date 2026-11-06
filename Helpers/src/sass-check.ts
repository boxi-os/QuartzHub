// Compiles with the *project's own* Sass, for the SCSS check of the Styles page and for reading
// Quartz's frame measures (QuartzControl's checkStyles, checkStyleSource and
// readQuartzFrameMeasures in styleService.ts). The project's copy, not one bundled here: it is the
// dart-sass Quartz's build uses (quartz/cli/handlers.js registers esbuild-sass-plugin, which
// resolves `sass` from the project), so the check stays honest across Quartz versions.
//
// QuartzControl loaded it into its main process; here it runs in this short child process, which
// holds nothing worth protecting. Nothing is decided here: the helper compiles what it is asked and
// says what Sass said; QuartzHub (ScssCheck.swift) makes the diagnostic and the measures from it.
//
// Request: { project: string, calls: Call[] }
//   Call = { kind: 'compile', path, loadPaths }
//        | { kind: 'compileString', source, url, syntax: 'scss' | 'css', loadPaths }
// Answer:  { loaded: true, results: ({ css } | { error: { message, sassMessage?, url?, line?, column? } })[] }
//        | { loaded: false }                       the project has no sass that loads
import { createRequire } from 'node:module'
import { join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { runHelper } from './protocol'

interface Call {
  kind: 'compile' | 'compileString'
  path?: string
  source?: string
  url?: string
  syntax?: 'scss' | 'css'
  loadPaths?: string[]
}

interface ProjectSass {
  compile: (path: string, options?: Record<string, unknown>) => { css: string }
  compileString: (source: string, options?: Record<string, unknown>) => { css: string }
}

function errorOf(err: unknown): Record<string, unknown> {
  const e = err as { message?: string; sassMessage?: string; span?: { url?: unknown; start?: { line: number; column: number } } }
  const url = e.span?.url
  return {
    message: e.message ?? String(err),
    ...(e.sassMessage !== undefined ? { sassMessage: e.sassMessage } : {}),
    ...(typeof url === 'string' ? { url } : url && typeof url === 'object' && 'href' in url ? { url: String((url as URL).href) } : {}),
    ...(e.span?.start ? { line: e.span.start.line, column: e.span.start.column } : {})
  }
}

runHelper((raw) => {
  const request = raw as { project: string; calls: Call[] }
  let sass: ProjectSass
  try {
    sass = createRequire(join(request.project, 'package.json'))('sass') as ProjectSass
  } catch {
    return { loaded: false }
  }
  const results = request.calls.map((call) => {
    try {
      if (call.kind === 'compile') {
        return { css: sass.compile(call.path!, { loadPaths: call.loadPaths, quietDeps: true, verbose: false }).css }
      }
      return {
        css: sass.compileString(call.source!, {
          url: pathToFileURL(call.url!),
          ...(call.syntax ? { syntax: call.syntax } : {}),
          loadPaths: call.loadPaths,
          quietDeps: true
        }).css
      }
    } catch (err) {
      return { error: errorOf(err) }
    }
  })
  return { loaded: true, results }
})
