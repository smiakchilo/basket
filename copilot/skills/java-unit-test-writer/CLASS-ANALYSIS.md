# Class Analysis — Expert Subagent Protocol

> **Purpose**: This document is read by an **expert-model subagent** invoked early in the java-unit-test-writer skill. The subagent gets a clean context window with full attention devoted to understanding the class under test — its purpose, logic, invariants, and edge cases. Its output is a **Test Scenario Catalog** that the main agent uses as a blueprint for writing tests.
>
> **Why an expert subagent?** Deep semantic analysis — reasoning about cardinality, uniqueness, state interaction, and error cascading — requires sustained attention that degrades in a long session filled with build output and iterative edits. A dedicated subagent with a fresh context window and the expert model produces significantly better analysis than inline reasoning in the main workflow.

## Inputs

The calling agent provides these values in the subagent prompt:

| Variable | Description |
|----------|-------------|
| `CLASS_UNDER_TEST_PATH` | Absolute path to the production class being tested |
| `EXISTING_TEST_CLASS_PATH` | Absolute path to the existing test class, or `none` |
| `CALLER_FILE_PATHS` | Comma-separated absolute paths to up to 5 files that call/use the class under test, or `none` |
| `RELATED_CLASS_PATHS` | Comma-separated absolute paths to related classes (parent, sibling, implemented interfaces), or `none` |
| `PROJECT_MODULE` | Maven module name (e.g. `core`) — for contextual understanding |

## Phase 1 — Load Instructions

Read the following files **in full**. These are the authoritative source of every testing and coding rule. Internalize every rule before proceeding — they inform what constitutes a valid test scenario and what patterns to avoid.

1. `java-testing.instructions.md` (absolute path provided in the subagent prompt)
2. `java-code.instructions.md` (absolute path provided in the subagent prompt)

## Phase 2 — Read Source and Context

1. Read the **full source** of the class under test at `CLASS_UNDER_TEST_PATH`.
2. Read all **Javadoc, inline comments, and documentation** present in the class. Treat them as a first-class source of intent.
3. If `CALLER_FILE_PATHS` is not `none`, read each caller file. Note how the class is actually used: which methods are called, what inputs are passed, what return values are consumed. This reveals real-world usage patterns that inform test scenarios.
4. If `RELATED_CLASS_PATHS` is not `none`, read each related class. Note inheritance contracts, interface methods that must be honored, and sibling classes that share common patterns.
5. Confirm whether the class is a **Sling Model**, an **OSGi service**, a **servlet**, or a **plain Java class** — the setup pattern differs.

## Phase 3 — Critical Issues Scan

Perform a **focused critical-issues scan** while reading the class. This is NOT a full code review — it targets only issues that would make tests encode wrong behavior.

### What to Scan For (Critical Only)

- **Logic bugs**: inverted conditions, off-by-one errors, return values that contradict Javadoc
- **Null-safety violations**: dereferencing without null checks, missing `Optional` handling
- **Resource leaks**: `ResourceResolver`, `Session`, `InputStream` not closed via try-with-resources
- **Security flaws**: XSS, injection, unvalidated input used in JCR queries or paths
- **Data corruption risks**: incorrect property writes, missing transaction boundaries

**Skip**: style issues, naming, performance, consistency, documentation, cross-cutting analysis.

### If Critical Issues Are Found

Include each issue in the output under a dedicated `## Critical Issues` section with:
- Exact code location (method, line range)
- Description of the issue
- Potential impact
- Recommended fix

The **main agent** will present these to the user and handle the A/B/C decision flow. The analysis subagent does NOT interact with the user directly — it reports findings in its output.

### If No Critical Issues Are Found

Note `## Critical Issues: None` in the output and continue.

## Phase 4 — Deep Semantic Analysis

This is the core analytical phase. For **every public and package-private method** in the class, perform each of the following analyses. Do not skip any analysis dimension — even if a method seems simple, apply every lens. Simple methods often hide subtle edge cases.

### 4.1 — Purpose and Domain Context

For each method, answer:
- **What domain problem does this method solve?** (Not "what does the code do" — why does it exist?)
- **Who calls this method and what do they expect?** (Use caller files from Phase 2 if available.)
- **What invariants must hold before and after this method runs?**

### 4.2 — Behavioral Contracts

For each code path (branch) in the method, document the **specific observable effects**:
- Return value — exact type, value, and meaning
- Properties set on output objects — key AND value
- Collection contents — elements, ordering, uniqueness
- State mutations on injected dependencies or shared objects
- Exceptions thrown — type, message pattern, conditions that trigger them

This contract table is the test oracle. Every test scenario in the catalog must assert against effects listed here.

### 4.3 — Cardinality Analysis

For every collection, array, iterable, stream, iterator, or data source that the method processes:

