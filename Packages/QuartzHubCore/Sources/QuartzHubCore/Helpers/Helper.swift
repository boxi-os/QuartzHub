import Foundation

/// One call of a JS helper (`Helpers/src`, `scripts/build-helpers.sh`): one JSON request on stdin,
/// one JSON answer on stdout, then exit (`Helpers/src/protocol.ts`). A process per call rather than
/// a long-lived one: the spike's sidecar idled at 200 MB, and a call costs some 50 ms.
///
/// Always QuartzHub's own Node, whatever the user chose for Quartz: the helpers are QuartzHub's
/// code, bundled against the Node they were built with. And an environment of its own, not the
/// app's: `NODE_OPTIONS` from a shell profile could load anything into the process.
public enum Helper {
  public enum Failure: Error, Equatable, CustomStringConvertible {
    /// The helper answered that it could not answer (`ok: false`): a request it does not
    /// understand, which is a bug on this side.
    case refused(String)
    /// The helper did not answer at all: missing, crashed, timed out, or printed something else.
    case broken(String)

    public var description: String {
      switch self {
      case .refused(let error): "helper refused the request: \(error)"
      case .broken(let report): "helper did not answer: \(report)"
      }
    }
  }

  public static func call(
    _ name: String,
    _ request: JSONObject,
    runtime: RuntimeLocation = .current,
    timeout: Duration = .seconds(30)
  ) async throws(Failure) -> JSONObject {
    let script = "\(runtime.helpers)/\(name).cjs"
    let command = Command("\(runtime.nodeBin)/node", [script],
                          environment: ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin"],
                          input: Data(JSJSON.stringify(.object(request)).utf8), timeout: timeout)
    let result = await ProcessRunner.run(command)
    guard result.success, case .object(let answer)? = try? JSJSON.parse(result.stdout) else {
      throw .broken(result.report(for: command))
    }
    guard answer["ok"] == .bool(true) else {
      throw .refused(answer["error"]?.stringValue ?? result.stdout)
    }
    return answer
  }
}
