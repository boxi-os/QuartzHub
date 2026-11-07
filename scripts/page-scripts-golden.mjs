#!/usr/bin/env node
// Golden file for the export window's page scripts: the sha256 of QuartzControl's
// export/pageScripts.ts and shared/exportModel.ts, which Helpers/src/export/ carries unchanged.
// PageScriptsTests compares the copies against these, so a change on either side is seen.
//
//   Runtime/node/bin/node scripts/page-scripts-golden.mjs [../QuartzControl]
import { createHash } from 'node:crypto'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'page-scripts')
const sha = (path) => createHash('sha256').update(readFileSync(join(control, path))).digest('hex')
const sources = { 'pageScripts.ts': sha('electron/main/services/export/pageScripts.ts'), 'exportModel.ts': sha('shared/exportModel.ts') }
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'sources.json'), JSON.stringify(sources, null, 1) + '\n')
console.log(sources)
