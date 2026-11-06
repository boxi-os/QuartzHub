import Foundation
import Testing
@testable import QuartzHubCore

/// The JSON reader and writer against Node itself, the program whose bytes they must reproduce.
/// Node is the one QuartzHub ships (`Runtime/node`, fetched by scripts/fetch-runtime.sh); without
/// it these tests are reported as skipped, not passed.
@Suite struct JSJSONTests {
  static let node: URL? = {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Runtime/node/bin/node")
    return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
  }()

  /// Runs `script` in Node with `input` on stdin and returns stdout.
  static func runNode(_ script: String, input: String) throws -> String {
    let process = Process()
    process.executableURL = node!
    process.arguments = ["-e", script]
    let stdin = Pipe(), stdout = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    try process.run()
    stdin.fileHandleForWriting.write(Data(input.utf8))
    try stdin.fileHandleForWriting.close()
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    return String(decoding: data, as: UTF8.self)
  }

  // Each text goes through JSON.parse and JSON.stringify(…, null, 2) on both sides.
  static let corpus: [String] = [
    #"{"b":1,"a":2,"10":3,"2":4,"02":5,"-1":6,"4294967294":7,"4294967295":8,"1.0":9}"#,
    #"{"a":1,"b":2,"a":3}"#,
    #"{"s":"\"\\/\b\f\n\r\t\u0001\u001f\u007f\u2028\u2029äöü€😀","e":"\ud83d\ude00"}"#,
    #"[0,-0,1,-1,0.1,1e21,1e-7,1e-6,123456789012345680000,1.5e300,5e-324,1.7976931348623157e308,2e308,0.000001,1e20,100,12.50,1E3,-1.25e-10]"#,
    #"{"empty":{},"list":[],"nested":{"x":[{"y":[[]]},null,true,false]}}"#,
    " \t\r\n {\"spaced\" : [ 1 , 2 ] } \n",
    #""just a string""#,
    "[]",
    "{}"
  ]

  @Test(.enabled(if: node != nil, "Runtime/node fehlt: scripts/fetch-runtime.sh"))
  func roundTripMatchesNode() throws {
    let script = """
    let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{
      const out=JSON.parse(s).map(t=>JSON.stringify(JSON.parse(t),null,2));
      process.stdout.write(JSON.stringify(out));
    })
    """
    let input = JSJSON.stringify(.array(Self.corpus.map { .string($0) }))
    let fromNode = try JSJSON.parse(try Self.runNode(script, input: input)).arrayValue!.map { $0.stringValue! }
    let ours = try Self.corpus.map { JSJSON.stringify(try JSJSON.parse($0)) }
    #expect(fromNode.count == ours.count)
    for (index, (expected, actual)) in zip(fromNode, ours).enumerated() {
      #expect(actual == expected, "corpus[\(index)]")
    }
  }

  @Test(.enabled(if: node != nil, "Runtime/node fehlt: scripts/fetch-runtime.sh"))
  func numbersMatchNode() throws {
    var generator = SystemRandomNumberGenerator()
    var values: [Double] = [0, 1, 0.1, 0.2 + 0.1, 1e21, 1e-7, 123e-20, 4.35, 1.0 / 3]
    for _ in 0..<5000 {
      let bits = generator.next() as UInt64
      let value = Double(bitPattern: bits)
      if value.isFinite { values.append(value) }
    }
    for _ in 0..<2000 { values.append(Double(Int64.random(in: -1_000_000_000...1_000_000_000)) / 1000) }
    let input = values.map { String($0.bitPattern, radix: 16) }.joined(separator: "\n")
    let script = """
    let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{
      const b=Buffer.alloc(8);
      process.stdout.write(s.split('\\n').map(h=>{b.writeBigUInt64BE(BigInt('0x'+h));return String(b.readDoubleBE())}).join('\\n'));
    })
    """
    let fromNode = try Self.runNode(script, input: input).split(separator: "\n").map(String.init)
    #expect(fromNode.count == values.count)
    for (value, expected) in zip(values, fromNode) {
      #expect(JSJSON.numberToString(value) == expected, "bits \(String(value.bitPattern, radix: 16))")
    }
  }

  @Test func rejectsWhatJSONParseRejects() {
    for text in ["", "\u{FEFF}{}", "{'a':1}", "[1,]", "{\"a\":1,}", "01", "1.", ".5", "+1", "NaN",
                 "\"\u{01}\"", "\"\\x\"", "[1] [2]", "{\"a\"}", "tru", "\"\\u12\""] {
      #expect(throws: JSJSON.ParseError.self, "\(text.debugDescription)") { try JSJSON.parse(text) }
    }
  }

  @Test func objectKeepsJavaScriptOrder() {
    var object = JSONObject()
    object["b"] = .number(1)
    object["5"] = .number(2)
    object["a"] = .number(3)
    object["1"] = .number(4)
    object["b"] = .number(5)
    #expect(object.keys == ["1", "5", "b", "a"])
    object["5"] = nil
    object["b"] = nil
    #expect(object.keys == ["1", "a"])
  }
}
