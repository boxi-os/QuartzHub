#!/usr/bin/env node
// Golden files for FontFaces, GoogleFontRequest and FontService, made by QuartzControl's own
// fontService.ts, styleService.ts and shared/googleFontRequest.ts:
//
// - `pure.json`: parseFontFaces, fontFileIn, googleFontRequest and googleFontsCss2Url on many inputs.
// - `steps/<case>.json`: a project (quartz/styles, quartz/static/fonts, the config), a scripted
//   Google (CSS answers and font files by URL; `net.fetch` replaced), a sequence of calls, and after
//   each the answer, every file it changed (a font file as its size and SHA-1) and the requests it
//   made. Font files in the tree that have to be real fonts come from Fixtures/font-file.
//
//   Runtime/node/bin/node scripts/fonts-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const fixtures = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures')
const out = join(fixtures, 'fonts')

const stubs = {
  ...commonStubs,
  './projectDependencies': 'export function halfUnpackedModule() { return null }',
  electron: `export const net = { fetch: (...args) => globalThis.__fetch(...args) }`,
  './configService': `export async function readConfig() {
    if (globalThis.__config instanceof Error) throw globalThis.__config
    return globalThis.__config
  }`
}
const fonts = await loadQuartzControl(control, 'electron/main/services/fontService.ts', stubs)
const style = await loadQuartzControl(control, 'electron/main/services/styleService.ts', stubs)
const request = await loadQuartzControl(control, 'shared/googleFontRequest.ts', {})

// ── pure ─────────────────────────────────────────────────────────────────────────────────────
const faceTexts = [
  '',
  '@font-face { font-family: "Inter"; src: url("static/fonts/inter.woff2") format("woff2"); font-weight: 400 700; }',
  "@font-face{font-family:'A B';src:local('x'),url( 'static/fonts/a.woff2' ) format('woff2'),url(static/fonts/a.ttf);font-style:italic;unicode-range:U+0000-00FF, U+0131}",
  '@font-face { src: url(static/fonts/x.woff2); }',
  '@font-face {\n  FONT-FAMILY : Upper ;\n  Font-Weight: bold;\n}',
  '@font-face { font-family: "Sass"; src: url("#{$base}/static/fonts/s.woff2"); font-weight: #{$w}; }',
  '@font-face { font-family: Old; src: url(old.eot); src: url(old.eot?#iefix) format("embedded-opentype"), url(static/fonts/old.woff) format("woff"); }',
  '/* @font-face { font-family: Commented; } */ @font-face { font-family: "Two"; } @font-face { font-family: "Three"; font-weight: 300 }',
  '@font-face { font-family: "Broken"; src: url("static/fonts/b.woff2")',
  '@font-face { font-family: "Hash # in it"; src: url(static/fonts/h#x.woff2) }',
  '@font-face { font-family: ""; } @font-face { font-family: \'\' ; }',
  '@font-face { font-family: "Ünïcödé 日本"; src: url("static/fonts/%E6%97%A5.woff2"); }'
]
const urls = [undefined, '', 'static/fonts/a.woff2', '/static/fonts/a.woff2', 'https://x.example/static/fonts/a.woff2?v=1#f', 'static/fonts/a%20b.woff2',
  'static/fonts/%E0%A4%A', 'static/fonts/.hidden.woff2', 'static/fonts/a%5Cb.woff2', 'static/fonts/sub/a.woff2', 'fonts/a.woff2', 'xstatic/fonts/a.woff2',
  'static/fonts/%2E%2E', 'static/fonts/..', 'static/fonts/a.woff2/', 'data:font/woff2;base64,AAA', 'static/fonts/%2Fetc']
