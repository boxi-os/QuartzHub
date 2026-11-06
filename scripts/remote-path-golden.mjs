#!/usr/bin/env node
// Golden file for RemotePath, made by QuartzControl's own shared/remotePath.ts: each case is one
// call with its arguments and the answer. The inputs walk the edges the comments there name ("~"
// and "~user", ".." anywhere, the login's root with and without deletion, every shell character
// rsync cannot carry, whitespace beyond ASCII, NUL in a relay folder) and the line ends a `$`
// without the m flag must not stop at.
//
//   Runtime/node/bin/node scripts/remote-path-golden.mjs [../QuartzControl]
import { loadQuartzControl } from './lib/qc-bundle.mjs'
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const control = resolve(process.argv[2] ?? join(here, '..', '..', 'QuartzControl'))
const out = join(here, '..', 'Packages', 'QuartzHubCore', 'Tests', 'QuartzHubCoreTests', 'Fixtures', 'remote-path')
const rp = await loadQuartzControl(control, 'shared/remotePath.ts', {})

const paths = [
  '', ' ', '\t\n', ' ', '　', '﻿', '/', '//', '.', './', '/.', './/./', '..', '../x', 'a/..', 'a/../b', 'a/..b', 'a/b..',
  '...', 'httpdocs', '/var/www/site', 'www/site/', ' www ', '~', '~/', '~//', '~/.', '~/x', '~qchost', '~qchost/', '~qchost/blog',
  '~other/x', '~ab/c/', 'x/~', '~/../x', '~\n', '~\nfoo', 'a\n', 'a b', 'neu!', 'fix58-v[a]', 'kontakt!', "it's", 'a"b', 'a\\b',
  'a$b', 'a`b', 'a;b', 'a&b', 'a|b', 'a<b', 'a>b', 'a(b', 'a)b', 'a{b', 'a}b', 'a*b', 'a?b', 'a#b', 'a b', 'a\u0085b',
  'Gärten/Ü', 'ü ', '~/a b', 'a b', 'a᠎b', 'a!b c', 'a\0b'
]
const cases = []
for (const path of paths) {
  for (const deleteRemoved of [false, true]) {
    cases.push({ fn: 'remotePathProblem', args: [path, deleteRemoved], result: rp.remotePathProblem(path, deleteRemoved) })
  }
  cases.push({ fn: 'rsyncUnsafeChar', args: [path], result: rp.rsyncUnsafeChar(path) })
  cases.push({ fn: 'relaySubdir', args: [path], result: rp.relaySubdir(path) })
}
const subdirs = ['relay', '/relay/', '//relay//', 'forms/relay', 'forms//relay', 'forms/./relay', 'forms/../relay', ' relay ', 'a/b/c/',
  'relay\0', '\nrelay\n', 'relay/\n', '/', '//', '.', '..', 'x/.', 'Kontakt-Ü']
for (const s of subdirs) cases.push({ fn: 'relaySubdir', args: [s], result: rp.relaySubdir(s) })
const logins = [['/home/qchost', 'qchost'], ['/home/qchost/', 'qchost'], ['/', 'qchost'], ['', 'qchost'], ['//', 'u'], ['/srv/qc/www', 'qcsftp'], ['/home/ä', 'ä']]
const tildes = ['~', '~/', '~//', '~/blog', '~//blog', '~/blog/', '~qchost', '~qchost/', '~qchost/blog', '~other', '~other/blog', 'blog',
  '/abs', '', 'x~', '~\n', '~qchost\n', '~\nqchost', '~ä/x', '~/a b', '~qcsftp/x']
for (const [loginDir, account] of logins) {
  for (const path of tildes) cases.push({ fn: 'fromLoginDir', args: [path, loginDir, account], result: rp.fromLoginDir(path, loginDir, account) })
}

mkdirSync(out, { recursive: true })
writeFileSync(join(out, 'cases.json'), JSON.stringify(cases, null, 1) + '\n')
console.log(`${cases.length} cases`)
