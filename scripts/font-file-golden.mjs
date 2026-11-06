#!/usr/bin/env node
// Golden file for FontFile, made by QuartzControl's own fontFile.ts: `readFontFace` on made-up
// fonts in all three containers (sfnt, WOFF with zlib tables, WOFF2 with a brotli stream), with the
// edges it has to survive (truncated files, lying lengths, decompression bombs, a wght axis, the two
// italic bits), and on four real WOFF2 files of gui-test (Noto and Google's, SIL OFL; copied into
// the fixtures, read only).
//
//   Runtime/node/bin/node scripts/font-file-golden.mjs [../QuartzControl] [~/Documents/QuartzProjekte]
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { copyFileSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { brotliCompressSync, deflateRawSync, deflateSync } from 'node:zlib'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const projects = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'font-file')
const { readFontFace } = await loadQuartzControl(control, 'electron/main/services/fontFile.ts', {})

// ── tables ───────────────────────────────────────────────────────────────────────────────────
function os2({ weight = 400, italic = false, length = 96 } = {}) {
  const b = Buffer.alloc(length)
  if (length >= 6) b.writeUInt16BE(weight, 4)
  if (length >= 64) b.writeUInt16BE(italic ? 0x01 : 0x40, 62)
  return b
}
function head({ italic = false, length = 54 } = {}) {
  const b = Buffer.alloc(length)
  if (length >= 46) b.writeUInt16BE(italic ? 0x02 : 0, 44)
  return b
}
function fvar(axes, { axisSize = 20, truncate } = {}) {
  const b = Buffer.alloc(16 + axes.length * axisSize)
  b.writeUInt16BE(16, 4)
  b.writeUInt16BE(axes.length, 8)
  b.writeUInt16BE(axisSize, 10)
  axes.forEach(([tag, min, def, max], i) => {
    const at = 16 + i * axisSize
    b.write(tag, at, 'latin1')
    b.writeInt32BE(Math.round(min * 65536), at + 4)
    b.writeInt32BE(Math.round(def * 65536), at + 8)
    b.writeInt32BE(Math.round(max * 65536), at + 12)
  })
  return truncate ? b.subarray(0, truncate) : b
}
const filler = (n) => Buffer.alloc(n, 7)

// ── containers ───────────────────────────────────────────────────────────────────────────────
function sfnt(tables, { lie } = {}) {
  const entries = Object.entries(tables)
  const headerSize = 12 + entries.length * 16
  const dir = Buffer.alloc(headerSize)
  dir.writeUInt32BE(0x00010000, 0)
  dir.writeUInt16BE(entries.length, 4)
  let offset = headerSize
  const bodies = []
  entries.forEach(([tag, data], i) => {
    const at = 12 + i * 16
    dir.write(tag.padEnd(4), at, 'latin1')
    dir.writeUInt32BE(offset, at + 8)
    dir.writeUInt32BE(lie?.[tag] ?? data.length, at + 12)
    bodies.push(data)
    offset += data.length
  })
  return Buffer.concat([dir, ...bodies])
}
function woff(tables, { compress = true, lieOrig } = {}) {
  const entries = Object.entries(tables)
  const headerSize = 44 + entries.length * 20
  const dir = Buffer.alloc(headerSize)
  dir.write('wOFF', 0, 'latin1')
  dir.writeUInt16BE(entries.length, 12)
  let offset = headerSize
  const bodies = []
  entries.forEach(([tag, data], i) => {
    const at = 44 + i * 20
    const packed = compress === true || compress?.[tag] ? deflateSync(data) : data
    dir.write(tag.padEnd(4), at, 'latin1')
    dir.writeUInt32BE(offset, at + 4)
    dir.writeUInt32BE(packed.length, at + 8)
    dir.writeUInt32BE(lieOrig?.[tag] ?? data.length, at + 12)
    bodies.push(packed)
    offset += packed.length
  })
  return Buffer.concat([dir, ...bodies])
}
const KNOWN = ['cmap', 'head', 'hhea', 'hmtx', 'maxp', 'name', 'OS/2', 'post', 'cvt ', 'fpgm', 'glyf', 'loca']
function base128(n) {
  const bytes = []
  do { bytes.unshift(n & 0x7f); n = Math.floor(n / 128) } while (n > 0)
  return Buffer.from(bytes.map((b, i) => (i < bytes.length - 1 ? b | 0x80 : b)))
}
function woff2(tables, { transformed = {}, stream, declared } = {}) {
  const entries = Object.entries(tables)
  const parts = []
  for (const [tag, data] of entries) {
    const known = KNOWN.indexOf(tag)
    const t = transformed[tag]
    // glyf/loca: version 0 is the transform, 3 is null; others: 0 is untransformed.
    const version = tag === 'glyf' || tag === 'loca' ? (t ? 0 : 3) : (t ? 1 : 0)
    const flags = (version << 6) | (known === -1 ? 0x3f : known)
    parts.push(Buffer.from([flags]))
    if (known === -1) parts.push(Buffer.from(tag.padEnd(4), 'latin1'))
    parts.push(base128(declared?.[tag] ?? data.length))
    if (t) parts.push(base128(declared?.[tag] ?? data.length))
  }
  const header = Buffer.alloc(48)
  header.write('wOF2', 0, 'latin1')
  header.writeUInt16BE(entries.length, 12)
  const body = stream ?? brotliCompressSync(Buffer.concat(entries.map(([, d]) => d)))
  return Buffer.concat([header, ...parts, body])
}

