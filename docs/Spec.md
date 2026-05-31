# Step Lang (working name) — Format Specification (draft)

> A plain-text, markdown-superset format for any procedure made of **steps** with
> **typed, measured quantities** attached — recipes, workouts, or any activity with
> steps, sets, and convertible units. One source document drives multiple outputs:
> an interactive stepper, a scaled shopping/equipment list, a flow diagram, and a
> "when do I start what" timeline.

Status: **draft**. Working name is **Step Lang** (leaning, not final).

---

## 1. Design goals

1. **Readable first.** A document should read well as plain text and render acceptably
   in any markdown viewer with zero tooling.
2. **Markdown superset.** It *is* markdown. All extra structure hides inside constructs
   markdown already ignores (links, headings, list items, end-of-line text), so
   formatters (`prettier`, GitHub) don't fight it.
3. **Progressive disclosure.** Trivially simple by default; more structure only when you
   opt in. A bare recipe needs none of the advanced features.
4. **Typed and structured enough for multiple outputs.** The parse produces a typed
   tree/DAG: sections → steps → {text, ingredients, timers, references, tags}.
5. **General, not recipe-specific.** Recipes are the first *profile*; workouts and
   generic procedures use the same engine.

### Non-goals
- Not a templating or scripting language. No conditionals beyond tag filtering, and no
  *general* loops — only **bounded, declarative** block repetition (`scheme`, see §9.4).
- Not a units library on its own — it *carries* typed quantities; conversion/scaling is
  the parser/host's job.

---

## 2. Document structure

```
Document
  ├─ Frontmatter        (YAML metadata)
  └─ Section[]          (## heading, optionally tagged)
       └─ Step[]        (ordered list item)
            ├─ text      (prose; may reference @handles and contain inline tokens)
            ├─ Ingredient[]  (nested sub-list items)
            ├─ Token[]   (timer:, goto: — inline markdown links)
            └─ tags[]    (filter tags applied to this step)
```

Everything below is organized by the four **layers**. A parser MUST support all four
to be conformant, but a *document* may use only the layers it needs.

### 2.1 Delimiter roles

Each bracket type has exactly one job. They never compete, which is what lets human prose
and machine metadata coexist on the same line.

| Delimiter | Role | Audience | Parsed? |
|---|---|---|---|
| `( )` | free-text aside / note (`butter (soft, room temp)`) | human | kept as `annotation`, not interpreted |
| `{ }` | structured **hint**: tag, attribute, scheme | machine | yes |
| `[ ]( )` | interactive token: `timer:`, `goto:` | both (renders as a link) | yes |
| `_ _` | prep emphasis (`_finely chopped_`) | human | kept as `annotation` |

Rationale: `[ ]` is reserved by markdown (links, reference links, footnotes, task lists)
and by our own `timer:`/`goto:` tokens — it cannot also mean attributes. `( )` reads
nicely but is already how writers add natural-language asides (the recipe corpus is full
of them), so overloading it would make `(soft, room temp)` ambiguous against `(side:both)`
and force awkward nesting. `{ }` has near-zero markdown meaning *and* matches the
pandoc/kramdown attribute convention (`{#id .class key=val}`), so it carries the
"this is metadata, step over it" hint cleanly. **Curly braces win for all structured hints.**

### 2.2 `{ }` contents: tags vs attributes

A `{ }` token holds one or more space-separated entries. An entry is either:

- a **tag** — a bareword (optionally `!`-negated): `{mint}`, `{!deload}`. Used for
  filtering (§4). (Namespaced tags for independent axes are deferred — §4.4.)
- an **attribute** — a `key:value` pair: `{tempo:3-1-3}`, `{rest:10s}`, `{repeat:3}`,
  `{side:both}`. Used to carry structured parameters (§9).

Tags and attributes may share a token: `{repeat:3, rest:2m}` or `{side:both} {!deload}`.

**Splitting rule.** Entries split on **commas** first. A bare space also separates entries
*only outside* a `key:value`'s value, so a value may carry a trailing keyword:
`{repeat:3, rest:30s between}` → `repeat:3` and `rest:'30s between'`. (To keep this
unambiguous, an entry without a comma and without a `key:` prefix is treated as a tag.)

---

## 3. Layer 1 — Core (always valid)

### 3.1 Frontmatter
Standard YAML between `---` fences at the top of the file.

