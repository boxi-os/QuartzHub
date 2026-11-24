import Testing
@testable import QuartzHubCore

/// `ThemeSource`: the four sources of the Community-Themes page, read in core 3.1.1's order
/// (`resolveTheme`) and written so core reads them as meant.
struct ThemeSourceTests {
  @Test func readsAsCoreDoes() {
    #expect(ThemeSource.kind(of: "Minimal") == .catalog)
    #expect(ThemeSource.kind(of: "catppuccin.frappe") == .catalog)
    #expect(ThemeSource.kind(of: " Obsidian default ") == .catalog)
    #expect(ThemeSource.kind(of: "kepano/obsidian-minimal") == .repo)
    #expect(ThemeSource.kind(of: "https://example.org/t/theme.css?quartzhub") == .address)
    // core takes a path before an address: anything on .css is a file.
    #expect(ThemeSource.kind(of: "https://example.org/t/theme.css") == .file)
    #expect(ThemeSource.kind(of: "./themes/mine") == .file)
    #expect(ThemeSource.kind(of: "themes/mine/theme.css") == .file)
    #expect(ThemeSource.kind(of: "~/x") == .file)
  }

  @Test func writesWhatCoreReadsAsMeant() {
    #expect(ThemeSource.value(" Things ", kind: .catalog) == .success("Things"))
    #expect(ThemeSource.value("https://github.com/kepano/obsidian-minimal.git", kind: .repo) == .success("kepano/obsidian-minimal"))
    #expect(ThemeSource.value("kepano", kind: .repo) == .failure(.notRepo))
    #expect(ThemeSource.value("https://example.org/t/theme.css", kind: .address) == .success("https://example.org/t/theme.css?quartzhub"))
    #expect(ThemeSource.value("https://example.org/t/theme", kind: .address) == .success("https://example.org/t/theme"))
    #expect(ThemeSource.value("example.org/theme.css", kind: .address) == .failure(.notAddress))
    #expect(ThemeSource.value("themes/mine", kind: .file) == .success("./themes/mine"))
    #expect(ThemeSource.value("/abs/theme.css", kind: .file) == .success("/abs/theme.css"))
    #expect(ThemeSource.value("  ", kind: .repo) == .failure(.empty))
    // Each written value reads back as its kind.
    for kind in ThemeSource.Kind.allCases {
      let typed = ["catalog": "Things", "repo": "a/b", "address": "https://x.org/theme.css", "file": "t/theme"][kind.rawValue]!
      guard case .success(let written) = ThemeSource.value(typed, kind: kind) else { Issue.record("\(kind)"); continue }
      #expect(ThemeSource.kind(of: written) == kind)
    }
  }

  @Test func showsTheAddressAsTyped() {
    #expect(ThemeSource.display("https://example.org/theme.css?quartzhub") == "https://example.org/theme.css")
    #expect(ThemeSource.display("https://example.org/theme?quartzhub") == "https://example.org/theme?quartzhub")
    #expect(ThemeSource.display("Minimal") == "Minimal")
  }

  @Test func pathsInsideTheProjectAreRelative() {
    #expect(ThemeSource.projectPath("/p/Über/themes/x.css", project: "/p/Über") == "./themes/x.css")
    #expect(ThemeSource.projectPath("/p/Über/themes/x.css", project: "/p/Über/") == "./themes/x.css")
    #expect(ThemeSource.projectPath("/p/Über2/x.css", project: "/p/Über") == "/p/Über2/x.css")
  }

  @Test func versionOnlyForTheListAndRepos() {
    #expect(ThemeSource.takesVersion("Minimal"))
    #expect(ThemeSource.takesVersion("kepano/obsidian-minimal"))
    #expect(!ThemeSource.takesVersion("default"))
    #expect(!ThemeSource.takesVersion("./t.css"))
    #expect(!ThemeSource.takesVersion("https://x.org/t"))
  }
}