1. **Zero items**: What happens when the collection is empty? Does the method short-circuit, return a default, throw, or silently produce an empty/null result?
2. **One item**: The minimum case that enters any processing loop. What does the output look like?
3. **Two or more items**: The critical case. Ask:
   - Are there **interactions between iterations**? (Shared counters, accumulated state, string builders, maps that could have key collisions, DOM nodes that share a parent.)
   - Does the loop **generate identifiers** (IDs, names, keys, paths) for each item? If so, are they guaranteed unique? What happens if two items produce the same identifier? (See 4.4.)
   - Does the loop **modify shared state** (a map, a parent node, a counter) that could cause interference between iterations?
   - Is the **first or last iteration** special? (Initialization on first, finalization on last, separator logic, boundary conditions.)
4. **Large N**: Are there performance cliffs, memory issues, or practical limits?

**This analysis must produce at least one test scenario for cardinality 0, one for cardinality 1, and one for cardinality ≥ 2** for every collection-processing path — unless a cardinality is structurally impossible.

### 4.4 — Uniqueness and Identity Analysis

For every identifier, key, name, ID, path, or distinguishing value that the method generates, derives, or assigns:

1. **Source**: Where does the identifier come from? Is it derived from input data, generated independently (UUID, counter), or hardcoded?
2. **Uniqueness guarantee**: What mechanism ensures no two items get the same identifier? Is it the caller's responsibility, enforced by the method, or neither?
3. **Collision scenario**: Construct a concrete scenario where two inputs would produce the same identifier. If the identifier is derived from input fields, what happens when two inputs have the same value in that field?
4. **Downstream impact**: If a collision occurs, what breaks? DOM nodes with duplicate IDs? Map entries overwriting each other? Resources with conflicting paths?

### 4.5 — Null and Empty Propagation

For each parameter and each injected dependency:

1. **Null input**: Trace what happens when this input is `null`. Which branch activates? Does it NPE, return a default, or silently skip work?
2. **Empty input**: For strings, collections, and optionals — trace the empty case separately from null. An empty string passes a `!= null` check but may fail a `.isEmpty()` check (or vice versa).
3. **Downstream nulls**: If the method calls `.adaptTo()`, `.getChild()`, `.getValueMap()`, or similar — what happens when the return is `null`? Is there a null check before the next dereference?

### 4.6 — State Interaction and Idempotency

For methods that modify shared state (fields, injected services, JCR nodes, caches):

1. **Repeated calls**: What happens if the method is called twice with the same input? Does it produce the same result (idempotent)? Does it create duplicates? Does it throw on the second call?
2. **Interleaved calls**: If method A and method B both modify the same state, does calling A then B produce a different result than B then A?
3. **Initialization dependencies**: Does the method assume another method was called first? (e.g., `activate()` before `doGet()`, `init()` before `process()`)

### 4.7 — Ordering Sensitivity

For methods that process ordered inputs or produce ordered outputs:

1. **Input order dependence**: Would different orderings of the same input items produce different outputs? If yes, is this intentional or a bug?
2. **Output ordering guarantees**: Does the method's contract guarantee a specific output order? If callers depend on ordering, is it preserved?

### 4.8 — Error Cascading and Partial Failure

For methods that perform multiple operations in sequence (e.g., creating multiple nodes, writing multiple properties, calling multiple services):

1. **Mid-operation failure**: If the 2nd of 3 operations fails (throws an exception), what state is left? Are the effects of the 1st operation rolled back, committed, or left dangling?
2. **Resource cleanup**: Are resources (streams, resolvers, sessions) properly closed in the error path?
3. **Error reporting**: Does the caller get enough information to understand what succeeded and what failed?

### 4.9 — Dependency Mock Hierarchy

For each dependency (injected service, `ResourceResolver`, `Session`, etc.), determine how to satisfy it in tests using the **Mock Avoidance Hierarchy**:

1. Can `AemContext` or the Sling testing libraries provide it?
2. Is there a real `…Impl` class in the project that can be registered with `context.registerService()` / `context.registerInjectActivateService()`?
3. Can a makeshift inline implementation satisfy it?
4. Does it need a custom `AdapterFactory`?
5. Only as a last resort: `Mockito.mock()`.

Record the decision for each dependency — the main agent will use this when writing test setup code.

## Phase 5 — Study Existing Tests

If `EXISTING_TEST_CLASS_PATH` is not `none`:

1. Read the **full existing test class**.
2. For each existing test method, identify:
   - Which method and code path it exercises
   - What inputs it provisions (pay special attention to **cardinality** — does it use exactly 1 item when the code processes a collection?)
   - What it asserts (substantive values vs. just non-null/size checks)