```yaml
---
title: Matcha Oreos
makes: ~14 large cookies      # scalable: leading quantity ~14; see §6.3
# makes: a dozen muffins      # (alt) free-text: no leading quantity, unscalable
---
```

A `makes:` value is **scalable** iff it begins with a parseable quantity (§6.1:
number / fraction / range / approx). The leading quantity is the **base count**; the
trailing text is the display label. A value with no leading quantity is **free-text** and
disables scaling for the document (§6.3).

Reserved keys: `title`, `makes` (alias `yields`, `serves`, `duration`), `variations`
(see §5), `profile` (e.g. `recipe`, `workout`; defaults to `recipe`).
Unknown keys are preserved and passed through to the host.

### 3.2 Sections
A section is a markdown heading. The heading text is the section name; a slugified
form is its **anchor** (used as a `goto:` target).

```markdown
## Base
## Lemon Curd        →  anchor: lemon-curd
### Sub-section      →  nesting via heading depth
```

A document with no headings is a single implicit section.

### 3.3 Steps
Steps are **ordered list items** (`1.`, `2.`, …). Numbering may be lazy (`1.` repeated)
— the parser assigns sequence. A step's prose may wrap onto indented continuation lines.

**Continuation rule (adopts markdown's own).** A line is a **continuation** of the current
step iff it is indented to (at least) the list item's content column and is **not** itself
a new list marker. A new ordered marker (`1.`, `2.`) starts a new step; a new unordered
marker (`-`) starts an ingredient/item sub-list. A blank line followed by more indented
text is still continuation (a second paragraph within the step). Tokens (`timer:`,
`goto:`) and `{tags}` on a continuation line are honored — they are scanned over the
step's full text, and a `{tag}` applies to the step regardless of which line it sits on.

A step's prose may resume **after** its sub-list (prose before *and* after the
ingredients). Such segments concatenate in document order into the single `Step.text`;
don't assume all prose precedes the sub-list.

```markdown
1. To a stand mixer, add:
   - 250g butter
   and cream until pale.   ← still step 1; text = "To a stand mixer, add: … and cream until pale."
```

```markdown
1. Pre-heat the oven to 180°C.
2. Roll out between two sheets of baking paper,
   about 5–8mm thick.              ← continuation (indented, no marker)

   Work quickly so it stays cold.  ← still step 2 (blank line + indent = 2nd paragraph)
   - 2c flour                      ← ingredient of step 2 (unordered marker)
3. Refrigerate.                    ← new step (ordered marker)
```

### 3.4 Ingredients (quantified items)
Ingredients are a **nested unordered sub-list** directly under their step. This keeps the
scannable "ingredient column" while staying markdown-native.

```markdown
2. In a bowl, sift together and set aside:
   - 1c cocoa
   - 2c flour
   - pinch of salt
```

At Layer 1 the item text is opaque (not yet parsed into quantity + unit). Layer 4
formalizes it.

**Indentation.** Indent with spaces. A sub-list (ingredients/items) must be indented past
its parent step's content column; a line indented to (or beyond) that column with no list
marker is step continuation (§3.3). Tabs are discouraged — they make the content column
ambiguous.

> "Ingredient" is the recipe-profile name. The generic concept is a **quantified item**
> attached to a step (a workout's `4x5 @ 80kg`, a generic step's `2 screws`).

---

## 4. Layer 2 — Filters (variations)

### 4.1 Filter tokens
A trailing `{tag}` or `{!tag}` token applies a filter to the **node it sits on** — a
section heading, a step, or an ingredient. It is plain end-of-line text, so it renders
literally in dumb viewers and survives formatters.

```markdown
## Lemon Curd {meringue}              ← whole section only in the meringue variation
3. Fold the zest through {!strawberry}
   - 2 lemons' zest         {!strawberry}
   - 50g pistachios         {strawberry}
```

### 4.2 Algebra
For an active variation set `V` (the tags currently selected), tags form a single flat
namespace. A node is included iff:

> **(at least one positive tag is in `V`, if the node has any positives) AND (no negative
> tag is in `V`)**.

Positives OR together; negatives must each be absent; the two halves AND.

