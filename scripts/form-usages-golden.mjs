#!/usr/bin/env node
// Golden file for FormUsages, made by QuartzControl's own code: `quartzSlug` and `pageFormUse` of
// shared/formUsages.ts over the cases below (the front matter parsed with QuartzControl's yaml, as
// contentService does), and `formUsages` of contentService.ts over small projects (files,
// quartz.config.yaml, globby linked in from gui-test or not, a linked vault, a file that cannot be
// read). Run with LANG=de_DE.UTF-8: pages and slugs are sorted with localeCompare.
//
//   LANG=de_DE.UTF-8 Runtime/node/bin/node scripts/form-usages-golden.mjs [../QuartzControl] [gui-test]
import { loadQuartzControl, commonStubs } from './lib/qc-bundle.mjs'
import { chmodSync, existsSync, mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { homedir, tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const guiTest = resolve(process.argv[3] ?? join(homedir(), 'Documents', 'QuartzProjekte', 'gui-test'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'form-usages')
if (!existsSync(join(guiTest, 'node_modules', 'globby'))) throw new Error(`no globby in ${guiTest}/node_modules`)

const shared = await loadQuartzControl(control, 'shared/formUsages.ts', {})
const { parse } = createRequire(join(control, 'package.json'))('yaml')
const content = await loadQuartzControl(control, 'electron/main/services/contentService.ts', {
  ...commonStubs,
  './backupService': 'export async function snapshotContent() { throw new Error("no backups here") }',
  // readConfig's shape as far as formUsages reads it; a source is a plain name here, which
  // deriveName keeps as it is.
  './configService': `import { parse } from 'yaml'; import { readFileSync } from 'fs'
    export async function readConfig(p) {
      const c = parse(readFileSync(p + '/quartz.config.yaml', 'utf8'))
      return { configuration: c.configuration, plugins: (c.plugins ?? []).map((e) => ({ ...e, name: e.source, enabled: !!e.enabled })) }
    }`,
  './projectDependencies': 'export function halfUnpackedModule() { return null }'
})

const nfd = 'Über'
const slugCases = [
  'Ordner/Umfrage Seite.md', 'a/a.md', 'x/Y/y.md', '_index.md', 'x/_index.md', 'x/_index', '/lead/trail/', 'a//b.md',
  'a b&c%d?e#f<g>h:i"j|k*l.md', 'x.png', 'x.HTML', 'x.html', 'a.b.c', 'noext', 'dir/', 'Über.md', `${nfd}.md`,
  'ΣΑΣ.md', 'İstanbul.md', 'tab\there.md', 'nbsp x.md', 'ls x.md', 'kKx.md', 'ü/Ü.md', 'x.md/', 'x.Md',
  'emoji 😀.md', '', '/', 'a.tar.gz', 'Teil 10.md'
]

const fm = (yaml, body = '') => `---\n${yaml}\n---\n${body}`
const useCases = [
  ['fm-string', fm('form: kontakt\ntitle: "  Kontakt  "'), 'quartz-form', 'form'],
  ['fm-list', fm('form: [a, b, a, 5, " c "]\ntitle: 7'), 'quartz-form', 'form'],
  ['fm-false', fm('form: false\ndraft: true\npublish: "true"'), 'quartz-form', 'form'],
  ['fm-false-string', fm('form: "false"\ndraft: "yes"'), 'quartz-form', 'form'],
  ['fm-crlf', '---\r\nform: crlf\r\n---\r\nText', 'quartz-form', 'form'],
  ['fm-dots', '---\nform: dots\n...\nText', 'quartz-form', 'form'],
  ['fm-trailing-space', '---\nform: ts\n---   \n\nText {{form:after}}', 'quartz-form', 'form'],
  ['fm-no-newline-end', '---\nform: eof\n---', 'quartz-form', 'form'],
  ['fm-text-after-dashes', '---\nform: x\n--- no\nform: y\n---\nBody', 'quartz-form', 'form'],
  ['fm-empty', '---\n---\n{{form:a}}', 'quartz-form', 'form'],
  ['fm-blank-yaml', '---\n\n---\n{{form:b}}', 'quartz-form', 'form'],
  ['fm-invalid', fm('form: [unclosed'), 'quartz-form', 'form'],
  ['fm-duplicate-key', fm('form: a\nform: b'), 'quartz-form', 'form'],
  ['fm-array-root', fm('- form'), 'quartz-form', 'form'],
  ['fm-date-title', '---\n%YAML 1.1\n--- !!map\ntitle: 2001-01-01\nform: d\n---\nText', 'quartz-form', 'form'],
  ['fm-timestamp-11', fm('title: 2001-01-01\nform: t'), 'quartz-form', 'form'],
  ['fm-bom', '﻿---\nform: bom\n---\n', 'quartz-form', 'form'],
  ['fm-custom-key', fm('formular: eigen\nform: nicht'), 'quartz-form', 'formular'],
  ['fm-nfd-pair', fm(`form: ["Über", "${nfd}", " Über"]`), 'quartz-form', 'form'],
  ['fm-title-blank', fm('title: "   "\nform: z'), 'quartz-form', 'form'],
  ['code-basic', 'Text\n\n```quartz-form\n\n  kontakt  \nrest\n```\n', 'quartz-form', 'form'],
  ['code-info', '```quartz-form extra words\nid1\n```', 'quartz-form', 'form'],
  ['code-tilde', '~~~quartz-form\nid2\n~~~', 'quartz-form', 'form'],
  ['code-indent3', '   ```quartz-form\nid3\n   ```', 'quartz-form', 'form'],
  ['code-indent4', '    ```quartz-form\nid4\n    ```\n{{form:p4}}', 'quartz-form', 'form'],
  ['code-unclosed', '```quartz-form\nopen\n{{form:inside}}', 'quartz-form', 'form'],
  ['code-short-close', '````quartz-form\nlong\n```\nstill {{form:hidden}}\n````\n{{form:out}}', 'quartz-form', 'form'],
  ['code-close-text', '```quartz-form\nidc\n``` x\n{{form:hidden2}}\n```\n{{form:out2}}', 'quartz-form', 'form'],
  ['code-mixed-close', '```quartz-form\nmix\n~~~\n{{form:hidden3}}\n```', 'quartz-form', 'form'],
  ['code-other-hides', '```js\n{{form:nope}}\n```\n{{form:yes}}', 'quartz-form', 'form'],
  ['code-empty-lang', '```\n{{form:nope}}\n```\n', 'quartz-form', 'form'],
  ['code-custom', '```formular\neins\n```\n```quartz-form\nzwei\n```', 'formular', 'form'],
  ['code-blank-block', '```quartz-form\n\n   \n```', 'quartz-form', 'form'],
  ['code-crlf', '```quartz-form\r\ncr\r\n```\r\n{{form:after}}', 'quartz-form', 'form'],
  ['code-cr-only', '```quartz-form\rcr-only\r```', 'quartz-form', 'form'],
  ['code-ls', '```quartz-form x\nls\n```', 'quartz-form', 'form'],
  ['code-nel', '```quartz-form\u0085x\nnel\n```', 'quartz-form', 'form'],
  ['code-nel-lang', '```quartz-form\u0085\nnel2\n```', 'quartz-form', 'form'],
  ['code-nbsp-lang', '``` quartz-form x\nnb\n```', 'quartz-form', 'form'],
  ['inline', 'a `{{form:no}}` b ``{{form:no2}}`` c {{form:yes}}', 'quartz-form', 'form'],
  ['inline-multiline', 'a `x\n{{form:no}}\ny` {{form:yes}}', 'quartz-form', 'form'],
  ['inline-unmatched', 'a ` {{form:yes}}', 'quartz-form', 'form'],
  ['inline-mismatch', 'a `` {{form:no}} ` `` {{form:yes}}', 'quartz-form', 'form'],
  ['ph-spaces', '{{ form:abc }} {{\tform:t\t}} {{ form:nb }} {{ form:ls}}', 'quartz-form', 'form'],
  ['ph-case', '{{FORM:Abc}} {{Form:abc}} %7b%7bFORM:enc%7d%7d %7B%7Bform:enc2%7D%7D', 'quartz-form', 'form'],
  ['ph-invalid', '{{form:a_b}} {{form:}} {{form:a b}} {{form:ä}} {{form:kK}} {{ſorm:x}} %7B%7B form:x%7D%7D', 'quartz-form', 'form'],
  ['ph-order', fm('form: [z]', '{{form:y}}\n```quartz-form\nx\n```\n{{form:z}} {{form:w}}'), 'quartz-form', 'form'],
  ['ph-nfd', `{{form:x}} ${nfd}`, 'quartz-form', 'form'],
  ['nothing', 'Nur Text.', 'quartz-form', 'form'],
  ['empty', '', 'quartz-form', 'form']
]

// The use of one page, with every front matter QuartzControl parsed in the order it asked.
const uses = useCases.map(([id, text, codeBlockLang, frontmatterKey]) => {
  const { draft, publish, ...rest } = shared.pageFormUse(text, codeBlockLang, frontmatterKey, (yaml) => parse(yaml))
  return { id, text, codeBlockLang, frontmatterKey, answer: { ...rest, draft, publish } }
})
const slugs = slugCases.map((path) => ({ path, slug: shared.quartzSlug(path), slugPath: shared.slugPath(shared.quartzSlug(path)) }))

const config = (patterns, plugins = []) =>
  `configuration:\n  pageTitle: Test\n  ignorePatterns: ${JSON.stringify(patterns)}\nplugins:\n` +
  (plugins.length ? plugins.map(([source, enabled]) => `  - source: ${source}\n    enabled: ${enabled}\n`).join('') : '  []\n')
const garden = [
  ['kontakt.md', '---\ntitle: Kontakt\nform: kontakt\n---\nText'],
  ['Teil 10.md', '{{form:umfrage}}'],
  ['Teil 2.md', '```quartz-form\numfrage\n```'],
  ['äpfel.md', '{{form:kontakt}} {{form:unbekannt}}'],
  ['Zebra.md', '---\nform: false\n---\n'],
  ['entwurf.md', '---\ndraft: true\nform: kontakt\n---\n'],
  ['öffentlich.md', '---\npublish: true\n---\n{{form:kontakt}}'],
  ['ohne.md', 'Nichts hier.'],
  ['private/geheim.md', '{{form:kontakt}}'],
  ['Ordner/Umfrage Seite.md', '---\ntitle: "  Umfrage  "\n---\n{{ form:umfrage }}'],
  ['Ordner/Ordner.md', '{{form:kontakt}}'],
  ['bild.png', 'p'],
  ['GROSS.MD', '{{form:kontakt}}'],
  ['.hidden.md', '{{form:kontakt}}'],
  ['Mappe.md/inner.md', '{{form:x}}']
]
const scenarios = [
  { id: 'fallback', files: garden, config: config(['private']), codeBlockLang: 'quartz-form', frontmatterKey: 'form' },
  { id: 'quartz-filters', files: garden, config: config(['private'], [['remove-draft', true], ['explicit-publish', true]]), globby: true, codeBlockLang: '', frontmatterKey: '' },
  { id: 'quartz-filters-off', files: garden, config: config([], [['remove-draft', false], ['explicit-publish', 'yes']]), globby: true, codeBlockLang: 'quartz-form', frontmatterKey: 'form' },
  { id: 'custom-keys', files: [['a.md', '---\nformular: eins\nform: zwei\n---\n```formular\ndrei\n```\n```quartz-form\nvier\n```']], config: config([]), codeBlockLang: 'formular', frontmatterKey: 'formular' },
  { id: 'gitignore', files: [['geheim/g.md', '{{form:g}}'], ['offen/o.md', '{{form:o}}'], ['.gitignore', 'geheim/\n']], config: config([]), globby: true, codeBlockLang: 'quartz-form', frontmatterKey: 'form' },
  { id: 'unreadable', files: [['lesbar.md', '{{form:a}}'], ['zu.md', '{{form:b}}']], unreadable: ['zu.md'], config: config([]), globby: true, codeBlockLang: 'quartz-form', frontmatterKey: 'form' },
  { id: 'no-content', files: null, config: config([]), codeBlockLang: 'quartz-form', frontmatterKey: 'form' },
  { id: 'dangling-link', link: '../nirgends', files: null, config: config([]), codeBlockLang: 'quartz-form', frontmatterKey: 'form' },
  { id: 'linked', link: '../vault', vault: [['Gärten-Ü/a.md', '{{form:g}}'], [`${nfd}.md`, '---\ntitle: Über\nform: [u, g]\n---\n']], config: config([]), globby: true, codeBlockLang: 'quartz-form', frontmatterKey: 'form' },
  { id: 'bad-config', files: [['private/p.md', '{{form:p}}'], ['a.md', '{{form:a}}']], config: 'configuration: [unclosed\n', codeBlockLang: 'quartz-form', frontmatterKey: 'form' },
  { id: 'nothing', files: [['a.md', 'a'], ['b/c.md', 'c']], config: config([]), codeBlockLang: 'quartz-form', frontmatterKey: 'form' },
  { id: 'empty', files: [], config: config([]), codeBlockLang: 'quartz-form', frontmatterKey: 'form' }
]

const work = realpathSync(mkdtempSync(join(tmpdir(), 'qh-form-usages-')))
const write = (root, files) => {
  for (const [rel, text] of files) {
    mkdirSync(dirname(join(root, rel)), { recursive: true })
    writeFileSync(join(root, rel), text)
  }
}
const results = []
for (const s of scenarios) {
  const project = join(work, s.id, 'projekt')
  mkdirSync(project, { recursive: true })
  writeFileSync(join(project, 'quartz.config.yaml'), s.config)
  if (s.globby) symlinkSync(join(guiTest, 'node_modules'), join(project, 'node_modules'))
  if (s.vault) write(join(work, s.id, 'vault'), s.vault)
  if (s.link) symlinkSync(s.link, join(project, 'content'))
  else if (s.files) { mkdirSync(join(project, 'content'), { recursive: true }); write(join(project, 'content'), s.files) }
  for (const file of s.unreadable ?? []) chmodSync(join(project, 'content', file), 0o000)
  let answer
  try {
    answer = await content.formUsages(project, s.codeBlockLang, s.frontmatterKey)
  } catch (err) {
    answer = { error: String(err.message) }
  }
  for (const file of s.unreadable ?? []) chmodSync(join(project, 'content', file), 0o644)
  results.push({ ...s, answer })
}
rmSync(work, { recursive: true, force: true })
mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify({ locale: Intl.DateTimeFormat().resolvedOptions().locale, slugs, uses, scenarios: results }, null, 1) + '\n')
for (const u of uses) console.log(u.id, JSON.stringify(u.answer))
for (const r of results) console.log(r.id, r.answer.error ?? `${r.answer.listSource} pages=${r.answer.pages.length} slugs=${r.answer.slugs.length} unreadable=${r.answer.unreadable}${r.answer.noContent ? ' noContent' : ''}`)