3. Map existing tests against the Phase 4 analysis:
   - Which scenarios from Phase 4 are already covered?
   - Which scenarios are **missing entirely**?
   - Which scenarios are covered with **minimum viable input** (e.g., 1 item) but not with **realistic variations** (e.g., 2+ items)?
4. Flag every gap explicitly — these become HIGH priority scenarios in the catalog.

If `EXISTING_TEST_CLASS_PATH` is `none`, note that no existing tests were found.

## Phase 6 — Logic Error Protocol

During Phases 3 through 5, if the agent identifies behavior that appears incorrect — for example, a condition that seems inverted, a return value that contradicts the Javadoc, an off-by-one error, a null check where a non-null check is needed, a missing edge case that would cause data corruption, or any deviation from documented or reasonably expected intent — the agent **must**:

1. **Stop** further analysis of the affected method.
2. **Analyze** the suspected error thoroughly: read surrounding code, callers, consumers of the return value, related tests, and all available documentation to confirm or dismiss the suspicion.
3. **Include** the finding in the output under a `## Suspected Logic Errors` section with:
   - The exact code location (file, method, line range).
   - What the code **actually does**.
   - What it **appears it should do** and why (citing Javadoc, naming, domain conventions, or logical reasoning).
   - The **potential impact** if the code is indeed wrong (data corruption, silent failures, security exposure, etc.).
4. For affected methods, generate test scenarios in the catalog for **both** interpretations:
   - Scenario A: tests that validate the *corrected* behavior (marked with rationale `logic-error-fix`)
   - Scenario B: tests that validate the *current* behavior as-is (marked with rationale `logic-error-current`)
   - The main agent will present the finding to the user and select the appropriate scenario set based on the user's decision.

**Never** produce a catalog that silently encodes a suspected bug as "expected behavior" without flagging it.

This protocol applies to **any** code path noticed during analysis — even one already covered by existing tests.

## Phase 7 — Generate Test Scenario Catalog

Produce a **Test Scenario Catalog** — a structured list of concrete test scenarios organized by method. This catalog is the primary deliverable of this subagent.

### Catalog Format

```markdown
## Test Scenario Catalog

### `methodName(ParamType)`

#### Scenario: descriptiveScenarioName
- **Setup**: What fixtures, resources, content, or mocks to provision. Be specific — include property names and values, resource paths, node structures.
- **Action**: What method to call, with what arguments.
- **Expected**: Specific observable outcomes — return values, properties set (key AND value), collection contents, exceptions thrown (type and message pattern), state changes on dependencies.
- **Rationale**: Which analysis heuristic identified this scenario (cardinality-N, uniqueness-collision, null-propagation, error-cascade, ordering, state-interaction, behavioral-contract, logic-error-fix, logic-error-current).
- **Priority**: HIGH | MEDIUM | LOW
- **Existing coverage**: `covered` | `partial` (explain gap) | `missing`

#### Scenario: anotherScenarioName
...

### `anotherMethod()`
...
```

### Priority Rules

- **HIGH**: Covers a suspected bug, an untested invariant, a cardinality ≥ 2 scenario for a collection-processing loop, a uniqueness collision, or a gap flagged in Phase 5.
- **MEDIUM**: Covers an edge case (null input, empty collection, boundary value), error path, or ordering sensitivity.
- **LOW**: Additional robustness (large N, repeated calls, unusual but valid inputs).

### Completeness Requirements

The catalog **must** include at least:

1. One scenario per code path identified in the behavioral contracts (Phase 4.2).
2. Cardinality 0, 1, and ≥ 2 scenarios for every collection-processing path (Phase 4.3).
3. A collision scenario for every generated identifier (Phase 4.4) — unless uniqueness is structurally guaranteed (e.g., UUID).
4. Null and empty input scenarios for every parameter and critical dependency return value (Phase 4.5).
5. Both interpretations for every suspected logic error (Phase 6).

### What NOT to Include

- Scenarios that test framework behavior (e.g., "OSGi injects the service correctly").
- Scenarios that require real I/O, network calls, or external services.
- Scenarios that would violate the rules in `java-testing.instructions.md` (e.g., testing private methods directly).

## Phase 8 — Return Complete Output

Return the following sections in order:

```markdown
## Class Summary
- **Class**: <fully qualified class name>
- **Type**: Sling Model | OSGi service | Servlet | Plain Java
- **Methods analyzed**: <count>
- **Total scenarios**: <count> (HIGH: N, MEDIUM: N, LOW: N)

## Critical Issues
<findings from Phase 3, or "None">

## Suspected Logic Errors
<findings from Phase 6, or "None">

## Dependency Setup
<for each dependency: name, type, and recommended satisfaction strategy from Phase 4.9>

## Test Scenario Catalog
<full catalog from Phase 7>

## Existing Test Coverage Gaps
<summary of gaps found in Phase 5, or "No existing tests" / "All scenarios covered">
```
