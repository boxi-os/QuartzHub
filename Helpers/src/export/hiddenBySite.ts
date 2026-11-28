/**
 * QuartzHub's own step before `extractArticle` (pageScripts.ts stays QuartzControl's, verbatim):
 * every element of the page's article that the site's own CSS hides (`display: none`) gets the
 * `hidden` attribute, which extractArticle already removes. It is hidden either way, so the page
 * looks the same. What the site hides then stays out of the document whatever it is: Obsidian's
 * fold arrows before every heading (Quartz 5.3; they stood in the ePub, whose stylesheet is
 * QuartzHub's own), an embed's icon link, what a later release adds (plan „Quartz-Updates ohne
 * ständiges Nachziehen“, 2026-11-28).
 *
 * Measured at the export's width on gui-test (5.2.2, 5.3.1) and Example: no text goes that
 * extractArticle did not remove already. Never inside an SVG: Mermaid's <style> is display: none
 * and draws the diagram. Stringified and run on its own (scripts/export-pages-golden.mjs runs it
 * in Chrome), so it closes over nothing. Answers how many it marked.
 */
export function markHiddenBySite(): number {
  const root = document.querySelector('article') ?? document.querySelector('.bases-page')
  if (!root) return 0
  let marked = 0
  for (const el of root.querySelectorAll('*')) {
    if (el instanceof SVGElement || el.closest('svg') || el.hasAttribute('hidden')) continue
    if (getComputedStyle(el).display !== 'none') continue
    el.setAttribute('hidden', '')
    marked++
  }
  return marked
}
