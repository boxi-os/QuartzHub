// A stand-in for quartz-forms' dist/cli.js, for the forms goldens: answers what fake-cli.json in
// the working directory (the project) says for the subcommand, and logs its arguments and QF_*
// variables to fake-cli.log there. An answer: `stdout`, `stderr` (written first, stdout 50 ms
// later, so their order in the combined output is fixed), `exit`, and `files` written below --out.
import { appendFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'

const argv = process.argv.slice(2)
const scenario = JSON.parse(readFileSync('fake-cli.json', 'utf8'))
const env = Object.fromEntries(Object.entries(process.env).filter(([k]) => k.startsWith('QF_')).sort())
appendFileSync('fake-cli.log', `${JSON.stringify({ argv, env })}\n`)
const answer = scenario[argv[0]] ?? {}
if (answer.files) {
  const out = argv[argv.indexOf('--out') + 1]
  for (const [rel, text] of Object.entries(answer.files)) {
    mkdirSync(dirname(join(out, rel)), { recursive: true })
    writeFileSync(join(out, rel), text)
  }
}
if (answer.stderr) process.stderr.write(answer.stderr)
setTimeout(() => {
  process.stdout.write(answer.stdout ?? '')
  process.exitCode = answer.exit ?? 0
}, answer.stderr ? 50 : 0)