| On the node | Included when |
|---|---|
| *(no tag)* | always |
| `{x}` | `x ∈ V` |
| `{!x}` | `x ∉ V` |
| `{x} {y}` | `x ∈ V` **OR** `y ∈ V` |
| `{!x} {!y}` | `x ∉ V` **AND** `y ∉ V` |
| `{x} {!y}` | `x ∈ V` **AND** `y ∉ V` |

Filtering a section removes all its steps and ingredients. Filtering a step removes its
ingredients. Filtering an ingredient removes only that line.

### 4.3 Declaring variations
```yaml
variations:
  mint: Peppermint Oreos          # tag: human description
  meringue: Adds lemon curd & Italian meringue icing
```
A variation MAY activate multiple tags (host concern). Selecting "mint" puts `mint` in `V`.

### 4.4 Filter dimensions (deferred)
> **Deferred — not in the draft.** A future layer MAY add namespaced tags for independent
> axes (`{diet:vegan}`, `{equip:no-oven}`) that hosts can filter separately. The current
> draft keeps a single flat tag namespace (§4.2). Because a namespaced tag is still just a
> tag to a flat parser, this can be added later without an AST shape change or breaking
> existing documents.

---

## 5. Layer 3 — Named handles & references

### 5.1 Defining a handle
Append `@name` to an ingredient to give it a stable handle. `name` is kebab-case.

```markdown
- 300g cheddar cheese  @cheese
```

**`@` disambiguation (lexical).** A handle starts with a **letter** (`@cheese`); a load
or other `@`-quantity starts with a **digit** (`@24kg`, `@2x12kg`). This rule is what lets
the workout profile reuse `@` for inline prescriptions (§9.1) without colliding with
handles.

### 5.2 Referencing a handle
Write `@name` in later step prose (or another ingredient line) to reference the **same**
item. References do **not** re-declare quantity; the item is tallied **once** at its
definition.

```markdown
1. Grate & mix in the cheese, reserving a handful for the top.
   - 300g cheddar cheese  @cheese
2. Roll out and cut into 15 rectangles.
3. Top with the reserved @cheese, then bake.
```

This is **explicit** referencing (chosen over implicit noun-matching) so links are
unambiguous. A renderer MAY hyperlink `@cheese` in prose to its definition row; a flow
diagram wires the `@cheese` node as an input edge into every referencing step.

### 5.3 Rules
- **Filtering runs before handle resolution.** Handles are resolved against the *included*
  tree for the active variation set `V` (§4), not the raw document.
- A handle is defined **exactly once among included nodes**. This makes the
  variation-handle pattern legal: two definitions of the same handle under mutually
  exclusive tags (`@flavour {mint}` / `@flavour {!mint}`) are fine because at most one
  survives filtering.
- Referencing an undefined handle is an **error**, evaluated per active variation. A
  reference that survives while its definition was filtered out is therefore an error for
  that `V` (you kept the user but dropped the source).
- Handles are document-global (unique across sections, among included nodes).
- An ingredient with no handle cannot be referenced (and that's fine — most aren't).
- **Validity is relative to `V`.** A document may resolve cleanly for one variation and
  fail for another; that is honest, since a variation is effectively a different document.
  A linter SHOULD check that resolution succeeds for every declared variation.

---

## 6. Layer 4 — Typed quantities & scaling

### 6.1 Quantity grammar
An ingredient line parses as:

```
[quantity] [unit] item [_annotation_] [@handle] [{tags}]
```

```
quantity   := number | fraction | range | approx | paired | open
number     := 230 | 1.5
fraction   := 1/4 | 1¾            (unicode or ASCII)
range      := 15-18 | 15–18
approx     := ~14
paired     := 2x12kg              (count × value — e.g. double kettlebell)
open        := max | AMRAP | to failure   (unbounded; tally reports "≥ N")
unit       := g kg ml l c t T tsp tbsp cup … | °C °F | min m s h | reps sets kg(load) …
item       := free text noun ("cheddar cheese", "butter")
annotation := _italic_ prep note ("_finely chopped_")
```

Lines with no leading quantity (e.g. `pinch of salt`) are **unitless** items.

### 6.2 Unit types
Every unit resolves to a **type**, which determines conversion and scaling behavior:

| Type | Examples | Scales with yield? |
|---|---|---|
| `mass` | g, kg, oz, lb | yes |
| `volume` | ml, l, c, t (tsp), T (tbsp) | yes |
| `count` | eggs, 14 cookies | yes (round sensibly) |
| `duration` | s, min, h | **no** (or nonlinear — see §6.4) |
| `temperature` | °C, °F | **no** |
| `load` | kg/lb on a lift | yes (workout overload) |
| `unitless` | pinch, handful | loosely / no |

