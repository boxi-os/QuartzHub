// npm for the core-update golden steps, run by QuartzControl's service and by QuartzHub's: it
// writes down each call and does what `install` does to the two files, nothing else. The mode is
// read from npm-mode.txt next to this file:
//   ok         every call succeeds
//   eacces     every install fails before it writes anything (node_modules at 555)
//   resolve    succeeds, but writes the range npm would resolve (^3.0.0 becomes ^3.0.1)
//   fail-peer  the --save-peer call fails without writing, the others succeed
// A spec named does-not-exist@… fails as a 404, without writing.
const fs = require('fs')
const W = __dirname
const args = process.argv.slice(2)
// The note as it stands while npm runs: the one an app that ends now would leave behind.
let note = null
try { note = fs.readFileSync('.quartz-gui/core-update.json', 'utf-8') } catch {}
fs.appendFileSync(`${W}/npm-calls.log`, `${JSON.stringify({ args, cwd: process.cwd().replace(W, '@W@'), note })}\n`)
let mode = 'ok'
try { mode = fs.readFileSync(`${W}/npm-mode.txt`, 'utf-8').trim() || 'ok' } catch {}
if (args[0] !== 'install') process.exit(0)
if (mode === 'eacces') {
  process.stderr.write("npm error code EACCES\nnpm error syscall mkdir\nnpm error path node_modules/.staging\n")
  process.exit(243)
}
const flag = args.find((a) => a.startsWith('--save-'))
const specs = args.slice(1).filter((a) => !a.startsWith('-'))
if (specs.some((s) => s.startsWith('does-not-exist@')) || (mode === 'fail-peer' && flag === '--save-peer')) {
  process.stderr.write('npm error code E404\nnpm error 404 Not Found\n')
  process.exit(1)
}
const sections = { '--save-prod': 'dependencies', '--save-dev': 'devDependencies', '--save-optional': 'optionalDependencies', '--save-peer': 'peerDependencies' }
const pkg = JSON.parse(fs.readFileSync('package.json', 'utf-8'))
for (const spec of specs) {
  const at = spec.lastIndexOf('@')
  const name = spec.slice(0, at)
  let range = spec.slice(at + 1)
  if (mode === 'resolve') range = range.replace(/(\d+)$/, (n) => String(Number(n) + 1))
  const section = sections[flag] ?? 'dependencies'
  const entries = { ...(pkg[section] ?? {}), [name]: range }
  pkg[section] = Object.fromEntries(Object.keys(entries).sort().map((key) => [key, entries[key]]))
}
if (specs.length > 0) fs.writeFileSync('package.json', `${JSON.stringify(pkg, null, 2)}\n`)
const lock = { name: pkg.name, version: pkg.version, lockfileVersion: 3, generator: 'npm-stub', packages: { '': { dependencies: pkg.dependencies ?? {}, devDependencies: pkg.devDependencies ?? {} } } }
fs.writeFileSync('package-lock.json', `${JSON.stringify(lock, null, 2)}\n`)
process.stdout.write(specs.length > 0 ? `added ${specs.length} packages\n` : 'up to date, audited 1 package\n')
