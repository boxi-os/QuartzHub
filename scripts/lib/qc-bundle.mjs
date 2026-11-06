// Loads a service of QuartzControl's main process into Node, for the golden scripts: esbuild
// bundles the TypeScript file with QuartzControl's own node_modules, and the neighbours named in
// `stubs` (an import specifier as it is written there → JavaScript source) are replaced. Loaded,
// not copied: the rule "ein Prüfskript lädt die Logik, statt sie abzuschreiben".
import { build } from '../../Helpers/node_modules/esbuild/lib/main.js'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { createRequire } from 'node:module'

/** The stand-ins every golden script needs: no snapshots, and mainT answering key and arguments. */
export const commonStubs = {
  './snapshotService': 'export async function createSnapshot() { throw new Error("no snapshots here") }',
  '../i18n': 'export function mainT(key, args) { return JSON.stringify({ key, args: args ?? {} }) }'
}

export async function loadQuartzControl(control, entry, stubs = commonStubs) {
  const work = mkdtempSync(join(tmpdir(), 'qh-qc-bundle-'))
  const outfile = join(work, 'bundle.cjs')
  const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  try {
    await build({
      entryPoints: [join(control, entry)],
      // CommonJS: yaml's ESM build requires "process" dynamically, which an ESM bundle refuses.
      bundle: true, platform: 'node', format: 'cjs', outfile, logLevel: 'warning', absWorkingDir: control,
      // QuartzControl's own alias (electron.vite.config.ts), for services that import from shared/.
      alias: { '@shared': join(control, 'shared') },
      plugins: [{
        name: 'stand-ins',
        setup(b) {
          for (const specifier of Object.keys(stubs)) {
            b.onResolve({ filter: new RegExp(`^${escape(specifier)}$`) }, () => ({ path: specifier, namespace: 'stub' }))
          }
          b.onLoad({ filter: /.*/, namespace: 'stub' }, (args) => ({ contents: stubs[args.path], loader: 'js' }))
        }
      }]
    })
    return createRequire(import.meta.url)(outfile)
  } finally {
    rmSync(work, { recursive: true, force: true })
  }
}
