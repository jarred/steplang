import Foundation

public enum ResolveError: Error, Equatable, Sendable {
    case duplicateHandle(String)
    case danglingReference(String)
}

public extension Document {
    /// Apply the active variation set, then resolve handles (§4, §5.3).
    /// Filtering runs first; handles are resolved against the surviving tree.
    func resolved(for variations: Set<String> = []) throws -> Document {
        try Resolver.resolve(self, variations: variations)
    }
}

public enum Resolver {
    /// §4.2 algebra: positives OR (if any), negatives each absent, the two halves AND.
    static func included(_ tags: [Tag], _ v: Set<String>) -> Bool {
        let positives = tags.filter { !$0.negated }
        let negatives = tags.filter { $0.negated }
        let positivePass = positives.isEmpty || positives.contains { v.contains($0.name) }
        let negativePass = negatives.allSatisfy { !v.contains($0.name) }
        return positivePass && negativePass
    }

    static func resolve(_ doc: Document, variations v: Set<String>) throws -> Document {
        // 1. Filter. A filtered section drops entirely; a filtered step drops its
        //    ingredients with it; a filtered ingredient drops just that line.
        var sections: [Section] = []
        for section in doc.sections where included(section.tags, v) {
            var s = section
            s.steps = section.steps.compactMap { step in
                guard included(step.tags, v) else { return nil }
                var st = step
                st.ingredients = step.ingredients.filter { included($0.tags, v) }
                return st
            }
            sections.append(s)
        }

        // 2. Rebuild the handle table among survivors; "defined once among included nodes".
        var handles: [String: Ingredient] = [:]
        for s in sections {
            for st in s.steps {
                for ing in st.ingredients {
                    guard let h = ing.handle else { continue }
                    if handles[h] != nil { throw ResolveError.duplicateHandle(h) }
                    handles[h] = ing
                }
            }
        }

        // 3. Validate references against the surviving handle table.
        for s in sections {
            for st in s.steps {
                for ref in st.refs where handles[ref] == nil {
                    throw ResolveError.danglingReference(ref)
                }
            }
        }

        return Document(meta: doc.meta, variations: doc.variations,
                        handles: handles, sections: sections)
    }
}
