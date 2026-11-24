import CoreGraphics
import Darwin
import Foundation
import ImageIO
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import QuartzHubCore

/// The screenshot server for `ThemeScreenshotsTests`: bytes per address, or a network error without
/// them; every request counted.
final class ScreenshotNet: URLProtocol, @unchecked Sendable {
  struct State {
    var answers: [String: Data] = [:]
    var requests: [String] = []
  }

  static let state = Mutex(State())

  static var configuration: URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ScreenshotNet.self]
    return configuration
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let url = request.url!.absoluteString
    let body: Data? = Self.state.withLock { state in
      state.requests.append(url)
      return state.answers[url]
    }
    guard let body else {
      client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
      return
    }
    let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [:])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite(.serialized)
struct ThemeScreenshotsTests {
  static let address = "https://raw.githubusercontent.com/kepano/obsidian-minimal/HEAD/dark-simple.png"
  let scratch = TestFolder.make("qh-screenshots")
  var profile: ProfileDirectory { ProfileDirectory("\(scratch)/userData") }

  init() {
    ScreenshotNet.state.withLock { $0 = ScreenshotNet.State() }
  }

  static func png(width: Int, height: Int) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let out = NSMutableData()
    let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return out as Data
  }

  static func size(_ data: Data) -> (Int, Int)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
    return (properties[kCGImagePropertyPixelWidth] as! Int, properties[kCGImagePropertyPixelHeight] as! Int)
  }

  func serve(_ data: Data?) { ScreenshotNet.state.withLock { $0.answers[Self.address] = data } }
  var requests: Int { ScreenshotNet.state.withLock { $0.requests.count } }

  func screenshots(now: @escaping @Sendable () -> Date = Date.init) -> ThemeScreenshots {
    ThemeScreenshots(profile: profile, configuration: ScreenshotNet.configuration, now: now)
  }

  @Test func scaledOnceThenKept() async throws {
    serve(Self.png(width: 2400, height: 1500))
    let shots = screenshots()
    let data = try #require(await shots.image(Self.address))
    let size = try #require(Self.size(data))
    #expect(size.0 == ThemeScreenshots.maxPixels && size.1 == 500)
    #expect(data.starts(with: [0xFF, 0xD8]))
    _ = await shots.image(Self.address)
    #expect(requests == 1)
    // A new run reads the profile's copy, without the network.
    serve(nil)
    #expect(await screenshots().image(Self.address) == data)
    #expect(requests == 1)
    // A small picture is not scaled up.
    let small = ThemeScreenshots.scale(Self.png(width: 300, height: 200))
    #expect(small.flatMap(Self.size).map { $0.0 == 300 && $0.1 == 200 } == true)
  }

  @Test func aFailureIsNotAskedAgainAtOnce() async throws {
    let clock = ThemeCatalogTests.Clock()
    let shots = screenshots(now: clock.now)
    #expect(await shots.image(Self.address) == nil)
    #expect(await shots.image(Self.address) == nil)
    #expect(requests == 1)
    clock.advance(hours: 0.3)
    serve(Self.png(width: 100, height: 100))
    #expect(await shots.image(Self.address) != nil)
    #expect(requests == 2)
  }

  @Test func anOldCopyAnswersWhenTheNetworkDoesNot() async throws {
    serve(Self.png(width: 100, height: 100))
    let first = try #require(await screenshots().image(Self.address))
    serve(nil)
    let clock = ThemeCatalogTests.Clock()
    clock.advance(hours: 24 * 8)
    #expect(await screenshots(now: clock.now).image(Self.address) == first)
    #expect(requests == 2)
  }

  @Test func onlyPicturesWithinTheLimit() async throws {
    #expect(ThemeScreenshots.scale(Data("<svg xmlns='http://www.w3.org/2000/svg'/>".utf8)) == nil)
    #expect(ThemeScreenshots.scale(Self.png(width: ThemeScreenshots.maxSourcePixels + 1, height: 1)) == nil)
    #expect(ThemeScreenshots.scale(Self.png(width: ThemeScreenshots.maxSourcePixels, height: 1)) != nil)
    // Not an http(s) address: not asked.
    #expect(await screenshots().image("file:///etc/hosts") == nil)
    #expect(requests == 0)
  }
}
