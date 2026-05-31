import Foundation

// AST mirrors docs/Spec.md §8 and schema/ast.schema.json.
// Optionals encode as absent keys (Codable uses encodeIfPresent for them),
// matching the fixtures which omit unset fields.

public struct Document: Codable, Equatable, Sendable {
    public var meta: [String: String]
    public var variations: [String: String]
    public var handles: [String: Ingredient]
    public var sections: [Section]
}

public struct Section: Codable, Equatable, Sendable {
    public var name: String
    public var anchor: String
    public var depth: Int
    public var tags: [Tag]
    public var attrs: [String: String]
    public var scheme: Scheme?
    public var steps: [Step]
}

public struct Step: Codable, Equatable, Sendable {
    public var seq: Int
    public var text: String
    public var prescription: Prescription?
    public var ingredients: [Ingredient]
    public var tokens: [Token]
    public var refs: [String]
    public var side: String?
    public var tempo: [TempoPhase]?
    public var duration: Duration?
    public var tags: [Tag]
    public var attrs: [String: String]
}

public struct Prescription: Codable, Equatable, Sendable {
    public var reps: Quantity?
    public var load: Quantity?
}

public struct Ingredient: Codable, Equatable, Sendable {
    public var raw: String
    public var quantity: Quantity?
    public var item: String
    public var annotation: String?
    public var handle: String?
    public var tags: [Tag]
}

public struct Quantity: Codable, Equatable, Sendable {
    public var kind: String      // number | fraction | range | approx | paired | open
    public var value: QuantityValue
    public var unit: String?
    public var type: String?     // UnitType
}

public enum QuantityValue: Codable, Equatable, Sendable {
    case number(Double)
    case range(Double, Double)
    case paired(count: Double, each: Double)
    case open

    private struct Paired: Codable { var count: Double; var each: Double }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let arr = try? c.decode([Double].self), arr.count == 2 { self = .range(arr[0], arr[1]); return }
        if let p = try? c.decode(Paired.self) { self = .paired(count: p.count, each: p.each); return }
        if let s = try? c.decode(String.self), s == "max" { self = .open; return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unrecognized Quantity.value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let n): try c.encode(n)
        case .range(let lo, let hi): try c.encode([lo, hi])
        case .paired(let count, let each): try c.encode(Paired(count: count, each: each))
        case .open: try c.encode("max")
        }
    }
}

public enum TempoPhase: Codable, Equatable, Sendable {
    case seconds(Double)
    case explosive

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Double.self) { self = .seconds(n); return }
        if let s = try? c.decode(String.self), s == "X" { self = .explosive; return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unrecognized TempoPhase")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .seconds(let n): try c.encode(n)
        case .explosive: try c.encode("X")
        }
    }
}

public struct Scheme: Codable, Equatable, Sendable {
    public var kind: String      // repeat | emom | amrap | interval | for-time
    public var rounds: Int?
    public var cap: Duration?
    public var work: Duration?
    public var rest: Duration?
    public var restBetween: String?  // rounds | items
}

public struct Tag: Codable, Equatable, Sendable {
    public var dim: String       // flat draft: always "var"
    public var name: String
    public var negated: Bool
}

public struct Token: Codable, Equatable, Sendable {
    public var scheme: String    // timer | goto
    public var raw: String
    public var duration: Duration?
    public var anchor: String?
    public var step: Int?
}

public struct Duration: Codable, Equatable, Sendable {
    public var raw: String
    public var seconds: Double
}
