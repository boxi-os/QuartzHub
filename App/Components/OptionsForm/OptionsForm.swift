import QuartzHubCore
import SwiftUI

/// A plugin entry's `options` as a form built from what the plugin says about them
/// (QuartzControl's `components/PluginOptionsForm`). Not tied to the Plugins page: the Layout page's
/// inspector shows the same form.
///
/// - a field shows its value, or the plugin's default where none is set; resetting removes the key
/// - a field whose condition (`x-quartz-when`) does not hold stays in its group with "wirkt nicht"
///   and the reason: greyed where it stands, never disabled
/// - keys the config sets and no schema names stand under "Unbekannte Schlüssel"; the free
///   key/value row beside them only where the schema does not describe every option
/// - named groups fold; above eight options a search narrows the form, the groups keep their titles
///
/// `onChange` gets the whole new options object, or nil when nothing is left. Text fields write
/// when they are left or on Return, as QuartzControl's did on blur. It renders `Section`s and so
/// belongs in a grouped `Form`.
struct OptionsForm: View {
  let schema: NormalizedOptionSchema?
  let values: JSONObject
  let onChange: (JSONObject?) -> Void
  var explicitEmpty = false
  var languages: [String] = []
  /// Only the options this accepts, for a caller that shows the rest elsewhere.
  var pick: ((String) -> Bool)?
  /// The free key/value row; off in the editors that know every option.
  var freeKeys = true
  var root: RootExtras?
  /// The project the options belong to, for the editors that read and write its files (snippets);
  /// without it they are text fields.
  var projectPath: String?

  @State private var search = ""

  private static let searchFrom = 8

  private var language: OptionFormText.Language { L10n.language == "en" ? .en : .de }

  private var merged: NormalizedOptionSchema {
    let all = OptionSchema.withPresentKeys(schema ?? .empty, .object(values))
    guard let pick else { return all }
    var picked = all
    picked.fields = all.fields.filter { pick($0.key) }
    return picked
  }

  var body: some View {
    let merged = merged
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let context = OptionsFormContext(language: language, explicitEmpty: explicitEmpty, languages: languages, query: query,
                                     mark: query, entryReason: root?.entryReason, projectPath: projectPath)
    let incomplete = schema == nil || schema?.source == .defaults || !(schema?.notes.isEmpty ?? true)
    if merged.fields.count >= Self.searchFrom || schema?.source == .defaults || merged.fields.isEmpty || !(schema?.notes.isEmpty ?? true) {
      Section {
        if merged.fields.count >= Self.searchFrom {
          TextField(L10n.t("pluginOptions.searchPlaceholder"), text: $search, prompt: Text(L10n.t("pluginOptions.searchPlaceholder")))
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            .accessibilityIdentifier("options.search")
          if !query.isEmpty, !merged.fields.contains(where: { OptionFormText.match($0, query: query, language) != .none }) {
            Note(L10n.t("pluginOptions.noMatch"))
          }
        }
        if schema?.source == .defaults { Note(L10n.t("pluginOptions.fromDefaults")) }
        if merged.fields.isEmpty { Note(L10n.t("pluginOptions.none")) }
        // What the reader could not read, counted rather than passed over, in the reader's words.
        if let notes = schema?.notes, !notes.isEmpty {
          Fold(L10n.t("pluginOptions.notes", ["count": String(notes.count)], count: notes.count)) {
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
              Text(verbatim: (note.path.isEmpty ? "" : note.path.joined(separator: ".") + ": ") + note.reason)
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            }
          }
          .font(.callout)
        }
      }
    }
    ObjectBlock(fields: merged.fields, values: values, onValue: { onChange($0.isEmpty ? nil : $0) }, context: context, root: root,
                topLevel: true, freeRow: freeKeys && incomplete)
  }
}

/// What the editors with tiles above the form add on the top level (`OptionRoot` in the core,
/// where the editors' tables build it).
typealias RootExtras = OptionRoot

struct OptionsFormContext {
  var language: OptionFormText.Language
  var explicitEmpty: Bool
  var languages: [String]
  /// The search, lower-cased; empty under a field that matched by its own words.
  var query: String
  /// The search for marking it in the texts; kept under such a field.
  var mark: String
  /// Inside an option that does nothing right now: the labels below are muted too.
  var muted = false
  var entryReason: ((String, JSONObject, JSONObject) -> String?)?
  var projectPath: String?
  /// What "wie oben" is called where the values above are known by another name.
  var above: (short: String, choice: String)?
}

/// Where a condition inside a record entry looks for what it does not find in the entry itself:
/// layout-box's byLang entries are laid over the options above them.
struct Inherited {
  var values: JSONObject
  var fields: [OptionField]
}

extension JSONObject {
  /// `{ ...self, ...over }`.
  func merging(_ over: JSONObject) -> JSONObject {
    var merged = self
    for key in over.keys { merged[key] = over[key] }
    return merged
  }
}

