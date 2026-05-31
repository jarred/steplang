import XCTest
@testable import StepLang

final class TimelineTests: XCTestCase {
    private func timeline(_ source: String) -> [TimedSegment] {
        (try? Parser.parse(source).resolved())?.timeline() ?? []
    }

    // EMOM: cap / 60 slots, cycling movements, each 60s.
    func testEMOM() {
        let segs = timeline("""
        ## E {emom:3m}
        - A
        - B
        """)
        XCTAssertEqual(segs.map(\.label), ["A", "B", "A"])
        XCTAssertTrue(segs.allSatisfy { $0.seconds == 60 && $0.kind == .work })
    }

    // AMRAP: a single cap-long segment listing the movements.
    func testAMRAP() {
        let segs = timeline("""
        ## A {amrap:5m}
        - 5 pull-ups
        - 10 push-ups
        """)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].seconds, 300)
        XCTAssertEqual(segs[0].label, "5 pull-ups · 10 push-ups")
    }

    // Tabata: 8 rounds of work/rest, trailing rest dropped (ends on work).
    func testTabata() {
        let segs = timeline("""
        ## T {tabata}
        - hollow rocks
        """)
        XCTAssertEqual(segs.count, 15)  // 8 work + 7 rest
        XCTAssertEqual(segs.filter { $0.kind == .work }.count, 8)
        XCTAssertEqual(segs.filter { $0.kind == .rest }.count, 7)
        XCTAssertEqual(segs.first?.seconds, 20)
        XCTAssertEqual(segs[1].seconds, 10)
    }

    // repeat with rest between rounds.
    func testRepeatBetweenRounds() {
        let segs = timeline("""
        ## S {repeat:3, rest:2m}
        - a
        - b
        """)
        // 3 rounds × 2 items + 2 rests between rounds
        XCTAssertEqual(segs.count, 8)
        XCTAssertEqual(segs.filter { $0.kind == .rest }.count, 2)
        XCTAssertTrue(segs.filter { $0.kind == .rest }.allSatisfy { $0.seconds == 120 })
    }

    // repeat with rest between items.
    func testRepeatBetweenItems() {
        let segs = timeline("""
        ## C {repeat:2, rest:30s between}
        - a
        - b
        """)
        // per round: a, rest, b  (rest between items, not after last) × 2 rounds
        XCTAssertEqual(segs.count, 6)
        XCTAssertEqual(segs.filter { $0.kind == .rest }.count, 2)
        XCTAssertTrue(segs.filter { $0.kind == .rest }.allSatisfy { $0.seconds == 30 })
    }

    // Distributed {each:} fills durations; {rest:} inserts rests between items.
    func testDistributedDefaults() {
        let segs = timeline("""
        ## M {each:1m, rest:10s}
        - a
        - b
        - c
        """)
        XCTAssertEqual(segs.map(\.label), ["a", "Rest", "b", "Rest", "c"])
        XCTAssertEqual(segs.filter { $0.kind == .work }.count, 3)
        XCTAssertTrue(segs.filter { $0.kind == .work }.allSatisfy { $0.seconds == 60 })
    }

    // Recipe timers become timer segments; prep steps are manual (0s).
    func testRecipeTimers() {
        let segs = timeline("""
        ## Bake
        1. Mix everything.
        2. Bake for [12 minutes](timer:12m).
        """)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].kind, .manual)
        XCTAssertEqual(segs[0].seconds, 0)
        XCTAssertEqual(segs[1].kind, .timer)
        XCTAssertEqual(segs[1].seconds, 720)
        XCTAssertEqual(segs[1].label, "Bake for 12 minutes.")
    }

    // Real fixture: EMOM 20m -> 20 one-minute slots cycling 4 movements.
    func testKettlebellEMOMFixture() throws {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { url.deleteLastPathComponent() }
        let src = try String(contentsOf: url.appendingPathComponent("fixtures/kettlebell-session.step"), encoding: .utf8)
        let segs = Parser.parse(src).timeline()
        let emom = segs.prefix(20)
        XCTAssertEqual(emom.count, 20)
        XCTAssertTrue(emom.allSatisfy { $0.seconds == 60 })
        XCTAssertEqual(segs[0].label, "15 goblet squats")
        XCTAssertEqual(segs[0].note, "24kg")
        XCTAssertEqual(segs[1].note, "2×12kg")  // paired load
    }
}
