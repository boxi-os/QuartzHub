import QuartzHubCore
import SwiftUI

/// Übersetzungen: the fixed texts of the site in the locale files the project ships
/// (QuartzControl's `ConfigEditor/Localization.tsx`). One locale at a time, with a search; saved
/// per locale by the button beside it, not by the page's "Speichern".
///
/// The chosen locale, the search and the unsaved edits survive a trip to another page, as
/// QuartzControl's `useStickyState` did: kept in memory per project (`LocalizationModel.forProject`).
/// The entries under them are read from disk again every time.
struct LocalizationTab: View {
  @Bindable var model: LocalizationModel
  /// The locale quartz.config.yaml names, the first choice when nothing was picked yet.
  let configured: String?

  var body: some View {
    Form {
      if let error = model.listError {
        Section {
          Text(L10n.t("localization.loadFailed")).fontWeight(.medium).foregroundStyle(.red)
          Text(error).font(.system(.callout, design: .monospaced)).foregroundStyle(.red).textSelection(.enabled)
        }
      } else if let locales = model.locales {
        if locales.isEmpty {
          Section { Text(L10n.t("localization.none")).foregroundStyle(.secondary).accessibilityIdentifier("localization.none") }
        } else {
          protection
          toolbarSection(locales)
          entries
        }
      } else {
        Section { Text(L10n.t("common.loading")).foregroundStyle(.secondary) }
      }
    }
    .formStyle(.grouped)
    .task { await model.load(configured: configured) }
    .onChange(of: model.code) { _, _ in Task { await model.loadEntries() } }
  }

  private var protection: some View {
    Section {
      HStack {
        if model.gitAttributesActive == true {
          StateBadge(text: L10n.t("localization.gitAttributesOk"), color: .green)
        } else {
          StateBadge(text: L10n.t("localization.gitAttributesMissing"), color: .orange)
          Spacer()
          Button(L10n.t("localization.gitAttributesEnable")) { Task { await model.enableProtection() } }
            .disabled(model.enabling)
        }
      }
      Note(L10n.t("localization.gitAttributesExplain"))
    }
  }

  /// Save beside the locale it saves: the two describe one action together.
  private func toolbarSection(_ locales: [String]) -> some View {
    Section {
      HStack(spacing: 10) {
        Picker(L10n.t("siteSettings.locale"), selection: $model.code) {
          ForEach(locales, id: \.self) { Text(verbatim: $0).tag($0) }
        }
        // Named by its hidden title: an added label made VoiceOver read "Sprache der Website,
        // Sprache der Website" (measured 2026-11-09).
        .labelsHidden()
        .fixedSize()
        TextField(L10n.t("localization.searchPlaceholder"), text: $model.query, prompt: Text(L10n.t("localization.searchPlaceholder")))
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
        if !model.dirtyKeys.isEmpty {
          Text(L10n.t("localization.unsavedCount", ["count": String(model.dirtyKeys.count)], count: model.dirtyKeys.count))
            .font(.callout).foregroundStyle(.orange).fixedSize()
            .accessibilityIdentifier("localization.unsaved")
        }
        Button(model.saving ? L10n.t("common.saving") : L10n.t("common.save")) { Task { await model.saveAll() } }
          .disabled(model.saving || model.dirtyKeys.isEmpty)
          .accessibilityIdentifier("localization.save")
      }
    }
  }

  @ViewBuilder private var entries: some View {
    if let error = model.entriesError {
      Section {
        Text(L10n.t("localization.localeLoadFailed", ["code": model.code])).fontWeight(.medium).foregroundStyle(.red)
        Text(error).font(.system(.callout, design: .monospaced)).foregroundStyle(.red).textSelection(.enabled)
      }
    } else if model.entries == nil {
      Section { Text(L10n.t("common.loading")).foregroundStyle(.secondary) }
    } else {
      let shown = model.filtered
      Section {
        if shown.isEmpty {
          Text(L10n.t("localization.noResults")).foregroundStyle(.secondary)
        }
        ForEach(shown, id: \.key) { item in
          EntryRow(model: model, entry: item.entry, key: item.key)
        }
      }
    }
  }
}

