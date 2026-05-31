import Foundation

extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}

public enum Parser {
    public static func parse(_ source: String) -> Document {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.components(separatedBy: "\n")

        var meta: [String: String] = [:]
        var variations: [String: String] = [:]

        // --- frontmatter ---
        if lines.first?.trimmed == "---" {
            var i = 1
            var front: [String] = []
            while i < lines.count, lines[i].trimmed != "---" { front.append(lines[i]); i += 1 }
            if i < lines.count { i += 1 }  // skip closing ---
            lines = Array(lines[i...])

            var inVariations = false
            for raw in front {
                if raw.trimmed.isEmpty { continue }
                let indented = raw.first == " " || raw.first == "\t"
                guard let colon = raw.firstIndex(of: ":") else { continue }
                let key = String(raw[..<colon]).trimmed
                let value = String(raw[raw.index(after: colon)...]).trimmed
                if indented && inVariations {
                    variations[key] = value
                } else if key == "variations" {
                    inVariations = true
                } else {
                    inVariations = false
                    meta[key] = value
                }
            }
        }

        // --- sections ---
        var sections: [Section] = []
        var headingLine: String? = nil
        var buffer: [String] = []

        func flush() {
            guard let h = headingLine else {
                if buffer.contains(where: { !$0.trimmed.isEmpty }) {
                    sections.append(makeSection(heading: "", depth: 1, lines: buffer))
                }
                return
            }
            let hashes = h.prefix(while: { $0 == "#" }).count
            let text = String(h.dropFirst(hashes)).trimmed
            sections.append(makeSection(heading: text, depth: hashes, lines: buffer))
        }

        for line in lines {
            if line.first == "#", line.contains(" ") || line.allSatisfy({ $0 == "#" }) {
                flush()
                headingLine = line
                buffer = []
            } else {
                buffer.append(line)
            }
        }
        flush()

        // --- global handle table ---
        var handles: [String: Ingredient] = [:]
        for s in sections {
            for st in s.steps {
                for ing in st.ingredients where ing.handle != nil {
                    handles[ing.handle!] = ing
                }
            }
        }

        return Document(meta: meta, variations: variations, handles: handles, sections: sections)
    }

    // MARK: - Section

    private static func makeSection(heading: String, depth: Int, lines: [String]) -> Section {
        let (name, parsedTags, parsedAttrs) = extractBraces(heading)
        var tags = parsedTags
        var attrs = parsedAttrs
        let scheme = resolveScheme(&attrs, &tags)
        let anchor = Lexer.slug(name)

        let hasOrdered = lines.contains { orderedContent($0) != nil }
        var steps = hasOrdered ? parseOrdered(lines) : parseMovements(lines)

        // Distributed default: {each:…} fills duration on any item that didn't set its own (§9.3).
        if !hasOrdered, let eachRaw = attrs["each"], let eachDur = Lexer.duration(eachRaw) {
            for i in steps.indices where steps[i].duration == nil {
                steps[i].duration = eachDur
            }
        }

        return Section(name: name, anchor: anchor, depth: depth,
                       tags: tags, attrs: attrs, scheme: scheme, steps: steps)
    }

    // MARK: - Ordered (recipe) steps

    private static func parseOrdered(_ lines: [String]) -> [Step] {
        var steps: [Step] = []
        var seq = 0
        var cur: Step? = nil

        for line in lines {
            if let c = orderedContent(line) {
                if let s = cur { steps.append(finalizeStep(s)) }
                seq += 1
                cur = Step(seq: seq, text: c, prescription: nil, ingredients: [],
                           tokens: [], refs: [], side: nil, tempo: nil, duration: nil,
                           tags: [], attrs: [:])
            } else if let ic = unorderedContent(line) {
                cur?.ingredients.append(parseIngredient(ic))
            } else if line.trimmed.isEmpty {
                continue
            } else if cur != nil {
                cur!.text += " " + line.trimmed
            }
        }
        if let s = cur { steps.append(finalizeStep(s)) }
        return steps
    }

    private static func finalizeStep(_ input: Step) -> Step {
        var s = input
        let (rest, tags, attrs) = extractBraces(s.text)
        s.text = rest
        s.tags = tags
        for (k, v) in attrs { s.attrs[k] = v }
        s.tokens = extractTokens(s.text)
        s.refs = extractRefs(s.text)
        return s
    }

    // MARK: - Movement (workout) steps