### 6.3 Scaling
A `makes:` value is **scalable** iff it begins with a parseable quantity (§6.1); the
leading quantity is the **base count**. With a scalable `makes:` (e.g. `12 small cakes`,
base `12`), the host computes a factor (`target ÷ base`) and rescales all `mass` /
`volume` / `count` / `load` quantities. `temperature` and `duration` are left untouched
by default.

The **target** is supplied host-side (UI or a host-specific override), never by the
format — the document only carries the base. If `makes:` is **free-text** (no leading
quantity) there is no base, so **scaling is disabled** and ingredients render at their
written amounts.

### 6.4 Non-scaling & nonlinear flags
- Temperatures and times never scale by the yield factor.
- A range bake time (`[15–18 minutes]`) is presentational, not multiplied.
- Hosts MAY apply profile-specific heuristics (e.g. larger batch → longer bake) but the
  format does not prescribe them; the **default is leave time/temp alone**.

---

## 7. Inline tokens (markdown links)

Interactive elements are markdown links with a custom URI scheme. They work at any layer
and render as plain links in dumb viewers.

```markdown
Bake for [12 minutes](timer:12m).
Meanwhile, [make the filling](goto:filling).
```

| Scheme | Meaning | Target |
|---|---|---|
| `timer:` | a countdown | duration (`12m`, `90s`, `1h30m`) |
| `goto:` | cross-reference / branch | a section anchor or `step:N` |

`goto:` edges plus "meanwhile"-style prose are what make the document a **DAG** rather
than a linear list, powering the flow-diagram and timeline outputs.

---

## 8. The parse result (AST)

A conformant parser emits roughly:

```ts
interface Document {
  meta: Record<string, unknown> & { title?: string; profile?: string };
  variations: Record<string, string>;
  sections: Section[];
  handles: Record<string, Ingredient>;   // global handle table
}
interface Section {
  name: string; anchor: string; depth: number;
  tags: Tag[]; attrs: Attrs;              // attrs incl. distributed defaults + scheme
  scheme?: Scheme;                        // resolved from {emom|amrap|repeat|tabata|...}
  steps: Step[];
}
interface Step {
  seq: number; text: string;
  prescription?: { reps?: Quantity; load?: Quantity };  // inline workout prescription
  ingredients: Ingredient[];
  tokens: Token[];                        // timers, gotos found in text
  refs: string[];                         // @handles referenced in text
  side?: 'left'|'right';                  // set on expanded items from {side:both}
  tempo?: (number|'X')[];                 // e.g. [3,1,3] or [3,1,'X',0]
  duration?: Duration;                    // from `| 1m`, {dur:…}, or inherited {each:…}
  tags: Tag[]; attrs: Attrs;
}
interface Ingredient {
  raw: string;
  quantity?: Quantity;                    // undefined => unitless/opaque
  item: string; annotation?: string;
  handle?: string; tags: Tag[];
}
interface Quantity {
  kind: 'number'|'fraction'|'range'|'approx'|'paired'|'open';
  value: number | [number, number] | { count: number; each: number } | 'max';
  unit?: string; type?: UnitType;
}
type Attrs = Record<string, string>;     // raw key:value entries from { } tokens
interface Scheme { kind: 'repeat'|'emom'|'amrap'|'interval'|'for-time';
                   rounds?: number; cap?: Duration; work?: Duration; rest?: Duration; restBetween?: 'rounds'|'items'; }
type Tag = { dim: string; name: string; negated: boolean };  // flat draft: dim always 'var'. {!deload} => {dim:'var',name:'deload',negated:true}. dim reserved for future namespacing (§4.4)
type Token = { scheme: 'timer'|'goto'; raw: string; /* duration | anchor */ };
```

Output generators consume this:
- **Stepper** → walk sections/steps, fire `timer:` tokens.
- **Shopping/equipment list** → tally `Ingredient.quantity` by `item`/`handle`, scaled.
- **Flow diagram** → sections = nodes, `goto:` + handle refs = edges.
- **Timeline** → schedule backward from the end using `timer:` durations + `goto:` overlaps.

---

## 9. Profiles

