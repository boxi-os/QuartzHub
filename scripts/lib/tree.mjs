// Lays out a test tree for the golden scripts: path → text (a file), { link }, { dir: mode } or
// { text, mode }. `@W@` in texts and link targets becomes `w`. The Swift tests read the same form
// (ProjectDuplicatorTests.layOut).
import { chmodSync, mkdirSync, symlinkSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'

export function layOut(root, tree, w) {
  const fill = (text) => text.replaceAll('@W@', w)
  mkdirSync(root, { recursive: true })
  const modes = []
  for (const [path, spec] of Object.entries(tree)) {
    const full = join(root, path)
    mkdirSync(dirname(full), { recursive: true })
    if (typeof spec === 'string') writeFileSync(full, fill(spec))
    else if (spec.link !== undefined) symlinkSync(fill(spec.link), full)
    else if (spec.dir !== undefined) { mkdirSync(full, { recursive: true }); modes.push([full, spec.dir]) }
    else { writeFileSync(full, fill(spec.text)); chmodSync(full, spec.mode) }
  }
  for (const [full, mode] of modes) chmodSync(full, mode)
}
