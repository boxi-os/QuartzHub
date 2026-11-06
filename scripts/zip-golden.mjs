#!/usr/bin/env node
// Golden file for ZipArchive, made by QuartzControl's own zipArchive.ts:
// - `createZip` on entry lists (stored, deflated, empty, unicode names, the date clamp), the
//   archives kept as they came out;
// - `readZip` on archives built by hand with every edge the reader has to refuse or survive
//   (unsafe names, lying sizes, the 256-MiB ceiling, damaged headers, data descriptors, comments,
//   duplicate names) and on archives of three foreign writers (Python's zipfile, Info-ZIP, ditto);
// - `read-zip.cjs`, QuartzControl's reader bundled as it is, so the Swift tests can let it read
//   QuartzHub's archives (the other direction).
//
//   Runtime/node/bin/node scripts/zip-golden.mjs [../QuartzControl]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { build } from '../Helpers/node_modules/esbuild/lib/main.js'
import { execFileSync } from 'node:child_process'
import { createHash, randomBytes } from 'node:crypto'
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { crc32, deflateRawSync } from 'node:zlib'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'zip')
rmSync(out, { recursive: true, force: true })
mkdirSync(join(out, 'files'), { recursive: true })
const { createZip, readZip } = await loadQuartzControl(control, 'electron/main/services/zipArchive.ts', commonStubs)

// QuartzControl's reader as a file of its own, for the other direction.
await build({
  entryPoints: [join(control, 'electron/main/services/zipArchive.ts')],
  bundle: true, platform: 'node', format: 'cjs', outfile: join(out, 'read-zip-lib.cjs'), logLevel: 'warning', absWorkingDir: control,
  plugins: [{
    name: 'stand-ins',
    setup(b) {
      b.onResolve({ filter: /^\.\.\/i18n$/ }, () => ({ path: 'i18n', namespace: 'stub' }))
      b.onLoad({ filter: /.*/, namespace: 'stub' }, () => ({ contents: commonStubs['../i18n'], loader: 'js' }))
    }
  }]
})
writeFileSync(join(out, 'read-zip.cjs'), `// Reads each archive named on the command line with QuartzControl's readZip (read-zip-lib.cjs,
// bundled by scripts/zip-golden.mjs) and prints one JSON line per archive.
const { readZip } = require('./read-zip-lib.cjs')
const { readFileSync } = require('node:fs')
const { createHash } = require('node:crypto')
for (const path of process.argv.slice(2)) console.log(JSON.stringify(${describe.toString()}(() => readZip(readFileSync(path)))))
`)

// What a reader answered: the files in order with length and sha256 (and short text as text), or
// what it threw. A RangeError is Node running past the buffer, not one of the reader's sentences.
function describe(run) {
  try {
    const files = [...run()].map(([name, data]) => ({
      name, length: data.length, sha256: createHash('sha256').update(data).digest('hex'),
      ...(data.length <= 64 && !data.includes(0) ? { text: data.toString('utf-8') } : {})
    }))
    return { files }
  } catch (error) {
    return error instanceof RangeError ? { threw: error.message, range: true } : { threw: error.message }
  }
}

// ── createZip ────────────────────────────────────────────────────────────────────────────────
const random = randomBytes(3000)
const sample = {
  text: Buffer.from('Ein Absatz, der sich wiederholt. '.repeat(40)),
  short: Buffer.from('abc'),
  empty: Buffer.alloc(0),
  random,
  zeros: Buffer.alloc(20000)
}
writeFileSync(join(out, 'files', 'random.bin'), random)
const createCases = [
  { name: 'stored-only', when: [2026, 10, 6, 13, 37, 42], entries: [['mimetype', 'short', true], ['a/kurz.txt', 'short'], ['leer.txt', 'empty'], ['zufall.bin', 'random']] },
  { name: 'deflated', when: [2026, 10, 6, 13, 37, 43], entries: [['manifest.json', 'text'], ['teile/schriften/Ünicode.woff2', 'random'], ['nullen.bin', 'zeros'], ['leer', 'empty']] },
  { name: 'stored-forced', when: [2026, 0, 31, 23, 59, 59], entries: [['mimetype', 'text', true], ['nullen.bin', 'zeros', true]] },
  { name: 'year-1970', when: [1970, 0, 1, 0, 0, 0], entries: [['a', 'short']] },
  { name: 'year-2200', when: [2200, 5, 15, 12, 30, 10], entries: [['a', 'short']] },
  { name: 'none', when: [2026, 10, 6, 0, 0, 0], entries: [] }
]
const created = []
for (const c of createCases) {
  const zip = createZip(c.entries.map(([name, data, store]) => ({ name, data: sample[data], ...(store ? { store } : {}) })), new Date(...c.when))
  writeFileSync(join(out, 'files', `create-${c.name}.zip`), zip)
  created.push({ ...c, file: `create-${c.name}.zip`, read: describe(() => readZip(zip)) })
}