A profile renames concepts and sets host defaults; the grammar is unchanged.

| Concept | `recipe` | `workout` | `generic` |
|---|---|---|---|
| Document | recipe | routine | procedure |
| Section | component | block | phase |
| Step | instruction | exercise / movement | step |
| Quantity | ingredient (mass/vol) | reps · load | count/duration |
| Timer | bake / rest | work / rest interval | wait |
| Variation | recipe variation | difficulty / deload | variant |

### 9.1 Inline prescriptions (vs. recipe sub-lists)

A recipe step combines *many* ingredients, so they live in a scannable sub-list. A workout
movement carries *one* prescription, so it reads better **inline** — the scannable column
becomes the column of movements, with loads aligned at the end. A step MAY therefore carry
its quantity inline instead of (or as well as) a sub-list.

**Unordered items as steps.** In a section with **no ordered (`1.`) items**, the top-level
`-` items are **Steps** (movements), not ingredients — there is no parent step for them to
attach to. (When ordered items *are* present, `-` items remain ingredient sub-lists per
§3.4.) `seq` is assigned in document order.

```markdown
## EMOM {emom:20m}
- 15 goblet squats   @ 24kg
- 10 kb rows         @ 2x12kg
- 12 kb push press   @ 2x12kg
- 15 kb swings       @ 24kg
```

Inline grammar: `[reps] movement [each side] @ [load]`. The reps and load become a
`prescription: { reps?, load? }` on the step (§8) — two separate typed quantities, since
they carry different units/types.
- `@24kg` → a `load`-typed quantity. `@` means "at"; the unit decides the type, so `@1m`
  on the same `@` is a `duration` cap, not a load.
- `@2x12kg` → a **paired** load: two 12kg implements (24kg total, presented as the pair).
- `@` disambiguates against handles (§5) lexically: a load starts with a **digit**, a
  handle (`@cheese`) starts with a **letter**.
- Open/unbounded reps (`{reps:max}`, "to failure", AMRAP) use the `open` quantity value
  (§6.1); tally reports "≥ N" or defers to logged actuals.

### 9.2 Sides — `{side:both}` always expands

`each side`, `e/s`, and `{side:both}` are interchangeable surface forms for one fact:
the movement is performed on both sides. **It always desugars to two adjacent items / two
sets** (left, then right — kept adjacent, not all-left-then-all-right), each inheriting the
block's distributed defaults (§9.3). `{side:left}` / `{side:right}` emit a single side.

```markdown
- 10 push press @ 16kg {side:both}   ≡   - 10 push press each side @ 16kg
```

Both expand to a left set and a right set. Volume tallies use the **per-implement** load
as the base, with pairing and sides as independent `×2` multipliers:
`reps × load(per-implement) × pair × sides`. So `10 push press @2x12kg {side:both}` is
`10 × 12 × 2 (pair) × 2 (sides) = 480` kg·reps. `side` is **item-only** — it is not a
valid block (heading) default.

### 9.3 Distributed defaults — say it once

Block-level attributes on the heading distribute to the block's children so per-item
repetition isn't hand-written:

| Attribute | Effect |
|---|---|
| `{each:1m}` | default duration for every item that doesn't override |
| `{rest:10s}` | insert a rest of that length *between* consecutive items (not after the last) |

An item overrides a default with its own value: `- Deep squat \| 90s` (the `name \| duration`
pipe is readable sugar for a per-item duration) or `- Deep squat {dur:90s}`.

```markdown
## Mobility {each:1m, rest:10s}
- Deep squat
- Cobras
- Greatest stretch   {side:both}
- Cat and camel
- Ankles             {side:both}
```

### 9.4 Schemes — bounded block repetition

EMOM, AMRAP, Tabata, for-time, and plain repeat are one family: **block execution
schemes** that differ only in what is fixed vs. measured. They are modelled as a single
`scheme` with parameters; the keys below are friendly shorthands that desugar to it.

| Shorthand | Desugars to | Fixed | Measured / open |
|---|---|---|---|
| `{repeat:3}` | `scheme:repeat, rounds:3` | rounds | — |
| `{repeat:3, rest:2m}` | + `rest:2m` (between **rounds**) | rounds | — |
| `{repeat:3, rest:30s between}` | + `rest:30s` (between **items**) | rounds | — |
| `{emom:20m}` | `scheme:emom, cap:20m` | time + cadence | — |
| `{amrap:12m}` | `scheme:amrap, cap:12m` | time | rounds completed |
| `{tabata}` | `scheme:interval, work:20s, rest:10s, rounds:8` | work/rest/rounds | reps/round |
| `{for-time}` | `scheme:for-time` | the work | total time |