extension JSONValue {
  var isEmptyObject: Bool { if case .object(let object) = self { object.isEmpty } else { false } }
}

// MARK: - One object

struct ObjectBlock: View {
  let fields: [OptionField]
  let values: JSONObject
  let onValue: (JSONObject) -> Void
  let context: OptionsFormContext
  var inherit: Inherited?
  var root: RootExtras?
  /// Sections in the page's Form, or a stack inside a row.
  var topLevel = false
  var freeRow = false

  private func set(_ key: String, _ value: JSONValue?) {
    let value = value?.isEmptyObject == true ? nil : value
    onValue(OptionSchema.setting(value, at: [key], in: values))
  }

  private var conditionValues: JSONObject { inherit.map { $0.values.merging(values) } ?? values }
  private var conditionFields: [OptionField] { inherit?.fields ?? fields }

  /// Why a field does nothing now, or nil. The app's reason first: where it has one, it names the
  /// variants, which says more than the schema's condition on the same field.
  private func inactiveReason(_ field: OptionField) -> String? {
    if let reason = root?.inactiveReason?(field.key) { return reason }
    if let inherit, let reason = context.entryReason?(field.key, values, inherit.values) { return reason }
    if OptionSchema.evaluate(field.when, values: .object(conditionValues), fields: conditionFields) { return nil }
    return OptionFormText.conditionText(field, siblings: conditionFields, context.language,
                                        keyPrefix: inherit != nil ? "" : (root?.keyPrefix ?? ""))
  }

  private func match(_ field: OptionField) -> OptionFormText.Match {
    OptionFormText.match(field, query: context.query, context.language)
  }

  var body: some View {
    let searching = !context.query.isEmpty
    let shown = OptionFormText.ordered(fields).filter { field in
      searching || values[field.key] != nil || !(root?.hideUnlessSet?(field.key) ?? false) || inactiveReason(field) == nil
    }
    let found = shown.filter { match($0) != .none }
    let described = found.filter { $0.origin != .config }
    let unknown = found.filter { $0.origin == .config }
    let lead = root?.lead
    // In the lead, what works comes first; in the groups below every field keeps its place.
    let leading = lead.map { lead in
      described.filter { lead.has($0.key) }.enumerated()
        .sorted { (inactiveReason($0.element) != nil ? 1 : 0, $0.offset) < (inactiveReason($1.element) != nil ? 1 : 0, $1.offset) }
        .map(\.element)
    } ?? []
    let rest = lead.map { lead in described.filter { !lead.has($0.key) } } ?? described
    let groups = OptionFormText.groups(rest, context.language)

    if let lead, !leading.isEmpty || !searching {
      group(title: lead.title, aside: searching ? L10n.t("pluginOptions.matches", ["count": String(leading.count)], count: leading.count) : nil,
            fold: nil) {
        if let note = lead.note { Note(note) }
        if leading.isEmpty { Note(lead.empty) } else { rows(leading) }
      }
    }
    ForEach(Array(groups.enumerated()), id: \.offset) { index, entry in
      if let title = entry.group, !(root?.flat ?? false) {
        let changed = entry.fields.filter { values[$0.key] != nil }.count
        let count = entry.fields.count
        group(title: title,
              aside: searching ? L10n.t("pluginOptions.matches", ["count": String(count)], count: count)
                : changed > 0 ? L10n.t("pluginOptions.groupCountChanged", ["count": String(count), "changed": String(changed)]) : String(count),
              fold: (open: lead == nil && (index == 0 || changed > 0), locked: searching)) {
          rows(entry.fields)
        }
      } else {
        group(title: entry.group, aside: nil, fold: nil) { rows(entry.fields) }
      }
    }
    if !unknown.isEmpty || (freeRow && !searching) {
      group(title: root?.flat == true && described.isEmpty ? nil : unknown.isEmpty ? L10n.t("pluginOptions.freeKey") : L10n.t("pluginOptions.moreKeys"),
            aside: nil, fold: nil) {
        if !unknown.isEmpty { Note(L10n.t("pluginOptions.moreKeysHint")) }
        ForEach(unknown, id: \.key) { row($0) }
        if freeRow, !searching {
          AddOptionRow(existing: values.keys) { key, value in set(key, value) }
        }
      }
    }
  }

