import XCTest
@testable import StepLang

final class ResolverTests: XCTestCase {
    private var fixturesDir: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        return url.appendingPathComponent("fixtures")
    }

    private func parseFixture(_ name: String) throws -> Document {
        let src = try String(contentsOf: fixturesDir.appendingPathComponent("\(name).step"), encoding: .utf8)
        return Parser.parse(src)
    }

    private func fillingItems(_ doc: Document) -> [String] {
        guard let filling = doc.sections.first(where: { $0.name == "Filling" }) else { return [] }
        return filling.steps.flatMap { $0.ingredients.map(\.item) }
    }

    // §4.2: default (no variation) keeps {!mint}, drops {mint}.
    func testDefaultVariationKeepsBase() throws {
        let resolved = try parseFixture("matcha-oreos").resolved(for: [])
        let items = fillingItems(resolved)
        XCTAssertTrue(items.contains("matcha powder"))
        XCTAssertFalse(items.contains("peppermint essence"))
    }

    // Selecting "mint" flips it: keep {mint}, drop {!mint}.
    func testMintVariation() throws {
        let resolved = try parseFixture("matcha-oreos").resolved(for: ["mint"])
        let items = fillingItems(resolved)
        XCTAssertFalse(items.contains("matcha powder"))
        XCTAssertTrue(items.contains("peppermint essence"))
    }

    // Handles resolve against the surviving tree.
    func testHandleResolves() throws {
        let resolved = try parseFixture("cheese-scones").resolved()
        XCTAssertNotNil(resolved.handles["cheese"])
        XCTAssertEqual(resolved.handles["cheese"]?.item, "cheddar cheese")
    }

    func testDanglingReferenceThrows() throws {
        let doc = Parser.parse("""
        ## S
        1. Use the @ghost.
        """)
        XCTAssertThrowsError(try doc.resolved()) { error in
            XCTAssertEqual(error as? ResolveError, .danglingReference("ghost"))
        }
    }

    func testDuplicateHandleThrows() throws {
        let doc = Parser.parse("""
        ## S
        1. First.
           - 1c flour @base
        2. Second.
           - 1c sugar @base
        """)
        XCTAssertThrowsError(try doc.resolved()) { error in
            XCTAssertEqual(error as? ResolveError, .duplicateHandle("base"))
        }
    }

    // Variation-scoped duplicate handles are legal: only one survives filtering (§5.3).
    func testVariationScopedHandlesAreLegal() throws {
        let doc = Parser.parse("""
        ---
        variations:
          mint: Minty
        ---
        ## S
        1. Flavour.
           - 2t matcha @flavour {!mint}
           - 2t peppermint @flavour {mint}
        2. Use @flavour.
        """)
        // Neither variation should error, and each resolves @flavour to the surviving def.
        let base = try doc.resolved(for: [])
        XCTAssertEqual(base.handles["flavour"]?.item, "matcha")
        let mint = try doc.resolved(for: ["mint"])
        XCTAssertEqual(mint.handles["flavour"]?.item, "peppermint")
    }
}
