// osascript -l JavaScript axpos.js <process> [list | press <x> <y>]  (x,y in window points)
function run(argv) {
  const proc = Application('System Events').processes.byName(argv[0])
  const win = proc.windows[0]
  const [wx, wy] = win.position()
  const out = []
  let hit = null
  function walk(el, depth) {
    if (depth > 25) return
    let kids = []
    try { kids = el.uiElements() } catch (e) { return }
    for (const k of kids) {
      let role = ''
      try { role = k.role() } catch (e) {}
      if (role === 'AXButton' || role === 'AXLink' || role === 'AXRadioButton' || role === 'AXCheckBox' || role === 'AXDisclosureTriangle' || role === 'AXRow') {
        const [x, y] = k.position(); const [w, h] = k.size()
        const rx = x - wx, ry = y - wy
        out.push(`${role} @${rx},${ry} ${w}x${h}`)
        if (argv[1] === 'press') {
          const px = Number(argv[2]), py = Number(argv[3])
          if (px >= rx && px <= rx + w && py >= ry && py <= ry + h) hit = k
        }
      }
      walk(k, depth + 1)
    }
  }
  walk(win, 0)
  if (argv[1] === 'press') {
    if (!hit) return 'nothing at ' + argv[2] + ',' + argv[3]
    proc.frontmost = true
    if (hit.role() === 'AXRow') hit.selected = true
    else hit.actions.byName('AXPress').perform()
    return 'pressed ' + hit.role()
  }
  return out.join('\n')
}
