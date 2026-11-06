// Reads each archive named on the command line with QuartzControl's readZip (read-zip-lib.cjs,
// bundled by scripts/zip-golden.mjs) and prints one JSON line per archive.
const { readZip } = require('./read-zip-lib.cjs')
const { readFileSync } = require('node:fs')
const { createHash } = require('node:crypto')
for (const path of process.argv.slice(2)) console.log(JSON.stringify(function describe(run) {
  try {
    const files = [...run()].map(([name, data]) => ({
      name, length: data.length, sha256: createHash('sha256').update(data).digest('hex'),
      ...(data.length <= 64 && !data.includes(0) ? { text: data.toString('utf-8') } : {})
    }))
    return { files }
  } catch (error) {
    return error instanceof RangeError ? { threw: error.message, range: true } : { threw: error.message }
  }
}(() => readZip(readFileSync(path)))))