// ── cases ────────────────────────────────────────────────────────────────────────────────────
const plain = { 'OS/2': os2({ weight: 300 }), head: head() }
const cases = {
  'sfnt static 300': sfnt(plain),
  'sfnt italic by OS/2': sfnt({ 'OS/2': os2({ weight: 400, italic: true }), head: head() }),
  'sfnt italic by head': sfnt({ 'OS/2': os2({ weight: 700 }), head: head({ italic: true }) }),
  'sfnt variable 100-900': sfnt({ 'OS/2': os2({ weight: 400 }), head: head(), fvar: fvar([['wdth', 75, 100, 100], ['wght', 100, 400, 900]]) }),
  'sfnt variable fractional': sfnt({ 'OS/2': os2(), fvar: fvar([['wght', 399.999, 400, 700.4]]) }),
  'sfnt variable one value': sfnt({ 'OS/2': os2(), fvar: fvar([['wght', 500, 500, 500]]) }),
  'sfnt variable min 0': sfnt({ 'OS/2': os2({ weight: 450 }), fvar: fvar([['wght', 0, 400, 900]]) }),
  'sfnt variable max below min': sfnt({ 'OS/2': os2({ weight: 450 }), fvar: fvar([['wght', 700, 400, 300]]) }),
  'sfnt fvar truncated': sfnt({ 'OS/2': os2({ weight: 600 }), fvar: fvar([['wght', 100, 400, 900]], { truncate: 30 }) }),
  'sfnt fvar short': sfnt({ 'OS/2': os2({ weight: 600 }), fvar: Buffer.alloc(10) }),
  'sfnt fvar wide axes': sfnt({ 'OS/2': os2(), fvar: fvar([['ital', 0, 0, 1], ['wght', 200, 400, 800]], { axisSize: 24 }) }),
  'sfnt weight 0': sfnt({ 'OS/2': os2({ weight: 0 }) }),
  'sfnt weight 1001': sfnt({ 'OS/2': os2({ weight: 1001 }) }),
  'sfnt short OS/2': sfnt({ 'OS/2': os2({ length: 5 }) }),
  'sfnt OS/2 without fsSelection': sfnt({ 'OS/2': os2({ weight: 500, length: 20 }), head: head({ italic: true }) }),
  'sfnt short head': sfnt({ 'OS/2': os2(), head: head({ length: 40 }) }),
  'sfnt no OS/2': sfnt({ head: head({ italic: true }) }),
  'sfnt table past the end': sfnt(plain, { lie: { 'OS/2': 100000 } }),
  'sfnt only a header': Buffer.from([0, 1, 0, 0, 0, 2]),
  'empty': Buffer.alloc(0),
  'three bytes': Buffer.from([1, 2, 3]),
  'woff zlib': woff({ 'OS/2': os2({ weight: 800, italic: true }), head: head(), fvar: fvar([['wght', 300, 400, 600]]) }),
  'woff stored': woff(plain, { compress: false }),
  'woff mixed': woff({ 'OS/2': os2({ weight: 200 }), head: head({ italic: true }), glyf: filler(3000) }, { compress: { glyf: true, head: true } }),
  'woff corrupt zlib': (() => { const b = woff(plain); b[44 + 40 + 2] ^= 0xff; return b })(),
  'woff bad checksum': (() => { const b = woff({ 'OS/2': os2({ weight: 900 }) }); b[b.length - 1] ^= 0x55; return b })(),
  'woff bomb': woff({ 'OS/2': os2(), glyf: Buffer.alloc(80 * 1024 * 1024) }),
  'woff orig smaller than inflated': woff({ 'OS/2': os2({ weight: 350 }), glyf: filler(5000) }, { lieOrig: { glyf: 100 } }),
  'woff2 plain': woff2(plain),
  'woff2 unknown tags and fvar': woff2({ glyf: filler(500), loca: filler(40), fvar: fvar([['wght', 250, 400, 750]]), 'OS/2': os2(), head: head({ italic: true }) }),
  'woff2 transformed glyf before OS/2': woff2({ glyf: filler(700), 'OS/2': os2({ weight: 650 }) }, { transformed: { glyf: true } }),
  'woff2 transformed hmtx': woff2({ hmtx: filler(64), 'OS/2': os2({ weight: 333 }) }, { transformed: { hmtx: true } }),
  'woff2 bomb': woff2({ 'OS/2': os2() }, { stream: brotliCompressSync(Buffer.alloc(80 * 1024 * 1024)) }),
  'woff2 bomb declared large': woff2({ glyf: Buffer.alloc(0), 'OS/2': os2() }, { stream: brotliCompressSync(Buffer.alloc(80 * 1024 * 1024)), declared: { glyf: 200 * 1024 * 1024 } }),
  'woff2 stream short': woff2(plain, { declared: { 'OS/2': 5000 } }),
  'woff2 not brotli': woff2(plain, { stream: Buffer.from('not a brotli stream at all') }),
  'woff2 truncated directory': woff2(plain).subarray(0, 50),
  'woff2 long base128': Buffer.concat([woff2(plain).subarray(0, 48), Buffer.from([0x06, 0x81, 0x81, 0x81, 0x81, 0x81, 0x01])]),
  'woff2 trailing bytes': Buffer.concat([woff2(plain), Buffer.from('trailing metadata')]),
  // The counter-checks that first went uncaught each got a case: a raw deflate stream behind a zlib
  // header that is not one, a wght axis at exactly .5, a stream cut after the table that matters,
  // and a base128 padded past its five bytes.
  'woff bad zlib header': (() => { const b = woff({ 'OS/2': os2({ weight: 550 }) }); b[44 + 20] = 0x79; return b })(),
  'woff raw deflate': (() => {
    const t = os2({ weight: 560 })
    const packed = deflateRawSync(t)
    const dir = Buffer.alloc(64); dir.write('wOFF', 0, 'latin1'); dir.writeUInt16BE(1, 12)
    dir.write('OS/2', 44, 'latin1'); dir.writeUInt32BE(64, 48); dir.writeUInt32BE(packed.length, 52); dir.writeUInt32BE(t.length, 56)
    return Buffer.concat([dir, packed])
  })(),
  'sfnt variable half': sfnt({ 'OS/2': os2(), fvar: fvar([['wght', 100.5, 400, 700.5]]) }),
  'woff2 stream cut': (() => {
    // Bytes that do not compress, from a fixed seed so the fixture is the same on every run.
    let seed = 12345
    const random = Buffer.from(Array.from({ length: 20000 }, () => (seed = (seed * 1103515245 + 12345) % 2147483648) >> 16 & 0xff))
    const full = brotliCompressSync(Buffer.concat([os2({ weight: 610 }), random]))
    return woff2({ 'OS/2': os2({ weight: 610 }), glyf: random }, { stream: full.subarray(0, full.length - 40) })
  })(),
  'woff2 base128 padded past five bytes': Buffer.concat([woff2(plain).subarray(0, 12), Buffer.from([0, 1]), woff2(plain).subarray(14, 48),
    Buffer.from([0x06, 0x80, 0x80, 0x80, 0x80, 0x80, 0x60]), brotliCompressSync(os2({ weight: 620 }))])
}

rmSync(out, { recursive: true, force: true })
mkdirSync(join(out, 'files'), { recursive: true })
const results = []
for (const [name, data] of Object.entries(cases)) {
  const file = name.replace(/[^\w]+/g, '-') + '.bin'
  // The bombs are recorded as the recipe, not as 80 MiB: their files are a few hundred bytes.
  writeFileSync(join(out, 'files', file), data)
  results.push({ name, file, face: readFontFace(data) })
}
const realDir = join(projects, 'gui-test', 'quartz', 'static', 'fonts')
const real = ['noto-sans-latin-400-700.woff2', 'noto-sans-latin-italic-400-700.woff2', 'noto-sans-mono-latin-400-700.woff2',
  readdirSync(realDir).filter((n) => n.startsWith('o-0b')).sort()[0]]
for (const name of real) {
  copyFileSync(join(realDir, name), join(out, 'files', name))
  results.push({ name: `real ${name}`, file: name, face: readFontFace(readFileSync(join(realDir, name))) })
}
writeFileSync(join(out, 'faces.json'), JSON.stringify(results, null, 2) + '\n')
console.log(`font-file: ${results.length} files`)
for (const r of results) console.log(`  ${r.name}: ${JSON.stringify(r.face)}`)
