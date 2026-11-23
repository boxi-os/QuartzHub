// theme-fetch: asks the project's own @quartz-themes/core (3.x) what a theme entry resolves to, the
// way its build will, and leaves what it downloaded in the cache the build reads
// (docs/plan-themes-core-3.md, step 1; ThemeFetch.swift).
//
// Request on stdin (one per call):
//   { "project": "…", "options": { …the plugin entry's options… }, "offline": false }
//       → { core: "missing" }                      no @quartz-themes/core installed
//       → { core: "broken", error }                installed, does not load
//       → { core: "old", coreVersion }             loads, has no resolveTheme (2.x)
//       → { core: "3", coreVersion, theme: {…} }   resolved: name, modes, version, source,
//                                                  styleSettings (the preset of a 2.x id), css
//       → { core: "3", coreVersion, failed }       core's own message (a typo with its three
//                                                  suggestions, offline and not cached, …)
//
// What the build does with the options, from core 3.1.1's `QuartzTheme` (src/transformer.ts):
// `{ ...defaultOptions, ...userOptions }` with `theme: "Tokyo Night"`, the spec `theme.variation`
// when `variation` is set, and `cacheDir`, `cacheHours` (as `cacheTtl`) and `version` handed to
// `resolveTheme`. The build runs in the project folder, so a relative `cacheDir` and a local theme
// path resolve there; so does this helper. With `offline` (QuartzHub's `-QHOffline`) core gets a
// fetch that fails as a closed network does, and answers from its cache alone.
//
// The project's core runs in this short child process, as content-files runs the project's globby.
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join } from 'node:path'
import { pathToFileURL } from 'node:url'
import { runHelper } from './protocol'

type Resolved = {
  name: string
  css: string
  modes?: string[]
  styleSettings?: Record<string, unknown>
  source: string
  version?: string
}
type Core = { resolveTheme?: (spec: string, opts: Record<string, unknown>) => Promise<Resolved> }

// The package is ESM with an `import`-only export map, which `require.resolve` does not follow;
// its package.json is exported, and the entry is read from there.
function coreEntry(project: string): { entry: string; version?: string } | undefined {
  let manifestPath: string
  try {
    manifestPath = createRequire(join(project, 'package.json')).resolve('@quartz-themes/core/package.json')
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === 'MODULE_NOT_FOUND') return undefined
    throw err
  }
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf-8')) as {
    version?: string
    main?: string
    exports?: string | { '.'?: string | { import?: string; default?: string } }
  }
  const dot = typeof manifest.exports === 'string' ? manifest.exports : manifest.exports?.['.']
  const target = typeof dot === 'string' ? dot : (dot?.import ?? dot?.default ?? manifest.main ?? 'index.js')
  return { entry: join(dirname(manifestPath), target), version: manifest.version }
}

const offlineFetch = (): Promise<Response> => Promise.reject(new TypeError('fetch failed (QuartzHub is offline)'))

runHelper(async (request) => {
  const r = request as { project?: unknown; options?: unknown; offline?: unknown }
  if (typeof r.project !== 'string') throw new Error('project missing')
  const options = { theme: 'Tokyo Night', ...(r.options && typeof r.options === 'object' ? r.options : {}) } as Record<string, unknown>
  process.chdir(r.project)

  let found: ReturnType<typeof coreEntry>
  let core: Core
  try {
    found = coreEntry(r.project)
    if (!found) return { core: 'missing' }
    core = (await import(pathToFileURL(found.entry).href)) as Core
  } catch (err) {
    return { core: 'broken', error: err instanceof Error ? err.message : String(err) }
  }
  if (typeof core.resolveTheme !== 'function') return { core: 'old', coreVersion: found.version }

  const spec = options.variation ? `${String(options.theme)}.${String(options.variation)}` : options.theme
  const sourceOpts: Record<string, unknown> = {
    cacheDir: options.cacheDir,
    cacheTtl: ((options.cacheHours as number | undefined) ?? 24) * 60 * 60 * 1e3,
    version: options.version
  }
  if (r.offline === true) sourceOpts.fetch = offlineFetch
  try {
    const theme = await core.resolveTheme(spec as string, sourceOpts)
    return {
      core: '3',
      coreVersion: found.version,
      theme: {
        name: theme.name,
        modes: theme.modes ?? null,
        version: theme.version ?? null,
        source: theme.source,
        styleSettings: theme.styleSettings ?? null,
        css: theme.css
      }
    }
  } catch (err) {
    return { core: '3', coreVersion: found.version, failed: err instanceof Error ? err.message : String(err) }
  }
})