private struct EntryRow: View {
  @Bindable var model: LocalizationModel
  let entry: LocaleFiles.Entry
  let key: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Text(verbatim: key).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
        if entry.kind == .template {
          Text(L10n.t("localization.advancedBadge"))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(.quaternary))
        }
      }
      // The key is the field's name: a hundred fields called "Text" would be no help.
      if entry.kind == .string {
        TextField(key, text: binding).labelsHidden().textFieldStyle(.roundedBorder)
      } else {
        TextField(key, text: binding, axis: .vertical)
          .labelsHidden()
          .textFieldStyle(.roundedBorder)
          .font(.system(.callout, design: .monospaced))
          .lineLimit(2...8)
      }
      if let error = model.errors[key] {
        Text(error).font(.caption).foregroundStyle(.red)
      }
    }
    .accessibilityElement(children: .contain)
  }

  private var binding: Binding<String> {
    Binding(get: { model.edits[key] ?? entry.value }, set: { model.edits[key] = $0 })
  }
}

@MainActor @Observable
final class LocalizationModel {
  /// One per project for the app's lifetime: what QuartzControl's sticky state kept across pages.
  private static var models: [String: LocalizationModel] = [:]

  static func forProject(_ project: ProjectContext) -> LocalizationModel {
    if let model = models[project.id] { return model }
    let model = LocalizationModel(path: project.path)
    models[project.id] = model
    return model
  }

  let path: String
  private(set) var locales: [String]?
  private(set) var listError: String?
  var code = ""
  private(set) var entries: [LocaleFiles.Entry]?
  private(set) var entriesError: String?
  var edits: [String: String] = [:]
  private(set) var errors: [String: String] = [:]
  var query = ""
  private(set) var saving = false
  private(set) var gitAttributesActive: Bool?
  private(set) var enabling = false
  /// The locale the edits belong to: a real switch drops them, coming back to the page does not.
  private var editsCode: String?

  init(path: String) {
    self.path = path
  }

  private func files() async -> LocaleFiles { LocaleFiles(environment: await AppServices.current()) }

  func load(configured: String?) async {
    let files = await files()
    let path = path
    do {
      let list = try await Task.detached { try files.list(project: path) }.value
      locales = list
      listError = nil
      // A locale picked in this session wins over the configured one; then the configured one;
      // then the first.
      if !list.contains(code) {
        code = configured.flatMap { list.contains($0) ? $0 : nil } ?? list.first ?? ""
      }
      await loadEntries()
    } catch {
      listError = String(describing: error)
    }
    gitAttributesActive = await files.gitAttributesActive(project: path)
  }

  func loadEntries() async {
    guard !code.isEmpty else { return }
    if let editsCode, editsCode != code {
      edits = [:]
      errors = [:]
    }
    editsCode = code
    entries = nil
    entriesError = nil
    let asked = code
    do {
      let read = try await files().entries(project: path, code: asked)
      guard asked == code else { return }
      entries = read
    } catch {
      guard asked == code else { return }
      entriesError = String(describing: error)
    }
  }

  static func key(_ entry: LocaleFiles.Entry) -> String { entry.path.joined(separator: ".") }

  var dirtyKeys: [String] {
    (entries ?? []).compactMap { entry in
      let key = Self.key(entry)
      guard let edit = edits[key], edit != entry.value else { return nil }
      return key
    }
  }

  var filtered: [(key: String, entry: LocaleFiles.Entry)] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return (entries ?? []).map { (Self.key($0), $0) }.filter { item in
      q.isEmpty || item.0.lowercased().contains(q) || item.1.value.lowercased().contains(q)
    }
  }

  func saveAll() async {
    guard let entries, !saving else { return }
    saving = true
    defer { saving = false }
    let files = await files()
    let dirty = Set(dirtyKeys)
    var failed: [String: String] = [:]
    for entry in entries where dirty.contains(Self.key(entry)) {
      let key = Self.key(entry)
      do {
        let result = try await files.save(project: path, code: code, path: entry.path, kind: entry.kind, value: edits[key] ?? entry.value)
        if !result.success { failed[key] = result.error ?? L10n.t("localization.saveError") }
      } catch {
        failed[key] = String(describing: error)
      }
    }
    errors = failed
    if let fresh = try? await files.entries(project: path, code: code) {
      self.entries = fresh
      for entry in fresh where failed[Self.key(entry)] == nil { edits[Self.key(entry)] = nil }
    }
    gitAttributesActive = await files.gitAttributesActive(project: path)
    Announce.post(failed.isEmpty ? L10n.t("common.saved") : L10n.t("localization.saveError"))
  }

  /// For a project with translations to protect that was not edited here yet: the badge would
  /// otherwise only state a problem QuartzHub can fix itself.
  func enableProtection() async {
    enabling = true
    defer { enabling = false }
    let files = await files()
    await files.ensureGitAttributes(project: path)
    gitAttributesActive = await files.gitAttributesActive(project: path)
  }
}