const typographies = [
  {}, { header: 'Inter' }, { header: 'Inter', body: 'Source Sans Pro', code: 'IBM Plex Mono' },
  { header: { name: 'Inter', weights: [400, 700, 900] }, body: { name: 'Noto Sans', includeItalic: false }, code: { name: 'Mono', weights: [500] } },
  { body: { name: 'Body', weights: [700, 400], includeItalic: true }, title: 'Title Font' },
  { header: '', body: { name: '' }, code: { weights: [1] }, title: 42 }, { header: '  Spaced  Name ' }, { header: 'Ä & ö/ß+x' },
  { header: { name: 'W', weights: ['400', 500, null] } }
]
const pure = {
  faces: faceTexts.map((text) => ({ text, faces: style.parseFontFaces(text) })),
  fileIn: urls.map((url) => ({ url: url ?? null, file: style.fontFileIn('/D', url) ?? null })),
  css2: typographies.map((typography) => ({ typography, url: request.googleFontsCss2Url(typography),
    requests: ['header', 'body', 'code', 'title'].map((role) => request.googleFontRequest(role, typography[role])) }))
}
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'pure.json'), JSON.stringify(pure, null, 2) + '\n')

// ── a scripted Google ────────────────────────────────────────────────────────────────────────
const G = 'https://fonts.googleapis.com/css2'
const S = (name) => `https://fonts.gstatic.com/s/x/v1/${name}`
const rule = (family, { style = 'normal', weight = 400, file, range, comment } = {}) =>
  `${comment ? `/* ${comment} */\n` : ''}@font-face {\n  font-family: '${family}';\n  font-style: ${style};\n  font-weight: ${weight};\n  font-display: swap;\n  src: url(${S(file)}) format('woff2');\n${range ? `  unicode-range: ${range};\n` : ''}}\n`
const LATIN = 'U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD'
const CYR = 'U+0301, U+0400-045F, U+0490-0491, U+04B0-04B1, U+2116'
const font = (n) => ({ status: 200, bytes: { size: n, fill: n % 251 } })

function urlFor(typography) { return request.googleFontsCss2Url(typography) }

const interPlus = { header: 'Inter', body: 'Source Sans Pro', code: 'IBM Plex Mono' }
const interPlusCss = rule('Inter', { weight: '400 700', file: 'inter-latin.woff2', range: LATIN, comment: 'latin' }) +
  rule('Inter', { weight: '400 700', file: 'inter-cyr.woff2', range: CYR, comment: 'cyrillic' }) +
  rule('Source Sans Pro', { style: 'italic', weight: 400, file: 'ssp-i.woff2', range: LATIN }) +
  rule('Source Sans Pro', { weight: 400, file: 'ssp.woff2', range: LATIN }) +
  rule('IBM Plex Mono', { weight: 400, file: 'plex.0.woff2' })
