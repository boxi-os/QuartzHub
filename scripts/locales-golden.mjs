#!/usr/bin/env node
// Golden file for LocaleFiles, made by QuartzControl's own localizationService.ts: a project in a
// temporary folder (a git repository) with gui-test's de-DE and en-US (copied, read only there)
// and locale files of every shape the walk has to survive, and a list of steps (list, read, save,
// the baseline, git's baseline, merge=ours). Each step's answer, the files it changed and git's
// `merge.ours.driver` afterwards are recorded.
//
//   Runtime/node/bin/node scripts/locales-golden.mjs [../QuartzControl] [~/Documents/QuartzProjekte]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { execFileSync } from 'node:child_process'
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { homedir, tmpdir } from 'node:os'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const projects = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'locales')

// git as QuartzControl's runCommand runs it: output is stdout and stderr together.
const runCommand = `
const { spawnSync } = require('node:child_process')
export async function runCommand(command, args, cwd) {
  const r = spawnSync(command, args, { cwd, encoding: 'utf-8' })
  return { success: r.status === 0, output: (r.stdout ?? '') + (r.stderr ?? ''), stdout: r.stdout ?? '' }
}`
const service = await loadQuartzControl(control, 'electron/main/services/localizationService.ts', { ...commonStubs, './runCommand': runCommand })

// ── the files ────────────────────────────────────────────────────────────────────────────────
const shapes = {
  // Parentheses, satisfies and as around the literal; every kind of key and value.
  'xx': `import { Translation } from "./definition"

// A comment that must stay.
export default (({
  plain: "eins",
  'quoted-key': 'zwei',
  "with space": "drei \\u00e4\\n",
  nested: { deeper: { leaf: \`ohne Ersatz\` }, sibling: "s" },
  template: ({ n }: { n: number }) => \`\${n} Seiten\`,
  withSubstitution: \`a \${"b"}\`,
  call: String(1),
  number: 42,
  [computed]: "nie",
  ...spread,
  shorthand,
  method() { return "nie" },
  get getter() { return "nie" },
  42: "numerischer Schlüssel",
  empty: "",
}) as const) satisfies Translation
`,
  // No default export at all.
  'yy': `export const translation = { a: "b" }\n`,
  // export =, which is no default export.
  'zz': `export = { a: "b" }\n`,
  // A default export that is no object.
  'ab-CD': `export default "kein Objekt"\n`,
  // Two default exports: the first counts.
  'Ab': `export default { first: "eins" }\nexport default { second: "zwei" }\n`,
  // A file that does not parse cleanly: the walk takes what the parser recovered.
  'qq-1234': `export default { kaputt: "a", , weiter: ("b" }\n`
}

function tree(root) {
  const files = {}
  const walk = (dir) => {
    for (const name of readdirSync(dir).sort()) {
      if (name === '.git') continue
      const full = join(dir, name)
      if (statSync(full).isDirectory()) walk(full)
      else files[relative(root, full)] = readFileSync(full, 'utf-8')
    }
  }
  walk(root)
  return files
}
const driver = (project) => {
  try { return execFileSync('git', ['config', '--get', 'merge.ours.driver'], { cwd: project, encoding: 'utf-8', stdio: ['ignore', 'pipe', 'ignore'] }).trim() } catch { return null }
}