    private static func parseMovements(_ lines: [String]) -> [Step] {
        var steps: [Step] = []
        var seq = 0

        func emit(_ base: Step, side: String?) {
            seq += 1
            var s = base
            s.seq = seq
            s.side = side
            steps.append(s)
        }

        for line in lines {
            guard let content = unorderedContent(line) else { continue }
            let collapsed = Lexer.collapseWhitespace(content.trimmed)
            var (rest, tags, attrs) = extractBraces(collapsed)

            // duration overrides: `name | 90s` pipe sugar and {dur:…}
            var pipeDur: Duration? = nil
            if let bar = rest.range(of: "|") {
                pipeDur = Lexer.duration(String(rest[bar.upperBound...]).trimmed)
                rest = String(rest[..<bar.lowerBound]).trimmed
            }
            var attrDur: Duration? = nil
            if let dv = attrs["dur"] { attrDur = Lexer.duration(dv); attrs["dur"] = nil }

            var both = false
            if let sv = attrs["side"] {
                if sv == "both" { both = true } else {
                    // single explicit side handled below
                }
                if sv == "both" { attrs["side"] = nil }
            }
            if rest.contains("each side") {
                both = true
                rest = rest.replacingOccurrences(of: "each side", with: "").trimmed
            } else if rest.contains("e/s") {
                both = true
                rest = rest.replacingOccurrences(of: "e/s", with: "").trimmed
            }

            // split movement vs @value
            var movementPart = rest
            var atPart: String? = nil
            if let r = rest.range(of: "@") {
                movementPart = String(rest[..<r.lowerBound]).trimmed
                atPart = String(rest[r.upperBound...]).trimmed
            }

            // reps
            var reps: Quantity? = nil
            var movementName = movementPart
            if let (kind, value, consumed) = Lexer.leadingQuantityValue(movementPart) {
                reps = Quantity(kind: kind, value: value, unit: nil, type: "count")
                movementName = String(Array(movementPart)[consumed...]).trimmed
            }

            // load / duration
            var load: Quantity? = nil
            var dur: Duration? = nil
            if let lp = atPart, !lp.isEmpty,
               let (kind, value, consumed) = Lexer.leadingQuantityValue(lp) {
                let chars = Array(lp)
                var unit = ""
                var j = consumed
                while j < chars.count, chars[j] != " " { unit.append(chars[j]); j += 1 }
                if Lexer.durationUnits.contains(unit) {
                    dur = Lexer.duration(lp)
                } else {
                    load = Quantity(kind: kind, value: value,
                                    unit: unit.isEmpty ? nil : unit, type: "load")
                }
            }

            let prescription = (reps != nil || load != nil)
                ? Prescription(reps: reps, load: load) : nil

            var explicitSide: String? = nil
            if let sv = attrs["side"], sv == "left" || sv == "right" {
                explicitSide = sv
                attrs["side"] = nil
            }

            let base = Step(seq: 0, text: movementName, prescription: prescription,
                            ingredients: [], tokens: [], refs: [], side: nil,
                            tempo: nil, duration: dur ?? pipeDur ?? attrDur,
                            tags: tags, attrs: attrs)

            if both {
                emit(base, side: "left")
                emit(base, side: "right")
            } else {
                emit(base, side: explicitSide)
            }
        }
        return steps
    }

    // MARK: - Ingredient

    private static func parseIngredient(_ content: String) -> Ingredient {
        let raw = Lexer.collapseWhitespace(content.trimmed)
        var (working, tags, _) = extractBraces(raw)

        var handle: String? = nil
        if let m = working.range(of: "@[A-Za-z][A-Za-z0-9-]*", options: .regularExpression) {
            handle = String(working[working.index(after: m.lowerBound)..<m.upperBound])
            working.removeSubrange(m)
            working = working.trimmed
        }

        var quantity: Quantity? = nil
        var item = working.trimmed

        if let (kind, value, consumed) = Lexer.leadingQuantityValue(working) {
            let chars = Array(working)
            var unit: String? = nil
            var type: String? = nil
            var idx = consumed
            if idx < chars.count, chars[idx] != " " {
                var cand = ""
                var j = idx
                while j < chars.count, chars[j] != " " { cand.append(chars[j]); j += 1 }
                if let t = Lexer.unitTypes[cand] {
                    unit = cand; type = t; idx = j
                }
            }
            if unit == nil { type = "count" }
            item = String(chars[idx...]).trimmed
            quantity = Quantity(kind: kind, value: value, unit: unit, type: type)
        }

        return Ingredient(raw: raw, quantity: quantity, item: item,
                          annotation: nil, handle: handle, tags: tags)
    }

    // MARK: - Line classifiers

    private static func orderedContent(_ line: String) -> String? {
        let t = line.trimmed
        guard let dot = t.firstIndex(of: "."), t[..<dot].allSatisfy(\.isNumber), !t[..<dot].isEmpty
        else { return nil }
        let after = t[t.index(after: dot)...]
        guard after.first == " " else { return nil }
        return String(after).trimmed
    }

