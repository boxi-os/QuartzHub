import CryptoKit
import Darwin
import Foundation
import Synchronization

/// What a relay upload or export answers (`RelayUploadResult`): the adapter's result, the probe
/// after an upload, where the counters were served, and the mode config.php got.
public struct RelayUploadResult: Equatable, Sendable {
  public var success: Bool
  public var output: String
  public var configReadable: Bool?
  public var check: RelayCheck?
  public var countersOpen: String?

  public init(success: Bool, output: String, configReadable: Bool? = nil, check: RelayCheck? = nil, countersOpen: String? = nil) {
    self.success = success
    self.output = output
    self.configReadable = configReadable
    self.check = check
    self.countersOpen = countersOpen
  }
}

/// A site target whose rsync --delete would remove the relay (`RelayConflict`).
public struct RelayConflict: Equatable, Sendable {
  public let targetId: String
  public let targetName: String
  /// The relay's folder relative to that target's remote path, as its excludes would name it.
  public let exclude: String
}

/// `RelayState`: what the relay section shows.
public struct RelayState: Equatable, Sendable {
  public struct Secrets: Equatable, Sendable {
    public let stored: Bool
    public let recipients: [String]
    public let captchaSecret: Bool
    public let captchaSecrets: [String]
    public let storageAvailable: Bool
    /// `RelaySecretInfo.missing`.
    public var missing = false
  }

  public struct Target: Equatable, Sendable {
    public let id: String
    public let name: String
    public let type: String
    public let `where`: String
    /// An SFTP target that transfers with rsync, which cannot carry some folder names.
    public let rsync: Bool
  }

  /// The stored settings over the defaults (`RelayFile.settings`).
  public let settings: JSONObject
  public let lastUpload: JSONObject?
  public let removedAt: String?
  public let secrets: Secrets
  public let targets: [Target]
  public let conflict: RelayConflict?
  public let currentHash: String?
  public let hashProblem: String?
  public let siteOrigin: String?
  public let relayForms: [String]
  public let recipientNames: [String]
  /// nil without a target or a last upload.
  public let moved: Bool?
  public let configModeChanged: Bool
  public let operatorChanged: Bool
}

/// The quartz-forms relay (the second part of QuartzControl's `formsService.ts`): its settings,
/// state, upload, export and removal. What is not secret lives with the project in
/// `.quartz-gui/forms-relay.json`; what is secret in the Keychain (`Connections`, by project id).
/// The relay itself is written by quartz-forms (`dist/cli.js relay`) into a temporary folder, with
/// the owner's values in the child's environment, uploaded through the target's adapter
/// (`Deploy.directoryUpload`), and removed at every exit: a plain-text config.php never stays in
/// the project.
///
/// Deviations, each a decision:
/// - `excludeFromSite` keeps the site target's `withDocuments`; QuartzControl saved the target
///   without it and so dropped "Dokumente mitnehmen" (a finding of QuartzControl's).
/// - A Keychain failure while reading or making the relay's secrets is the upload's failed answer;
///   QuartzControl rejected the call.
/// - The temporary folders are `qh-relay-*`.
public struct FormsRelay: Sendable {
  public let project: String
  public let projectId: String
  public let cli: FormsCLI
  public let connections: Connections
  public let deploy: Deploy
  public let probe: RelayProbe
  let now: @Sendable () -> Date

  public init(projectId: String, cli: FormsCLI, connections: Connections, deploy: Deploy, probe: RelayProbe = RelayProbe(),
              now: @escaping @Sendable () -> Date = { Date() }) {
    self.project = cli.project
    self.projectId = projectId
    self.cli = cli
    self.connections = connections
    self.deploy = deploy
    self.probe = probe
    self.now = now
  }

  /// The relay's files that carry its code and the owner's values; counters/ is the server's.
  static let removed = ["send.php", "config.php", "config.generated.php"]

  var files: QuartzGuiDirectory { QuartzGuiDirectory(project: project) }
  var targets: PublishTargets { PublishTargets(project: project) }

  func readFile() -> RelayFile {
    if case .ok(let value) = JSONStore.read(files.formsRelay), let object = value.objectValue { return RelayFile(object: object) }
    return RelayFile(object: JSONObject())
  }