const work = mkdtempSync(join(tmpdir(), 'qh-locales-golden-'))
const steps = []
let start
try {
  const project = join(work, 'project')
  const plain = join(work, 'plain')
  const source = join(projects, 'gui-test', 'quartz', 'i18n', 'locales')
  const L = 'quartz/i18n/locales/'
  // What is committed, what is changed after the commit, and the second project (no git).
  const committed = {}
  for (const name of ['de-DE.ts', 'en-US.ts', 'definition.ts']) committed[L + name] = readFileSync(join(source, name), 'utf-8')
  for (const [code, text] of Object.entries(shapes)) committed[`${L}${code}.ts`] = text
  // Sorted apart by ICU and by bytes: "Ef" comes before "ab-CD" in bytes, after "de-DE" in ICU.
  committed[`${L}Ef.ts`] = 'export default { e: "f" }\n'
  // Not locales: a name that is no code, another extension.
  committed[`${L}a.ts`] = 'export default { a: "b" }\n'
  committed[`${L}README.md`] = 'nicht\n'
  const edited = {
    // Edited by hand after the commit: git's HEAD is the baseline.
    [`${L}en-US.ts`]: committed[`${L}en-US.ts`].replace('title: "Untitled"', 'title: "Nameless"'),
    // New and untracked: git has no HEAD version.
    [`${L}tlh-Latn.ts`]: 'export default { title: "neu" }\n'
  }
  const plainFiles = { [`${L}de-DE.ts`]: 'export default { title: "x" }\n' }
  start = { committed, edited, plain: plainFiles }
  const put = (root, files) => {
    for (const [path, text] of Object.entries(files)) {
      mkdirSync(dirname(join(root, path)), { recursive: true })
      writeFileSync(join(root, path), text)
    }
  }
  put(project, committed)
  const git = (...args) => execFileSync('git', args, { cwd: project, stdio: ['ignore', 'pipe', 'pipe'] })
  git('init', '-q')
  git('config', 'user.email', 'golden@example.invalid')
  git('config', 'user.name', 'golden')
  git('add', '-A')
  git('commit', '-q', '-m', 'start')
  put(project, edited)
  put(plain, plainFiles)
  // A folder named like a locale file: listed, and reading it fails.
  mkdirSync(join(plain, L, 'xy.ts'))

  const where = { project, plain }
  let before = { project: tree(project), plain: tree(plain) }
  const run = async (call, args = [], on = 'project') => {
    const dir = where[on]
    let result
    try {
      switch (call) {
        case 'writeFile': writeFileSync(join(dir, args[0]), args[1]); result = null; break
        case 'git': result = execFileSync('git', args, { cwd: dir, encoding: 'utf-8' }); result = null; break
        default: result = (await service[call](dir, ...args)) ?? null
      }
    } catch (error) {
      result = { threw: error.message }
    }
    const after = { project: tree(project), plain: tree(plain) }
    const changed = {}
    for (const side of ['project', 'plain']) {
      for (const path of new Set([...Object.keys(before[side]), ...Object.keys(after[side])])) {
        if (before[side][path] !== after[side][path]) changed[`${side}/${path}`] = after[side][path] ?? null
      }
    }
    before = after
    steps.push({ on, call, args, result, changed, driver: driver(dir) })
  }

  await run('listLocales')
  for (const code of ['de-DE', 'xx', 'yy', 'zz', 'ab-CD', 'Ab', 'qq-1234', 'fr-FR']) await run('getLocaleEntries', [code])
  await run('getGitAttributesStatus')
  await run('getTranslationCustomizations')
  await run('saveLocaleEntry', ['de-DE', ['propertyDefaults', 'title'], 'string', 'Ohne „Titel“ – "zitiert" \\ ${x}\nzweite Zeile'])
  await run('saveLocaleEntry', ['de-DE', ['components', 'recentNotes', 'seeRemainingMore'], 'template', '({ remaining }) => `noch ${remaining}`'])
  await run('saveLocaleEntry', ['de-DE', ['components', 'recentNotes', 'seeRemainingMore'], 'template', '({ remaining }) => `kaputt'])
  await run('saveLocaleEntry', ['de-DE', ['components', 'recentNotes', 'seeRemainingMore'], 'template', '"Text statt Funktion"'])
  await run('saveLocaleEntry', ['de-DE', ['components', 'fehlt'], 'string', 'x'])
  await run('saveLocaleEntry', ['de-DE', ['propertyDefaults', 'title', 'zu-tief'], 'string', 'x'])
  await run('saveLocaleEntry', ['de-DE', [], 'string', 'x'])
  await run('saveLocaleEntry', ['fr-FR', ['a'], 'string', 'x'])
  await run('saveLocaleEntry', ['yy', ['a'], 'string', 'x'])
  await run('saveLocaleEntry', ['xx', ['nested'], 'string', 'ganzes Objekt'])
  await run('saveLocaleEntry', ['xx', ['42'], 'string', 'neu'])
  await run('saveLocaleEntry', ['xx', ['quoted-key'], 'string', 'neu'])
  await run('saveLocaleEntry', ['xx', ['computed'], 'string', 'neu'])
  await run('saveLocaleEntry', ['qq-1234', ['kaputt'], 'string', 'neu'])
  await run('getGitAttributesStatus')
  await run('getTranslationCustomizations')
  // Back to the original wording: no longer a change.
  await run('saveLocaleEntry', ['de-DE', ['propertyDefaults', 'title'], 'string', 'Unbenannt'])
  await run('getTranslationCustomizations')
  for (const code of ['de-DE', 'xx']) await run('getLocaleEntries', [code])
  // The two halves of merge=ours, one at a time.
  await run('git', ['config', '--unset', 'merge.ours.driver'])
  await run('getGitAttributesStatus')
  await run('ensureGitAttributes')
  // A driver that is set but empty is no driver.
  await run('git', ['config', 'merge.ours.driver', ''])
  await run('getGitAttributesStatus')
  await run('ensureGitAttributes')
  await run('writeFile', ['.gitattributes', '*.png binary'])
  await run('getGitAttributesStatus')
  await run('ensureGitAttributes')
  await run('ensureGitAttributes')
  await run('writeFile', ['.gitattributes', ''])
  await run('ensureGitAttributes')
  // Ends with a newline already: the line follows without a blank one.
  await run('writeFile', ['.gitattributes', '*.png binary\n'])
  await run('ensureGitAttributes')
  // No git repository: the line is written, the driver cannot be.
  await run('getGitAttributesStatus', [], 'plain')
  await run('ensureGitAttributes', [], 'plain')
  await run('getGitAttributesStatus', [], 'plain')
  await run('saveLocaleEntry', ['de-DE', ['title'], 'string', 'y'], 'plain')
  await run('getTranslationCustomizations', [], 'plain')
  await run('listLocales', [], 'plain')
} finally {
  rmSync(work, { recursive: true, force: true })
}
rmSync(out, { recursive: true, force: true })
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'start.json'), JSON.stringify(start, null, 1) + '\n')
writeFileSync(join(out, 'steps.json'), JSON.stringify(steps, null, 1) + '\n')
console.log(`${steps.length} steps → ${out}`)