  /// A group's rarely needed fields stay in it, after the others.
  @ViewBuilder private func rows(_ list: [OptionField]) -> some View {
    ForEach(list.filter { !$0.advanced }, id: \.key) { row($0) }
    let rare = list.filter(\.advanced)
    if !rare.isEmpty {
      Text(L10n.t("pluginOptions.rarelyUsed")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
      ForEach(rare, id: \.key) { row($0) }
    }
  }

  private func row(_ field: OptionField) -> some View {
    let searching = !context.query.isEmpty
    let reason = inactiveReason(field)
    var rowContext = context
    if searching, match(field) == .own { rowContext.query = "" }
    return FieldRow(field: field, value: values[field.key], onValue: { set(field.key, $0) }, context: rowContext,
                    inherit: Inherited(values: conditionValues, fields: conditionFields), inherited: fallback(field),
                    inactive: reason, keyLabel: root?.keyPrefix.map { $0 + field.key })
  }

  /// In a record entry an unset field is not "the plugin's default" but "what stands above".
  private func fallback(_ field: OptionField) -> JSONValue?? {
    guard let inherit else { return nil }
    if let value = inherit.values[field.key] { return .some(value) }
    if let above = inherit.fields.first(where: { $0.key == field.key }), above.hasDefault { return .some(above.defaultValue) }
    return nil
  }

  /// A section of the page's Form on the top level, a titled stack inside a row. `fold`: a group
  /// that folds, open from the start or not, and held open while searching.
  @ViewBuilder private func group<Content: View>(title: String?, aside: String?, fold: (open: Bool, locked: Bool)?,
                                                 @ViewBuilder content: @escaping () -> Content) -> some View {
    if let fold, let title {
      FoldGroup(title: title, aside: aside, initiallyOpen: fold.open, locked: fold.locked, mark: context.mark, topLevel: topLevel,
                content: content)
    } else if topLevel {
      Section {
        content()
      } header: {
        if let title { GroupTitle(title: title, aside: aside, mark: context.mark) }
      }
    } else {
      VStack(alignment: .leading, spacing: 10) {
        if let title { GroupTitle(title: title, aside: aside, mark: context.mark) }
        content()
      }
    }
  }
}

private struct GroupTitle: View {
  let title: String
  let aside: String?
  let mark: String

  var body: some View {
    HStack {
      Marked(text: title, query: mark)
      Spacer()
      if let aside { Text(aside).foregroundStyle(.secondary).monospacedDigit() }
    }
  }
}

/// A group of options that folds, with its count on the right; while searching it is held open.
private struct FoldGroup<Content: View>: View {
  let title: String
  let aside: String?
  let initiallyOpen: Bool
  let locked: Bool
  let mark: String
  let topLevel: Bool
  @ViewBuilder let content: () -> Content

  @State private var open: Bool?

  var body: some View {
    let binding = Binding(get: { locked || (open ?? initiallyOpen) }, set: { if !locked { open = $0 } })
    let disclosure = Fold(isExpanded: binding) {
      VStack(alignment: .leading, spacing: 12) { content() }
        .padding(.top, 6)
    } label: {
      // The whole band folds (`Fold`), as QuartzControl's `FoldBox` is one button; on its own,
      // the disclosure group answered only its chevron (measured 2026-11-09).
      GroupTitle(title: title, aside: aside, mark: mark).fontWeight(.medium)
    }
    if topLevel {
      Section { disclosure }
    } else {
      disclosure
    }
  }
}

/// The text with each place the search matches marked, as `fieldMatch` matches: lower-cased,
/// anywhere.
struct Marked: View {
  let text: String
  let query: String

  var body: some View {
    Text(Self.attributed(text, query))
  }

  /// Found case-insensitively in the text itself, so a range of the text is a range of what is
  /// shown; marking is a help to the eye, the search that filters is `OptionFormText.match`.
  static func attributed(_ text: String, _ query: String) -> AttributedString {
    var result = AttributedString(text)
    guard !query.isEmpty else { return result }
    var from = text.startIndex
    while from < text.endIndex, let found = text.range(of: query, options: [.caseInsensitive, .literal], range: from..<text.endIndex) {
      if let range = Range(found, in: result) { result[range].backgroundColor = .yellow.opacity(0.45) }
      from = found.upperBound
    }
    return result
  }
}

// MARK: - The free key/value row

/// A key no schema names, typed in by hand.
private struct AddOptionRow: View {
  let existing: [String]
  let add: (String, JSONValue) -> Void

  @State private var key = ""
  @State private var value = ""

  var body: some View {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    let duplicate = existing.contains(trimmed)
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        TextField(L10n.t("pluginsInstalled.optionKeyPlaceholder"), text: $key, prompt: Text(L10n.t("pluginsInstalled.optionKeyPlaceholder")))
          .labelsHidden().font(.system(.body, design: .monospaced)).frame(maxWidth: 140)
        TextField(L10n.t("pluginsInstalled.optionValuePlaceholder"), text: $value, prompt: Text(L10n.t("pluginsInstalled.optionValuePlaceholder")))
          .labelsHidden().font(.system(.body, design: .monospaced))
        Button(L10n.t("pluginsInstalled.addOption")) {
          add(trimmed, OptionFormText.typedValue(value))
          key = ""
          value = ""
        }
        .disabled(trimmed.isEmpty || duplicate)
      }
      .textFieldStyle(.roundedBorder)
      Text(duplicate ? L10n.t("pluginsInstalled.optionKeyExists") : L10n.t("pluginsInstalled.optionValueHint"))
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }
}
