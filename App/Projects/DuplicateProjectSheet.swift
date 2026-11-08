import QuartzHubCore
import SwiftUI

/// "„Name“ duplizieren": QuartzControl's `DuplicateWizard` (`Home.tsx`). The same two fields for
/// the place as creating, plus the one question a copy has to answer: where its content comes
/// from. The original's content folder is not offered: it is either a link into a vault, which two
/// projects would then write through, or a folder that belongs to the original.
struct DuplicateProjectSheet: View {
  let source: ProjectOverview
  /// The copy's id when it should be opened; nil when cancelled.
  let finish: (String?) -> Void

  private enum Content: Hashable { case blank, copy, symlink }

  @State private var parent = ProjectsModel.defaultDirectory ?? ""
  @State private var name: String
  @State private var content = Content.blank
  @State private var contentSource = ""
  @State private var busy = false
  @State private var error: String?

  init(source: ProjectOverview, finish: @escaping (String?) -> Void) {
    self.source = source
    self.finish = finish
    _name = State(initialValue: "\(source.name)-2")
  }

  private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var nameInvalid: Bool { trimmedName.contains("/") || trimmedName == "." || trimmedName == ".." }
  private var target: String {
    guard !parent.isEmpty, !trimmedName.isEmpty else { return "" }
    var base = parent
    while base.hasSuffix("/") { base.removeLast() }
    return "\(base)/\(trimmedName)"
  }
  private var canRun: Bool { !busy && !target.isEmpty && !nameInvalid && (content == .blank || !contentSource.isEmpty) }

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          Text(L10n.t("home.duplicate.intro")).foregroundStyle(.secondary)
        } header: {
          Text(L10n.t("home.duplicate.title", ["name": source.name])).font(.title3.weight(.semibold))
        }
        Section {
          FormField(hint: L10n.t("home.wizard.parentDirectoryHint")) {
            FolderField(label: L10n.t("home.wizard.parentDirectory"), placeholder: L10n.t("home.wizard.parentDirectoryPlaceholder"),
                        path: $parent, start: ProjectsModel.defaultDirectory)
          }
          FormField(hint: L10n.t("home.duplicate.nameHint")) {
            TextField(L10n.t("home.wizard.projectName"), text: $name)
              .accessibilityIdentifier("duplicate.name")
          }
          if nameInvalid {
            Text(L10n.t("home.wizard.nameInvalid")).foregroundStyle(.red).font(.callout)
          } else if !target.isEmpty {
            LabeledContent(L10n.t("home.wizard.targetPreview")) {
              Text(target).font(.callout.monospaced()).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
            }
          }
        }
        Section {
          FormField(hint: L10n.t("home.duplicate.contentHint")) {
            Picker(L10n.t("home.duplicate.contentLabel"), selection: $content) {
              Text(L10n.t("home.duplicate.contentBlank")).tag(Content.blank)
              Text(L10n.t("home.duplicate.contentSymlink")).tag(Content.symlink)
              Text(L10n.t("home.duplicate.contentCopy")).tag(Content.copy)
            }
          }
          if content != .blank {
            FormField(hint: L10n.t("home.duplicate.contentFolderHint")) {
              FolderField(label: L10n.t("home.duplicate.contentFolder"), placeholder: nil, path: $contentSource, start: nil)
            }
          }
        } footer: {
          Text(L10n.t("home.duplicate.whatStaysBehind")).font(.caption).foregroundStyle(.secondary)
        }
        if let error {
          Section {
            Text(error).foregroundStyle(.red).font(.callout).textSelection(.enabled)
          }
        }
      }
      .formStyle(.grouped)
      .disabled(busy)
      HStack {
        if busy {
          ProgressView().controlSize(.small)
          Text(L10n.t("home.duplicate.running")).foregroundStyle(.secondary)
        }
        Spacer()
        Button(L10n.t("common.cancel"), role: .cancel) { finish(nil) }
          .keyboardShortcut(.cancelAction)
          .disabled(busy)
        Button(L10n.t("home.duplicate.confirm"), action: run)
          .keyboardShortcut(.defaultAction)
          .disabled(!canRun)
          .accessibilityIdentifier("duplicate.confirm")
      }
      .padding()
    }
    .frame(width: 560)
    .frame(minHeight: 460, idealHeight: 560)
    .interactiveDismissDisabled(busy)
  }

  private func run() {
    guard canRun else { return }
    let choice: ProjectDuplicator.Content = switch content {
    case .blank: .blank
    case .copy: .copy(from: contentSource)
    case .symlink: .symlink(to: contentSource)
    }
    let options = ProjectDuplicator.Options(source: source.path, target: target, content: choice)
    busy = true
    error = nil
    Task {
      defer { busy = false }
      do {
        let outcome = try await ProjectsModel.shared.list.duplicate(options, environment: await AppServices.shared.environment.value)
        await ProjectsModel.shared.reload()
        if let entry = outcome.entry {
          finish(entry.id)
        } else {
          error = outcome.result.output.isEmpty ? L10n.t("home.duplicate.failed") : outcome.result.output
        }
      } catch {
        self.error = error.localizedMessage
      }
    }
  }
}
