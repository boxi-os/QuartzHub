import Foundation

/// The module an authored frame becomes: `dist/frames.js`, which Quartz imports as the frame
/// plugin (`generateFrameJs` in QuartzControl's `layoutFrameService.ts`). Plain JavaScript
/// with `h()` instead of JSX, because Quartz skips the build of a plugin whose `dist/` exists.
///
/// The JavaScript below is copied out of QuartzControl 1.3's output and must stay word for word
/// what QuartzControl writes: both apps rewrite the same file before every build, and a project
/// opened in one after the other would otherwise change on every switch. Four values go in:
/// the frame's name, its areas as frame.json has them, the group orderings that can reach it
/// (`GroupLayouts`) and its CSS (`GridFrameCss`), each as `JSON.stringify` writes it.
/// The cross-check is `LayoutFramesTests`, byte for byte against QuartzControl's own files.
enum FrameModule {
  static func source(frameName: JSONValue?, areas: JSONValue?, groupLayouts: [GroupLayouts.Candidate], css: String) -> String {
    // Spliced in one pass: a frame name holding "@@AREAS@@" must stay a name.
    let values = [
      frameName.map(JSJSON.compact) ?? "undefined",
      areas.map(JSJSON.compact) ?? "undefined",
      JSJSON.compact(.array(groupLayouts.map(\.json))),
      JSJSON.compact(.string(css))
    ]
    var out = pieces[0]
    for (value, piece) in zip(values, pieces.dropFirst()) { out += value + piece }
    return out
  }

  static let pieces: [String] = {
    var rest = Substring(template), result: [String] = []
    for marker in ["@@FRAME_NAME@@", "@@AREAS@@", "@@GROUP_LAYOUTS@@", "@@CSS@@"] {
      let range = rest.range(of: marker)!
      result.append(String(rest[..<range.lowerBound]))
      rest = rest[range.upperBound...]
    }
    return result + [String(rest)]
  }()

