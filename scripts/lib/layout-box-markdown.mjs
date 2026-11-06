#!/usr/bin/env node
// The Markdown chain of quartz-layout-box, out of the plugin itself, for `qh-check inline-svg`: a
// snippet in Markdown is read by remark first and by parse5 after, and an SVG pasted into one has
// to come out of that chain as harmless as it went in. The plugin bundles the chain into
// dist/index.js (tsup, only preact and vfile external), so this loads that bundle from the project
// it is given and calls its renderMarkdown, rather than holding a copy of the chain with version
// ranges that drift (QuartzControl's forty-fourth review, Niedrig 9).
//
// stdin:  { "project": "<path>", "inputs": ["<markdown>", …] }
// stdout: { "version": "0.4.2", "outputs": ["<html>", …] } or { "error": "<why not>" }
import { build } from '../../Helpers/node_modules/esbuild/lib/main.js'
import { existsSync, readFileSync, realpathSync, unlinkSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { dirname, join } from 'node:path'

const chunks = []
for await (const chunk of process.stdin) chunks.push(chunk)
const request = JSON.parse(Buffer.concat(chunks).toString('utf8'))
const answer = (value) => process.stdout.write(JSON.stringify(value))

const dir = join(request.project, '.quartz/plugins/quartz-layout-box')
const dist = join(dir, 'dist/index.js')
if (!existsSync(dist)) {
  answer({ error: `${dist} fehlt` })
} else {
  const real = realpathSync(dist)
  const text = readFileSync(real, 'utf8')
  if (!/\bfunction renderMarkdown\(/.test(text)) {
    answer({ error: 'das Bündel hat keine Funktion renderMarkdown' })
  } else {
    const out = join(tmpdir(), `qh-layout-box-${process.pid}.mjs`)
    await build({
      stdin: { contents: `${text}\nexport { renderMarkdown as __renderMarkdown };\n`, resolveDir: dirname(real), sourcefile: real, loader: 'js' },
      bundle: true, platform: 'node', format: 'esm', outfile: out, logLevel: 'error'
    })
    try {
      const { __renderMarkdown } = await import(`file://${out}`)
      const version = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8')).version
      answer({ version, outputs: request.inputs.map((input) => __renderMarkdown(input)) })
    } finally {
      unlinkSync(out)
    }
  }
}
