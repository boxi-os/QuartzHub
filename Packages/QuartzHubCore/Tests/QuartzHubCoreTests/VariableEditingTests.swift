import Foundation
import Testing
@testable import QuartzHubCore

/// VariableEditing: the rules of QuartzControl's VariableRow.tsx, one case per review that found them.
struct VariableEditingTests {
  typealias O = VariableResolve.Override

  /// A graph with `secondary` differing between the modes (gui-test's), `space` the same in both,
  /// `gray` with a lower-case hex.
  static func context(_ overrides: [(key: String, value: O)]) -> VariableResolve.Context {
    let vars = JSONObject([
      ("secondary", .object(JSONObject([("origin", .string("build")), ("light", .string("#284b63")), ("dark", .string("#84a59d"))]))),
      ("space", .object(JSONObject([("origin", .string("build")), ("light", .string("2rem")), ("dark", .string("2rem"))]))),
      ("gray", .object(JSONObject([("origin", .string("build")), ("light", .string("#999999")), ("dark", .string("#a1a1a1"))]))),
      ("weight", .object(JSONObject([("origin", .string("theme")), ("light", .string("400")), ("dark", .string("500"))])))
    ])
    return VariableResolve.Context(vars: vars, overrides: overrides, colors: JSONObject(), typography: nil)
  }

  @Test func aLightEditKeepsTheDarkHalfOfAVariableThatDiffers() {
    // 1.0.1: the dark half became '' and the site showed the new light colour in dark mode too.
    let edit = VariableEditing(key: "secondary", context: Self.context([]), moved: false)
    #expect(edit.setting(.light, "#ff0000") == O(light: "#ff0000", dark: "#84a59d"))
    // Moved: written for light mode only, the dark mode keeps the theme's value.
    let moved = VariableEditing(key: "secondary", context: Self.context([]), moved: true)
    #expect(moved.setting(.light, "#ff0000") == O(light: "#ff0000", dark: "", lightOnly: true))
    #expect(moved.setting(.light, "#284b63") == nil)
  }

  @Test func aVariableTheSameInBothModesStaysOneDeclaration() {
    let edit = VariableEditing(key: "space", context: Self.context([]), moved: true)
    #expect(edit.setting(.light, "3rem") == O(light: "3rem", dark: ""))
    #expect(edit.setting(.light, "2rem") == nil)
    #expect(edit.setting(.dark, "1rem") == O(light: "2rem", dark: "1rem"))
  }

  @Test func aDarkHalfThatRepeatsTheBaseCountsAsUnset() {
    // gui-test's --gray: the file holds what was typed (#A1A1A1), the graph hands #a1a1a1.
    let ctx = Self.context([("gray", O(light: "#B0B0B0", dark: "#A1A1A1"))])
    let edit = VariableEditing(key: "gray", context: ctx, moved: true)
    #expect(edit.setting(.light, "#c0c0c0") == O(light: "#c0c0c0", dark: "", lightOnly: true))
    // Not moved: the dark half is written explicitly, as 1.0.x reads it.
    let unmoved = VariableEditing(key: "gray", context: ctx, moved: false)
    #expect(unmoved.setting(.light, "#c0c0c0") == O(light: "#c0c0c0", dark: "#A1A1A1"))
  }

  @Test func theDraft() {
    // A light-only override leaves the dark mode to the theme, and the field shows the theme's value.
    let lightOnly = VariableEditing(key: "secondary", context: Self.context([("secondary", O(light: "#f00", dark: "", lightOnly: true))]), moved: true)
    #expect(lightOnly.draft == O(light: "#f00", dark: "#84a59d"))
    // Without a dark half the dark field shows the light value, which is what applies there.
    let noDark = VariableEditing(key: "secondary", context: Self.context([("secondary", O(light: "#f00"))]), moved: false)
    #expect(noDark.draft == O(light: "#f00", dark: "#f00"))
    // An emptied light field stays empty instead of jumping back to the base under the cursor.
    let emptied = VariableEditing(key: "space", context: Self.context([("space", O(light: ""))]), moved: false)
    #expect(emptied.draft == O(light: "", dark: "2rem"))
    let none = VariableEditing(key: "secondary", context: Self.context([]), moved: false)
    #expect(none.draft == O(light: "#284b63", dark: "#84a59d"))
  }

  @Test func anOwnVariableIsNeverTakenAwayByAnEdit() {
    let edit = VariableEditing(key: "tpl-space", context: Self.context([("tpl-space", O(light: "1rem"))]), moved: true)
    #expect(edit.isOwn)
    #expect(edit.setting(.light, "") == O(light: "", dark: ""))
    #expect(edit.followingLight() == O(light: "1rem", dark: ""))
  }

  @Test func followingLightTakesTheDarkHalfAway() {
    let edit = VariableEditing(key: "space", context: Self.context([("space", O(light: "3rem", dark: "1rem"))]), moved: true)
    #expect(edit.followingLight() == O(light: "3rem", dark: ""))
    let back = VariableEditing(key: "space", context: Self.context([("space", O(light: "2rem", dark: "1rem"))]), moved: true)
    #expect(back.followingLight() == nil)
  }

  @Test func whenTwoFieldsShow() {
    let ctx = Self.context([])
    #expect(VariableEditing(key: "secondary", context: ctx, moved: true).splitModes(context: ctx, darkOpen: false))
    #expect(!VariableEditing(key: "space", context: ctx, moved: true).splitModes(context: ctx, darkOpen: false))
    // No colour, but the theme has another value in dark mode.
    #expect(VariableEditing(key: "weight", context: ctx, moved: true).splitModes(context: ctx, darkOpen: false))
    #expect(VariableEditing(key: "space", context: ctx, moved: true).splitModes(context: ctx, darkOpen: true))
    let split = Self.context([("space", O(light: "3rem", dark: "1rem"))])
    #expect(VariableEditing(key: "space", context: split, moved: true).splitModes(context: split, darkOpen: false))
  }
}