  // ── copied ── from the output of layoutFrameService.ts (QuartzControl 1.3.0), placeholders @@…@@
  static let template = #"""
import { h, Fragment } from "preact"

const FRAME_NAME = @@FRAME_NAME@@
const AREAS = @@AREAS@@
const GROUP_LAYOUTS = @@GROUP_LAYOUTS@@

// What each area shows. Six positions is all quartz sorts components into
// (config-loader.ts's buildLayoutForEntries), so a frame with more component areas than that needs
// a second key, and quartz has one: `layout.group` collapses a position's grouped entries into a
// single Flex component (resolveGroups) and leaves the ungrouped ones as themselves. Measured on a
// real build, a position holding one group arrived as [MobileOnly, Flex, ExplorerComponent] - the
// group is a function literally named "Flex" (quartz builds itself with esbuild's keepNames), and
// `displayName` was undefined on every entry, so that name is the whole identity available here.
//
// So the k-th Flex in a position is the k-th group of the ordering, an area with a group takes its
// own, and the area without one takes everything else - including any group this frame gave no
// area, which would otherwise vanish from the page.
//
// Which ordering, though, is not a property of the config: quartz builds a layout per page type
// (loadQuartzLayout drops what `byPageType.<t>.exclude` names, runs buildLayoutForEntries on the
// rest, then empties the positions `positions` cleared), and it hands the frame the finished
// lists without ever saying which page type they belong to - PageFrameProps carries no name, and
// neither does componentData. Hence GROUP_LAYOUTS: every ordering that can reach this frame, and
// pickGroupOrder to work out which one arrived. A page type whose `template` names another frame
// is not in this list - see groupLayoutCandidates for why leaving it in was not harmless.
const POSITIONS = ["header", "beforeBody", "afterBody", "left", "right", "footer"]
// The positions this frame divides. Only these are ever taken apart, and only these decide when
// the counts of all six cannot (see pickGroupOrder). A position without a group area still speaks
// as evidence, but never about its own contents - it has none to get wrong, and a page type that
// merely cleared it was enough to spend the position's one warning before a real break could
// have it.
const SPLIT_POSITIONS = POSITIONS.filter((p) => AREAS.some((a) => a.slot === p && a.group))
const warned = new Set()

function orderOf(order, position) {
  return order[position] || []
}

function countsLike(order, counts, positions) {
  return positions.every((p) => orderOf(order, p).length === counts[p])
}

// The relaxed key of the second pass: every divided position exactly, every other one only as an
// upper bound. See pickGroupOrder for why the direction is the whole point.
function countsFit(order, counts) {
  return POSITIONS.every((p) =>
    SPLIT_POSITIONS.indexOf(p) === -1 ? orderOf(order, p).length >= counts[p] : orderOf(order, p).length === counts[p]
  )
}

function splitsAlike(a, b) {
  return SPLIT_POSITIONS.every((p) => orderOf(a, p).join("\u0000") === orderOf(b, p).join("\u0000"))
}

// Same groups on every divided position, whatever their order. The difference decides which of the
// two ambiguity messages is true: telling the groups apart by an ordering rule only works when
// there is an ordering to fix.
function namesAlike(a, b) {
  return SPLIT_POSITIONS.every(
    (p) => orderOf(a, p).slice().sort().join("\u0000") === orderOf(b, p).slice().sort().join("\u0000")
  )
}

function nameOf(candidate) {
  return candidate.pageType === null ? "the config as a whole" : 'page type "' + candidate.pageType + '"'
}

function countsOf(order) {
  return SPLIT_POSITIONS.map((p) => p + " " + orderOf(order, p).length).join(", ")
}

function renderedOf(counts, positions) {
  return positions.map((p) => p + " " + counts[p]).join(", ")
}

function groupsOf(order) {
  return SPLIT_POSITIONS.map((p) => p + ": " + (orderOf(order, p).join(", ") || "no group")).join("; ")
}

// The only thing a frame can measure about the layout it was handed is how many Flexes each
// position holds, so that is the whole key: the candidate whose group counts match is the one this
// page was built with. Exactly one match is the answer; several that name the same groups in the
// same order are the same answer said twice. Anything else means guessing, and a guess here is the
// one failure that cannot be seen on the built page - two areas quietly showing each other's
// contents - so it falls back to not splitting at all and says why.
//
// Matched in two passes, and the second pass is what keeps the first one honest. All six positions
// are the sharper key: one this frame does not divide can still be the only thing telling two page
// types apart, so it is asked first. But a count that disagrees *there* need not say the candidate
// is wrong - matching everywhere and nowhere else meant a group on `footer` that quartz renders no
// flex for emptied both group areas of `header` on every page of the site (measured: 201 of 201).
//
// So the second pass relaxes the positions this frame does not divide - but only in the one
// direction they can be wrong about *and still be this page*. A position that renders **fewer**
// flexes than the candidate describes has the ordinary explanation: a group whose members all got
// disabled, an entry whose `layout.group` quartz makes no flex for. A position that renders
// **more** has none - nothing about this page can add a group the ordering has never heard of, so
// that is the candidate contradicting itself, and it stays out. Measured, at the generated module
// and at a real build: dropping the outside positions entirely instead threw away the very
// evidence that kept a wrong candidate out. A break *inside* a divided position leaves a count
// there that some other page type happens to hit (one that excludes a whole group), and with the
// outside no longer looking, that candidate won - 203 of 211 editorial pages showed group
// `custom-8`'s components in the area of `custom-9`, under a warning that said the position had
// been "divided as usual". Asking for "described >= rendered" keeps the seventh review's case and
// puts that one back on the fallback, where it says the counts fit nothing.
//
// Only ever a widening of a match set that was empty - a candidate that fits all six exactly is
// still preferred over one that merely fits within the relaxed key.
function pickGroupOrder(bySlot) {
  if (SPLIT_POSITIONS.length === 0) return null
  const counts = {}
  for (const p of POSITIONS) counts[p] = (bySlot[p] || []).filter((C) => C.name === "Flex").length
  let matches = GROUP_LAYOUTS.filter((c) => countsLike(c.order, counts, POSITIONS))
  const relaxed = matches.length === 0
  if (relaxed) matches = GROUP_LAYOUTS.filter((c) => countsFit(c.order, counts))
  const order =
    matches.length === 1 || (matches.length > 1 && matches.every((c) => splitsAlike(c.order, matches[0].order)))
      ? matches[0].order
      : null
  // Once per distinct shape, not once per page: the same mismatch is true for every one of the
  // 100-odd pages built with this layout, and a warning repeated 300 times reads like noise.
  if (order && !relaxed) return order
  if (order) {
    // Divided as usual - but the config describes flexes somewhere this frame does not divide that
    // the page did not render. Nothing here changes what the areas show; it is said because "no
    // groups" and "a group whose members never render" look the same on the built page, and this
    // is the one place that can still tell them apart. Always fewer than described, never more -
    // countsFit does not let the other direction through.
    const off = POSITIONS.filter((p) => SPLIT_POSITIONS.indexOf(p) === -1 && orderOf(order, p).length !== counts[p])
    const key = "undivided@" + renderedOf(counts, off)
    if (!warned.has(key)) {
      warned.add(key)
      // The counts named here are the chosen ordering's. Several candidates can divide alike and
      // still describe these positions differently, and then this one is an arbitrary pick among
      // equals - so it says so rather than naming one as if it were the only fit.
      const alsoFit = matches.filter((c) => POSITIONS.some((p) => orderOf(c.order, p).length !== orderOf(order, p).length))
      console.warn(
        "[" + FRAME_NAME + "] " +
          off.map((p) => p + " renders " + counts[p] + " group flex(es), not the " + orderOf(order, p).length + " " +
            nameOf(matches[0]) + " describes").join("; ") + ". " +
          (alsoFit.length > 0
            ? "(" + alsoFit.map(nameOf).join(" and ") + " divide" + (alsoFit.length === 1 ? "s" : "") +
              " these positions the same way and would fit too.) "
            : "") +
          "This frame divides none of those positions, so " + SPLIT_POSITIONS.join(" and ") + " was divided as usual. " +
          "Usually a group whose members all got disabled, or an entry whose layout.group quartz renders no flex for."
      )
    }
    return order
  }
  const key = matches.length + "@" + renderedOf(counts, SPLIT_POSITIONS)
  if (!warned.has(key)) {
    warned.add(key)
    const rendered = renderedOf(counts, SPLIT_POSITIONS)
    if (matches.length === 0) {
      // A candidate can hit every divided position and still be out, ruled out by a position
      // outside them where this page rendered a group flex it has no group for (countsFit). The
      // list below only shows the divided positions, so without this clause the message would say
      // "no layout produces header 1" while printing a layout that says header 1 - and the one
      // thing that actually ruled it out would be the one thing left unsaid.
      const contradicted = GROUP_LAYOUTS.filter((c) => countsLike(c.order, counts, SPLIT_POSITIONS)).map(
        (c) =>
          nameOf(c) + " fits that, but " +
          POSITIONS.filter((p) => SPLIT_POSITIONS.indexOf(p) === -1 && counts[p] > orderOf(c.order, p).length)
            .map((p) => p + " renders " + counts[p] + " group flex(es) it has no group for")
            .join(" and ")
      )
      console.warn(
        "[" + FRAME_NAME + "] this page renders " + rendered + " group flex(es), which no layout in " +
          "quartz.config.yaml accounts for (" + GROUP_LAYOUTS.map((c) => nameOf(c) + ": " + countsOf(c.order)).join("; ") + "). " +
          (contradicted.length > 0 ? contradicted.join("; ") + ". " : "") +
          "Not splitting: every position's area without a group takes the lot, the group areas stay empty. " +
          "Usually a group whose members all got disabled, or a quartz.config.yaml edited by hand since this frame was written."
      )
    } else if (matches.every((c) => namesAlike(c.order, matches[0].order))) {
      console.warn(
        "[" + FRAME_NAME + "] this page renders " + rendered + " group flex(es), which fits " +
          matches.map(nameOf).join(" and ") + " - and they order the groups differently (" +
          matches.map((c) => nameOf(c) + " -> " + groupsOf(c.order)).join("; ") + "). " +
          "Not splitting, because guessing would swap what the areas show. Give those groups an explicit " +
          "priority under layout.groups so their order is the same for every page type."
      )
    } else {
      // Not a question of order at all: these name *different* groups, so there is nothing an
      // ordering rule could line up - measured, with and without layout.groups priorities, the same
      // message and the same fallback word for word. Two page types that each drop a whole group
      // are indistinguishable from in here, because the flex count is the only thing this can
      // measure and both produce the same one. Both ways out are measured too: keeping one member
      // of each group leaves both groups standing, which collapses the candidates into one; and
      // clearing the position for one page type makes its count differ, which tells them apart.
      console.warn(
        "[" + FRAME_NAME + "] this page renders " + rendered + " group flex(es), which fits " +
          matches.map(nameOf).join(" and ") + " - and they name different groups there (" +
          matches.map((c) => nameOf(c) + " -> " + groupsOf(c.order)).join("; ") + "). " +
          "Not splitting, because guessing would put one group's components in the other's area - and no " +
          "priority under layout.groups can line up groups that are not the same ones. All this can " +
          "measure is how many flexes arrived, and excluding a whole group per page type leaves both of " +
          "these with the same number. Leave one member of each group in place to keep both groups and " +
          "both counts, or clear the position for one of the page types so the counts differ."
      )
    }
  }
  return null
}

function contentsFor(area, list, order) {
  if (!area.slot || area.slot === "pageBody") return list
  // No area of this frame divides this position, so there is nothing to take apart - and nothing
  // to warn about either, whatever the config says about groups here.
  if (!AREAS.some((a) => a.slot === area.slot && a.group)) return list
  const groups = order ? orderOf(order, area.slot) : []
  if (groups.length === 0) return area.group ? [] : list
  // Guaranteed equal in length: pickGroupOrder only returns an ordering whose group count matches
  // the Flexes of every position it divides, and this line is only reached for one it divides (the
  // early return above). It returns null when no candidate does. The relaxed second pass loosens
  // the *other* positions, never these.
  const flexes = list.filter((C) => C.name === "Flex")
  if (area.group) {
    // Nothing else in this position has an area to go to, so the components that are in no group
    // are about to be dropped from every page. Measured on a real build: two group areas on
    // `left` and no plain one took the spacer and both toggles off all 20 pages, and neither the
    // editor nor the build said a word. The editor warns about the shape now; this says what it
    // actually cost.
    const plain = AREAS.filter((a) => a.slot === area.slot && !a.group)
    if (plain.length === 0 && !warned.has("homeless:" + area.slot)) {
      warned.add("homeless:" + area.slot)
      const claimed = AREAS.filter((a) => a.slot === area.slot && a.group).map((a) => groups.indexOf(a.group))
      const lost = list.filter((C, i) => C.name !== "Flex" || claimed.indexOf(flexes.indexOf(C)) === -1).length
      if (lost > 0) {
        // "entries", not "components": one of them may be another group's Flex, which is one
        // entry and any number of components, and this cannot see inside it. An understated
        // number would be worse than a vague noun.
        console.warn(
          "[" + FRAME_NAME + "] " + area.slot + ": every area here has a group, so " + lost + " entr" +
            (lost === 1 ? "y" : "ies") + " outside those groups render on no page. " +
            "Give the position an area without a group to hold them."
        )
      }
    }
    const rank = groups.indexOf(area.group)
    return rank === -1 ? [] : [flexes[rank]]
  }
  // The plain area keeps every group no area of this frame claimed, in place among the others.
  const claimed = AREAS.filter((a) => a.slot === area.slot && a.group).map((a) => groups.indexOf(a.group))
  return list.filter((C) => C.name !== "Flex" || claimed.indexOf(flexes.indexOf(C)) === -1)
}

export const Frame = {
  name: FRAME_NAME,
  css: @@CSS@@,
  render(props) {
    const { componentData, header, beforeBody, pageBody, afterBody, left, right, footer } = props
    const bySlot = { header, beforeBody, afterBody, left, right, footer, pageBody: [pageBody] }
    // Once per page, not once per area: the decision is about the whole layout that arrived.
    const order = pickGroupOrder(bySlot)
    return h(
      Fragment,
      null,
      h(
        "div",
        { class: "qgframe-grid" },
        AREAS.map((area) => {
          // An area without a slot is an empty cell by design (a spacer) - see GridFrameArea.
          const components = area.slot ? contentsFor(area, bySlot[area.slot] ?? [], order) : []
          // The area holding pageBody also carries `center`, because quartz's own three frames
          // do (DefaultFrame/FullWidthFrame/MinimalFrame all render <div class="center …">) and
          // client scripts rely on it: the mermaid initialiser runs
          // `document.querySelector(".center").querySelectorAll("code.mermaid")` unconditionally
          // on every page. Without the class that threw a TypeError inside the nav handler, which
          // aborted every component script registered after it - measured on a real build, where
          // the explorer rendered its container but never its tree or its title. The class alone
          // is inert for layout here: base.scss only uses it for `.center > article { grid-area }`
          // (no effect on a flex child) and for its .full-width/.minimal variants.
          const isPageBody = area.slot === "pageBody"
          return h(
            "div",
            {
              key: area.id,
              class: "qgframe-area qgframe-area-" + area.name + (isPageBody ? " center" : "")
            },
            components.map((Component) => h(Component, componentData))
          )
        })
      )
    )
  }
}

"""#
}