const google = {
  [urlFor(interPlus)]: { status: 200, text: interPlusCss },
  [S('inter-latin.woff2')]: font(1200), [S('inter-cyr.woff2')]: font(800), [S('ssp-i.woff2')]: font(900), [S('ssp.woff2')]: font(901), [S('plex.0.woff2')]: font(700),
  [urlFor({ header: 'Inter' })]: { status: 200, text: rule('Inter', { weight: '400 700', file: 'inter-latin.woff2', range: LATIN }) },
  [urlFor({ header: 'Nope' })]: { status: 400, text: 'bad family' },
  [urlFor({ header: 'Empty' })]: { status: 200, text: '/* nothing */' },
  [urlFor({ header: 'BadName' })]: { status: 200, text: rule('BadName', { file: 'bad%20name.woff2' }) },
  [urlFor({ header: 'Missing' })]: { status: 200, text: rule('Missing', { file: 'here.woff2' }) + rule('Missing', { weight: 700, file: 'gone.woff2' }) },
  [S('here.woff2')]: font(500), [S('gone.woff2')]: { status: 404, text: 'not found' },
  [urlFor({ header: 'Huge' })]: { status: 200, text: rule('Huge', { file: 'huge.woff2' }) },
  [S('huge.woff2')]: { status: 200, headers: { 'content-length': String(65 * 1024 * 1024) }, bytes: { size: 10, fill: 1 } },
  [urlFor({ header: 'Many' })]: { status: 200, text: Array.from({ length: 801 }, (_, i) => rule('Many', { weight: 100 + i, file: `m${i}.woff2` })).join('') },
  [urlFor({ header: 'Down' })]: { fail: true },
  [urlFor({ header: 'Inter', body: 'Mixed' })]: { status: 200, text: rule('Inter', { weight: '400 700', file: 'inter-latin.woff2', range: LATIN }) },
  [urlFor({ header: 'Unreachable file' })]: { status: 200, text: rule('Unreachable file', { file: 'nofile.woff2' }) },
  [S('nofile.woff2')]: { fail: true },
  [urlFor({ header: 'Noto Sans', body: 'Inter' })]: { status: 200, text:
    rule('Noto Sans', { weight: '100 900', file: 'noto-cyr.woff2', range: CYR, comment: 'cyrillic' }) +
    rule('Noto Sans', { weight: '100 900', file: 'noto-latin.woff2', range: LATIN, comment: 'latin' }) +
    rule('Inter', { weight: '400 700', file: 'inter-latin.woff2', range: LATIN }) },
  [S('noto-cyr.woff2')]: font(1500), [S('noto-latin.woff2')]: font(1600),
  [urlFor({ header: 'Inter', body: 'Mine' })]: { status: 200, text: rule('Inter', { weight: '400 700', file: 'inter-latin.woff2', range: LATIN }) },
  [urlFor({ body: 'Noto Sans' })]: { status: 200, text: rule('Noto Sans', { weight: '100 900', file: 'noto-latin.woff2', range: LATIN }) },
  [urlFor({ header: 'Inter', body: 'Noto Sans' })]: { status: 200, text: rule('Inter', { weight: '400 700', file: 'inter-latin.woff2', range: LATIN }) +
    rule('Noto Sans', { weight: '100 900', file: 'noto-latin.woff2', range: LATIN }) }
}

// The Swift test answers from the same script.
writeFileSync(join(out, 'google.json'), JSON.stringify(google, null, 2) + '\n')

let requests = []
globalThis.__fetch = async (input, init = {}) => {
  const url = String(input)
  requests.push({ url, userAgent: init.headers?.['User-Agent'] ?? null })
  const answer = google[url]
  if (!answer || answer.fail) throw new TypeError('fetch failed')
  const bytes = answer.bytes ? Buffer.alloc(answer.bytes.size, answer.bytes.fill) : Buffer.from(answer.text ?? '')
  const headers = new Map(Object.entries(answer.headers ?? { 'content-length': String(bytes.length) }))
  return {
    ok: answer.status >= 200 && answer.status < 300, status: answer.status,
    headers: { get: (name) => headers.get(name.toLowerCase()) ?? null },
    text: async () => bytes.toString('utf8'), arrayBuffer: async () => bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.length)
  }
}

// ── cases ────────────────────────────────────────────────────────────────────────────────────
const M = (id) => [`/* --- QuartzControl:managed:${id}:start --- */`, `/* --- QuartzControl:managed:${id}:end --- */`]
const block = (id, body) => `${M(id)[0]}\n${body}\n${M(id)[1]}`
const moved = (blocks, extra = '') => ({
  'quartz/styles/custom.scss': `@use "./variables.scss" as *;\n\n@use "./quartzcontrol";\n${extra}`,
  'quartz/styles/_quartzcontrol.scss': `// head\n\n${blocks.join('\n\n')}\n`
})
const template = ['Noto Sans'].map((family) => `@font-face {\n  font-family: "${family}";\n  src: url("static/fonts/noto-sans-latin-400-700.woff2") format("woff2");\n  font-weight: 100 900;\n  font-display: swap;\n  unicode-range: ${LATIN};\n}`).join('\n\n')
const ownInter = '@font-face {\n  font-family: "Inter";\n  src: url("static/fonts/own-inter.woff2") format("woff2");\n  font-weight: 100 900;\n}'
const realFont = { fixture: 'font-file/files/noto-sans-latin-400-700.woff2' }
const step = (call, ...args) => ({ call, args })
const config = (theme) => ({ configuration: {}, theme, plugins: [] })