`rest:Xm` (bare) = rest **between rounds**; the `between` keyword flips it to rest
**between items**. The scheme + params is exactly what the timeline generator (§8)
consumes — it understands "scheme + params," never per-acronym special cases.

### 9.5 Tempo

A per-rep timing prescription, as an attribute on the movement:

```markdown
- 8 back squat @ 60kg {tempo:3-1-3}     ← 3s down · 1s pause · 3s up
- 8 back squat @ 60kg {tempo:3-1-X-0}   ← X = explosive; 4th digit = pause at top
```

Format: 3 or 4 phases (`down-pause-up-pause`), digits = seconds, `X`/`x` = explosive.
Drives a per-rep pacer in the stepper and time-under-tension in analytics.

### 9.6 Worked example

```markdown
---
title: Kettlebell session
profile: workout
variations:
  deload: 60% loads, drop last set
---

## EMOM {emom:20m}
- 15 goblet squats   @ 24kg
- 10 kb rows         @ 2x12kg
- 12 kb push press   @ 2x12kg
- 15 kb swings       @ 24kg

## Superset A {repeat:3, rest:2m}
- 10 push press @ 16kg {side:both}
- 12 curls @ 10kg {side:both}
- 10 tri extensions @ 10kg

## Circuit C {repeat:3, rest:30s between}
- 10 burpees  @ 1m
- 10 pushups  @ 1m
```

---

## 10. Reference example (Candidate A+, all layers)

```markdown
---
title: Matcha Oreos
makes: ~14 large cookies
profile: recipe
variations:
  mint: Peppermint Oreos
---

## Base
1. Pre-heat your oven to 180°C.
2. In a bowl, sift together and set aside:
   - 1c cocoa
   - 2c flour
   - pinch of salt
3. In another bowl cream until light and fluffy:
   - 250g butter
   - ¾c brown sugar
   - 1t vanilla paste
4. Combine both bowls and knead together.
5. Roll out between two sheets of baking paper, ~5–8mm thick.
6. Refrigerate for [8 minutes](timer:8m).
7. Cut out ~28 circles with a cutter, re-rolling scraps; place on a lined tray.
8. Bake for [12 minutes](timer:12m). Meanwhile, [make the filling](goto:filling).
9. Set aside to cool.

## Filling
1. In a bowl, beat until smooth:
   - 160g butter
   - 1¾c icing sugar
   - 2t matcha powder         {!mint}
   - 2.5t peppermint essence  {mint}
   - 1t vanilla
   - pinch of salt
   - 1T milk
2. Pipe between two cooled cookies.
```

---

## 11. Prior art

What exists in the world that's adjacent, and what we take from each. The honest gap: no
one has a *general* steps-with-typed-quantities format spanning recipes **and** workouts
**and** runbooks with filtering + a DAG. Each neighbor is locked to one domain or one axis.

### Recipes — the near neighbor: Cooklang
The closest competitor. Plain-text recipe markup, same elevator pitch (one source →
shopping list, steps, scaling). Inline sigils: `@ingredient{2%cups}`, `#cookware{}`,
`~timer{10%minutes}`.
- **Take:** proven model — parsers in many languages, real apps, a shopping-list
  aggregator. Clean `%` quantity/unit split.
- **Lesson:** Cooklang made **cookware (`#`) first-class from day one** — the equipment
  decision we deferred (§3.4 open Q). That it was needed for recipes *alone* says the
  pressure is real and will likely return (especially for `assembly`).
- **Where we differ / lead:** no variations, no `goto`/DAG, no profiles, recipe-only. Its
  inline-sigil prose (`@butter{250%g}`) also reads *worse* as plain text than our sub-list
  — a point for our "readable first" goal.
- Also: RecipeMD (simpler), Open Recipe Format / RecipeML (data, not authoring),
  schema.org/Recipe (a possible *emit* target).

