// content-files: which files Quartz's build reads from content/, and the front matter of a new
// note, for "Startseite anlegen" (QuartzControl's quartzInputFiles and createIndexPage in
// contentService.ts; ContentIndexPage.swift does the rest).
//
// Requests on stdin (one per call):
//   { "op": "list", "project": "…", "cwd": "…/content", "patterns": ["…"] }
//       → { source: "quartz", files }     the project's own globby, as quartz/util/glob.ts runs it
//       → { source: "fallback", files }   no globby installed: the walk below, which reads no .gitignore
//       → { broken: "…" }                 a globby that is there and does not load
//   { "op": "frontmatter", "value": {…} } → { text }   yaml's stringify, as createIndexPage writes it
//   { "op": "parse", "texts": ["…"] }      → { values }  yaml's parse of each front matter, null where
//       it throws (FormUsages.swift: contentService.formUsages parses with `parseYaml` in a try)
//
// The project's globby runs in this short child process, not in QuartzHub: QuartzControl loaded it
// into its main process, which held safeStorage. The half-unpacked check (npm still unpacking) is
// QuartzHub's, before the call (ProjectDependencies.halfUnpackedModule).
import { readdir, realpath, stat } from 'node:fs/promises'
import { createRequire } from 'node:module'
import { join, matchesGlob, posix, sep } from 'node:path'
import { pathToFileURL } from 'node:url'
import { parse, stringify } from 'yaml'
import { runHelper } from './protocol'

async function list(project: string, cwd: string, patterns: string[]): Promise<Record<string, unknown>> {
  let entry: string
  try {
    entry = createRequire(join(project, 'quartz', 'util', 'glob.ts')).resolve('globby')
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code !== 'MODULE_NOT_FOUND') throw err
    return { source: 'fallback', files: await walkUnignored(await realpath(cwd), patterns) }
  }
  let globby: (pattern: string, options: object) => Promise<string[]>
  try {
    globby = ((await import(pathToFileURL(entry).href)) as { globby: typeof globby }).globby
    if (typeof globby !== 'function') throw new Error(`${entry} exports no globby()`)
  } catch (err) {
    return { broken: err instanceof Error ? err.message : String(err) }
  }
  const files = await globby('**/*.*', { cwd, ignore: patterns, gitignore: true })
  return { source: 'quartz', files: files.map((p) => p.split(sep).join('/')) }
}

// What the answer keeps of a parsed value: JSON has no Date (a `%YAML 1.1` document has
// timestamps), and JSON.stringify would make one a string, which the scan reads as a title or an
// id. Everything the scan looks at is a string, a boolean or an array; a Date becomes null.
function jsonSafe(value: unknown): unknown {
  if (value === undefined || value instanceof Date) return null
  if (Array.isArray(value)) return value.map(jsonSafe)
  if (value && typeof value === 'object') {
    if (value instanceof Map || value instanceof Set || ArrayBuffer.isView(value)) return {}
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, jsonSafe(v)]))
  }
  return value
}

runHelper(async (request) => {
  const r = request as { op?: string; project?: string; cwd?: string; patterns?: unknown; value?: unknown }
  switch (r.op) {
    case 'list':
      if (typeof r.project !== 'string' || typeof r.cwd !== 'string' || !Array.isArray(r.patterns)) throw new Error('project, cwd, patterns missing')
      return list(r.project, r.cwd, r.patterns.filter((p): p is string => typeof p === 'string'))
    case 'frontmatter':
      return { text: stringify(r.value) }
    case 'parse': {
      const texts = (request as { texts?: unknown }).texts
      if (!Array.isArray(texts)) throw new Error('texts missing')
      return {
        values: texts.map((text) => {
          try {
            return typeof text === 'string' ? jsonSafe(parse(text)) : null
          } catch {
            return null
          }
        })
      }
    }
    default:
      throw new Error(`unknown op ${String(r.op)}`)
  }
})

