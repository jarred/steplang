import Foundation

enum Lexer {
    static let unicodeFractions: [Character: Double] = [
        "¼": 0.25, "½": 0.5, "¾": 0.75,
        "⅐": 1.0/7, "⅑": 1.0/9, "⅒": 0.1,
        "⅓": 1.0/3, "⅔": 2.0/3,
        "⅕": 0.2, "⅖": 0.4, "⅗": 0.6, "⅘": 0.8,
        "⅙": 1.0/6, "⅚": 5.0/6,
        "⅛": 0.125, "⅜": 0.375, "⅝": 0.625, "⅞": 0.875
    ]

    // unit -> UnitType, in a non-load (ingredient) context.
    static let unitTypes: [String: String] = [
        "g": "mass", "kg": "mass", "mg": "mass", "oz": "mass", "lb": "mass",
        "ml": "volume", "l": "volume", "L": "volume",
        "c": "volume", "cup": "volume", "t": "volume", "tsp": "volume",
        "T": "volume", "tbsp": "volume",
        "s": "duration", "sec": "duration", "m": "duration", "min": "duration", "h": "duration",
        "°C": "temperature", "°F": "temperature"
    ]

    static let durationUnits: Set<String> = ["s", "sec", "m", "min", "h"]
    static let loadUnits: Set<String> = ["kg", "lb"]

    static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

    static func slug(_ s: String) -> String {
        var out = ""
        var lastDash = false
        for ch in s.lowercased() {
            if ch.isLetter || ch.isNumber {
                out.append(ch); lastDash = false
            } else if !lastDash {
                out.append("-"); lastDash = true
            }
        }
        while out.hasPrefix("-") { out.removeFirst() }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    static func collapseWhitespace(_ s: String) -> String {
        s.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
    }

    // Parse "1h30m", "90s", "12m" -> seconds. Returns nil if not a duration form.
    static func duration(_ raw: String) -> Duration? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        var total = 0.0
        var num = ""
        var sawUnit = false
        for ch in s {
            if ch.isNumber || ch == "." {
                num.append(ch)
            } else {
                guard let n = Double(num) else { return nil }
                switch ch {
                case "h": total += n * 3600
                case "m": total += n * 60
                case "s": total += n
                default: return nil
                }
                num = ""; sawUnit = true
            }
        }
        if !num.isEmpty { return nil }   // trailing number with no unit
        guard sawUnit else { return nil }
        return Duration(raw: s, seconds: total)
    }

    // Parse a leading numeric value (number, decimal, unicode/mixed/ascii fraction,
    // range, approx). Returns (kind, value, charactersConsumed) or nil.
    static func leadingQuantityValue(_ s: String) -> (kind: String, value: QuantityValue, consumed: Int)? {
        let chars = Array(s)
        var i = 0
        var kind = "number"

        if i < chars.count, chars[i] == "~" { kind = "approx"; i += 1 }

        // integer / decimal part
        var numStr = ""
        while i < chars.count, Lexer.isDigit(chars[i]) || chars[i] == "." {
            numStr.append(chars[i]); i += 1
        }

        // attached unicode fraction, e.g. 1¾ or bare ¾
        var fracValue: Double? = nil
        if i < chars.count, let f = unicodeFractions[chars[i]] {
            fracValue = f; i += 1
            if kind == "number" { kind = "fraction" }
        }

        // ascii fraction "a/b" (only when no decimal/unicode part yet)
        if fracValue == nil, !numStr.isEmpty, i < chars.count, chars[i] == "/" {
            var den = ""
            var j = i + 1
            while j < chars.count, Lexer.isDigit(chars[j]) { den.append(chars[j]); j += 1 }
            if let d = Double(den), d != 0, let n = Double(numStr) {
                return ("fraction", .number(n / d), j)
            }
        }

        guard !numStr.isEmpty || fracValue != nil else { return nil }
        let base = Double(numStr) ?? 0

        // range "lo-hi" or "lo–hi"
        if fracValue == nil, i < chars.count, chars[i] == "-" || chars[i] == "–" {
            var hi = ""
            var j = i + 1
            while j < chars.count, Lexer.isDigit(chars[j]) || chars[j] == "." { hi.append(chars[j]); j += 1 }
            if let h = Double(hi) {
                return ("range", .range(base, h), j)
            }
        }

        // paired "NxN" (e.g. 2x12)
        if fracValue == nil, i < chars.count, chars[i] == "x" || chars[i] == "×" {
            var each = ""
            var j = i + 1
            while j < chars.count, Lexer.isDigit(chars[j]) || chars[j] == "." { each.append(chars[j]); j += 1 }
            if let e = Double(each) {
                return ("paired", .paired(count: base, each: e), j)
            }
        }

        let value = base + (fracValue ?? 0)
        return (kind, .number(value), i)
    }
}
