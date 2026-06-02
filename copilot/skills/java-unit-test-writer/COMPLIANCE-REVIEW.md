# Test Compliance Review

> **Purpose**: This document is read by a **subagent** invoked at the end of the java-unit-test-writer skill. The subagent gets a fresh context window — free from the accumulated build output, analysis notes, and iterative edits that cause attention drift in long sessions. Its job is to re-read the original instruction files, systematically check every rule against the finished test class, auto-fix violations, and confirm the tests still pass.
>
> **Single source of truth**: This file defines the **review process** only. All rules come from `java-testing.instructions.md` and `java-code.instructions.md`. This file must NEVER duplicate or restate rules from those files.

## Inputs

The calling agent provides these values in the subagent prompt:

| Variable | Description |
|----------|-------------|
| `TEST_CLASS_PATH` | Absolute path to the test class file |
| `CLASS_UNDER_TEST_PATH` | Absolute path to the production class being tested |
| `TEST_CLASS_NAME` | Simple class name of the test class (e.g. `MyServiceTest`) |
| `MAVEN_COMMAND` | The Maven command template for re-running tests |
| `JAVA_HOME_OVERRIDE_REQUIRED` | `YES` or `NO` — from env-facts.md; when YES, prepend `set JAVA_HOME=<JAVA_SDK_PATH>&&` before running the command |
| `JAVA_SDK_PATH` | Absolute path to the project JDK — from env-facts.md; only needed when `JAVA_HOME_OVERRIDE_REQUIRED` is YES |
| `COVERAGE_LINE` | Final LINE coverage % from Step 7 |
| `COVERAGE_BRANCH` | Final BRANCH coverage % from Step 7 |
| `UNTESTABLE_PATHS` | List of untestable paths documented during Step 7 (may be empty) |
| `CRITICAL_ISSUES_STATUS` | "none", "auto-fixed", "manual-fixed", or "proceed-anyway" |
| `LOGIC_ERROR_DECISIONS` | List of logic error protocol decisions made (may be empty) |
| `TEST_SCENARIO_CATALOG_PATH` | Absolute path to the Test Scenario Catalog produced by the expert analysis subagent, or `none` |

## Phase 1 — Load Instructions

Read the following files **in full**. These are the authoritative source of every rule. Internalize every rule before proceeding.

1. `java-testing.instructions.md` (absolute path provided in the subagent prompt)
2. `java-code.instructions.md` (absolute path provided in the subagent prompt)

## Phase 2 — Read the Test Class and Class Under Test

1. Read the **full test class** at `TEST_CLASS_PATH`.
2. Read the **full class under test** at `CLASS_UNDER_TEST_PATH` — this provides context for behavioral contracts and assertion quality checks.

## Phase 3 — Rule Compliance Scan

Walk through `java-testing.instructions.md` **section by section** and `java-code.instructions.md` **section by section**. For each rule in each section, scan the entire test class for violations. Record every violation with its exact location (method name or line range).

**Do not skip any rule.** The instruction files are the complete checklist.

### High-Frequency Violation Areas

The following categories are the most commonly violated during long test-writing sessions. Give them extra scrutiny — but do NOT limit your review to these areas:

1. **Mock Avoidance Hierarchy compliance** — the "Mock Avoidance Hierarchy" and "AEM / Sling Mocks" sections of `java-testing.instructions.md`. For **every** `Mockito.mock()` call and `@Mock` annotation in the test class, verify that levels 1–4 of the hierarchy are genuinely infeasible: (1) AemContext / Sling testing libraries, (2) real `…Impl` class from the project registered with `context.registerService()` / `context.registerInjectActivateService()`, (3) inline makeshift implementation for simple interfaces, (4) custom `AdapterFactory` or `context.registerAdapter()` for `.adaptTo()` needs. Any mock that could be replaced by a higher-level alternative is a violation.
2. **Null safety & variable extraction** — the "Extract method results to local variables" and "Guard custom assertion helpers" rules. Especially: chained method calls without intermediary variables.
3. **Static imports** — the static import restrictions in both instruction files.
4. **Field scope** — the "DO NOT create class-wide fields for single-method usage" rule.
5. **Assertion quality** — the "Use the most specific assertion", "Do not assert what is already proven", and "No assertion messages" rules.
6. **Test naming** — see the naming convention section in `java-testing.instructions.md`. Check every `@Test` / `@ParameterizedTest` method name against all naming rules; flag any violation.
7. **Comments** — the "Minimal comments only" rule. Verify that any inline comments explain a non-obvious condition or edge case, not obvious narration or separator.
8. **Method grouping and section dividers** — see the Method Grouping and Section Dividers section in `java-code.instructions.md` for full rules (divider format, section naming as captions not method signatures, ordering within sections, exact dash-row character count). Applies when the test class has more than ~8 test methods.
9. **Input-value-only duplicate tests** — see the DRY and parameterization rules in `java-testing.instructions.md`. Flag any pair of `@Test` methods whose bodies are ≥70% structurally identical; auto-fix by merging into a `@ParameterizedTest` (JUnit 5) or loop-based equivalent (JUnit 4).
10. **Inline literals where named constants exist** — see the constants rules in `java-code.instructions.md`. Scan the entire test class aggressively for literals that have named constant equivalents (`""` → `StringUtils.EMPTY`, `" "` → `StringUtils.SPACE`, HTTP codes, project constants, etc.). Auto-fix every occurrence; verify imports and recompile.

### Mock Audit

After the section-by-section scan, perform a dedicated mock audit:

1. Enumerate every `Mockito.mock()` call and every `@Mock`-annotated field in the test class.
2. For each one, identify the mocked type and determine which level of the Mock Avoidance Hierarchy could replace it:
   - Is it an AEM/Sling class available from AemContext or the Sling testing libraries? → **Violation** (level 1).
   - Is there a concrete `…Impl` class in the project for this interface? → **Violation** (level 2).
   - Is it an interface with ≤3 methods used by the code under test? → **Violation** (level 3 — a makeshift implementation should be used).
   - Does the code under test call `.adaptTo()` for this type? → **Violation** (level 4 — a custom adapter should be registered).
3. If the mock survives all four checks (e.g., complex third-party class with inaccessible constructor, or the test specifically needs `Mockito.verify()` with no observable state change), it is acceptable.
4. Record every replaceable mock as a violation with the recommended hierarchy level.

## Phase 4 — Assertion Quality Audit

This is a deeper semantic check on assertion coverage, beyond the structural checks in Phase 3.

1. Re-read the class under test. For each non-trivial public/package-private method, identify the **behavioral contract**: what each code path produces (return values, properties set, collections populated, exceptions thrown, state mutations).
2. For each test method, identify which code path it exercises and list its assertions.
3. Cross-reference: does the test assert on **every substantive effect** in the contract for that path?
4. Flag any test that:
   - Asserts only on collection size without verifying element contents or properties
   - Asserts only non-null / non-empty without verifying the actual value
   - Asserts only no-throw when the path produces a meaningful return value or side effect
   - Covers a branch that sets *N* properties but asserts on fewer than *N*
   - Asserts on inputs or setup state rather than on the method's outputs

Record each finding with the test method name and the missing assertion(s).

### Catalog Coverage Check

If `TEST_SCENARIO_CATALOG_PATH` is not `none`, read the Test Scenario Catalog and cross-reference it against the test class:

1. For every **HIGH** priority scenario in the catalog, verify that a corresponding test method exists that exercises the described setup and asserts the described expected outcomes.
2. For every **MEDIUM** priority scenario, verify the same.
3. Flag any HIGH or MEDIUM scenario that has **no corresponding test method** as a violation.
4. Flag any test method whose assertions do not match the catalog's **Expected** section (e.g., the catalog specifies asserting property values but the test only asserts non-null).

### Adversarial Gap Check

After completing the structural and catalog checks, perform one final scan for **minimum-viable-input tests** — tests that use the smallest possible input to enter a branch without exercising realistic variations:

1. For every test method that exercises a code path containing a **loop, iterator, or stream** over a collection:
   - Check the test's setup: how many items does it provision in the input collection?
   - If the answer is **exactly 1** (or the minimum to enter the loop), and no other test method exercises the **same code path with 2+ items**, flag this as a gap.
2. For every test method that exercises a code path where **identifiers, keys, or names are generated** for each item in a collection:
   - Check whether any test verifies **uniqueness** of the generated identifiers across multiple items.
   - If no test does, flag this as a gap.
3. For every test method that exercises a code path that **accumulates state** across iterations (string builders, maps, counters, DOM node trees):
   - Check whether any test verifies the **accumulated result** with 2+ items, not just the single-item case.
   - If no test does, flag this as a gap.

Record each adversarial gap with the test method name, the code path it exercises, and a description of the missing variation.

## Phase 5 — Auto-Fix

For every violation found in Phases 3 and 4:

1. Fix the violation in the test class file.
2. After all fixes are applied, re-read the full test class to catch cascading issues (e.g. a fix that introduced a new import but created a duplicate, or a variable rename that broke a reference).
3. Fix any cascading issues.

### Fix Priorities

If fixes conflict (e.g. extracting a helper changes method signatures, which affects other rules), apply in this order:

1. Correctness (null safety, mock boundaries) — highest priority
2. Structure (field scope, DRY extraction, method grouping and section dividers)
3. Style (naming, imports, assertion messages)

## Phase 6 — Re-Run Tests

Run the Maven command provided in `MAVEN_COMMAND` to confirm all tests still pass after fixes. If `JAVA_HOME_OVERRIDE_REQUIRED` is `YES`, prepend `set JAVA_HOME=<JAVA_SDK_PATH>&&` inside the `cmd /c "..."` block before running.

- If `BUILD SUCCESS` → proceed to Phase 7.
- If `BUILD FAILURE` → diagnose, fix the regression, and re-run. Repeat until green.

Use `execution_subagent` or `run_in_terminal` with `mode=sync` and `timeout=600000`. Wrap in `cmd /c "..."` for Windows. Include `-B -ntp` flags.

## Phase 7 — Final Report

Return a structured report to the calling agent with the following sections:

```
### Compliance Review Report

**Test class**: <TEST_CLASS_NAME>
**Violations found**: <count>
**Violations fixed**: <count>
**Tests pass**: YES / NO

#### Violations Fixed
1. [<instruction file section name>] <method or location> — <brief description of what was wrong and what was changed>
2. ...

#### Assertion Quality Improvements
1. <test method> — added assertion for <missing effect>
2. ...

#### Catalog Coverage Gaps
1. <scenario name> — <missing test or weak assertions>
2. ...
(or "All HIGH/MEDIUM scenarios covered" / "Catalog not provided")

#### Adversarial Gaps Fixed
1. <test method> — <description of minimum-viable-input gap and fix applied>
2. ...
(or "No adversarial gaps found")

#### Final Checklist
- [ ] java-testing.instructions.md and java-code.instructions.md rules followed throughout
- [ ] All tests pass (BUILD SUCCESS)
- [ ] Line coverage: <COVERAGE_LINE>% / Branch coverage: <COVERAGE_BRANCH>%
- [ ] Coverage meets target OR untestable paths documented: <UNTESTABLE_PATHS or "all covered">
- [ ] No significant boilerplate repetition without extraction
- [ ] No inline literals where named constants exist
- [ ] Every test asserts substantive outcomes (verified by assertion quality audit)
- [ ] All HIGH/MEDIUM catalog scenarios have corresponding tests (or catalog not provided)
- [ ] No minimum-viable-input gaps detected (adversarial gap check)
- [ ] Critical issues status: <CRITICAL_ISSUES_STATUS>
- [ ] Logic error decisions: <LOGIC_ERROR_DECISIONS or "none">
```

If no violations were found, the report should state that explicitly and confirm the test class is compliant.
