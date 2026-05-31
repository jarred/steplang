import XCTest
@testable import StepLang

// Structural JSON value so comparisons ignore key order and int/double spelling.
indirect enum JSON: Decodable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSON])
    case object([String: JSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSON].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSON].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "bad JSON")
    }
}

final class FixtureTests: XCTestCase {
    private var fixturesDir: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }  // .../Tests/StepLangTests/<file> -> repo
        return url.appendingPathComponent("fixtures")
    }

    private func canonical(_ data: Data) throws -> JSON {
        try JSONDecoder().decode(JSON.self, from: data)
    }

    private func check(_ name: String) throws {
        let src = try String(contentsOf: fixturesDir.appendingPathComponent("\(name).step"), encoding: .utf8)
        let expected = try Data(contentsOf: fixturesDir.appendingPathComponent("\(name).ast.json"))

        let doc = Parser.parse(src)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let produced = try encoder.encode(doc)

        let got = try canonical(produced)
        let want = try canonical(expected)
        if got != want {
            let pretty = String(data: produced, encoding: .utf8) ?? ""
            XCTFail("AST mismatch for \(name).\nProduced:\n\(pretty)")
        }
    }

    func testMatchaOreos() throws { try check("matcha-oreos") }
    func testKettlebellSession() throws { try check("kettlebell-session") }
    func testMobility() throws { try check("mobility") }
    func testCrossfitWod() throws { try check("crossfit-wod") }
    func testCheeseScones() throws { try check("cheese-scones") }
}