  func writeFile(_ file: RelayFile) throws(PublishFailure) {
    do {
      try files.create()
      try JSONStore.write(.object(file.object), to: files.formsRelay)
    } catch {
      throw PublishFailure(PublishFailure.message(of: error))
    }
  }

  public func saveSettings(_ settings: JSONObject) throws(PublishFailure) {
    var file = readFile()
    file.object["settings"] = .object(settings)
    try writeFile(file)
  }

  // MARK: helpers as in formsService.ts

  /// The account a relay upload reaches through the target's connection, as user@host.
  func server(of target: PublishTarget) -> String? {
    guard let id = target.connectionId, let connection = connections.get(id), connection.kind == .ssh || connection.kind == .ftp else { return nil }
    return "\(connection.username)@\(JS.trim(connection.host).lowercased())"
  }

  /// Where a relay upload lands, as one string: a change of it means the remote has not seen this relay.
  static func location(of target: PublishTarget, _ subdir: String) -> String {
    let d = target.destination
    let type = JS.string(d["type"])
    let place = type == "folder" ? JS.string(d["path"]) : d["remotePath"].map { JS.string($0) } ?? ""
    return "\(type)|\(target.connectionId ?? "")|\(place)|\(subdir)"
  }

  /// A site target that would delete the relay: rsync with "delete removed files" on the same
  /// connection, with the relay's folder inside its remote path and not in its excludes.
  func rsyncConflict(_ relayTarget: PublishTarget, _ subdir: String) -> RelayConflict? {
    let d = relayTarget.destination
    guard d["type"] == .string("sftp") else { return nil }
    let relayRemote = NodePath.join(JS.string(d["remotePath"]), subdir)
    for site in targets.list() {
      let s = site.destination
      guard s["type"] == .string("sftp"), s["transfer"] == .string("rsync"), JS.truthy(s["deleteRemoved"]),
            site.connectionId == relayTarget.connectionId else { continue }
      let rel = NodePath.relative(JS.string(s["remotePath"]), relayRemote)
      if rel.isEmpty || JSText.startsWith(rel, "..") || JSText.startsWith(rel, "/") { continue }
      if site.excludes.contains(rel) || site.excludes.contains("\(rel)/") { continue }
      return RelayConflict(targetId: site.id, targetName: site.name, exclude: rel)
    }
    return nil
  }

  static func `operator`(_ settings: JSONObject, _ secrets: RelaySecrets) -> JSONObject {
    var o = JSONObject()
    o["secret"] = .string(secrets.secret)
    o["allowedOrigins"] = settings["allowedOrigins"]
    o["from"] = settings["from"]
    o["subjectPrefix"] = settings["subjectPrefix"]
    if let captcha = secrets.object["captchaSecret"], JS.truthy(captcha) { o["captchaSecret"] = captcha }
    if let captchas = secrets.object["captchaSecrets"], JS.truthy(captchas) { o["captchaSecrets"] = captchas }
    o["mailer"] = settings["mailer"] == .string("sendmail") ? .object(JSONObject([("sendmail", settings["sendmailPath"] ?? .null)])) : .string("mail")
    // Only when off: a key with the default would change operatorStamp() of every relay uploaded before.
    if !JS.truthy(settings["envelopeSender"]) { o["envelopeSender"] = .bool(false) }
    o["recipients"] = .object(secrets.recipients)
    let counterDir = JS.trim(JS.string(settings["counterDir"]))
    if !counterDir.isEmpty { o["counterDir"] = .string(counterDir) }
    return o
  }

