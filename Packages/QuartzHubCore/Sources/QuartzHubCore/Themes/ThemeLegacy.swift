import Foundation

/// What a project keeps from core 2 that core 3 does not use, and taking it away on request
/// (docs/plan-themes-core-3.md, step 5). Three kinds, each measured against core 3.1.1:
///
/// - **Packages** `@quartz-themes/<id>` in package.json (not `core`): core 3 loads every theme
///   itself; the old packages have no peer dependency and only lie around after the core update
///   (decisions/phase-5-gleichstand.md, „themes-core 3: Messung vor dem Bau“).
/// - **Options** of the theme entry that core 3 passes over with a line in the log
///   (`DEPRECATED` in its `transformer.ts`: `aspects`, `include`, `calloutStyle`, `fonts`).
/// - **Colours in QuartzControl's form**: an `hsl-split` colour as three keys `-h`/`-s`/`-l`, which
///   core 3 logs as unknown Style Settings keys; it reads one key with the colour
///   (`StyleSettingsValues.colorPatch`). Known only with the theme's schema: without it, a key
///   ending in `-h` is not certainly a part.
///
/// The theme id stays as it is, an old one like `catppuccin.frappe` too: core 3 knows it
/// (`LEGACY_THEMES`). `theme: default` is no finding since core 3.1.1.
public enum ThemeLegacy {
  public static let ignoredOptions = ["aspects", "include", "calloutStyle", "fonts"]
  static let packagePrefix = "@quartz-themes/"
  static let corePackage = "@quartz-themes/core"

  public struct Patch: Equatable, Sendable {
    public var key: String
    /// nil removes the key.
    public var value: JSONValue?
  }

  public struct Findings: Equatable, Sendable {
    /// package.json's `dependencies` and `devDependencies`, in their order.
    public var packages: [String] = []
    /// The options core 3 passes over, in `ignoredOptions`' order.
    public var options: [String] = []
    /// The colours that are written in QuartzControl's form: one per field and mode.
    public var colors: Int = 0
    /// What turns them into core 3's form: the colour under its own key, the parts removed.
    public var styleSettingsPatch: [Patch] = []

    public var isEmpty: Bool { packages.isEmpty && options.isEmpty && styleSettingsPatch.isEmpty }
  }

  /// The old theme packages package.json names; empty when it cannot be read.
  public static func packages(project: String) -> [String] {
    guard let data = try? Posix.read(NodePath.join(project, "package.json")), let pkg = try? JSJSON.parse(data) else { return [] }
    var out: [String] = []
    for section in ["dependencies", "devDependencies"] {
      for name in pkg[section]?.objectValue?.keys ?? [] where name.hasPrefix(packagePrefix) && name != corePackage && !out.contains(name) {
        out.append(name)
      }
    }
    return out
  }

  static func themeEntryIndex(_ config: QuartzConfig) -> Int? {
    config.plugins.firstIndex(where: FontDelivery.isThemePlugin)
  }

  /// The parts of hsl-split colours in `settings` turned into one key each, per field and mode.
  /// A part beside a colour of its own goes without replacement (the colour is what core reads); a
  /// set of parts that does not make a colour goes too, core ignores it either way.
  public static func colorPatch(settings: JSONObject, schema: JSONValue?) -> (colors: Int, patch: [Patch]) {
    var colors = 0
    var patch: [Patch] = []
    for field in StyleSettingsValues.fields(schema) where field.format == "hsl-split" && field.kind.hasSuffix("color") {
      let modes: [StyleSettingsValues.Mode?] = field.kind == "variable-themed-color" ? [.light, .dark] : [nil]
      for mode in modes {
        let parts = ["-h", "-s", "-l"].map { StyleSettingsValues.optionKey(field, suffix: $0, mode: mode) }
        guard parts.contains(where: { settings[$0] != nil }) else { continue }
        let own = settings[StyleSettingsValues.optionKey(field, mode: mode)] != nil
        let read = StyleSettingsValues.readColor(field, values: settings, mode: mode)
        if !own, read.isSet, let hex = read.hex {
          colors += 1
          patch += StyleSettingsValues.colorPatch(field, hex: hex, mode: mode).map { Patch(key: $0.key, value: $0.value) }
        } else {
          patch += parts.filter { settings[$0] != nil }.map { Patch(key: $0, value: nil) }
        }
      }
    }
    return (colors, patch)
  }

  /// What there is to clear away. `schema` is the active theme's (`StyleSettingsSchema.schema(of:)`);
  /// without it the colours are not looked at.
  public static func find(project: String, config: QuartzConfig, schema: JSONValue? = nil) -> Findings {
    var findings = Findings(packages: packages(project: project))
    guard let index = themeEntryIndex(config), let options = config.plugins[index].object["options"]?.objectValue else { return findings }
    findings.options = ignoredOptions.filter { options[$0] != nil }
    if let settings = options["styleSettings"]?.objectValue {
      let colors = colorPatch(settings: settings, schema: schema)
      findings.colors = colors.colors
      findings.styleSettingsPatch = colors.patch
    }
    return findings
  }

  public struct Outcome: Equatable, Sendable {
    public var findings: Findings
    /// npm's answer when it was asked and failed; the config is written by then.
    public var npmFailure: String?
  }

  /// Clears everything `find` sees now: one snapshot first (a failed one stops here), then the
  /// config, then `npm uninstall` of the packages. The config goes first because it needs no
  /// network and is what core reads at every build.
  public static func clean(project: String, schema: JSONValue? = nil, runtime: RuntimeLocation = .current,
                           npm: @escaping TemplatePackage.Npm, snapshot: SnapshotStore.Take) async throws -> Outcome {
    let config = try await ConfigFile.read(project: project, runtime: runtime)
    let findings = find(project: project, config: config, schema: schema)
    guard !findings.isEmpty else { return Outcome(findings: findings) }
    _ = try await snapshot(project, "pluginChange", L10n.t("themeLegacy.snapshotLabel"))
    if !findings.options.isEmpty || !findings.styleSettingsPatch.isEmpty, let index = themeEntryIndex(config) {
      var next = config
      var entry = next.plugins[index].object
      var options = entry["options"]?.objectValue ?? JSONObject()
      for name in findings.options { options[name] = nil }
      if var settings = options["styleSettings"]?.objectValue, !findings.styleSettingsPatch.isEmpty {
        settings = StyleSettingsValues.apply(findings.styleSettingsPatch.map { ($0.key, $0.value) }, to: settings)
        options["styleSettings"] = settings.keys.isEmpty ? nil : .object(settings)
      }
      entry["options"] = .object(options)
      next.plugins[index] = PluginEntry(object: entry)
      try await ConfigFile.write(next, project: project, runtime: runtime)
    }
    var outcome = Outcome(findings: findings)
    if !findings.packages.isEmpty {
      let result = await npm(["uninstall"] + findings.packages, project)
      if !result.success { outcome.npmFailure = JSText.slice(result.output, -400) }
    }
    return outcome
  }
}

extension ThemeLegacy.Findings {
  /// Nothing found.
  public static let none = ThemeLegacy.Findings()
}
