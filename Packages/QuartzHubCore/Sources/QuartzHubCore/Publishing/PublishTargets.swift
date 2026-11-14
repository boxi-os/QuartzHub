import Foundation

/// What the target form saves (`SavePublishTargetInput`). `destination` is the loose object of
/// `PublishDestination`: a field a later version adds survives.
public struct SavePublishTargetInput: Equatable, Sendable {
  public var id: String?
  public var name: String
  public var connectionId: String?
  public var destination: JSONObject
  public var excludes: [String]?
  public var withDocuments: [String]?

  public init(id: String? = nil, name: String, connectionId: String? = nil, destination: JSONObject, excludes: [String]? = nil,
              withDocuments: [String]? = nil) {
    self.id = id
    self.name = name
    self.connectionId = connectionId
    self.destination = destination
    self.excludes = excludes
    self.withDocuments = withDocuments
  }

  /// Why the input cannot be saved, or nil: QuartzControl's `savePublishTargetInput` schema (it
  /// guarded the IPC boundary there; here the form and `save` share it). Lengths in UTF-16 units.
  public var problem: String? {
    let length = { (text: String) in JSText.length(text) }
    if length(name) < 1 || length(name) > 200 { return "name" }
    if let excludes, excludes.count > 100_000 || excludes.contains(where: { length($0) > 4096 }) { return "excludes" }
    if let connectionId, !Self.isUUID(connectionId) { return "connectionId" }
    if let withDocuments, withDocuments.count > 20 || !withDocuments.allSatisfy(Self.isUUID) { return "withDocuments" }
    return Self.destinationProblem(destination)
  }