  /// What config.php would get from the settings and the stored secrets, as one value: the secrets
  /// as their fingerprint.
  static func operatorStamp(_ settings: JSONObject, _ fingerprint: String?) -> String {
    let open = `operator`(settings, RelaySecrets(object: JSONObject([("secret", .string("")), ("recipients", .object(JSONObject()))])))
    let text = JSJSON.compact(.array([.object(open), fingerprint.map(JSONValue.string) ?? .null]))
    return String(SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32))
  }

  /// The stored secrets, or a first set with only a fresh signing secret.
  func secretsFor() throws(PublishFailure) -> RelaySecrets {
    if let stored = try connections.relaySecrets(projectId) { return stored }
    try connections.saveRelaySecrets(projectId, RelaySecretsChange())
    // Its addresses are entered in the forms editor; Settings ▸ Connections has nothing for them
    // (review 2026-11-13, nebenbei).
    guard let made = try connections.relaySecrets(projectId) else { throw PublishFailure(L10n.t("main.relaySecretsMissing")) }
    return made
  }

  /// The modes the relay is uploaded with, set on the folder quartz-forms wrote: folders 0755,
  /// files 0644, config.php 0600 (0644 where the web server's PHP must read it).
  static func setModes(_ dir: String, configReadable: Bool) {
    func walk(_ folder: String) {
      chmod(folder, 0o755)
      for entry in Posix.entries(folder) ?? [] {
        let path = "\(folder)/\(entry.name)"
        if entry.kind == .directory {
          walk(path)
        } else {
          chmod(path, folder == dir && entry.name == "config.php" ? (configReadable ? 0o644 : 0o600) : 0o644)
        }
      }
    }
    walk(dir)
  }

  /// `relay --json`; a refusal over problems lists them, else the error and the warnings.
  func runRelay(_ outDir: String, operator: JSONObject?, skipPatternCheck: Bool = false) async -> FormsCLI.Answer {
    let variables = `operator`.map { ["QF_RELAY_OPERATOR": JSJSON.compact(.object($0))] } ?? [:]
    let answer = await cli.run(["relay", "--site", project, "--out", outDir] + (skipPatternCheck ? ["--skip-pattern-check"] : []), variables: variables)
    guard case .failed(let reason, let json?) = answer else { return answer }
    let problems = FormsCLI.strings(json["problems"])
    if !problems.isEmpty { return .failed(problems.map { "- \($0)" }.joined(separator: "\n"), json) }
    let lines = [json["error"]?.stringValue ?? ""] + FormsCLI.strings(json["warnings"])
    _ = reason
    return .failed(lines.filter { !$0.isEmpty }.joined(separator: "\n"), json)
  }

  // MARK: temporary folders

  static let tempPrefix = "qh-relay-"
  static let openTempDirs = Mutex<Set<String>>([])

  public static var tempRoot: String {
    let base = NSTemporaryDirectory()
    return base.hasSuffix("/") ? String(base.dropLast()) : base
  }

  func withTempDir<T>(_ run: (String) async throws(PublishFailure) -> T) async throws(PublishFailure) -> T {
    var template = Array("\(Self.tempRoot)/\(Self.tempPrefix)XXXXXX".utf8CString)
    guard let made = mkdtemp(&template) else { throw PublishFailure("mkdtemp: \(String(cString: strerror(errno)))") }
    let dir = String(cString: made)
    Self.openTempDirs.withLock { _ = $0.insert(dir) }
    defer {
      _ = try? FileManager.default.removeItem(atPath: dir)
      Self.openTempDirs.withLock { _ = $0.remove(dir) }
    }
    return try await run(dir)
  }

  /// At quit: the folders a run still holds (with config.php and the relay's secret in them).
  public static func removeOpenTempDirs() {
    let open = openTempDirs.withLock { dirs -> Set<String> in
      defer { dirs.removeAll() }
      return dirs
    }
    for dir in open { _ = try? FileManager.default.removeItem(atPath: dir) }
  }

  /// At start: the folders a previous run left after a crash, only `qh-relay-*` directly in the
  /// temporary folder and only after an hour (a second instance may be in the middle of one).
  @discardableResult
  public static func sweepTempDirs(now: Date = Date(), root: String = tempRoot) -> [String] {
    sweep(prefix: tempPrefix, now: now, root: root)
  }

  /// Folders named `<prefix>*` directly in `root`, older than an hour; also SSH's (`SSHLogin`).
  static func sweep(prefix: String, now: Date, root: String) -> [String] {
    var removed: [String] = []
    for entry in Posix.entries(root) ?? [] where JSText.startsWith(entry.name, prefix) && entry.kind == .directory {
      let dir = "\(root)/\(entry.name)"
      var info = stat()
      guard lstat(dir, &info) == 0 else { continue }
      let modified = Date(timeIntervalSince1970: Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1e9)
      guard now.timeIntervalSince(modified) >= 3600 else { continue }
      _ = try? FileManager.default.removeItem(atPath: dir)
      removed.append(dir)
    }
    return removed
  }

  // MARK: the calls

  public func state() async -> RelayState {
    let file = readFile()
    let settings = file.settings
    let info = connections.relaySecretInfo(projectId)
    let choices = targets.list().filter { ["sftp", "ftp", "folder"].contains(JS.string($0.destination["type"])) }.map { t in
      let d = t.destination
      let type = JS.string(d["type"])
      return RelayState.Target(id: t.id, name: t.name, type: type, where: type == "folder" ? JS.string(d["path"]) : d["remotePath"].map { JS.string($0) } ?? "",
                               rsync: type == "sftp" && d["transfer"] == .string("rsync"))
    }
    let subdir = JS.string(settings["subdir"])
    let target = settings["targetId"].flatMap { JS.truthy($0) ? $0.stringValue : nil }.flatMap { targets.get($0) }
    let conflict = target.flatMap { rsyncConflict($0, subdir) }
    let generated = try? await withTempDir { dir throws(PublishFailure) in await runRelay(dir, operator: nil, skipPatternCheck: true) }
    var currentHash: String?, siteOrigin: String?, forms: [String] = [], recipients: [String] = [], hashProblem: String?
    switch generated {
    case .ok(let json)?:
      currentHash = json["hash"]?.stringValue
      siteOrigin = json["siteOrigin"]?.stringValue
      forms = FormsCLI.strings(json["forms"])
      recipients = FormsCLI.strings(json["recipients"])
    case .failed(let reason, _)?: hashProblem = reason
    case nil: hashProblem = "mkdtemp"
    }
    let last = file.lastUpload
    var moved: Bool?
    if let target, let last {
      let server = last["server"]
      moved = last["location"] != .string(Self.location(of: target, subdir)) || (server != nil && server != self.server(of: target).map(JSONValue.string))
    }
    let configModeChanged = last?["configReadable"].map { $0 != settings["configReadable"] } ?? false
    let operatorChanged = last?["operator"].map { $0 != .string(Self.operatorStamp(settings, info.fingerprint)) } ?? false
    // storageAvailable stays in the state for QuartzControl's format (Electron's safeStorage could be
    // missing on Linux); on macOS the Keychain is always there, so it is true, and the two hints
    // for "no storage" are gone from the page - their sentence about placeholders was not even
    // what the export does (review 2026-11-13, handbook, N9).
    return RelayState(settings: settings, lastUpload: last, removedAt: last == nil ? file.removedAt : nil,
                      secrets: .init(stored: info.stored, recipients: info.recipients, captchaSecret: info.captchaSecret,
                                     captchaSecrets: info.captchaSecrets, storageAvailable: true, missing: info.missing),
                      targets: choices, conflict: conflict, currentHash: currentHash, hashProblem: hashProblem, siteOrigin: siteOrigin,
                      relayForms: forms, recipientNames: recipients, moved: moved, configModeChanged: configModeChanged, operatorChanged: operatorChanged)
  }

  public func upload(url: String? = nil, form: String? = nil) async -> RelayUploadResult {
    let failed = { (output: String) in RelayUploadResult(success: false, output: output) }
    var file = readFile()
    let settings = file.settings
    guard let targetId = settings["targetId"].flatMap({ JS.truthy($0) ? JS.string($0) : nil }) else { return failed(L10n.t("main.relayNoTarget")) }
    guard let target = targets.get(targetId) else { return failed(L10n.t("main.deployTargetMissing", ["id": targetId])) }
    let subdir = JS.string(settings["subdir"])
    if let conflict = rsyncConflict(target, subdir) {
      return failed(L10n.t("main.relayRsyncConflict", ["target": conflict.targetName, "path": conflict.exclude]))
    }
    let configReadable = JS.truthy(settings["configReadable"])
    do {
      let secrets = try secretsFor()
      return try await withTempDir { dir throws(PublishFailure) -> RelayUploadResult in
        let generated: JSONObject
        switch await runRelay(dir, operator: Self.operator(settings, secrets)) {
        case .failed(let reason, _): return failed(reason)
        case .ok(let json): generated = json
        }
        let missing = FormsCLI.strings(generated["missingRecipients"])
        if !missing.isEmpty { return failed(L10n.t("main.relayMissingRecipients", ["names": missing.joined(separator: ", ")])) }
        let location = Self.location(of: target, subdir)
        Self.setModes(dir, configReadable: configReadable)
        let result = await deploy.directoryUpload(targetId: target.id, localDir: dir, subdir: subdir, manifestKey: "relay-\(target.id)")
        let generation = generated["generation"]?.stringValue
        if result.success, let hash = generated["hash"]?.stringValue {
          var last = JSONObject([("at", .string(JS.isoString(now()))), ("hash", .string(hash)), ("targetId", .string(target.id)),
                                 ("location", .string(location)), ("configReadable", settings["configReadable"] ?? .bool(false)),
                                 ("operator", .string(Self.operatorStamp(settings, connections.relaySecretInfo(projectId).fingerprint)))])
          let counterDir = JS.trim(JS.string(settings["counterDir"]))
          if !counterDir.isEmpty { last["counterDir"] = .string(counterDir) }
          if let server = server(of: target) { last["server"] = .string(server) }
          if let generation { last["generation"] = .string(generation) }
          file.object["removedAt"] = nil
          file.object["lastUpload"] = .object(last)
          try writeFile(file)
        }
        let warnings = FormsCLI.strings(generated["warnings"])
        let allowed = settings["allowedOrigins"]?.arrayValue ?? []
        let origin = generated["siteOrigin"]?.stringValue ?? allowed.first.map { JS.string($0) }
        let forms = FormsCLI.strings(generated["forms"])
        let probeForm = form.flatMap { forms.contains($0) ? $0 : nil } ?? forms.first
        var check = result.success ? await probe.check(url: url, origin: origin, form: probeForm, generation: generation) : nil
        if case .relayError(let u, let status, "origin", let message, _)? = check, let origin, !origin.isEmpty {
          let listed: RelayCheck.Listed = allowed.isEmpty ? .any : Self.originListed(allowed.map { JS.string($0) }, origin) ? .yes : .no
          check = .relayError(url: u, status: status, error: "origin", message: message, origin: .init(sent: origin, listed: listed))
        }
        // Not after `unreachable`: a server that kept silent once kept the upload waiting a second time.
        var countersOpen: String?
        if let check, let url = check.url, JS.trim(JS.string(settings["counterDir"])).isEmpty {
          if case .unreachable = check {} else { countersOpen = await probe.countersServed(url) }
        }
        return RelayUploadResult(success: result.success, output: (warnings + [result.output]).filter { !$0.isEmpty }.joined(separator: "\n"),
                                 configReadable: configReadable, check: check, countersOpen: countersOpen)
      }
    } catch {
      return failed(error.message)
    }
  }

  /// shared/relayOrigin.ts: send.php's rule, case aside (ASCII only), without a trailing slash; an
  /// empty list allows any.
  static func originListed(_ allowed: [String], _ origin: String) -> Bool {
    func bare(_ o: String) -> String {
      String(String.UnicodeScalarView(JSText.replaceAll(o, "/+$", with: "").unicodeScalars.map { ("A"..."Z").contains($0) ? Unicode.Scalar($0.value + 32)! : $0 }))
    }
    return allowed.isEmpty || allowed.contains { bare($0) == bare(origin) }
  }

  /// The whole relay into a folder the user chose, config.php included: with the stored secrets
  /// when there are any, else with the example's placeholders.
  public func export(to dir: String) async -> RelayUploadResult {
    let settings = readFile().settings
    let stored: RelaySecrets
    do {
      stored = try secretsFor()
    } catch {
      return RelayUploadResult(success: false, output: error.message)
    }
    let usable = !JS.trim(JS.string(settings["from"])).isEmpty
    switch await runRelay(dir, operator: usable ? Self.operator(settings, stored) : nil) {
    case .failed(let reason, _): return RelayUploadResult(success: false, output: reason)
    case .ok(let json):
      let written = FormsCLI.strings(json["written"]).map { "→ \($0)" }
      let lines = FormsCLI.strings(json["warnings"]) + written + [usable ? "" : L10n.t("main.relayExportPlaceholders")]
      return RelayUploadResult(success: true, output: lines.filter { !$0.isEmpty }.joined(separator: "\n"))
    }
  }

  /// Takes the relay down where it was last uploaded: send.php, config.php and
  /// config.generated.php, through the target's own adapter, only while the relay there is still
  /// that upload's. counters/ stays.
  public func remove() async -> DeployResult {
    var file = readFile()
    guard let last = file.lastUpload else { return DeployResult(success: false, output: L10n.t("main.relayRemoveNotUploaded")) }
    let targetId = JS.string(last["targetId"])
    guard let target = targets.get(targetId) else { return DeployResult(success: false, output: L10n.t("main.deployTargetMissing", ["id": targetId])) }
    let location = JS.string(last["location"])
    let parts = JSText.split(location, "|")
    let subdir = parts.last ?? ""
    if Self.location(of: target, subdir) != location {
      let type = parts.first ?? "", connectionId = parts.count > 1 ? parts[1] : ""
      let place = parts.count > 2 ? parts[2..<(parts.count - 1)].joined(separator: "|") : ""
      let path = NodePath.join(place, subdir)
      let login = !connectionId.isEmpty && connectionId != (target.connectionId ?? "") ? connections.get(connectionId)?.name : nil
      _ = type
      return DeployResult(success: false, output: L10n.t("main.relayRemoveMoved", ["target": target.name, "path": path,
                                                                                 "login": login.map { L10n.t("main.relayRemoveMovedLogin", ["name": $0]) } ?? ""]))
    }
    let server = server(of: target)
    if let then = last["server"], then != server.map(JSONValue.string) {
      let place = parts.count > 2 ? parts[2..<(parts.count - 1)].joined(separator: "|") : ""
      let path = NodePath.join(place, subdir)
      guard let connection = connections.get(target.connectionId ?? "") else {
        return DeployResult(success: false, output: L10n.t("main.relayRemoveLoginGone", ["target": target.name, "then": JS.string(then), "path": path]))
      }
      return DeployResult(success: false, output: L10n.t("main.relayRemoveServer", ["login": connection.name, "then": JS.string(then), "now": server ?? "", "path": path]))
    }
    do {
      return try await withTempDir { dir throws(PublishFailure) -> DeployResult in
        let result = await deploy.directoryUpload(targetId: target.id, localDir: dir, subdir: subdir, manifestKey: "relay-\(target.id)",
                                                  remove: Self.removed, ownGeneration: last["generation"]?.stringValue)
        guard result.success else { return result }
        file.object["lastUpload"] = nil
        file.object["removedAt"] = .string(JS.isoString(now()))
        try writeFile(file)
        let counterDir = last["counterDir"].flatMap { JS.truthy($0) ? JS.string($0) : nil }
        let stays = counterDir.map { L10n.t("main.relayRemovedRestCounterDir", ["subdir": subdir, "counterDir": $0]) } ?? L10n.t("main.relayRemovedRest", ["subdir": subdir])
        return JSText.test(result.output, "(?m)^✗ ") ? DeployResult(success: true, output: "\(Self.trimEnd(result.output))\n\(stays)") : result
      }
    } catch {
      return DeployResult(success: false, output: error.message)
    }
  }

  static func trimEnd(_ text: String) -> String {
    var scalars = Array(text.unicodeScalars)
    while let last = scalars.last, JS.isTrimmed(last) { scalars.removeLast() }
    return String(String.UnicodeScalarView(scalars))
  }

  /// Adds the relay's folder to a site target's excludes, so its rsync --delete leaves it alone.
  public func excludeFromSite(targetId: String, path: String) throws(PublishFailure) {
    guard let target = targets.get(targetId) else { throw PublishFailure(L10n.t("main.deployTargetMissing", ["id": targetId])) }
    if target.excludes.contains(path) { return }
    _ = try targets.save(SavePublishTargetInput(id: target.id, name: target.name, connectionId: target.connectionId, destination: target.destination,
                                                excludes: target.excludes + [path], withDocuments: target.withDocuments.isEmpty ? nil : target.withDocuments))
  }
}