const cases = {
  'import fonts': { tree: { 'quartz/styles/custom.scss': '.x {}\n', 'in/Noto Sans.woff2': realFont, 'in/plain.TTF': 'not a font', 'in/italic.woff2': { fixture: 'font-file/files/noto-sans-latin-italic-400-700.woff2' } }, steps: [
    step('importFontFile', '@IN@/Noto Sans.woff2', 'Noto Sans'), step('importFontFile', '@IN@/Noto Sans.woff2', 'Noto Sans'),
    step('importFontFile', '@IN@/plain.TTF', 'Plain'), step('importFontFile', '@IN@/italic.woff2', 'Noto Sans'),
    step('unusedImportedFonts', []), step('unusedImportedFonts', ['Plain']), step('removeImportedFont', 'noto sans'), step('removeImportedFont', 'Nobody')
  ] },
  'import into a moved project': { tree: { ...moved([block('fonts', ownInter)]), 'quartz/static/fonts/own-inter.woff2': 'x', 'in/x.otf': 'otf bytes' }, steps: [
    step('importFontFile', '@IN@/x.otf', 'Other'), step('unusedImportedFonts', ['Inter'])
  ] },
  'unused: who names what': { config: config({ typography: { header: 'Alpha', body: { name: 'Beta' }, code: 7 } }), tree: {
    ...moved([block('fonts', ['Alpha', 'Beta', 'Gamma', 'Delta', 'Epsilon', 'Zeta', 'Eta', 'Theta', 'Iota'].map((f, i) => `@font-face { font-family: "${f}"; src: url("static/fonts/${f.toLowerCase()}.woff2"), url(static/fonts/shared.woff2); }`).join('\n'))]),
    'quartz/styles/custom/a.scss': 'body { font-family: "Gamma", sans-serif; }\n/* Delta in a comment */\n// Epsilon in a line comment\n.q::after { content: "Zeta"; }\n',
    'quartz/styles/deep/x/y.scss': '.y { font-family: Eta; }',
    'quartz/components/styles/c.scss': '.c { font: 12px Iotaish; }',
    'quartz/static/giscus.css': '.g { font-family: Theta-Bold; }',
    'quartz/static/fonts/alpha.woff2': 'a', 'quartz/static/fonts/iota.woff2': 'i', 'quartz/static/fonts/shared.woff2': 's'
  }, steps: [step('unusedImportedFonts', []), step('removeImportedFont', 'Iota'), step('removeImportedFont', 'Theta'), step('unusedImportedFonts', [])] },
  'replaced rules': { tree: {
    ...moved([block('fonts', '@font-face { font-family: "Old"; src: url("static/fonts/old.woff2"); }')]),
    'quartz/styles/custom/keep.scss': '@font-face { font-family: "Keep"; src: url("#{$dir}/kept.woff2"); }',
    'quartz/static/fonts/old.woff2': 'o', 'quartz/static/fonts/kept.woff2': 'k', 'quartz/static/fonts/both.woff2': 'b'
  }, steps: [
    step('fontFilesReplacedRulesWouldRemove', '@font-face { font-family: X; src: url(static/fonts/old.woff2), url(static/fonts/kept.woff2), url(static/fonts/both.woff2), url(static/fonts/absent.woff2); }', '@font-face { src: url(static/fonts/both.woff2); }'),
    step('deleteFontFilesOfReplacedRules', '@font-face { font-family: X; src: url(static/fonts/both.woff2), url(static/fonts/kept.woff2); }')
  ] },
  'google: first fetch, unchanged, changed': { tree: { 'quartz/styles/custom.scss': '.x {}\n' }, steps: [
    step('fetchGoogleFonts', interPlus), step('fetchGoogleFonts', interPlus), step('fetchGoogleFonts', { header: 'Inter' }),
    step('dropGoogleFonts'), step('dropGoogleFonts')
  ] },
  'google: a torso is fetched again': { tree: { ...moved([block('google-fonts', `/* ${urlFor({ header: 'Inter' })} */\n` + rule('Inter', { weight: '400 700', file: 'inter-latin.woff2', range: LATIN }).replace(S('inter-latin.woff2'), 'static/fonts/inter-latin.woff2'))]),
    'quartz/static/fonts/inter-latin.woff2': '' }, steps: [step('fetchGoogleFonts', { header: 'Inter' }), step('fetchGoogleFonts', { header: 'Inter' })] },
  'google: own rules cover latin': { tree: { ...moved([block('fonts', template)]), 'quartz/static/fonts/noto-sans-latin-400-700.woff2': realFont }, steps: [
    step('fetchGoogleFonts', { header: 'Noto Sans', body: 'Inter' }), step('fetchGoogleFonts', { header: 'Noto Sans', body: 'Inter' }),
    // The own rules change, the request does not: the fingerprint in the head says it is a new answer.
    step('write', 'quartz/styles/custom.scss', `@use "./quartzcontrol";\n@font-face { font-family: "Noto Sans"; src: url(static/fonts/noto-greek.woff2); font-weight: 100 900; unicode-range: U+0370-03FF; }\n`),
    step('fetchGoogleFonts', { header: 'Noto Sans', body: 'Inter' })
  ] },
  'google: own families are delivered and kept': { tree: {
    ...moved([block('fonts', '@font-face { font-family: "Mine"; src: url(static/fonts/mine.woff2); unicode-range: U+0041-005A; }')]),
    'quartz/static/fonts/mine.woff2': 'm'
  }, steps: [
    step('fetchGoogleFonts', { header: 'Inter', body: 'Mine' }),
    step('fetchGoogleFonts', { header: 'Inter', body: 'Noto Sans' }),
    step('write', 'quartz/styles/custom.scss', `@use "./quartzcontrol";\n${ownInter}\n`),
    step('fetchGoogleFonts', { header: 'Inter', body: 'Noto Sans' })
  ] },
  'google: own rule without range': { tree: { ...moved([block('fonts', ownInter)]), 'quartz/static/fonts/own-inter.woff2': 'x' }, steps: [
    step('fetchGoogleFonts', { header: 'Inter' }), step('fetchGoogleFonts', { header: 'Inter' }), step('fetchGoogleFonts', { header: 'Inter', body: 'Mixed' })
  ] },
  'google: failures': { tree: { 'quartz/styles/custom.scss': '.x {}\n' }, steps: [
    step('fetchGoogleFonts', {}), step('fetchGoogleFonts', { header: 'Nope' }), step('fetchGoogleFonts', { header: 'Empty' }),
    step('fetchGoogleFonts', { header: 'BadName' }), step('fetchGoogleFonts', { header: 'Missing' }), step('fetchGoogleFonts', { header: 'Huge' }),
    step('fetchGoogleFonts', { header: 'Many' }), step('fetchGoogleFonts', { header: 'Down' }), step('fetchGoogleFonts', { header: 'Unreachable file' })
  ] },
  'refresh at the build door': { config: config({ fontOrigin: 'local', typography: interPlus }), tree: { 'quartz/styles/custom.scss': '.x {}\n' }, steps: [
    step('refreshGoogleFonts'), step('fetchGoogleFonts', { header: 'Inter' }), step('refreshGoogleFonts'), step('refreshGoogleFonts'),
    step('setConfig', config({ fontOrigin: 'local', typography: { header: 'Down' } })), step('refreshGoogleFonts'),
    step('setConfig', config({ fontOrigin: 'cdn', typography: interPlus })), step('refreshGoogleFonts'),
    step('setConfig', config({ fontOrigin: 'cdn', typography: { header: 'Inter' } })), step('refreshGoogleFonts'),
    step('setConfig', new Error('config broke')), step('refreshGoogleFonts'),
    step('setConfig', config({ fontOrigin: 'local', typography: { header: 'Noto Sans', body: 'Inter' } })), step('refreshGoogleFonts')
  ] },
  'refresh: every family own': { config: config({ fontOrigin: 'local', typography: { header: 'Inter' } }), tree: {
    ...moved([block('fonts', ownInter), block('google-fonts', `/* ${urlFor({ header: 'Inter' })} */\n@font-face { font-family: 'Inter'; src: url(static/fonts/g-inter.woff2); }`)]),
    'quartz/static/fonts/own-inter.woff2': 'x', 'quartz/static/fonts/g-inter.woff2': 'g'
  }, steps: [step('refreshGoogleFonts'), step('refreshGoogleFonts')] }
}