// ── copied ── from QuartzControl electron/main/services/contentService.ts (97afbbbc, 2026-10-21),
// `walkUnignored` with its comment, unchanged.
// The fallback, and it says what it is not: no `.gitignore` is read. The patterns follow fast-glob's
// two rules - a file is tested with its own path, and a folder is pruned only by a pattern whose last
// segment is static or which ends in `/**` (`isAffectDepthOfReadingPattern`), which is why `x/*`,
// `*` and `[xy]` keep a folder's subfolders while `x/` and `**/x` drop them. Before that, a pattern
// loses what fast-glob and picomatch take off it: one leading `!` (every ignore pattern is negative
// to fast-glob, `convertToPositivePattern`, unless it is `!(…)`), and whatever a path normaliser
// takes off - fast-glob and picomatch read `tpl//`, `tpl/.`, `tpl/./`, `.//x` and `x/..` as the
// folder they name, `matchesGlob` does not, so the fallback listed `tpl` where Quartz leaves it out
// (review 2026-09-19, finding 2). `posix.normalize` does the same, and what it reduces to the root
// (`.`, `./`, `x/..`, the empty pattern) drops everything in globby, hence `**`.
//
// Where it still differs, measured against globby 16.2.2 / fast-glob 3.3.3 under Electron's Node
// 24.18.1 and under Node 26.5.1 alike, over 63 patterns on eleven entries (review 2026-09-19; the
// first 31 were review 2026-09-18's): `{x,y}`, which fast-glob expands into two static patterns
// before it applies the pruning rule; `!!x`, which fast-glob turns into "everything but x"; `foo\*`,
// because Node's `matchesGlob` reads a backslash as a separator (`windowsPathsNoEscape`); on macOS a
// pattern with a wildcard ignores case (`priva*` drops `Privat.md`, `*.MD` drops `top.md`), because
// `matchesGlob` sets `nocase` there and fast-glob does not; and `**/tpl/` and `tpl/./**`, which
// globby does not apply to `tpl` at all. Those are 7 of the 63 answers, and apart from `{x,y}` and
// `!!x` every one leaves out something Quartz builds - a missing link, not a dead one. That holds
// for the patterns measured, not for every pattern there is. Hidden entries are skipped the way
// `dot: false` skips them.
// Links are followed, with `seen` against a link back to an ancestor - where fast-glob runs a loop
// to its depth limit, this stops at the first repeat; the folders found are the same.
async function walkUnignored(root: string, rawPatterns: string[]): Promise<string[]> {
  const patterns = rawPatterns.map((pattern) => {
    const positive = pattern.startsWith('!') && pattern[1] !== '(' ? pattern.slice(1) : pattern
    const normalized = posix.normalize(positive)
    return normalized === '.' || normalized === './' ? '**' : normalized
  })
  const test = (probe: string, pattern: string): boolean => {
    if (pattern === probe) return true
    try {
      return matchesGlob(probe, pattern)
    } catch {
      return false
    }
  }
  const pruning = patterns
    .filter((pattern) => pattern.endsWith('/**') || !/[*?[\]{}()!@+\\]/.test(posix.basename(pattern)))
    .map((pattern) => pattern.replace(/\/$/, ''))
  const ignored = (path: string): boolean => {
    const segments = path.split('/')
    const folders = segments.slice(0, -1).map((_, i) => segments.slice(0, i + 1).join('/'))
    return (
      patterns.some((pattern) => test(path, pattern)) ||
      folders.some((folder) => pruning.some((pattern) => test(folder, pattern)))
    )
  }
  const files: string[] = []
  const seen = new Set<string>([root])
  const walk = async (dir: string, prefix: string): Promise<void> => {
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      if (entry.name.startsWith('.')) continue
      const full = join(dir, entry.name)
      const rel = prefix ? `${prefix}/${entry.name}` : entry.name
      let isDir = entry.isDirectory()
      if (entry.isSymbolicLink()) {
        try {
          isDir = (await stat(full)).isDirectory()
        } catch {
          continue
        }
      }
      if (!isDir) {
        if (!ignored(rel)) files.push(rel)
        continue
      }
      const real = await realpath(full)
      if (seen.has(real)) continue
      seen.add(real)
      await walk(full, rel)
    }
  }
  await walk(root, '')
  return files
}
