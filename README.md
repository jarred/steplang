# Step Lang

A plain-text, **markdown-superset** format for any procedure made of *steps* with
*typed, measured quantities* — recipes, workouts, or any step/set/unit activity. One
source document drives multiple outputs: an interactive stepper, a scaled shopping list,
a flow diagram, and a "when do I start what" timeline.

> Status: **draft** (working name). The format spec lives in [`docs/Spec.md`](docs/Spec.md).

## At a glance

```markdown
---
title: Matcha Oreos
makes: ~14 large cookies
variations:
  mint: Peppermint Oreos
---

## Base
1. Pre-heat your oven to 180°C.
2. In a bowl, sift together:
   - 1c cocoa
   - 2c flour
3. Bake for [12 minutes](timer:12m). Meanwhile, [make the filling](goto:filling).

## Filling
1. Beat until smooth:
   - 2t matcha powder        {!mint}
   - 2.5t peppermint essence {mint}
```

It reads fine as plain markdown, and all extra structure hides inside constructs markdown
already ignores:

| Syntax | Meaning |
|---|---|
| `1.` ordered item | a **step** |
| `-` sub-list item | an **ingredient** / quantified item (or a **movement** in workouts) |
| `{ }` | structured hint — filter `{tag}`, `{!tag}`, or `key:value` attribute |
| `[label](timer:12m)` / `[label](goto:filling)` | interactive tokens |
| `@name` | a stable handle you can reference later |

Built in four progressive **layers** — core, filters/variations, named handles, typed
quantities & scaling — plus **profiles** (`recipe`, `workout`, `generic`) and **schemes**
(EMOM/AMRAP/Tabata/repeat). See the spec for the full grammar.

## Swift package

A reference parser + resolver + timeline generator, consumable via SwiftPM:

```swift
.package(url: "git@github.com:jarred/steplang.git", from: "0.2.0")
// target dependency: .product(name: "StepLang", package: "steplang")
```

```swift
import StepLang

let doc = Parser.parse(source)            // -> Document (the AST, §8)
let active = try doc.resolved(for: ["mint"])   // apply variations, resolve @handles
let plan = active.timelineBySection()     // expand schemes -> [SectionTimeline] of TimedSegments

for section in plan {
    for seg in section.segments {
        seg.label      // "15 goblet squats"
        seg.seconds    // countdown length (0 == manual / untimed)
        seg.kind       // .work / .rest / .timer / .manual
        seg.note       // e.g. "24kg"
    }
}
```

`resolved(...)` filters by the active variation set and validates handle references;
`timeline()` / `timelineBySection()` flatten the document into the concrete segments a
stepper or timer runs.

## Repo layout

```
docs/Spec.md            the format specification (draft)
schema/ast.schema.json  JSON Schema for the parse result (interchange contract)
fixtures/               golden corpus: .step sources + expected .ast.json
Sources/StepLang/       Swift package: Parser, Resolver, Timeline, AST
Tests/StepLangTests/    fixture conformance + resolver + timeline tests
```

The `fixtures/` corpus is the cross-implementation conformance suite: any parser (Swift
now, others later) must reproduce each `.ast.json` from its `.step` source.

## Develop

```sh
swift test        # parser/resolver/timeline tests
npx ajv-cli@5 validate -s schema/ast.schema.json -d "fixtures/*.ast.json" --spec=draft2020
```