    private static func unorderedContent(_ line: String) -> String? {
        let t = line.trimmed
        guard t.first == "-", t.dropFirst().first == " " else { return nil }
        return String(t.dropFirst(2)).trimmed
    }

    // MARK: - { } tokens

    static func extractBraces(_ s: String) -> (rest: String, tags: [Tag], attrs: [String: String]) {
        var tags: [Tag] = []
        var attrs: [String: String] = [:]
        var result = ""
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            if chars[i] == "{" {
                var j = i + 1
                var content = ""
                while j < chars.count, chars[j] != "}" { content.append(chars[j]); j += 1 }
                parseEntries(content, &tags, &attrs)
                i = (j < chars.count) ? j + 1 : j
            } else {
                result.append(chars[i]); i += 1
            }
        }
        return (Lexer.collapseWhitespace(result).trimmed, tags, attrs)
    }

    private static func parseEntries(_ content: String, _ tags: inout [Tag], _ attrs: inout [String: String]) {
        for chunk in content.split(separator: ",") {
            let e = chunk.trimmed
            if e.isEmpty { continue }
            if let colon = e.firstIndex(of: ":") {
                let key = String(e[..<colon]).trimmed
                let value = String(e[e.index(after: colon)...]).trimmed
                attrs[key] = value
            } else {
                for tok in e.split(separator: " ") {
                    var name = String(tok)
                    var neg = false
                    if name.hasPrefix("!") { neg = true; name.removeFirst() }
                    tags.append(Tag(dim: "var", name: name, negated: neg))
                }
            }
        }
    }

    // MARK: - Scheme resolution (§9.4)

    private static func resolveScheme(_ attrs: inout [String: String], _ tags: inout [Tag]) -> Scheme? {
        if let v = attrs["emom"] {
            attrs["emom"] = nil
            return Scheme(kind: "emom", rounds: nil, cap: Lexer.duration(v),
                          work: nil, rest: nil, restBetween: nil)
        }
        if let v = attrs["amrap"] {
            attrs["amrap"] = nil
            return Scheme(kind: "amrap", rounds: nil, cap: Lexer.duration(v),
                          work: nil, rest: nil, restBetween: nil)
        }
        if let v = attrs["repeat"] {
            attrs["repeat"] = nil
            let rounds = Int(v)
            var restDur: Duration? = nil
            var between: String? = nil
            if let rv = attrs["rest"] {
                attrs["rest"] = nil
                var token = rv
                if token.contains("between") {
                    between = "items"
                    token = token.replacingOccurrences(of: "between", with: "").trimmed
                } else {
                    between = "rounds"
                }
                restDur = Lexer.duration(token)
            }
            return Scheme(kind: "repeat", rounds: rounds, cap: nil,
                          work: nil, rest: restDur, restBetween: between)
        }
        // bareword shorthands arrive as tags (no colon): {tabata}, {for-time}
        func takeTag(_ name: String) -> Bool {
            if let idx = tags.firstIndex(where: { $0.name == name && !$0.negated }) {
                tags.remove(at: idx); return true
            }
            return false
        }
        if takeTag("tabata") {
            return Scheme(kind: "interval", rounds: 8, cap: nil,
                          work: Duration(raw: "20s", seconds: 20),
                          rest: Duration(raw: "10s", seconds: 10), restBetween: nil)
        }
        if takeTag("for-time") {
            return Scheme(kind: "for-time", rounds: nil, cap: nil,
                          work: nil, rest: nil, restBetween: nil)
        }
        return nil
    }

    // MARK: - Inline tokens & refs

    private static let tokenRegex = try! NSRegularExpression(
        pattern: #"\[[^\]]*\]\((timer|goto):([^)]*)\)"#)
    private static let refRegex = try! NSRegularExpression(
        pattern: #"@([A-Za-z][A-Za-z0-9-]*)"#)

    private static func extractTokens(_ text: String) -> [Token] {
        let ns = text as NSString
        var tokens: [Token] = []
        for m in tokenRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let scheme = ns.substring(with: m.range(at: 1))
            let target = ns.substring(with: m.range(at: 2))
            if scheme == "timer" {
                tokens.append(Token(scheme: "timer", raw: target,
                                    duration: Lexer.duration(target), anchor: nil, step: nil))
            } else {
                if target.hasPrefix("step:"), let n = Int(target.dropFirst(5)) {
                    tokens.append(Token(scheme: "goto", raw: target,
                                        duration: nil, anchor: nil, step: n))
                } else {
                    tokens.append(Token(scheme: "goto", raw: target,
                                        duration: nil, anchor: target, step: nil))
                }
            }
        }
        return tokens
    }

    private static func extractRefs(_ text: String) -> [String] {
        let ns = text as NSString
        var refs: [String] = []
        for m in refRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1))
            if !refs.contains(name) { refs.append(name) }
        }
        return refs
    }
}
