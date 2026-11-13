import AppKit
import QuartzHubCore
import SwiftUI
import UniformTypeIdentifiers

/// The project's picture (QuartzControl's `ProjectImage.tsx`): what QuartzHub shows for the
/// project, what the favicon is made from, and optionally the picture in the site header.
///
/// The files are written at once (a file operation, nothing for "Speichern" to carry); the header
/// picture is a layout-box entry in the page's draft and waits for "Speichern" like every other
/// field. The one exception is installing quartz-layout-box, which only the CLI can do: it saves
/// pending edits first and reads the config again.
struct ProjectImageSection: View {
  @Bindable var model: ConfigModel
  @Environment(\.openPage) private var openPage

  @State private var icon: ProjectIcon.Info?
  @State private var busy = false
  @State private var installing = false
  @State private var error: String?
  @State private var confirmInstall = false
  /// "Wird mit Speichern übernommen" stays in view until it is: as an announcement alone only
  /// VoiceOver heard it (review 2026-11-13, nebenbei).
  @State private var installedNote = false

  private var plugins: [PluginEntry] { model.plugins }
  private var savedPlugins: [PluginEntry] { model.saved?.plugins ?? [] }
  private var custom: Bool { icon?.custom == true }
  private var hasDark: Bool { icon?.darkThumbnail != nil }
  private var headerOn: Bool { ProjectImageBox.findOwn(plugins) != nil }
  private var hasLayoutBox: Bool { plugins.contains(where: ProjectImageBox.isLayoutBox) }
  /// A template's mark already shows the picture; switching the header on would show it twice.
  private var markShows: Bool { ProjectImageBox.findOther(plugins) != nil }

  var body: some View {
    SettingsSection(L10n.t("projectImage.label"), symbol: "photo") {
      HStack(alignment: .top, spacing: 14) {
        avatar
        VStack(alignment: .leading, spacing: 8) {
          HStack {
            Button(custom || icon?.unrecorded == true ? L10n.t("projectImage.replace") : L10n.t("projectImage.choose")) {
              pick({ [path = model.project.path] in try ProjectIcon.set(project: path, source: $0) }, after: lightApplied)
            }
            .accessibilityIdentifier("config.imageChoose")
            if custom {
              Button(L10n.t("projectImage.remove")) {
                run({ [path = model.project.path] in try ProjectIcon.clear(project: path) }, after: lightApplied)
              }
            }
          }
          .disabled(busy)
          Note(imageHint)
          faviconLine
        }
      }
      darkRow
      headerRow
      if installedNote, model.dirty {
        Callout(.info, L10n.t("projectImage.header.installed"))
      }
      if let error {
        Callout(.error, error)
      }
    }
    .task { await reloadIcon() }
    .alert(installParts.title, isPresented: $confirmInstall) {
      Button(L10n.t("common.cancel"), role: .cancel) {}
      Button(L10n.t("projectImage.header.installAction")) { Task { await install() } }
    } message: {
      Text(installParts.message)
    }
  }

  // MARK: Pieces

  private var avatar: some View {
    Group {
      if let data = icon?.thumbnail, custom || icon?.unrecorded == true, let image = NSImage(data: data) {
        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
      } else {
        RoundedRectangle(cornerRadius: 14)
          .fill(ProjectAvatar.colour(model.project.id).gradient)
          .overlay {
            Text(String(model.project.name.first.map(String.init)?.uppercased() ?? "?"))
              .font(.system(size: 28, weight: .semibold)).foregroundStyle(.white)
          }
      }
    }
    .frame(width: 64, height: 64)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
    .accessibilityHidden(true)
  }

  private var imageHint: String {
    if let icon, icon.custom { return L10n.t("projectImage.customHint", ["width": String(icon.width), "height": String(icon.height)]) }
    if icon?.unrecorded == true { return L10n.t("projectImage.unrecordedHint") }
    return L10n.t("projectImage.defaultHint")
  }