const work = mkdtempSync(join(tmpdir(), 'qh-fonts-golden-'))
const describe = (full) => {
  const data = readFileSync(full)
  if (/\.(woff2?|ttf|otf|TTF)$/.test(full) && !/^[\x09\x0a\x20-\x7e]*$/.test(data.toString('latin1'))) {
    return { size: data.length, sha1: createHash('sha1').update(data).digest('hex') }
  }
  return data.toString('utf8')
}
const filesOf = (dir) => {
  const result = {}
  const walk = (d) => {
    if (!existsSync(d)) return
    for (const name of readdirSync(d).sort()) {
      const full = join(d, name)
      if (statSync(full).isDirectory()) walk(full)
      else result[relative(dir, full)] = describe(full)
    }
  }
  walk(join(dir, 'quartz'))
  return result
}
mkdirSync(join(out, 'steps'), { recursive: true })
for (const file of readdirSync(join(out, 'steps'))) rmSync(join(out, 'steps', file))
for (const [name, c] of Object.entries(cases)) {
  const project = join(work, name.replace(/[^\w-]+/g, '-'))
  for (const [path, spec] of Object.entries(c.tree)) {
    mkdirSync(dirname(join(project, path)), { recursive: true })
    writeFileSync(join(project, path), typeof spec === 'string' ? spec : readFileSync(join(fixtures, spec.fixture)))
  }
  mkdirSync(join(project, 'quartz', 'styles'), { recursive: true })
  globalThis.__config = c.config ?? config({})
  const results = []
  let before = filesOf(project)
  for (const s of c.steps) {
    requests = []
    let result = null
    if (s.call === 'setConfig') {
      globalThis.__config = s.args[0]
    } else if (s.call === 'write') {
      mkdirSync(dirname(join(project, s.args[0])), { recursive: true })
      writeFileSync(join(project, s.args[0]), s.args[1])
    } else {
      const args = s.args.map((a) => (typeof a === 'string' ? a.replace('@IN@', join(project, 'in')) : a))
      try { result = (await fonts[s.call](project, ...args)) ?? null } catch (error) { result = { threw: error instanceof Error ? error.message : String(error) } }
    }
    const after = filesOf(project)
    const changed = {}
    for (const path of new Set([...Object.keys(before), ...Object.keys(after)])) {
      if (JSON.stringify(before[path]) !== JSON.stringify(after[path])) changed[path] = after[path] ?? null
    }
    results.push({ ...s, args: s.args.map((a) => (a instanceof Error ? { error: a.message } : a)), result, changed, requests })
    before = after
  }
  writeFileSync(join(out, 'steps', `${name.replace(/[^\w-]+/g, '-')}.json`), JSON.stringify({ name, tree: c.tree, config: c.config ?? config({}), steps: results }, null, 2) + '\n')
}
rmSync(work, { recursive: true, force: true })
console.log(`fonts: ${pure.faces.length} face texts, ${pure.fileIn.length} urls, ${pure.css2.length} typographies, ${Object.keys(cases).length} step cases`)
