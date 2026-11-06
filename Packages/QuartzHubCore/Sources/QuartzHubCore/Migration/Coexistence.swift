import Foundation

/// Running next to QuartzControl (docs/plan.md, "Nebeneinander-Betrieb"). QuartzControl knows no
/// locks across processes, so QuartzHub warns before it writes into a project while QuartzControl
/// runs or one of its dev servers does. A server QuartzControl started is never one of QuartzHub's
/// orphans: QuartzHub reports it, it does not stop it.
public enum Coexistence {
  /// QuartzControl's bundle id on macOS (electron-builder drops the underscore of boxi_os).
  public static let quartzControlBundleID = "io.github.boxios.quartzcontrol"

  public struct ForeignServer: Equatable, Sendable {
    public let projectId: String
    public let projectPath: String?
    public let pid: Int32
    public let port: Int?
  }

  /// QuartzControl's dev servers that are still running: entries of its `running-servers.json`
  /// whose pid lives and whose command line still has `quartz` and `--serve`, QuartzControl's own
  /// test before it signals (`buildService.ts` `isQuartzServer`; "eine PID trägt nicht über die
  /// Zeit"). Read only; QuartzControl empties the file on its next start.
  public static func foreignServers(
    profile: ProfileDirectory = .quartzControl,
    commandLine: (Int32) -> String? = Coexistence.commandLine
  ) -> [ForeignServer] {
    guard case .ok(let value) = JSONStore.peek(profile.runningServers) else { return [] }
    let servers = JSONMap<TrackedServer>(value)
    let projects: [String: String] = {
      guard case .ok(let list) = JSONStore.peek(profile.projects) else { return [:] }
      return Dictionary(JSONList<ProjectEntry>(list).items.map { ($0.id, $0.path) }, uniquingKeysWith: { first, _ in first })
    }()
    return servers.keys.compactMap { id in
      guard let server = servers[id], let pid = server.pid, pid > 0, kill(pid, 0) == 0,
            let command = commandLine(pid), command.contains("quartz"), command.contains("--serve")
      else { return nil }
      return ForeignServer(projectId: id, projectPath: projects[id], pid: pid, port: server.port)
    }
  }

  /// `ps -p <pid> -o command=`, as QuartzControl asks; nil when the process is gone.
  public static func commandLine(_ pid: Int32) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/ps") // path boundary: Process takes a URL; the path is a constant
    process.arguments = ["-p", String(pid), "-o", "command="]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }
    let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }
}
