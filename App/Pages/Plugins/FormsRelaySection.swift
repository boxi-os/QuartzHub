import QuartzHubCore
import SwiftUI

/// What the Formulare tab says about the relay: its state in words, whether it is out of date, and
/// what an upload would ask for (QuartzControl's `FormsRelay.tsx` and the helpers of `Forms.tsx`).
@MainActor enum RelayWords {
  /// Uploaded once, and what an upload would write or where it would go is no longer that.
  static func outdated(_ r: RelayState) -> Bool {
    guard let last = r.lastUpload, r.hashProblem == nil else { return false }
    return r.moved == true || r.configModeChanged || r.operatorChanged || r.currentHash != last["hash"]?.stringValue
  }

  enum Tone { case plain, red, orange, green }

  static func status(_ r: RelayState, dateOnly: Bool = false) -> (tone: Tone, text: String) {
    let date = r.lastUpload?["at"]?.stringValue.map { format($0, dateOnly: dateOnly) } ?? ""
    guard r.lastUpload != nil else {
      if let removed = r.removedAt { return (.plain, L10n.t("formsEditor.relay.statusRemoved", ["date": format(removed, dateOnly: dateOnly)])) }
      return (.plain, L10n.t("formsEditor.relay.statusNever"))
    }
    if r.hashProblem != nil { return (.red, L10n.t("formsEditor.relay.statusBroken")) }
    if r.moved == true, !dateOnly { return (.orange, L10n.t("formsEditor.relay.statusMoved", ["date": date])) }
    if outdated(r) { return (.orange, L10n.t("formsEditor.relay.statusChanged", ["date": date])) }
    return (.green, L10n.t("formsEditor.relay.statusCurrent", ["date": date]))
  }