### Workouts — structured-interval formats
Zwift `.ZWO` (XML) and TrainingPeaks/FIT structured workouts model intervals exactly like
§9.4: declarative blocks with fixed-vs-measured params. Independent convergence on "one
scheme + params, not per-acronym special cases" validates that abstraction. The CrossFit
EMOM/AMRAP/Tabata/for-time vocabulary is a de-facto DSL no text format owns — our opening.

### Philosophy — plain-text, one source / many outputs
- **Org-mode** — deepest "structured plain text → many exports." Its `:PROPERTIES:`
  drawers ≈ our `{ }` attributes; its tags ≈ our filter tags. **Cautionary:** it grew
  huge — an argument for our layered progressive-disclosure discipline.
- **Fountain** (screenplays) — best *design sibling*: readable-first, structure hidden
  where the eye skips, strong tooling. Emulate its restraint.
- **Ledger / Beancount** — typed quantities (amount + commodity) tallied into many
  reports; the same engine as our scaled item tally.
- **Gherkin** — natural-language-but-parseable steps; proof step-structured prose stays
  human-readable.
- **Taskpaper** `@tag(value)` and **Pandoc/kramdown** `{#id .class key=val}` — alternative
  attribute syntaxes; staying near pandoc (which we already cite, §2.1) means existing
  markdown tooling transfers.

### Three to study first
1. **Cooklang** — closest competitor; learn its model, ecosystem, and *why cookware is
   first-class*.
2. **`.ZWO` / structured intervals** — stress-test the §9.4 `scheme` design against it.
3. **Fountain** — how readable-first markup keeps machine structure invisible.

---

## Open questions

- **Equipment / tools as a distinct item type** *(deferred — not in the draft)* — a whisk
  or a 13mm socket is *used*, not *consumed*, so it shouldn't tally like an ingredient. The
  only genuinely new behaviors are no-scale + a separate output bucket (dedup-on-reuse is
  already given by handles, §5.2). Considered a `{role:tool}` item attribute but it clutters
  the content; for now equipment lives in **prose** ("To a stand mixer, add: …"). Revisit if
  a profile (e.g. `assembly`) forces an explicit equipment list/tally.
- **Name.** Working name **Step Lang**; confirm before publishing.
- **Multiple yields / per-section yields** (a recipe whose icing makes a different count).
- **Implicit `goto` from "meanwhile"** — detect, or require explicit `goto:`?
- **Scaling heuristics for time** beyond "leave alone" — opt-in per profile?
- **Profiles to stress-test next:** `runbook/SOP` (no quantities, all branching + filter
  dimensions — proves graceful degradation) and `assembly` (forces the equipment decision).

### Resolved this session
- `{ }` chosen for all structured hints over `( )` and `[ ]` (§2.1).
- `{ }` carries both tags and `key:value` attributes (§2.2).
- Workout: inline prescriptions, `{side:both}` always expands, distributed defaults,
  unified `scheme` model, tempo (§9).
- Filter algebra: single flat tag namespace; positives OR, negatives AND, the two halves
  AND (§4.2). Namespaced dimensions deferred (§4.4); `Tag.dim` kept as a constant `'var'`
  so they can be added later without an AST change.
- Step continuation: adopt markdown's own rule — indented non-marker lines continue the
  step; tokens/tags on continuation lines are honored (§3.3).
- Handle resolution: filter first, then resolve handles on the surviving tree; "defined
  once among included nodes"; dangling reference is a hard error per active variation
  (§5.3).
- Scalable yield: `makes:` scales iff it starts with a §6.1 quantity (base count);
  target is host-side; free-text yields disable scaling (§3.1, §6.3).
- Cleanups: `@` digit/letter lexing moved to §5.1; paired+sides tally is per-implement
  load ×pair ×sides (§9.2); `{ }` splits on commas, values may carry trailing keywords
  (§2.2); spaces-not-tabs indentation (§3.4); `tempo` AST type `(number|'X')[]` (§8).
- Equipment: deferred — lives in prose for now; dedup already comes from handles; revisit
  if `assembly` forces an explicit equipment tally. Step prose may resume after the
  sub-list, concatenating into `Step.text` (§3.3).
- AST refinements (from fixtures): in a section with no ordered items, top-level `-` items
  are Steps (§9.1); `Step.prescription` is now `{ reps?, load? }` (two quantities) not a
  single `Quantity` (§8). Added a JSON Schema (`schema/ast.schema.json`) and a fixtures
  corpus (`fixtures/`) as the interchange contract / conformance suite.
