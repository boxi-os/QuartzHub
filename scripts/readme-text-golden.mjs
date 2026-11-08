#!/usr/bin/env node
// Golden file for ReadmeText, made by QuartzControl's own `components/ReadmeText.tsx`: the blocks a
// README becomes on the Marktplatz. The component returns React elements; they are read back into
// a neutral form (block kind from the element's key, inline parts from their element type), so the
// Swift reader is compared with what QuartzControl would put on screen.
//
// Inputs: the READMEs of gui-test's plugins (read only, copied into the fixture like
// option-schema's real plugins), hand-made edges, and random strings over the characters the
// reader cares about (seeded, so the file only changes with QuartzControl).
//
//   Runtime/node/bin/node scripts/readme-text-golden.mjs [../QuartzControl] [gui-test]
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const guiTest = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte', 'gui-test'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'readme-text')

// QuartzControl builds with `jsx: react-jsx` from tsconfig.web.json, which esbuild does not read here.
const mod = await loadQuartzControl(control, 'src/components/ReadmeText.tsx', {}, {
  replace: [["import type { ReactNode } from 'react'", "import React, { type ReactNode } from 'react'"]],
  expose: ['resolveHref', 'stripTags', 'stripComments']
})

const flat = (children) => (Array.isArray(children) ? children.flat(Infinity) : children === undefined ? [] : [children])

function inlineOf(nodes) {
  return flat(nodes).filter((n) => n !== null && n !== false && n !== undefined).map((n) => {
    if (typeof n === 'string') return { text: n }
    const { type, props } = n
    if (type === 'code') return { code: flat(props.children).join('') }
    if (type === 'strong') return { strong: flat(props.children).join('') }
    if (type === 'a') return { link: { href: props.href, parts: inlineOf(props.children) } }
    if (type === 'span' && props.className === 'text-text-muted') {
      const parts = flat(props.children)
      if (parts[0] !== '[' || parts[parts.length - 1] !== ']') throw new Error('unexpected image span')
      return { image: parts.slice(1, -1).join('') }
    }
    if (type === 'span') return { link: { href: null, parts: inlineOf(props.children) } }
    throw new Error(`unexpected inline ${type}`)
  })
}

function blocksOf(text, repoUrl) {
  const root = mod.default({ text, repoUrl })
  return flat(root.props.children).map((el) => {
    const kind = String(el.key)[0]
    if (kind === 'p') return { paragraph: inlineOf(el.props.children) }
    if (kind === 'h') return { heading: { big: el.props.className.includes('text-heading'), parts: inlineOf(el.props.children) } }
    if (kind === 'c') return { code: flat(el.props.children).join('') }
    if (kind === 't') return { table: flat(el.props.children).join('') }
    if (kind === 'l') {
      return { list: { ordered: el.type === 'ol', items: flat(el.props.children).map((li) => inlineOf(li.props.children)) } }
    }
    throw new Error(`unexpected block ${el.key}`)
  })
}

// ── inputs ──────────────────────────────────────────────────────────────────────────────────────

const repo = 'https://github.com/quartz-community/example'
const cases = []

const plugins = join(guiTest, '.quartz', 'plugins')
if (!existsSync(plugins)) throw new Error(`${plugins} fehlt`)
for (const name of readdirSync(plugins).sort()) {
  const file = join(plugins, name, 'README.md')
  if (existsSync(file)) cases.push({ id: `real/${name}`, text: readFileSync(file, 'utf8'), repoUrl: `https://github.com/quartz-community/${name}` })
}
if (cases.length < 3) throw new Error('zu wenige READMEs aus gui-test')

const edges = {
  headings: '# One\n## Two ##\n### Three\n####### seven\n#NoSpace\n#   \n## trailing   ###   ',
  fences: '```js\nconst a = `x`\n```\ntext\n~~~\nunclosed ~~~ fence\n  ``` inside',
  fenceIndented: '   ```\ncode\n   ```after\nrest',
  tables: '| a | b |\n|---|:-:|\n| 1 | **2** |\n  | indented |\n|\n|-|-\ntext',
  lists: '- one\n- two\n  continued here\n   * nested-looking\n1. first\n2) second\n10. tenth\n+ plus\n-not a list\n- \n-\ttab',
  continuationAfterBlank: '- a\n\n  b',
  rules: '---\n* * *\n___\n- - -\n-- \n**\ntext',
  quotes: '> quoted\n>also\n   >  deep\n>',
  inline: 'Use `npx quartz` and **bold** and __under__ and [link](https://x.y "title") and [rel](./docs/a.md) and [abs](/root.md)'
    + ' and [anchor](#top) and [mail](mailto:a@b.c) and [UP](HTTP://X.Y) and ![alt](i.png) and ![](empty.png) and [**bold link**](b.md)'
    + ' and [`code`](c.md) and [unclosed](x and [a](b c) and [](d) and `` and ****',
  html: '<!-- comment -->\n<p align="center"><img src="x.png" alt="logo"></p>\n<!-- open\n<div>\ntext <b>bold</b> a < b > c\n<>\n<a\nhref>',
  unclosedComment: 'before <!-- never closed\nafter',
  crlf: 'line one\r\nline two\r\rthree\r\n- item\r\n',
  spaces: 'a b\n \n\u000b\n﻿# bom heading\n \n- x y\n# h \n\u0085para',
  unicode: 'Über **Grüße** 😀 [ü](ö.md) `ß`\n## Überschrift 🎉',
  longParagraph: '[a](b '.repeat(800),
  exactLimit: 'x'.repeat(3990) + ' **bold**',
  overLimit: 'x'.repeat(3992) + ' **bold**',
  repoTrailingSlash: '[r](./x.md)',
  empty: '',
  onlyBlank: '\n\n   \n'
}
for (const [id, text] of Object.entries(edges)) cases.push({ id: `edge/${id}`, text, repoUrl: id === 'repoTrailingSlash' ? repo + '/' : repo })

// A small PRNG with a fixed seed.
let seed = 20261108
const rand = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff)
const alphabet = ['a', 'b', ' ', '  ', '\n', '\n', '#', '# ', '-', '- ', '*', '**', '_', '__', '`', '```', '~~~', '|', '[', ']', '(', ')',
  '!', '<', '>', '<!--', '-->', '1.', '2)', ':', '/', './', 'http://', '#x', '\t', '\r', ' ', ' ', 'ü', '😀', '>', '\\']
for (let n = 0; n < 400; n++) {
  let text = ''
  const length = 1 + Math.floor(rand() * 60)
  for (let i = 0; i < length; i++) text += alphabet[Math.floor(rand() * alphabet.length)]
  cases.push({ id: `random/${n}`, text, repoUrl: repo })
}

const result = cases.map((c) => ({ ...c, blocks: blocksOf(c.text, c.repoUrl) }))

const hrefs = ['https://a.b', 'http://a.b', 'HTTPS://A.B', 'ftp://x', 'mailto:x@y', '#a', './x.md', '/x.md', 'x.md', '../x.md', '.x', '1:2', 'a:b']
  .map((href) => ({ href, repoUrl: repo, resolved: mod.resolveHref(href, repo) }))

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify({ cases: result, hrefs }, null, 1) + '\n')
console.log(`${result.length} READMEs, ${hrefs.length} Links → ${join(out, 'cases.json')}`)
