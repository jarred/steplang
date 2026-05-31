import Foundation

/// A single executable unit produced by flattening a document: the thing a
/// stepper/timer counts through. `seconds == 0` means untimed (manual advance).
public struct TimedSegment: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case work     // a prescribed movement / instruction with a duration
        case rest     // an inserted rest between items or rounds
        case timer    // a `timer:` token (recipe bake/rest)
        case manual   // no time — hold until the user advances
    }

    public var label: String
    public var seconds: Double
    public var kind: Kind
    public var note: String?
    public var side: String?

    public init(label: String, seconds: Double, kind: Kind, note: String? = nil, side: String? = nil) {
        self.label = label
        self.seconds = seconds
        self.kind = kind
        self.note = note
        self.side = side
    }
}

/// A section's name/anchor alongside its expanded segments — preserves grouping
/// for UIs that show section headers.
public struct SectionTimeline: Sendable {
    public let name: String
    public let anchor: String
    public let segments: [TimedSegment]
}

public extension Document {
    /// Flatten the document into an ordered list of timed segments, expanding
    /// block schemes (§9.4) into the concrete timeline (§8). Resolve variations
    /// first if needed: `try doc.resolved().timeline()`.
    func timeline() -> [TimedSegment] {
        sections.flatMap(Timeline.segments(for:))
    }

    /// Same expansion, grouped by section.
    func timelineBySection() -> [SectionTimeline] {
        sections.map {
            SectionTimeline(name: $0.name, anchor: $0.anchor, segments: Timeline.segments(for: $0))
        }
    }
}

enum Timeline {
    static func segments(for section: Section) -> [TimedSegment] {
        let base = section.steps.flatMap(baseSegments(for:))
        guard !base.isEmpty else { return [] }

        switch section.scheme?.kind {
        case "emom":
            return emom(base, cap: section.scheme?.cap)
        case "amrap":
            return amrap(base, cap: section.scheme?.cap)
        case "interval":
            return interval(base, scheme: section.scheme!)
        case "repeat":
            return repeated(base,
                            rounds: section.scheme?.rounds ?? 1,
                            betweenItems: schemeRest(section, "items"),
                            betweenRounds: schemeRest(section, "rounds"))
        default:
            // No scheme (incl. for-time): a single pass. A distributed {rest:…}
            // (§9.3) still inserts rests between items.
            return repeated(base, rounds: 1,
                            betweenItems: distributedRest(section),
                            betweenRounds: nil)
        }
    }

    // MARK: - Base segments (one step -> one or more segments)

    private static func baseSegments(for step: Step) -> [TimedSegment] {
        let label = renderedLabel(step)
        let note = step.prescription?.load.map(formatLoad)
        let side = step.side

        if let d = step.duration {
            return [TimedSegment(label: label, seconds: d.seconds, kind: .work, note: note, side: side)]
        }
        let timers = step.tokens.filter { $0.scheme == "timer" }
        if !timers.isEmpty {
            return timers.map {
                TimedSegment(label: label, seconds: $0.duration?.seconds ?? 0, kind: .timer, note: note, side: side)
            }
        }
        return [TimedSegment(label: label, seconds: 0, kind: .manual, note: note, side: side)]
    }

    // MARK: - Scheme expansions

    private static func emom(_ base: [TimedSegment], cap: Duration?) -> [TimedSegment] {
        guard let cap, cap.seconds >= 60 else { return base }
        let slots = Int(cap.seconds / 60)
        return (0..<slots).map { i in
            var seg = base[i % base.count]
            seg.seconds = 60
            seg.kind = .work
            return seg
        }
    }

    private static func amrap(_ base: [TimedSegment], cap: Duration?) -> [TimedSegment] {
        guard let cap, cap.seconds > 0 else { return base }
        let label = base.map(\.label).joined(separator: " · ")
        return [TimedSegment(label: label, seconds: cap.seconds, kind: .work)]
    }

    private static func interval(_ base: [TimedSegment], scheme: Scheme) -> [TimedSegment] {
        let work = scheme.work?.seconds ?? 0
        let rest = scheme.rest?.seconds ?? 0
        let rounds = scheme.rounds ?? 0
        guard rounds > 0, work > 0 else { return base }
        var out: [TimedSegment] = []
        for r in 0..<rounds {
            var seg = base[r % base.count]
            seg.seconds = work
            seg.kind = .work
            out.append(seg)
            if rest > 0, r < rounds - 1 { out.append(restSegment(rest)) }
        }
        return out
    }

    private static func repeated(_ base: [TimedSegment], rounds: Int,
                                 betweenItems: Double?, betweenRounds: Double?) -> [TimedSegment] {
        var out: [TimedSegment] = []
        for round in 1...max(rounds, 1) {
            for (i, seg) in base.enumerated() {
                out.append(seg)
                if let r = betweenItems, i < base.count - 1 { out.append(restSegment(r)) }
            }
            if let r = betweenRounds, round < rounds { out.append(restSegment(r)) }
        }
        return out
    }

    private static func restSegment(_ seconds: Double) -> TimedSegment {
        TimedSegment(label: "Rest", seconds: seconds, kind: .rest)
    }

    // MARK: - Rest sources

    private static func schemeRest(_ s: Section, _ between: String) -> Double? {
        guard let sch = s.scheme, sch.restBetween == between, let r = sch.rest else { return nil }
        return r.seconds
    }

    private static func distributedRest(_ s: Section) -> Double? {
        guard s.scheme == nil, let raw = s.attrs["rest"] else { return nil }
        return Lexer.duration(raw)?.seconds
    }

    // MARK: - Labels

    private static func renderedLabel(_ step: Step) -> String {
        var label = renderProse(step.text)
        if let reps = step.prescription?.reps, let v = scalar(reps) {
            label = "\(number(v)) \(label)"
        }
        return label.trimmingCharacters(in: .whitespaces)
    }

    private static func renderProse(_ text: String) -> String {
        let re = try! NSRegularExpression(pattern: #"\[([^\]]*)\]\([^)]*\)"#)
        let ns = text as NSString
        let out = re.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "$1")
        return out.trimmingCharacters(in: .whitespaces)
    }

    private static func scalar(_ q: Quantity) -> Double? {
        switch q.value {
        case .number(let n): return n
        case .range(let lo, _): return lo
        case .paired(let c, _): return c
        case .open: return nil
        }
    }

    private static func formatLoad(_ q: Quantity) -> String {
        let unit = q.unit ?? ""
        switch q.value {
        case .number(let n): return "\(number(n))\(unit)"
        case .range(let lo, let hi): return "\(number(lo))–\(number(hi))\(unit)"
        case .paired(let c, let e): return "\(number(c))×\(number(e))\(unit)"
        case .open: return "max"
        }
    }

    private static func number(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(d)
    }
}
