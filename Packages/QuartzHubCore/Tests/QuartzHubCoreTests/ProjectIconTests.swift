import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import QuartzHubCore

@Suite(.serialized) struct ProjectIconTests {
  let scratch: HostPathTests.Scratch
  init() throws { scratch = try HostPathTests.Scratch(umlaut: true) }

  var project: String { "\(scratch.path)/project" }
  // URLs only to read and write the test's own pictures.
  var icon: URL { URL(fileURLWithPath: ProjectIcon.iconPath(project)) }
  var dark: URL { URL(fileURLWithPath: ProjectIcon.darkIconPath(project)) }
  var marker: URL { URL(fileURLWithPath: QuartzGuiDirectory(project: project).projectIcon) }
  var original: URL { URL(fileURLWithPath: ProjectIcon.originalPath(project)) }

  /// A picture of `width` × `height` in `type`, a different colour per seed so two are not equal.
  func image(_ name: String, _ width: Int, _ height: Int, _ type: UTType = .png, seed: CGFloat = 0.2) throws -> URL {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red: seed, green: 0.5, blue: 1 - seed, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let url = scratch.url.appendingPathComponent(name)
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
  }

  func properties(_ url: URL) throws -> (type: String, width: Int, height: Int) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let size = try #require(ProjectIcon.pixelSize(source))
    return (CGImageSourceGetType(source) as String? ?? "", size.width, size.height)
  }

  func markerJSON() throws -> String { try String(contentsOf: marker, encoding: .utf8) }

  /// A project with the icon.png Quartz ships (any picture will do for that part).
  func quartzProject() throws -> Data {
    let shipped = try image("shipped.png", 300, 300, seed: 0.9)
    try FileManager.default.createDirectory(at: icon.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: shipped, to: icon)
    return try Data(contentsOf: shipped)
  }

  @Test func aPNGThatFitsIsCopiedAndTheOriginalKept() throws {
    let shipped = try quartzProject()
    let chosen = try image("mine.png", 256, 128)
    let info = try ProjectIcon.set(project: project, source: chosen.path)
    #expect(try Data(contentsOf: icon) == Data(contentsOf: chosen))
    #expect(try Data(contentsOf: original) == shipped)
    #expect(try markerJSON() == "{\n  \"custom\": true,\n  \"hasOriginal\": true,\n  \"customDark\": false\n}")
    #expect(info.custom && info.width == 256 && info.height == 128)
    #expect(info.thumbnail != nil && !info.unrecorded)

    // A second choice replaces ours and leaves the original alone.
    try ProjectIcon.set(project: project, source: try image("second.png", 64, 64, seed: 0.6).path)
    #expect(try Data(contentsOf: original) == shipped)

    // "Entfernen" restores Quartz's, byte for byte, and forgets everything.
    let cleared = try ProjectIcon.clear(project: project)
    #expect(try Data(contentsOf: icon) == shipped)
    #expect(!FileManager.default.fileExists(atPath: original.path))
    #expect(!FileManager.default.fileExists(atPath: marker.path))
    #expect(!cleared.custom && cleared.width == 300)
  }

  @Test func aJPEGOrAnOversizedPictureBecomesAPNGOf512() throws {
    let info = try ProjectIcon.set(project: project, source: try image("photo.JPG", 1200, 600, .jpeg).path)
    #expect(try properties(icon) == (UTType.png.identifier, 512, 256))
    #expect(info.width == 512 && info.height == 256)
    // Nothing to keep: there was no icon.png before.
    #expect(try markerJSON().contains("\"hasOriginal\": false"))
    try ProjectIcon.set(project: project, source: try image("big.png", 300, 2000).path)
    #expect(try properties(icon) == (UTType.png.identifier, 77, 512))
    // A small JPEG is not scaled up, only made a PNG.
    try ProjectIcon.set(project: project, source: try image("small.jpeg", 40, 30, .jpeg).path)
    #expect(try properties(icon) == (UTType.png.identifier, 40, 30))
    // No original: "Entfernen" leaves the project without icon.png, as it came.
    try ProjectIcon.clear(project: project)
    #expect(!FileManager.default.fileExists(atPath: icon.path))
  }

  @Test func aPhotoTakenUprightComesOutUpright() throws {
    // 100 × 50 pixels with EXIF orientation 6: shown rotated, as a 50 × 100 picture.
    let plain = try image("plain.jpg", 100, 50, .jpeg)
    let source = try #require(CGImageSourceCreateWithURL(plain as CFURL, nil))
    let rotated = scratch.url.appendingPathComponent("rotated.jpg")
    let destination = try #require(CGImageDestinationCreateWithURL(rotated as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
    CGImageDestinationAddImageFromSource(destination, source, 0, [kCGImagePropertyOrientation: 6] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    try ProjectIcon.set(project: project, source: rotated.path)
    #expect(try properties(icon) == (UTType.png.identifier, 50, 100))
  }

  @Test func aJPEGNamedPNGIsReencodedNotCopied() throws {
    let jpeg = try image("photo.jpg", 100, 100, .jpeg)
    let disguised = scratch.url.appendingPathComponent("photo.png")
    try FileManager.default.copyItem(at: jpeg, to: disguised)
    try ProjectIcon.set(project: project, source: disguised.path)
    #expect(try properties(icon).type == UTType.png.identifier)
  }

  @Test func refusedFilesLeaveTheIconAlone() throws {
    let shipped = try quartzProject()
    let gif = try image("anim.gif", 10, 10, .gif)
    #expect(throws: ProjectIcon.Failure.unsupportedFormat) { try ProjectIcon.set(project: project, source: gif.path) }
    let svg = scratch.url.appendingPathComponent("logo.svg")
    try Data("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'/>".utf8).write(to: svg)
    #expect(throws: ProjectIcon.Failure.unsupportedFormat) { try ProjectIcon.set(project: project, source: svg.path) }
    // The right name, the wrong content: an SVG and a text file.
    let fakeSVG = scratch.url.appendingPathComponent("logo.png")
    try FileManager.default.copyItem(at: svg, to: fakeSVG)
    #expect(throws: ProjectIcon.Failure.unreadable) { try ProjectIcon.set(project: project, source: fakeSVG.path) }
    let text = scratch.url.appendingPathComponent("notes.jpg")
    try Data("not a picture".utf8).write(to: text)
    #expect(throws: ProjectIcon.Failure.unreadable) { try ProjectIcon.set(project: project, source: text.path) }
    #expect(try Data(contentsOf: icon) == shipped)
    #expect(!FileManager.default.fileExists(atPath: marker.path))
    #expect(!FileManager.default.fileExists(atPath: original.path))
  }

  @Test func theDarkPictureIsAChoiceOfItsOwn() throws {
    _ = try quartzProject()
    try ProjectIcon.setDark(project: project, source: try image("dark.png", 64, 64, seed: 0.1).path)
    #expect(try markerJSON() == "{\n  \"custom\": false,\n  \"hasOriginal\": false,\n  \"customDark\": true\n}")
    try ProjectIcon.set(project: project, source: try image("light.png", 64, 64).path)
    try ProjectIcon.clear(project: project)
    // Clearing the light one keeps the dark one and says so.
    #expect(FileManager.default.fileExists(atPath: dark.path))
    #expect(try markerJSON() == "{\n  \"custom\": false,\n  \"hasOriginal\": false,\n  \"customDark\": true\n}")
    #expect(ProjectIcon.userChosenStaticFiles(project: project) == ["icon-dark.png"])
    let info = try ProjectIcon.clearDark(project: project)
    #expect(!info.darkCustom && info.darkThumbnail == nil)
    #expect(!FileManager.default.fileExists(atPath: marker.path), "nothing left to record")
  }

  @Test func aMarkerFromBeforeCustomDark() throws {
    // Up to then a dark picture could only be chosen after a light one.
    try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{\"custom\": true, \"hasOriginal\": true}".utf8).write(to: marker)
    _ = try image("x.png", 8, 8)
    try FileManager.default.createDirectory(at: icon.deletingLastPathComponent(), withIntermediateDirectories: true)
    #expect(ProjectIcon.userChosenStaticFiles(project: project) == ["icon.png"])
    try FileManager.default.copyItem(at: scratch.url.appendingPathComponent("x.png"), to: dark)
    #expect(ProjectIcon.userChosenStaticFiles(project: project) == ["icon.png", "icon-dark.png"])
    // Counter-check: without `custom` the same file is a template's.
    try Data("{\"hasOriginal\": true}".utf8).write(to: marker)
    #expect(ProjectIcon.hasUnrecordedDarkIcon(project: project))
    // The golden file from Example reads as written.
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/quartz-gui/Example/project-icon.json")
    try FileManager.default.removeItem(at: marker)
    try FileManager.default.copyItem(at: fixture, to: marker)
    #expect(ProjectIcon.readMarker(project) == .init(custom: true, hasOriginal: true, customDark: true))
  }

  @Test func blobIdIsGitHashObject() async throws {
    let picture = try image("any.png", 20, 20)
    let git = await ProcessRunner.run(Command("/usr/bin/git", ["hash-object", "--", picture.path]))
    #expect(ProjectIcon.gitBlobId(try Data(contentsOf: picture)) + "\n" == git.stdout)
  }

  static let guiTest = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents/QuartzProjekte/gui-test")

  @Test(.enabled(if: FileManager.default.fileExists(atPath: guiTest.appendingPathComponent(".git").path), "gui-test fehlt"))
  func quartzsOwnIconIsNotUnrecorded() async throws {
    // Quartz's icon.png out of gui-test's history, read only.
    let blob = await ProcessRunner.run(Command("/usr/bin/git", ["-C", Self.guiTest.path, "cat-file", "blob", ProjectIcon.quartzIconBlob]))
    try #require(blob.success)
    try FileManager.default.createDirectory(at: icon.deletingLastPathComponent(), withIntermediateDirectories: true)
    let bytes = await ProcessRunner.run(Command("/bin/sh", ["-c", "git -C \"$1\" cat-file blob \"$2\" > \"$3\"", "sh",
                                                             Self.guiTest.path, ProjectIcon.quartzIconBlob, icon.path]))
    try #require(bytes.success)
    #expect(!ProjectIcon.hasUnrecordedIcon(project: project))
    #expect(ProjectIcon.customThumbnail(project: project) == nil, "Quartz's icon shows as the initial")
    // Counter-check: one byte more and it is somebody's picture.
    try (Data(contentsOf: icon) + Data([0])).write(to: icon)
    #expect(ProjectIcon.hasUnrecordedIcon(project: project))
    #expect(ProjectIcon.customThumbnail(project: project) != nil)
  }

  @Test func thumbnailsAreCachedUntilTheFileChanges() throws {
    let big = try image("big.png", 1000, 500)
    let thumb = try #require(ProjectIcon.thumbnail(big.path))
    let source = try #require(CGImageSourceCreateWithData(thumb as CFData, nil))
    #expect(ProjectIcon.pixelSize(source)! == (128, 64))
    let before = ProjectIcon.decodes.load(ordering: .relaxed)
    #expect(ProjectIcon.thumbnail(big.path) == thumb)
    #expect(ProjectIcon.decodes.load(ordering: .relaxed) == before, "decoded again")
    // Another picture under the same name: other size, so decoded anew.
    try FileManager.default.removeItem(at: big)
    _ = try image("big.png", 40, 40)
    let small = try #require(ProjectIcon.thumbnail(big.path))
    #expect(ProjectIcon.decodes.load(ordering: .relaxed) == before + 1)
    #expect(ProjectIcon.pixelSize(CGImageSourceCreateWithData(small as CFData, nil)!)! == (40, 40), "scaled up")
  }
}