  /// zod's `uuid()`: RFC 9562 with version 1 to 8, or the nil and max UUIDs.
  static func isUUID(_ text: String) -> Bool {
    JSText.test(text, #"\A(?:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}|00000000-0000-0000-0000-000000000000|ffffffff-ffff-ffff-ffff-ffffffffffff)\z"#)
  }

  static func isAbsolutePath(_ value: JSONValue?) -> Bool {
    guard let path = value?.stringValue else { return false }
    return JSText.length(path) >= 1 && JSText.length(path) <= 4096 && JSText.startsWith(path, "/")
  }

  static func isRemotePath(_ value: JSONValue?) -> Bool {
    guard let path = value?.stringValue, JSText.length(path) >= 1, JSText.length(path) <= 4096 else { return false }
    let problem = RemotePath.problem(path, deleteRemoved: false)
    return problem != .traversal && problem != .empty
  }

  /// `branchName`: what git and an API path both take.
  static func isBranchName(_ value: JSONValue?) -> Bool {
    guard let branch = value?.stringValue, JSText.length(branch) >= 1, JSText.length(branch) <= 255 else { return false }
    return JSText.test(branch, #"\A[A-Za-z0-9][A-Za-z0-9._/\-]*\z"#) && !JSText.includes(branch, "..") && !JSText.endsWith(branch, ".lock")
  }

  static func destinationProblem(_ d: JSONObject) -> String? {
    let isBool = { (key: String) in d[key]?.boolValue != nil }
    switch d["type"]?.stringValue {
    case "sftp":
      guard isRemotePath(d["remotePath"]) else { return "remotePath" }
      guard ["sftp", "rsync"].contains(d["transfer"]?.stringValue ?? "") else { return "transfer" }
      guard isBool("deleteRemoved") else { return "deleteRemoved" }
    case "ftp":
      guard isRemotePath(d["remotePath"]) else { return "remotePath" }
      guard isBool("deleteRemoved") else { return "deleteRemoved" }
    case "folder":
      guard isAbsolutePath(d["path"]) else { return "path" }
      guard isBool("deleteRemoved") else { return "deleteRemoved" }
    case "webhook":
      break
    case "git-branch":
      guard isBranchName(d["branch"]) else { return "branch" }
      guard ["github", "gitlab", "codeberg"].contains(d["provider"]?.stringValue ?? "") else { return "provider" }
    case "document":
      guard isAbsolutePath(d["path"]) else { return "path" }
      guard let book = d["bookId"]?.stringValue, JSText.test(book, #"\A[a-z0-9][a-z0-9-]{0,62}\z"#) else { return "bookId" }
      guard let formats = d["formats"]?.arrayValue, (1...3).contains(formats.count),
            formats.allSatisfy({ ["pdf", "epub", "html"].contains($0.stringValue ?? "") }) else { return "formats" }
    default:
      return "type"
    }
    // The login's own directory with deletion would be emptied by a deploy.
    if let type = d["type"]?.stringValue, type == "sftp" || type == "ftp",
       RemotePath.problem(d["remotePath"]!.stringValue!, deleteRemoved: d["deleteRemoved"]!.boolValue!) == .wholeRoot {
      return "remotePath"
    }
    return nil
  }
}

/// The project's publish targets (`publishTargetsService.ts`): `.quartz-gui/publish-targets.json`,
/// in the project because a target says what this project publishes where, carries no secret
/// (that is the connection's half) and travels with the folder.

public struct PublishTargets: Sendable {
  public let project: String
  let makeID: @Sendable () -> String

  public init(project: String, makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }) {
    self.project = project
    self.makeID = makeID
  }

  var directory: QuartzGuiDirectory { QuartzGuiDirectory(project: project) }

  /// Reading never creates `.quartz-gui/`; a file of the wrong shape is moved aside.
  func read() -> JSONList<PublishTarget> { JSONList(JSONStore.read(directory.publishTargets, orEmpty: .array)) }

  func write(_ list: JSONList<PublishTarget>) throws(PublishFailure) {
    do {
      try directory.create()
      try JSONStore.write(list.json, to: directory.publishTargets)
    } catch {
      throw PublishFailure(String(describing: error))
    }
  }

  public func list() -> [PublishTarget] { read().items }

  public func get(_ id: String) -> PublishTarget? { read().items.first { $0.object["id"] == .string(id) } }

  /// Where a target points, as one comparable string: the manifest records what was last sent
  /// there, so a target pointed elsewhere starts over. Not part of it: the transfer (rsync and
  /// sftp reach the same folder), the name and the exclusions.
  static func locationKey(connectionId: JSONValue?, destination: JSONObject) -> String {
    let where_: String
    if let path = destination["remotePath"] { where_ = JS.string(path) }
    else if let path = destination["path"] { where_ = JS.string(path) }
    else if let branch = destination["branch"] { where_ = "\(JS.string(destination["provider"])):\(JS.string(branch))" }
    else { where_ = "" }
    let connection = connectionId.flatMap { $0 == .null ? nil : JS.string($0) } ?? ""
    return "\(connection)|\(JS.string(destination["type"]))|\(where_)"
  }

  static let known: Set<String> = ["id", "name", "connectionId", "destination", "excludes", "withDocuments"]

  /// `saveTarget`. What a later version wrote into the entry and this one does not know stays (it
  /// goes first, as QuartzControl's spread put it); a target that points elsewhere now loses its
  /// manifest, after the write.
  @discardableResult
  public func save(_ input: SavePublishTargetInput) throws(PublishFailure) -> PublishTarget {
    if let problem = input.problem { throw PublishFailure(L10n.t("main.publishTargetInvalid", ["field": problem])) }
    var list = read()
    let existing = input.id.flatMap { id in list.items.first { $0.object["id"] == .string(id) } }
    var object = JSONObject()
    if let existing {
      for key in existing.object.keys where !Self.known.contains(key) { object[key] = existing.object[key] }
    }
    object["id"] = existing?.object["id"] ?? .string(makeID())
    object["name"] = .string(input.name)
    object["connectionId"] = input.connectionId.map(JSONValue.string)
    object["destination"] = .object(input.destination)
    // An entry without the field keeps none: `all[index].excludes` was undefined there.
    object["excludes"] = input.excludes.map { .array($0.map(JSONValue.string)) } ?? (existing != nil ? existing!.object["excludes"] : .array([]))
    // Only a target that uploads a folder takes documents along; a document target never itself.
    let type = input.destination["type"]?.stringValue
    if let documents = input.withDocuments, !documents.isEmpty, type != "document", type != "webhook" {
      object["withDocuments"] = .array(documents.map(JSONValue.string))
    }
    let target = PublishTarget(object: object)
    let movedAway = existing.map {
      Self.locationKey(connectionId: $0.object["connectionId"], destination: $0.destination)
        != Self.locationKey(connectionId: object["connectionId"], destination: input.destination)
    } ?? false
    list.upsert(target, id: object["id"]!.stringValue ?? "")
    try write(list)
    if movedAway { DeployManifests(project: project).forget(target.id) }
    return target
  }

  public func delete(_ id: String) throws(PublishFailure) {
    var list = read()
    list.entries.removeAll { $0["id"] == .string(id) }
    try write(list)
  }

  /// The "still in use" check before a connection is deleted.
  public func using(connection id: String) -> [PublishTarget] { list().filter { $0.object["connectionId"] == .string(id) } }
}
