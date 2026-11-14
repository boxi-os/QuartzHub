import QuartzHubCore

/// Where QuartzHub's profile is. `-QHProfileDir <dir>` moves it for tests and measurements, so a run
/// never has to touch the real one.
enum AppProfile {
  static var own: ProfileDirectory {
    LaunchArgument.string("QHProfileDir").map { ProfileDirectory(Posix.onDisk($0)) } ?? .quartzHub
  }
}