  /// Read-only on purpose: switching a plugin on is the Plugins page's job, and this page's
  /// "Speichern" owns quartz.config.yaml.
  @ViewBuilder private var faviconLine: some View {
    let favicon = plugins.first { $0.name == "favicon" }
    if favicon?.enabled == true {
      Note(L10n.t("projectImage.faviconOn"))
    } else {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Note(favicon == nil ? L10n.t("projectImage.faviconMissing") : L10n.t("projectImage.faviconOff"))
        Button(L10n.t("projectImage.faviconLink")) { openPage(.plugins) }.buttonStyle(.link).font(.callout)
      }
    }
  }

  @ViewBuilder private var darkRow: some View {
    HStack(spacing: 12) {
      if let data = icon?.darkThumbnail, let image = NSImage(data: data) {
        Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
          .frame(width: 40, height: 40)
          .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.12)))
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .accessibilityHidden(true)
      }
      // Replacing a dark picture that is there needs no light one (a template leaves that state);
      // choosing a first one waits for a light picture, which the header needs.
      Button(hasDark ? L10n.t("projectImage.dark.replace") : L10n.t("projectImage.dark.choose")) {
        pick({ [path = model.project.path] in try ProjectIcon.setDark(project: path, source: $0) }, after: darkApplied)
      }
      .disabled(busy || (!custom && !hasDark))
      if hasDark {
        Button(L10n.t("projectImage.dark.remove")) {
          run({ [path = model.project.path] in try ProjectIcon.clearDark(project: path) }, after: darkApplied)
        }
        .disabled(busy)
      }
    }
    Note(darkHint)
    if custom, hasDark, icon?.darkCustom == false {
      Note(L10n.t("projectImage.dark.notChosen"))
    }
  }

  /// Removing is a file operation at once, the header's entry a draft until "Speichern": in between
  /// the saved config names a file that is gone. Said only in the state where that gap exists, and
  /// asked of the saved list, not the draft.
  private var darkHint: String {
    let savedMark = ProjectImageBox.findOther(savedPlugins).map { savedPlugins[$0] }
    let markNamesDark = Self.html(savedMark).contains("icon-dark.png")
    let savedHeader = ProjectImageBox.findOwn(savedPlugins).map { savedPlugins[$0] }
    let savedNamesDark = savedHeader?.enabled == true && Self.html(savedHeader).contains("icon-dark.png")
    if markNamesDark, hasDark { return L10n.t("projectImage.dark.hintMark") }
    if savedNamesDark, hasDark { return L10n.t("projectImage.dark.hintHeaderOn") }
    return L10n.t("projectImage.dark.hint")
  }

  private static func html(_ entry: PluginEntry?) -> String {
    entry?.object["options"]?.objectValue?["html"].map(JSRead.string) ?? ""
  }

  @ViewBuilder private var headerRow: some View {
    if markShows, !headerOn {
      Note(L10n.t("projectImage.header.shownByMark"))
    } else {
      FormField(hint: headerHint) {
        Toggle(L10n.t("projectImage.header.label"), isOn: Binding(get: { headerOn }, set: toggleHeader))
          .disabled(busy || installing || (!custom && !headerOn))
          .accessibilityIdentifier("config.imageHeader")
      }
    }
  }

  private var headerHint: String {
    if !custom { return L10n.t("projectImage.header.needsImage") }
    if installing { return L10n.t("projectImage.header.installing") }
    return hasLayoutBox ? L10n.t("projectImage.header.hint") : L10n.t("projectImage.header.hintInstall")
  }

  private var installParts: (title: String, message: String) {
    let text = L10n.t("projectImage.header.installConfirm")
    guard let split = text.range(of: "\n\n") else { return (text, "") }
    return (String(text[..<split.lowerBound]), String(text[split.upperBound...]))
  }

  // MARK: Actions

  private func toggleHeader(_ on: Bool) {
    error = nil
    if !on {
      model.setPlugins(ProjectImageBox.without(plugins))
    } else if hasLayoutBox {
      model.setPlugins(ProjectImageBox.with(plugins, hasDark: hasDark))
    } else {
      confirmInstall = true
    }
  }

  private func install() async {
    installing = true
    defer { installing = false }
    if model.dirty, await !model.save() {
      error = L10n.t("projectImage.header.saveFirstFailed")
      return
    }
    let environment = await AppServices.current()
    let result = await PluginCommands.shared.add(
      source: ProjectImageBox.layoutBoxSource, project: model.project.path, environment: environment,
      snapshot: SnapshotStore.live(environment: environment).take)
    guard result.success else {
      error = String(result.output.suffix(600))
      return
    }
    do {
      let fresh = try await model.reread()
      // Exactly one layout box exists now, the one the CLI just wrote: it becomes the header picture.
      let index = fresh.plugins.firstIndex(where: ProjectImageBox.isLayoutBox)
      model.setPlugins(ProjectImageBox.with(fresh.plugins, hasDark: hasDark, replaceIndex: index))
      installedNote = true
      Announce.post(L10n.t("projectImage.header.installed"))
    } catch {
      self.error = ConfigModel.message(error)
    }
  }

  private func lightApplied(_ next: ProjectIcon.Info) {
    Announce.post(next.custom ? L10n.t("projectImage.announceSet") : L10n.t("projectImage.announceCleared"))
    // The Projects window shows the picture too.
    Task { await ProjectsModel.shared.reload() }
  }

  /// The header's HTML names icon-dark.png only while the file exists, so it follows the file.
  private func darkApplied(_ next: ProjectIcon.Info) {
    if headerOn { model.setPlugins(ProjectImageBox.with(plugins, hasDark: next.darkThumbnail != nil)) }
    Announce.post(next.darkThumbnail != nil ? L10n.t("projectImage.dark.announceSet") : L10n.t("projectImage.dark.announceCleared"))
  }

  private func pick(_ action: @escaping @Sendable (String) throws -> ProjectIcon.Info, after: @escaping (ProjectIcon.Info) -> Void) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.png, .jpeg]
    panel.message = L10n.t("projectImage.fileFilter")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    let file = Posix.path(url)
    run({ try action(file) }, after: after)
  }

  private func run(_ action: @escaping @Sendable () throws -> ProjectIcon.Info, after: @escaping (ProjectIcon.Info) -> Void) {
    busy = true
    error = nil
    Task {
      do {
        let next = try await Task.detached(operation: action).value
        icon = next
        after(next)
      } catch {
        self.error = (error as? ProjectIcon.Failure)?.message ?? String(describing: error)
      }
      busy = false
    }
  }

  private func reloadIcon() async {
    let path = model.project.path
    icon = await Task.detached { ProjectIcon.info(project: path) }.value
  }
}