// ── readZip on archives built by hand ────────────────────────────────────────────────────────
// One entry's local header + data and its central record, with every field overridable.
function archive(entries, { comment = Buffer.alloc(0), count, centralOffsetDelta = 0, trailer = Buffer.alloc(0), lead = Buffer.alloc(0) } = {}) {
  const locals = [lead], centrals = []
  let offset = lead.length
  for (const e of entries) {
    const data = e.data ?? Buffer.alloc(0)
    const method = e.method ?? 0
    const body = e.body ?? (method === 8 ? deflateRawSync(data) : data)
    const name = Buffer.isBuffer(e.name) ? e.name : Buffer.from(e.name, 'utf-8')
    const crc = e.crc ?? crc32(data)
    const size = e.size ?? data.length
    const localExtra = e.localExtra ?? Buffer.alloc(0)
    const local = Buffer.alloc(30)
    local.writeUInt32LE(e.localSig ?? 0x04034b50, 0)
    local.writeUInt16LE(20, 4)
    local.writeUInt16LE(e.flags ?? 0x0800, 6)
    local.writeUInt16LE(method, 8)
    local.writeUInt32LE(e.descriptor ? 0 : crc, 14)
    local.writeUInt32LE(e.descriptor ? 0 : body.length, 18)
    local.writeUInt32LE(e.descriptor ? 0 : size, 22)
    local.writeUInt16LE(name.length, 26)
    local.writeUInt16LE(localExtra.length, 28)
    const descriptor = e.descriptor ? (() => { const d = Buffer.alloc(16); d.writeUInt32LE(0x08074b50, 0); d.writeUInt32LE(crc, 4); d.writeUInt32LE(body.length, 8); d.writeUInt32LE(size, 12); return d })() : Buffer.alloc(0)
    locals.push(local, name, localExtra, body, descriptor)
    const extra = e.centralExtra ?? Buffer.alloc(0)
    const fileComment = e.fileComment ?? Buffer.alloc(0)
    const central = Buffer.alloc(46)
    central.writeUInt32LE(e.centralSig ?? 0x02014b50, 0)
    central.writeUInt16LE(20, 4)
    central.writeUInt16LE(20, 6)
    central.writeUInt16LE(e.flags ?? 0x0800, 8)
    central.writeUInt16LE(method, 10)
    central.writeUInt32LE(crc, 16)
    central.writeUInt32LE(e.compressedSize ?? body.length, 20)
    central.writeUInt32LE(size, 24)
    central.writeUInt16LE(name.length, 28)
    central.writeUInt16LE(extra.length, 30)
    central.writeUInt16LE(fileComment.length, 32)
    central.writeUInt32LE(e.localOffset ?? offset, 42)
    centrals.push(central, name, extra, fileComment)
    offset += local.length + name.length + localExtra.length + body.length + descriptor.length
  }
  const central = Buffer.concat(centrals)
  const eocd = Buffer.alloc(22)
  eocd.writeUInt32LE(0x06054b50, 0)
  eocd.writeUInt16LE(count ?? entries.length, 8)
  eocd.writeUInt16LE(count ?? entries.length, 10)
  eocd.writeUInt32LE(central.length, 12)
  eocd.writeUInt32LE(offset + centralOffsetDelta, 16)
  eocd.writeUInt16LE(comment.length, 20)
  return Buffer.concat([...locals, central, eocd, comment, trailer])
}
const text = (s) => Buffer.from(s, 'utf-8')
const MiB = 1024 * 1024
const readCases = {
  'plain': archive([{ name: 'a.txt', data: text('Hallo') }, { name: 'b/c.txt', data: text('Welt'), method: 8 }]),
  'unicode-name': archive([{ name: 'teile/schriften/Ünicode – ß.woff2', data: text('x') }]),
  'invalid-utf8-name': archive([{ name: Buffer.from([0x61, 0xff, 0xfe, 0x62]), data: text('x') }]),
  'directory-entry': archive([{ name: 'ordner/' }, { name: 'ordner/datei', data: text('d') }]),
  'dotdot': archive([{ name: 'files/content/../PROOF.md', data: text('x') }]),
  'dotdot-only': archive([{ name: '..', data: text('x') }]),
  'dotdot-backslash': archive([{ name: 'a\\..\\b', data: text('x') }]),
  'dotdot-prefix-ok': archive([{ name: 'a/..b/...', data: text('x') }]),
  'absolute': archive([{ name: '/etc/x', data: text('x') }]),
  'drive': archive([{ name: 'C:x', data: text('x') }]),
  'drive-lower': archive([{ name: 'z:/x', data: text('x') }]),
  'drive-digit-ok': archive([{ name: '1:x', data: text('x') }]),
  'nul': archive([{ name: 'a\0b', data: text('x') }]),
  'empty-name': archive([{ name: '', data: text('x') }]),
  'unsafe-after-good': archive([{ name: 'ok', data: text('x') }, { name: '../x', data: text('x') }]),
  'method-12': archive([{ name: 'a', data: text('x'), method: 12 }]),
  'bad-crc': archive([{ name: 'a', data: text('x'), crc: 1 }]),
  'bad-crc-deflate': archive([{ name: 'a', data: text('xxxxxxxxxx'), method: 8, crc: 1 }]),
  'size-low-store': archive([{ name: 'a', data: text('Hallo'), size: 3 }]),
  'size-high-store': archive([{ name: 'a', data: text('Hallo'), size: 9 }]),
  'size-low-deflate': archive([{ name: 'a', data: text('Hallo Hallo Hallo'), method: 8, size: 5 }]),
  'size-high-deflate': archive([{ name: 'a', data: text('Hallo Hallo Hallo'), method: 8, size: 40 }]),
  'empty-deflated-0300': archive([{ name: 'leer', method: 8, body: Buffer.from([0x03, 0x00]) }]),
  'empty-deflated-garbage': archive([{ name: 'leer', method: 8, body: Buffer.from([0xff, 0xff, 0xff]) }]),
  'empty-stored': archive([{ name: 'leer' }]),
  'deflate-garbage': archive([{ name: 'a', data: text('Hallo'), method: 8, body: Buffer.from([0xff, 0xff, 0xff, 0xff]) }]),
  'deflate-truncated': archive([{ name: 'a', data: Buffer.from(random.subarray(0, 500).toString('hex')), method: 8, body: deflateRawSync(Buffer.from(random.subarray(0, 500).toString('hex'))).subarray(0, 100) }]),
  'compressed-size-past-end': archive([{ name: 'a', data: text('Hallo'), compressedSize: 5000 }]),
  // The first entry is honest, the second claims the rest: exactly 256 MiB passes (and is then
  // damaged), one byte more is refused before anything is unpacked.
  'ceiling-exact': archive([{ name: 'a', data: text('x') }, { name: 'b', data: text('y'), size: 256 * MiB - 1 }]),
  'ceiling-over': archive([{ name: 'a', data: text('x') }, { name: 'b', data: text('y'), size: 256 * MiB }]),
  'ceiling-single': archive([{ name: 'a', data: text('x'), size: 300 * MiB }]),
  'ceiling-after-directory': archive([{ name: 'd/', size: 300 * MiB }, { name: 'a', data: text('x') }]),
  'bomb-small-claim': archive([{ name: 'a', data: Buffer.alloc(MiB), method: 8, size: 1000 }]),
  'data-descriptor': archive([{ name: 'a', data: text('Hallo Hallo Hallo'), method: 8, flags: 0x0808, descriptor: true }]),
  'local-extra': archive([{ name: 'a', data: text('Hallo'), localExtra: Buffer.alloc(7, 1) }]),
  'central-extra-comment': archive([{ name: 'a', data: text('Hallo'), centralExtra: Buffer.alloc(9, 2), fileComment: text('Notiz') }, { name: 'b', data: text('zwei') }]),
  'archive-comment': archive([{ name: 'a', data: text('Hallo') }], { comment: text('Ein Kommentar') }),
  'comment-max': archive([{ name: 'a', data: text('Hallo') }], { comment: Buffer.alloc(0xffff, 0x41) }),
  'trailer-past-comment': archive([{ name: 'a', data: text('Hallo') }], { trailer: Buffer.alloc(0x10000, 0x41) }),
  'leading-junk': archive([{ name: 'a', data: text('Hallo') }], { lead: text('#!/bin/sh\n') }),
  'duplicate-names': archive([{ name: 'a', data: text('erst') }, { name: 'b', data: text('b') }, { name: 'a', data: text('dann') }]),
  'bad-central-sig': archive([{ name: 'a', data: text('x'), centralSig: 0x12345678 }]),
  'bad-local-sig': archive([{ name: 'a', data: text('x'), localSig: 0x12345678 }]),
  'count-too-high': archive([{ name: 'a', data: text('x') }], { count: 3 }),
  'count-zero': archive([{ name: 'a', data: text('x') }], { count: 0 }),
  'central-offset-past-end': archive([{ name: 'a', data: text('x') }], { centralOffsetDelta: 100000 }),
  'local-offset-past-end': archive([{ name: 'a', data: text('x'), localOffset: 100000 }]),
  'local-offset-near-end': archive([{ name: 'a', data: text('x'), localOffset: 1 }]),
  'no-eocd': text('PK\x03\x04 das ist kein Archiv, nur ein Anfang'),
  'empty-file': Buffer.alloc(0),
  'short-file': text('PK\x05\x06'),
  'eocd-only': archive([]),
  'eocd-truncated': archive([{ name: 'a', data: text('x') }]).subarray(0, -3)
}

