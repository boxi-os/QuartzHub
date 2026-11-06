// osascript -l JavaScript ax.js <process> <action: list|click> [label]
function run(argv) {
  const se = Application('System Events')
  const proc = se.processes.byName(argv[0])
  const out = []
  let clicked = false
  function walk(el, depth) {
    if (depth > 25 || clicked) return
    let kids = []
    try { kids = el.uiElements() } catch (e) { return }
    for (const k of kids) {
      let role = '', name = '', desc = ''
      try { role = k.role() } catch (e) {}
      try { name = k.name() || '' } catch (e) {}
      try { desc = k.description() || '' } catch (e) {}
      try { const t = k.attributes.byName('AXTitle').value(); if (t) name = t } catch (e) {}
      try { if (!name) { const t = k.attributes.byName('AXLabel').value(); if (t) name = t } } catch (e) {}
      if (!name && (role === 'AXButton' || role === 'AXLink')) { try { for (const c of k.uiElements()) { const v = c.value(); if (v) { name = String(v); break } } } catch (e) {} }
      if (role === 'AXButton' || role === 'AXRadioButton' || role === 'AXLink') {
        out.push(`${role}|${name}|${desc}`)
        if (argv[1] === 'click' && (name === argv[2] || desc === argv[2])) { k.actions.byName('AXPress').perform(); clicked = true; return }
      }
      walk(k, depth + 1)
    }
  }
  proc.frontmost = true
  walk(proc.windows[0], 0)
  return argv[1] === 'click' ? (clicked ? 'clicked ' + argv[2] : 'not found: ' + out.join(', ')) : out.join('\n')
}