  /// `new Date(at).toLocaleString()` / `toLocaleDateString()` in the app's language.
  static func format(_ iso: String, dateOnly: Bool) -> String {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: L10n.language)
    formatter.dateStyle = .medium
    formatter.timeStyle = dateOnly ? .none : .short
    return formatter.string(from: date)
  }

  /// The first relay form with an address, its own `transport.url` before the global one: the
  /// upload asks the relay for that form's stamp at that address.
  static func probe(_ view: FormsView) -> (form: String, url: String)? {
    let options = view.options
    let global = options["transport"]?.objectValue?["url"]?.stringValue.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    for form in view.forms where FormsOptions.transportKind(form.def, options) == "relay" {
      let own = form.def["transport"]?.objectValue?["url"]?.stringValue.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
      if !own.isEmpty || !global.isEmpty { return (form.id, own.isEmpty ? global : own) }
    }
    return nil
  }

  /// `configuration.baseUrl` as an https address without a trailing slash, or nil. A host beyond
  /// `WebURL` (non-ASCII) gives nil, where QuartzControl's `new URL` went on.
  static func siteBase(_ config: QuartzConfig?) -> String? {
    guard let raw = config?.configuration["baseUrl"]?.stringValue, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    let lower = raw.lowercased()
    let address = lower.hasPrefix("http://") || lower.hasPrefix("https://") ? raw : "https://\(raw)"
    guard let parts = WebURL(address).parts else { return nil }
    var path = parts.pathname
    while path.hasSuffix("/") { path.removeLast() }
    return parts.origin + path
  }

  /// The recipient names the relay forms use, read from the config.
  static func neededRecipients(_ view: FormsView) -> [String] {
    var out: [String] = []
    for form in view.forms where FormsOptions.transportKind(form.def, view.options) == "relay" {
      let name = form.def["recipient"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      if !name.isEmpty, !out.contains(name) { out.append(name) }
    }
    return out
  }

  static func checkText(_ check: RelayCheck, configReadable: Bool) -> String {
    switch check {
    case .ok(let url, _): return L10n.t("formsEditor.relay.checkOk", ["url": url])
    case .phpError: return configReadable ? L10n.t("formsEditor.relay.checkPhpErrorReadable") : L10n.t("formsEditor.relay.checkPhpError")
    case .relayError(let url, let status, let error, let message, let origin):
      if error == "origin", let origin {
        let values = ["url": url, "origin": origin.sent]
        switch origin.listed {
        case .any: return L10n.t("formsEditor.relay.checkRelayOriginAny", values)
        case .yes: return L10n.t("formsEditor.relay.checkRelayOriginOther", values)
        case .no: return L10n.t("formsEditor.relay.checkRelayOriginBase", values)
        }
      }
      if error == "origin" { return L10n.t("formsEditor.relay.checkRelayOrigin", ["url": url]) }
      if error == "secret_config" { return L10n.t("formsEditor.relay.checkRelaySecret", ["url": url]) }
      if error == "mbstring_config" { return L10n.t("formsEditor.relay.checkRelayMbstring", ["url": url]) }
      return L10n.t("formsEditor.relay.checkRelayError", ["status": String(status), "error": error, "message": message])
    case .noPhp(let url, _): return L10n.t("formsEditor.relay.checkNoPhp", ["url": url])
    case .redirect(let url, let to): return L10n.t("formsEditor.relay.checkRedirect", ["url": url, "to": to])
    case .postRedirect(let url, let to, let status):
      return L10n.t("formsEditor.relay.checkPostRedirect", ["url": url, "to": to, "status": String(status)])
    case .redirectNoRelay(let url, let to, let local):
      return local ? L10n.t("formsEditor.relay.checkRedirectLocal", ["url": url, "to": to])
        : L10n.t("formsEditor.relay.checkRedirectNoRelay", ["url": url, "to": to])
    case .otherRelay(let url): return L10n.t("formsEditor.relay.checkOtherRelay", ["url": url])
    case .phpMessage(let url, let message): return L10n.t("formsEditor.relay.checkPhpMessage", ["url": url, "message": message])
    case .phpCannotRead(let url): return L10n.t("formsEditor.relay.checkPhpCannotRead", ["url": url])
    case .http(let url, let status):
      // A 403, a 5xx and a 404 have different ways out; only the last is the address.
      if status == 403 { return L10n.t("formsEditor.relay.checkHttpDenied", ["url": url]) }
      if (502...504).contains(status) { return L10n.t("formsEditor.relay.checkHttpNoPhp", ["url": url, "status": String(status)]) }
      if status == 500 { return L10n.t("formsEditor.relay.checkHttpServerError", ["url": url]) }
      if status == 401 { return L10n.t("formsEditor.relay.checkHttpAuth", ["url": url]) }
      if status == 429 { return L10n.t("formsEditor.relay.checkHttpRate", ["url": url]) }
      if (520...527).contains(status) || status == 530 { return L10n.t("formsEditor.relay.checkHttpCdn", ["url": url, "status": String(status)]) }
      return L10n.t("formsEditor.relay.checkHttp", ["url": url, "status": String(status)])
    case .unreachable(_, let reason): return L10n.t("formsEditor.relay.checkUnreachable", ["reason": reason])
    case .noURL: return L10n.t("formsEditor.relay.checkNoUrl")
    }
  }

  static func blockers(_ r: RelayState, missing: [String], missingCaptcha: [String]) -> [String] {
    var out: [String] = []
    if !r.secrets.storageAvailable { out.append(L10n.t("formsEditor.relay.blockStorage")) }
    if r.settings["targetId"]?.stringValue.map({ $0.isEmpty }) ?? true { out.append(L10n.t("formsEditor.relay.blockTarget")) }
    if (r.settings["from"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(L10n.t("formsEditor.relay.blockFrom")) }
    if !missing.isEmpty { out.append(L10n.t("formsEditor.relay.blockRecipients", ["names": missing.joined(separator: ", ")])) }
    if !missingCaptcha.isEmpty { out.append(L10n.t("formsEditor.relay.blockCaptcha", ["names": missingCaptcha.joined(separator: ", ")])) }
    if r.conflict != nil { out.append(L10n.t("formsEditor.relay.blockConflict")) }
    if r.hashProblem != nil { out.append(L10n.t("formsEditor.relay.blockProblems")) }
    return out
  }

  /// The project's relay, with the app's connections and adapters.
  static func relay(_ model: PluginsModel, source: PluginSource) async -> FormsRelay {
    let environment = await AppServices.current()
    let cli = FormsCLI(project: model.project.path, source: source, environment: environment)
    return FormsRelay(projectId: model.project.id, cli: cli, connections: AppDeploy.connections(),
                      deploy: AppDeploy.make(project: model.project.path, environment: environment))
  }
}

/// The relay (QuartzControl's `RelaySection`): where it goes, what it is told, and the upload.
/// What is not secret is written at once to .quartz-gui/forms-relay.json; what is secret
/// (recipient addresses, the captcha secret) goes once into the Keychain and never comes back: the
/// section says "Adresse gesetzt", not the address. The relay itself is written by quartz-forms
/// into a temporary folder and uploaded through a publish target.
struct FormsRelaySection: View {
  let view: FormsView
  @Bindable var model: PluginsModel
  let state: FormsState
  @Binding var selection: String?
  @Environment(\.unsavedGuard) private var unsaved

  @State private var busy: String?
  @State private var result: RelayUploadResult?
  @State private var said: String?
  @State private var message: String?
  @State private var subdirInvalid = false
  @State private var drafts: [String: String] = [:]
  /// A refused address, under its row: at the top of the inspector it was out of sight (2026-11-11).
  @State private var rowProblems: [String: String] = [:]
  /// Rows whose secret was saved here, with the upload it was saved after: the row says so until
  /// the next upload.
  @State private var pending: [String: (at: String, before: RelayState)] = [:]

  private var options: JSONObject { view.options }

  var body: some View {
    if let relay = state.relay {
      content(relay)
    } else {
      Section { Note(state.relayLoading ? L10n.t("formsEditor.relay.loading") : "") }
    }
  }

  @ViewBuilder private func content(_ r: RelayState) -> some View {
    let s = r.settings
    let needed = RelayWords.neededRecipients(view)
    let names = needed + r.secrets.recipients.filter { !needed.contains($0) }
    let missing = needed.filter { !r.secrets.recipients.contains($0) }
    let captcha = FormsOptions.captchaNeeds(options, globalSpam: FormsOptions.resolvedGlobal(view.schema, options, key: "spam"))
    let missingCaptcha = (captcha.global != nil && !r.secrets.captchaSecret ? [L10n.t("formsEditor.relay.allForms")] : [])
      + captcha.forms.filter { !r.secrets.captchaSecrets.contains($0.id) }.map(\.id)
    let targetId = s["targetId"]?.stringValue ?? ""
    let canUpload = !targetId.isEmpty && !(s["from"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && missing.isEmpty && missingCaptcha.isEmpty && r.conflict == nil && r.secrets.storageAvailable && r.hashProblem == nil
    let status = RelayWords.status(r)
    let siteBase = RelayWords.siteBase(model.config)
    let siteOrigin = siteBase.flatMap { WebURL($0).parts?.origin } ?? r.siteOrigin
    let subdir = s["subdir"]?.stringValue ?? ""
    let trimmedSubdir = subdir.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let suggestedUrl = siteBase.map { "\($0)/\(trimmedSubdir)/send.php" }
    let transportUrl = options["transport"]?.objectValue?["url"]?.stringValue ?? ""
    let subdirRsync = r.targets.first { $0.id == targetId }?.rsync == true ? RemotePath.rsyncUnsafeChar(subdir) : nil

    Section {
      HStack {
        statusBadge(status)
        if state.relayLoading { Text(L10n.t("formsEditor.relay.loading")).font(.caption).foregroundStyle(.secondary) }
      }
      if let problem = r.hashProblem {
        Callout(.error) {
          Text(L10n.t("formsEditor.relay.problemsFirst"))
          Text(verbatim: problem).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
        }
      }
      if !r.secrets.storageAvailable { Callout(.warning, L10n.t("formsEditor.relay.noStorage")) }
      if r.secrets.missing { Callout(.warning, L10n.t("relay.secretsMissing")) }
      if let message { Callout(.error, message) }
    }

    Section {
      row(L10n.t("formsEditor.relay.target"), hint: r.targets.isEmpty ? L10n.t("formsEditor.relay.noTargets") : L10n.t("formsEditor.relay.targetHint")) {
        Picker(L10n.t("formsEditor.relay.target"), selection: Binding(get: { targetId }, set: { id in
          Task { await save(["targetId": id.isEmpty ? nil : .string(id)]) }
        })) {
          Text(L10n.t("formsEditor.relay.noTarget")).tag("")
          ForEach(r.targets, id: \.id) { target in Text(verbatim: "\(target.name) (\(target.type): \(target.where))").tag(target.id) }
        }
        .labelsHidden()
      }
      VStack(alignment: .leading, spacing: 4) {
        row(L10n.t("formsEditor.relay.subdir"), hint: L10n.t("formsEditor.relay.subdirHint")) {
          CommitField(name: L10n.t("formsEditor.relay.subdir"), text: subdir, placeholder: "forms",
                      revert: { subdirInvalid = false }) { raw in
            let next = RemotePath.relaySubdir(raw)
            subdirInvalid = next == nil
            if let next { Task { await save(["subdir": .string(next)]) } }
            return next != nil
          }
        }
        if subdirInvalid { FieldProblem(L10n.t("formsEditor.relay.subdirInvalid")) }
        if !subdirInvalid, let char = subdirRsync {
          FieldProblem(char.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
            ? L10n.t("formsEditor.relay.subdirRsyncSpace") : L10n.t("formsEditor.relay.subdirRsyncChar", ["char": char]))
        }
        if let conflict = r.conflict {
          Callout(.warning) {
            Text(L10n.t("formsEditor.relay.conflict", ["target": conflict.targetName, "path": conflict.exclude]))
            Button(L10n.t("formsEditor.relay.excludeSubmit", ["path": conflict.exclude])) { Task { await exclude(conflict) } }
          }
        }
      }
      VStack(alignment: .leading, spacing: 4) {
        Text(L10n.t("formsEditor.relay.url"))
        HStack {
          Text(verbatim: transportUrl.isEmpty ? L10n.t("formsEditor.noUrl") : transportUrl)
            .font(.system(.callout, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            .verbatimLineBreaks()
          Spacer()
          Button { selection = "section:transport" } label: { Label(L10n.t("formsEditor.sections.transport"), systemImage: "paperplane") }
        }
        if let suggestedUrl, suggestedUrl != transportUrl {
          VStack(alignment: .leading, spacing: 2) {
            Button(L10n.t("formsEditor.relay.useUrl")) { Task { await useUrl(suggestedUrl) } }
            Text(verbatim: suggestedUrl).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
              .verbatimLineBreaks()
          }
        }
        Text(L10n.t("formsEditor.relay.urlHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
      row(L10n.t("formsEditor.relay.from"), hint: L10n.t("formsEditor.relay.fromHint")) {
        CommitField(name: L10n.t("formsEditor.relay.from"), text: s["from"]?.stringValue ?? "", placeholder: "formulare@example.org") { raw in
          Task { await save(["from": .string(raw.trimmingCharacters(in: .whitespacesAndNewlines))]) }
          return true
        }
      }
      VStack(alignment: .leading, spacing: 4) {
        let origins = s["allowedOrigins"]?.arrayValue?.compactMap(\.stringValue) ?? []
        row(L10n.t("formsEditor.relay.origins"), hint: L10n.t("formsEditor.relay.originsHint")) {
          CommitField(name: L10n.t("formsEditor.relay.origins"), text: origins.joined(separator: ", "), placeholder: siteOrigin ?? "https://example.org") { raw in
            Task { await save(["allowedOrigins": .array(FormsOptions.origins(raw).map(JSONValue.string))]) }
            return true
          }
        }
        if origins.isEmpty, let siteOrigin {
          Button(L10n.t("formsEditor.relay.useOrigin", ["origin": siteOrigin])) { Task { await save(["allowedOrigins": .array([.string(siteOrigin)])]) } }
        }
      }
    }

    Section(L10n.t("formsEditor.relay.recipients")) {
      if names.isEmpty { Note(L10n.t("formsEditor.relay.noRecipients")) }
      ForEach(names, id: \.self) { name in recipientRow(name, r: r, used: needed.contains(name)) }
      Note(L10n.t("formsEditor.relay.recipientsHint"))
    }

    if captcha.global != nil || r.secrets.captchaSecret || !captcha.forms.isEmpty || !r.secrets.captchaSecrets.isEmpty {
      Section {
        if captcha.global != nil || r.secrets.captchaSecret {
          SecretRow(label: L10n.t("formsEditor.relay.captchaSecret"),
                    hint: captcha.global.map { L10n.t("formsEditor.relay.captchaSecretHint", ["provider": $0]) } ?? L10n.t("formsEditor.relay.captchaUnused"),
                    isSet: r.secrets.captchaSecret, needed: captcha.global != nil, disabled: !r.secrets.storageAvailable,
                    note: savedNote("captcha", r, L10n.t("formsEditor.relay.secretSetAnnounce"), L10n.t("formsEditor.relay.secretSetPending"))) { value in
            Task { await saveSecrets(RelaySecretsChange(captchaSecret: .set(value)),
                                     said: rowSaid(r, L10n.t("formsEditor.relay.secretSetAnnounce"), L10n.t("formsEditor.relay.secretSetPending")),
                                     row: "captcha", r: r) }
          } remove: {
            pending["captcha"] = nil
            Task { await saveSecrets(RelaySecretsChange(captchaSecret: .remove), said: L10n.t("formsEditor.relay.secretRemovedAnnounce"), row: nil, r: r) }
          }
        }
        let ids = captcha.forms.map(\.id) + r.secrets.captchaSecrets.filter { id in !captcha.forms.contains { $0.id == id } }
        ForEach(ids, id: \.self) { id in
          let need = captcha.forms.first { $0.id == id }
          SecretRow(label: L10n.t("formsEditor.relay.captchaSecretFor", ["form": id]),
                    hint: need.map { L10n.t("formsEditor.relay.captchaSecretForHint", ["provider": $0.provider]) } ?? L10n.t("formsEditor.relay.captchaUnused"),
                    isSet: r.secrets.captchaSecrets.contains(id), needed: need != nil, disabled: !r.secrets.storageAvailable,
                    note: savedNote("captcha:\(id)", r, L10n.t("formsEditor.relay.secretSetAnnounce"), L10n.t("formsEditor.relay.secretSetPending"))) { value in
            Task { await saveSecrets(RelaySecretsChange(captchaSecrets: JSONObject([(id, .string(value))])),
                                     said: rowSaid(r, L10n.t("formsEditor.relay.secretSetAnnounce"), L10n.t("formsEditor.relay.secretSetPending")),
                                     row: "captcha:\(id)", r: r) }
          } remove: {
            pending["captcha:\(id)"] = nil
            Task { await saveSecrets(RelaySecretsChange(captchaSecrets: JSONObject([(id, .null)])), said: L10n.t("formsEditor.relay.secretRemovedAnnounce"), row: nil, r: r) }
          }
        }
      }
    }

    Section {
      let mailer = s["mailer"]?.stringValue == "sendmail" ? "sendmail" : "mail"
      row(L10n.t("formsEditor.relay.mailer"), hint: L10n.t("formsEditor.relay.mailerHint")) {
        Picker(L10n.t("formsEditor.relay.mailer"), selection: Binding(get: { mailer }, set: { m in Task { await save(["mailer": .string(m)]) } })) {
          Text(L10n.t("formsEditor.relay.mailerMail")).tag("mail")
          Text(verbatim: "sendmail").tag("sendmail")
        }
        .pickerStyle(.segmented).labelsHidden()
      }
      if mailer == "sendmail" {
        row(L10n.t("formsEditor.relay.sendmailPath"), hint: L10n.t("formsEditor.relay.sendmailPathHint")) {
          CommitField(name: L10n.t("formsEditor.relay.sendmailPath"), text: s["sendmailPath"]?.stringValue ?? "", monospaced: true) { raw in
            let v = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { Task { await save(["sendmailPath": .string(v)]) } }
            return !v.isEmpty
          }
        }
      }
    }

    Section(L10n.t("pluginOptions.rarelyUsed")) {
      row(L10n.t("formsEditor.relay.subjectPrefix"), hint: L10n.t("formsEditor.relay.subjectPrefixHint")) {
        CommitField(name: L10n.t("formsEditor.relay.subjectPrefix"), text: s["subjectPrefix"]?.stringValue ?? "", placeholder: "[Website]") { raw in
          Task { await save(["subjectPrefix": .string(raw)]) }
          return true
        }
      }
      row(L10n.t("formsEditor.relay.counterDir"), hint: L10n.t("formsEditor.relay.counterDirHint")) {
        CommitField(name: L10n.t("formsEditor.relay.counterDir"), text: s["counterDir"]?.stringValue ?? "",
                    placeholder: "/home/name/quartz-forms-counters", monospaced: true) { raw in
          Task { await save(["counterDir": .string(raw.trimmingCharacters(in: .whitespacesAndNewlines))]) }
          return true
        }
      }
      toggle(L10n.t("formsEditor.relay.configReadable"), hint: L10n.t("formsEditor.relay.configReadableHint"), on: s["configReadable"] == .bool(true)) { on in
        Task { await save(["configReadable": .bool(on)]) }
      }
      VStack(alignment: .leading, spacing: 4) {
        toggle(L10n.t("formsEditor.relay.envelopeSender"), hint: L10n.t("formsEditor.relay.envelopeSenderHint"), on: s["envelopeSender"] == .bool(true)) { on in
          Task { await save(["envelopeSender": .bool(on)]) }
        }
        if let installed = state.schema?.packageVersion, SemVer.isNewer(FormsOptions.envelopeSenderSince, than: installed) {
          NoEffectLine(L10n.t("formsEditor.relay.envelopeSenderOlder", ["since": FormsOptions.envelopeSenderSince, "installed": installed]))
        }
      }
      VStack(alignment: .leading, spacing: 4) {
        Button { Task { await renewSecret(r) } } label: { Label(L10n.t("formsEditor.relay.renewSecret"), systemImage: "key") }
        Text(L10n.t("formsEditor.relay.renewSecretHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
    }

    Section {
      // One under the other: side by side in the inspector's width they read "Relay…", "Als O…".
      VStack(alignment: .leading, spacing: 6) {
        Button { Task { await upload() } } label: {
          Label(busy == "upload" ? L10n.t("formsEditor.relay.uploading") : L10n.t("formsEditor.relay.upload"), systemImage: "arrow.up.circle")
        }
        .disabled(!canUpload || busy != nil)
        .accessibilityIdentifier("forms.relay.upload")
        Button { Task { await export() } } label: { Label(L10n.t("formsEditor.relay.export"), systemImage: "folder") }
          .disabled(busy != nil)
        if r.lastUpload != nil {
          Button { Task { await remove(r) } } label: {
            Label(busy == "remove" ? L10n.t("formsEditor.relay.removing") : L10n.t("formsEditor.relay.remove"), systemImage: "trash")
          }
          .disabled(busy != nil)
        }
      }
      if status.tone == .orange { statusBadge(status) }
      if !canUpload {
        Note(L10n.t("formsEditor.relay.cannotUpload", ["reasons": RelayWords.blockers(r, missing: missing, missingCaptcha: missingCaptcha).joined(separator: " ")]))
      }
      if let result {
        ScrollView {
          Text(verbatim: (result.success ? L10n.t("formsEditor.relay.done") + "\n" : "") + result.output)
            .font(.system(.caption, design: .monospaced)).foregroundStyle(result.success ? .primary : Color.red)
            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }
        .frame(maxHeight: 180)
        if let check = result.check {
          let countersOff = if case .ok(_, let counters) = check { counters == false } else { false }
          let isOk = if case .ok = check { true } else { false }
          Text(RelayWords.checkText(check, configReadable: result.configReadable == true))
            .font(.caption).foregroundStyle(!isOk ? Color.red : countersOff ? Color.orange : Color.green)
            .fixedSize(horizontal: false, vertical: true)
          if case .noPhp(_, let open?) = check { Callout(.error, L10n.t("formsEditor.relay.configOpen", ["url": open])) }
          if countersOff { Callout(.warning, L10n.t("formsEditor.relay.countersNotWritable")) }
          if needsReadable(check), result.configReadable == false {
            Button(L10n.t("formsEditor.relay.makeReadable")) {
              Task { if await save(["configReadable": .bool(true)]) { await upload() } }
            }
            .disabled(!canUpload || busy != nil)
          }
        }
        if result.countersOpen != nil { Callout(.warning, L10n.t("formsEditor.relay.countersOpen")) }
      }
    }
  }

  private func needsReadable(_ check: RelayCheck) -> Bool {
    switch check {
    case .phpError: true
    case .phpMessage(_, let message): message.contains("config.php")
    default: false
    }
  }

  private func statusBadge(_ status: (tone: RelayWords.Tone, text: String)) -> some View {
    let color: Color? = switch status.tone {
    case .red: .red
    case .orange: .orange
    case .green: .green
    case .plain: nil
    }
    return WordBadge(text: status.text).foregroundStyle(color.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
  }

  private func recipientRow(_ name: String, r: RelayState, used: Bool) -> some View {
    let set = r.secrets.recipients.contains(name)
    let draft = drafts[name] ?? ""
    return VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        // The name first; the badges wrap. Squeezed, "probeempf" read "probe-empf".
        Text(verbatim: name).font(.system(.body, design: .monospaced)).verbatimLineBreaks().layoutPriority(1)
        WordBadge(text: set ? L10n.t("formsEditor.relay.addressSet") : L10n.t("formsEditor.relay.addressMissing"))
          .foregroundStyle(set ? .green : .red)
        if !used { WordBadge(text: L10n.t("formsEditor.relay.unusedName")) }
        Spacer()
        if set {
          Button {
            pending["recipient:\(name)"] = nil
            Task {
              await saveSecrets(RelaySecretsChange(recipients: JSONObject([(name, .null)])),
                                said: L10n.t("formsEditor.relay.addressRemovedAnnounce", ["name": name]), row: nil, r: r)
            }
          } label: {
            Label(L10n.t("formsEditor.relay.removeAddress", ["name": name]), systemImage: "trash").labelStyle(.iconOnly)
          }
          .buttonStyle(.borderless)
          .help(L10n.t("formsEditor.relay.removeAddress", ["name": name]))
        }
      }
      HStack {
        TextField(L10n.t("formsEditor.relay.addressFor", ["name": name]), text: Binding(get: { draft }, set: {
          drafts[name] = $0
          rowProblems[name] = nil
        }),
                  prompt: Text(verbatim: set ? L10n.t("formsEditor.relay.replaceAddress") : "name@example.org"))
          .textFieldStyle(.roundedBorder).labelsHidden()
          .textContentType(.none)
          .disabled(!r.secrets.storageAvailable)
        Button(L10n.t("formsEditor.relay.saveAddress")) {
          if FormsOptions.isExampleAddress(draft) {
            rowProblems[name] = L10n.t("formsEditor.relay.exampleAddress")
            Announce.post(L10n.t("formsEditor.relay.exampleAddress"))
            return
          }
          drafts[name] = ""
          Task { await saveSecrets(RelaySecretsChange(recipients: JSONObject([(name, .string(draft))])),
                                   said: rowSaid(r, L10n.t("formsEditor.relay.addressSetAnnounce", ["name": name]),
                                                 L10n.t("formsEditor.relay.addressSetPending", ["name": name])),
                                   row: "recipient:\(name)", r: r) }
        }
        .disabled(!draft.contains("@") || !r.secrets.storageAvailable)
      }
      if let problem = rowProblems[name] { FieldProblem(problem) }
      let note = savedNote("recipient:\(name)", r, L10n.t("formsEditor.relay.addressSetAnnounce", ["name": name]),
                           L10n.t("formsEditor.relay.addressSetPending", ["name": name]))
      if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.green) }
    }
  }

  /// The row's note as it will read once saved, said at the save: QuartzControl's note was a
  /// status line, read out when it appeared; here it was only shown (measured 2026-11-09). A saved
  /// secret changes config.php, so an uploaded relay is outdated after it (`RelayWords.outdated`).
  private func rowSaid(_ r: RelayState, _ set: String, _ setPending: String) -> String {
    r.lastUpload != nil && r.hashProblem == nil ? setPending : set
  }

  /// What saving a secret in a row did, until the next upload; asked of the state read after the save.
  private func savedNote(_ row: String, _ r: RelayState, _ set: String, _ setPending: String) -> String {
    guard let p = pending[row], p.at == (r.lastUpload?["at"]?.stringValue ?? ""), p.before != r else { return "" }
    return RelayWords.outdated(r) ? setPending : set
  }

  private func row<Content: View>(_ label: String, hint: String?, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
      content()
      if let hint { Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }
  }

  private func toggle(_ label: String, hint: String, on: Bool, set: @escaping @Sendable (Bool) -> Void) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Toggle(label, isOn: Binding(get: { on }, set: set))
      Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: Doing

  private func source() -> PluginSource? { PluginSource(view.entry.plugin.source) }

  @discardableResult
  private func save(_ change: [String: JSONValue?]) async -> Bool {
    guard let r = state.relay, let source = source() else { return false }
    var settings = r.settings
    for (key, value) in change { settings[key] = value }
    do {
      let relay = await RelayWords.relay(model, source: source)
      try relay.saveSettings(settings)
      message = nil
      result = nil
      state.relayRound += 1
      return true
    } catch {
      message = error.message
      return false
    }
  }

  private func saveSecrets(_ change: RelaySecretsChange, said: String?, row: String?, r: RelayState) async {
    do {
      try AppDeploy.connections().saveRelaySecrets(model.project.id, change)
      message = nil
      result = nil
      if let row { pending[row] = (r.lastUpload?["at"]?.stringValue ?? "", r) }
      if let said { Announce.post(said) }
      state.relayRound += 1
    } catch {
      message = error.message
    }
  }

  private func renewSecret(_ r: RelayState) async {
    let (question, detail) = Confirm.split(L10n.t("formsEditor.relay.renewSecretConfirm"))
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("formsEditor.relay.renewSecretSubmit"), destructive: true,
                            window: unsaved?.window) else { return }
    await saveSecrets(RelaySecretsChange(renewSecret: true), said: L10n.t("formsEditor.relay.renewSecretAnnounce"), row: nil, r: r)
  }

  private func useUrl(_ url: String) async {
    if await FormsTab.update(model, { options in
      var next = options
      var transport = options["transport"]?.objectValue ?? JSONObject([("kind", .string("relay"))])
      transport["url"] = .string(url)
      next["transport"] = .object(transport)
      return next
    }) {
      Announce.post(L10n.t("formsEditor.relay.urlAnnounce"))
    }
  }

  private func exclude(_ conflict: RelayConflict) async {
    guard let source = source() else { return }
    let relay = await RelayWords.relay(model, source: source)
    do {
      try relay.excludeFromSite(targetId: conflict.targetId, path: conflict.exclude)
      state.relayRound += 1
    } catch {
      message = error.message
    }
  }

  /// A refusal is said with its reason: the first line of the log that is no "↑"/"✗" entry.
  private func failedSaid(_ output: String, _ failed: String) -> String {
    let reason = output.split(separator: "\n").map(String.init).first { line in
      !line.trimmingCharacters(in: .whitespaces).isEmpty && !line.hasPrefix("↑ ") && !line.hasPrefix("✗ ")
    }
    return reason.map { "\(failed) \($0.trimmingCharacters(in: .whitespaces))" } ?? failed
  }

  private func upload() async {
    guard let source = source() else { return }
    busy = "upload"
    result = nil
    defer { busy = nil }
    let probe = RelayWords.probe(view)
    let r = await RelayWords.relay(model, source: source).upload(url: probe?.url, form: probe?.form)
    result = r
    let sentence = r.success ? L10n.t("formsEditor.relay.uploadedAnnounce") : failedSaid(r.output, L10n.t("formsEditor.relay.uploadFailedAnnounce"))
    Announce.post(r.check.map { "\(sentence) \(RelayWords.checkText($0, configReadable: r.configReadable == true))" } ?? sentence)
    state.relayRound += 1
  }

  private func export() async {
    guard let source = source() else { return }
    guard let dir = ProjectsModel.pickFolder(start: nil) else { return }
    let (question, detail) = Confirm.split(L10n.t("formsEditor.relay.exportConfirm", ["dir": dir]))
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("formsEditor.relay.exportSubmit"), destructive: true,
                            window: unsaved?.window) else { return }
    busy = "export"
    result = nil
    defer { busy = nil }
    result = await RelayWords.relay(model, source: source).export(to: dir)
  }

  private func remove(_ r: RelayState) async {
    guard let last = r.lastUpload, let source = source() else { return }
    let targetId = last["targetId"]?.stringValue ?? ""
    let target = r.targets.first { $0.id == targetId }?.name ?? targetId
    let subdir = (last["location"]?.stringValue ?? "").split(separator: "|", omittingEmptySubsequences: false).last.map(String.init) ?? ""
    let (question, detail) = Confirm.split(L10n.t("formsEditor.relay.removeConfirm", ["target": target, "subdir": subdir]))
    guard await Confirm.ask(question, detail: detail, confirm: L10n.t("formsEditor.relay.removeSubmit"), destructive: true,
                            window: unsaved?.window) else { return }
    busy = "remove"
    result = nil
    defer { busy = nil }
    let done = await RelayWords.relay(model, source: source).remove()
    result = RelayUploadResult(success: done.success, output: done.output)
    Announce.post(done.success ? L10n.t("formsEditor.relay.removedAnnounce")
                  : failedSaid(done.output, L10n.t("formsEditor.relay.removeFailedAnnounce")))
    state.relayRound += 1
  }
}

/// A secret the relay needs: whether it is set (never its value), a field to set or replace it, a
/// bin to remove it.
private struct SecretRow: View {
  let label: String
  let hint: String
  let isSet: Bool
  let needed: Bool
  let disabled: Bool
  /// What saving here did; empty until then.
  let note: String
  let save: (String) -> Void
  let remove: () -> Void

  @State private var draft = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text(label)
        if needed {
          WordBadge(text: isSet ? L10n.t("formsEditor.relay.secretSet") : L10n.t("formsEditor.relay.secretMissing")).foregroundStyle(isSet ? .green : .red)
        } else if isSet {
          WordBadge(text: L10n.t("formsEditor.relay.secretSet"))
        }
        Spacer()
        if isSet {
          Button(action: remove) { Label(L10n.t("formsEditor.relay.removeSecretNamed", ["name": label]), systemImage: "trash").labelStyle(.iconOnly) }
            .buttonStyle(.borderless)
            .help(L10n.t("formsEditor.relay.removeSecretNamed", ["name": label]))
        }
      }
      HStack {
        SecureField(label, text: $draft).textFieldStyle(.roundedBorder).labelsHidden().disabled(disabled)
        Button(L10n.t("formsEditor.relay.saveSecret")) {
          let value = draft
          draft = ""
          save(value)
        }
        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || disabled)
      }
      if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.green) }
      Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// A form's recipient when it sends through the relay (QuartzControl's `RelayRecipientField`): a
/// choice among the names already there (the other relay forms' and the ones with a stored
/// address), with the address's state beside it. "Neuer Empfänger …" takes a name and an address
/// at once; the address goes into the Keychain.
struct RelayRecipientField: View {
  let value: String
  /// The names to offer: the other relay forms' recipients and the stored ones.
  let names: [String]
  /// The names with a stored address; nil while the relay's state is not known.
  let stored: [String]?
  let storageAvailable: Bool
  let pick: (String?) -> Void
  let saveAddress: (String, String) async throws -> Void

  @State private var adding = false
  @State private var newName = ""
  @State private var address = ""
  @State private var error: String?
  @State private var busy = false

  private var options: [String] {
    var all: [String] = []
    for name in names + (value.isEmpty ? [] : [value]) where !all.contains(name) { all.append(name) }
    return all.sorted { $0.localizedCompare($1) == .orderedAscending }
  }

  var body: some View {
    let hasAddress: Bool? = stored == nil || value.isEmpty ? nil : stored!.contains(value)
    let nameProblem: String? = newName.isEmpty ? L10n.t("formsEditor.recipientPick.nameProblem.empty")
      : !FormsOptions.isRecipientName(newName) ? L10n.t("formsEditor.recipientPick.nameProblem.pattern")
      : options.contains(newName) ? L10n.t("formsEditor.recipientPick.nameProblem.taken") : nil
    VStack(alignment: .leading, spacing: 6) {
      Text(L10n.t("formsEditor.recipient.relay"))
      Picker(L10n.t("formsEditor.recipient.relay"), selection: Binding(get: { adding ? "__new" : value }, set: { next in
        error = nil
        if next == "__new" { adding = true; return }
        adding = false
        pick(next.isEmpty ? nil : next)
      })) {
        Text(L10n.t("formsEditor.recipientPick.none")).tag("")
        ForEach(options, id: \.self) { name in
          if let stored {
            Text(verbatim: "\(name) (\(stored.contains(name) ? L10n.t("formsEditor.relay.addressSet") : L10n.t("formsEditor.relay.addressMissing")))").tag(name)
          } else {
            Text(verbatim: name).tag(name)
          }
        }
        Text(L10n.t("formsEditor.recipientPick.new")).tag("__new")
      }
      .labelsHidden()
      if !adding, let hasAddress {
        WordBadge(text: hasAddress ? L10n.t("formsEditor.relay.addressSet") : L10n.t("formsEditor.relay.addressMissing"))
          .foregroundStyle(hasAddress ? .green : .red)
      }
      if !adding, hasAddress == false, storageAvailable {
        HStack {
          TextField(L10n.t("formsEditor.relay.addressFor", ["name": value]), text: $address, prompt: Text(verbatim: "name@example.org"))
            .textFieldStyle(.roundedBorder).labelsHidden()
          Button(L10n.t("formsEditor.relay.saveAddress")) { Task { if await save(value, address) { address = "" } } }
            .disabled(!address.contains("@") || busy)
        }
      }
      if adding {
        VStack(alignment: .leading, spacing: 6) {
          Text(L10n.t("formsEditor.recipientPick.name"))
          TextField(L10n.t("formsEditor.recipientPick.name"), text: Binding(get: { newName }, set: { newName = $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
                    prompt: Text(verbatim: "kontakt"))
            .textFieldStyle(.roundedBorder).labelsHidden()
          Text(L10n.t("formsEditor.recipientPick.nameHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          if !newName.isEmpty, let nameProblem { FieldProblem(nameProblem) }
          if storageAvailable {
            Text(L10n.t("formsEditor.recipientPick.address"))
            TextField(L10n.t("formsEditor.recipientPick.address"), text: $address, prompt: Text(verbatim: "name@example.org"))
              .textFieldStyle(.roundedBorder).labelsHidden()
            Text(L10n.t("formsEditor.recipientPick.addressHint")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          }
          HStack {
            Button(L10n.t("formsEditor.recipientPick.add")) {
              Task {
                if storageAvailable, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !(await save(newName, address)) { return }
                pick(newName)
                adding = false
                newName = ""
                address = ""
              }
            }
            .disabled(nameProblem != nil || busy)
            Button(L10n.t("common.cancel")) { adding = false }
          }
        }
        .padding(8)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
      }
      if let error { Callout(.error, error) }
      Text(L10n.t("formsEditor.recipientHint.relay")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }

  private func save(_ name: String, _ text: String) async -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.contains("@") else { return false }
    if FormsOptions.isExampleAddress(trimmed) {
      error = L10n.t("formsEditor.relay.exampleAddress")
      return false
    }
    busy = true
    defer { busy = false }
    do {
      try await saveAddress(name, trimmed)
      error = nil
      return true
    } catch {
      self.error = (error as? PublishFailure)?.message ?? String(describing: error)
      return false
    }
  }
}