// ── foreign writers ──────────────────────────────────────────────────────────────────────────
const work = mkdtempSync(join(tmpdir(), 'qh-zip-golden-'))
try {
  const tree = join(work, 'baum')
  mkdirSync(join(tree, 'teile', 'schriften'), { recursive: true })
  writeFileSync(join(tree, 'manifest.json'), '{"format":1}\n'.repeat(30))
  writeFileSync(join(tree, 'leer.txt'), '')
  writeFileSync(join(tree, 'teile', 'schriften', 'Ünicode.woff2'), random)
  // Python's zipfile: deflated, including the empty file (`03 00`).
  execFileSync('python3', ['-I', '-c', `
import zipfile, sys, os
root = sys.argv[1]
with zipfile.ZipFile(sys.argv[2], 'w', zipfile.ZIP_DEFLATED) as z:
    for dirpath, dirs, files in sorted(os.walk(root)):
        for f in sorted(files):
            full = os.path.join(dirpath, f)
            z.write(full, os.path.relpath(full, root))
`, tree, join(work, 'python.zip')])
  // Info-ZIP: directory entries and extra fields.
  execFileSync('/usr/bin/zip', ['-q', '-r', join(work, 'infozip.zip'), '.'], { cwd: tree })
  // ditto: data descriptors.
  execFileSync('/usr/bin/ditto', ['-c', '-k', '--norsrc', tree, join(work, 'ditto.zip')])
  for (const name of ['python', 'infozip', 'ditto']) readCases[`foreign-${name}`] = readFileSync(join(work, `${name}.zip`))
} finally {
  rmSync(work, { recursive: true, force: true })
}

const read = []
for (const [name, zip] of Object.entries(readCases)) {
  writeFileSync(join(out, 'files', `read-${name}.zip`), zip)
  read.push({ name, file: `read-${name}.zip`, result: describe(() => readZip(zip)) })
}
writeFileSync(join(out, 'cases.json'), JSON.stringify({ created, read }, null, 1) + '\n')
console.log(`${created.length} archives written, ${read.length} read → ${out}`)
