---
name: java-unit-test-writer
description: "Use when: writing unit tests for a Java class; updating unit tests after a class has changed; completing an existing test class to reach a coverage target; improving test coverage of a Java class; asked to add missing tests, fill coverage gaps, or reach a coverage target. Runs JaCoCo via Maven, reads the per-class coverage report, and iterates until line and branch coverage hit the given target — or the highest achievable floor when some paths are genuinely untestable. Follows project-specific testing standards in java-testing.instructions.md and java-code.instructions.md."
argument-hint: "Path or name of the Java class to test (e.g. MyService.java)"
---

# Java Unit Test Writer

Writes or improves unit tests for a Java class until **line and branch coverage both reach the coverage target** (or the highest achievable floor when some paths are genuinely untestable), following the rules in [java-testing.instructions.md](../../instructions/java-testing.instructions.md) and [java-code.instructions.md](../../instructions/java-code.instructions.md).

## When to Use

- User asks to write unit tests for a class
- User asks to update existing unit tests because the class under test has changed
- User asks to complete or improve an existing test class to reach a coverage target
- User asks to write tests for a class but a test class already exists — treat as update/completion, not fresh creation
- User asks to improve test coverage or reach a coverage target

## Multi-Class Strategy

When asked to test **more than one class**, process them **sequentially, one at a time**. For each class:

1. Execute Steps 1–8 fully for that class.
2. After delivering the final checklist (Step 8), save a summary to `/memories/session/skill-progress.md` — including the class name, final coverage numbers, and status.
3. **Clear intermediate state**: do not carry raw file contents, build outputs, or analysis notes from the completed class into the next one. Only retain the summary checkpoint.
4. Proceed to the next class.

This prevents context accumulation across classes, which is the primary cause of mid-execution terminations when testing multiple files.

## Configuration

**BLOCKING — do this before any other step.**

Read the shared model config to get model names for the two-tier workflow:

```
read_file: ../../model-config.md
```

Extract both model names from the **Roles** table:

- **worker** model — used for the [Java Version & Runner Resolution](#java-version--runner-resolution) blocking step.
- **expert** model — used for the [Expert Class Analysis](#step-3--expert-class-analysis-subagent) and [Compliance Review](#step-7--compliance-review-subagent) subagents.

## Java Version & Runner Resolution

**BLOCKING — executes immediately after reading model configs, before Step 0 and all other steps.**

Nothing else in this skill executes until this step completes successfully. If a confirmed, working JDK for the required Java version cannot be established, the skill **stops immediately** and reports the failure to the user.

### Worker Subagent: Detect and Locate JDK

Delegate detection to a **worker-model subagent**. The complete instructions are in [references/jdk-detector.md](./references/jdk-detector.md).

```
runSubagent(
  model: "<worker model from model-config.md>",
  prompt: "You are a Java environment detector. Read and follow all steps in [jdk-detector.md at: <absolute path to skills/java-unit-test-writer/references/jdk-detector.md>]. Return exactly the JSON format specified there.",
  description: "Detect Java version and locate JDK runner"
)
```

### Main Agent: Process Result and Memoize

After the subagent returns:

1. **If `status` is `version-unknown`**: stop immediately. Report to the user that the required Java version could not be determined from the POM and ask them to add `maven.compiler.release` to the project.

2. **If `status` is `not-found`**: ask the user via `vscode_askQuestions`:
   > *"The project requires Java `<N>` but I could not find a matching JDK on this machine. Please provide the absolute path to a JDK `<N>` installation (e.g. `C:\Program Files\Java\jdk-<N>`), or type `quit` to cancel."*
   - If the user types `quit` or provides no path → **stop immediately**. Do not proceed.
   - If the user provides a path, verify it exists (`Test-Path`). If it does not exist → **stop immediately**.
   - Derive `java_runner_path` as `<user path>\bin\java.exe`.

3. **Memoize to repo memory** — write or update `/memories/repo/jdk-paths.md`. If a stale row existed for this version, replace it:

   ```markdown
   # JDK Paths

   | Version | Path | Verified |
   |---------|------|----------|
   | 11 | C:\Program Files\Java\jdk-11.0.20 | 2026-05-01 |
   ```

4. **Memoize to session memory** — compute `JAVA_HOME_OVERRIDE_REQUIRED` (`YES` if the subagent returned `system_default: false`; `NO` if `true`), then append to `/memories/session/skill-progress.md` (create if absent):

   ```
   ## Java Runner
   - REQUIRED_VERSION: <N>
   - JAVA_SDK_PATH: <absolute path>
   - JAVA_RUNNER_PATH: <absolute path>\bin\java.exe
   - JAVA_HOME_OVERRIDE_REQUIRED: YES | NO
   ```

   All subsequent steps — Step 0 through Step 8, every Maven command, and every subagent invocation — **must** read `JAVA_SDK_PATH`, `JAVA_RUNNER_PATH`, and `JAVA_HOME_OVERRIDE_REQUIRED` from this session record rather than re-detecting them. A `YES` value means every Maven command must prepend `set JAVA_HOME=<JAVA_SDK_PATH>&&` inside `cmd /c ".."`.

## Environment Fact Sheet

**BLOCKING — executes immediately after JDK resolution, before Step 0 and all other steps.**

The Environment Fact Sheet captures the project's fundamental facts — Java version, available test dependencies, AEM version — so that every thinking session (main agent iterations, subagent invocations, diagnostic recovery) starts from ground truth rather than guessing or re-discovering.

### Why This Exists

Circular failures most often stem from the agent forgetting what tools are available: using Mockito when AEM Mocks provides the same capability, importing a class from a dependency not in the POM, or writing code that requires a Java version the project doesn't use. The fact sheet eliminates this class of errors by making the ground truth permanently accessible.

### Worker Subagent: Probe the POM

Delegate dependency extraction to a **worker-model subagent**. The complete instructions are in [references/pom-analyzer.md](./references/pom-analyzer.md).

```
runSubagent(
  model: "<worker model from model-config.md>",
  prompt: "You are a Maven POM analyzer. Read and follow all steps in [pom-analyzer.md at: <absolute path to skills/java-unit-test-writer/references/pom-analyzer.md>]. Return exactly the JSON format specified there.",
  description: "Extract test dependencies from POM"
)
```

### Main Agent: Build and Memoize the Fact Sheet

After the subagent returns, create `/memories/session/env-facts.md` with this content:

```markdown
# Environment Fact Sheet

## Java
- JAVA_VERSION: <N> (from JDK Resolution)
- JAVA_SDK_PATH: <absolute path> (from JDK Resolution)
- JAVA_RUNNER_PATH: <absolute path>\bin\java.exe (from JDK Resolution)
- JAVA_HOME_OVERRIDE_REQUIRED: YES | NO  (YES = every Maven command must prepend `set JAVA_HOME=<JAVA_SDK_PATH>&&`)

## AEM
- AEM_VERSION: <AEMaaCS | 6.5.x | 6.6.x | unknown>

## Test Dependencies
- JUNIT: <4 | 5 | both>
- AEM_MOCK: <groupId:artifactId:version | none>
- SLING_MOCK: <groupId:artifactId:version | none>
- MOCKITO: <groupId:artifactId:version | none>

### All Test-Scoped Dependencies
<one per line: groupId:artifactId:version>

## Ground Rules
- AEM Mocks first. Mockito only as absolute last resort.
- Do not import classes from dependencies not listed above.
- Do not use Java language features above Java <N>.
```

### How It's Consumed

- **Every subagent prompt** (CLASS-ANALYSIS, COMPLIANCE-REVIEW, Diagnostic) includes `ENV_FACTS_PATH` pointing to this file, with instructions to read it first.
- **Step 6 Critical Rules Refresher** references this file — re-read it if unsure about available dependencies.
- **The Diagnostic Subagent** uses it as its primary input for root cause analysis.
- **Maven commands** use `JAVA_SDK_PATH` from this file (or from session progress, which contains the same value).

## Coverage Target

**LINE ≥ 90 % and BRANCH ≥ 90 %.**

This is the single source of truth for the coverage requirement. All references to "the coverage target" throughout this skill refer to this value. To change the target, edit only this section.

## Guiding Principle — Informative Coverage

This skill exists to produce **informative test coverage** — tests that validate correctness, document intended behavior, and catch real bugs. It does **not** exist to mechanically cover lines and branches as if all code is correct by default.

- Coverage is a **means**, not an end. High percentages are worthless if the tests silently encode bugs as "expected behavior".
- Every test must answer: *"Does this code path produce the correct result?"* — not just *"Does this code path execute without crashing?"*
- The agent must reason about **what the code should do** (from Javadoc, comments, naming, domain logic, and common sense), not just what it happens to do.
- If the agent suspects a logic error at any point during test writing, it **must** stop and surface it to the user before writing tests that would encode incorrect behavior as passing.

## Step 0 — Read Skill Memos and Resilience Protocol

Read `/memories/skill-memos/java-unit-test-writer.md` and apply any recorded advice. Follow [Skill Learning — Persistent Memos](../../instructions/skill-learning.instructions.md) for the full memo protocol.

**Resilience protocol** — read and follow [Resilience Protocol](../../instructions/resilience-protocol.instructions.md). Check `/memories/session/skill-progress.md` for a prior checkpoint matching this task. If one exists, offer to resume. Checkpoint your progress after every major step. Emit a brief status message to the user after every step.

## Step 1 — Read the Rules

Load and internalize all rules from [java-testing.instructions.md](../../instructions/java-testing.instructions.md), and [java-code.instructions.md](../../instructions/java-code.instructions.md) before writing a single line of test code. Every decision in the following steps must comply with those rules.

## Step 2 — Confirm JDK Session State

> **Pre-condition**: Both blocking steps have already run. Read `JAVA_SDK_PATH`, `JAVA_RUNNER_PATH`, and `JAVA_HOME_OVERRIDE_REQUIRED` from `/memories/session/env-facts.md` — the authoritative single source of truth. Do **not** re-detect or re-scan.

Confirm all three values are present. If `env-facts.md` does not exist (e.g. a resumed run that lost state), re-execute both blocking steps in full before continuing.

### Result

All Maven commands in Steps 5, 6, and 7 must apply the JDK Override rules in [terminal-execution.md](./references/terminal-execution.md) based on `JAVA_HOME_OVERRIDE_REQUIRED` read from `env-facts.md`.

## Step 3 — Expert Class Analysis (Subagent)

Delegate deep analysis of the class under test to an **expert-model subagent**. This subagent runs in a clean context window with full attention devoted to understanding the class logic, identifying edge cases, and producing a comprehensive Test Scenario Catalog.

### Why an Expert Subagent?

In-line analysis degrades under coverage-loop pressure; an expert-model subagent in a clean context window forces systematic reasoning about cardinality, uniqueness, state interaction, and error cascading before a single test is written.

### Gather Inputs

Before invoking the subagent, the main agent must gather:

1. **CLASS_UNDER_TEST_PATH**: The absolute path to the production class.
2. **EXISTING_TEST_CLASS_PATH**: Find any existing test class (same package under `src/test/`). If found, provide its absolute path. Otherwise, `none`.
3. **CALLER_FILE_PATHS**: Search the project for files that import or reference the class under test (e.g., `grep_search` for the class name). Provide up to 5 absolute paths, comma-separated. If none found, `none`.
4. **RELATED_CLASS_PATHS**: Identify parent classes, implemented interfaces, and closely related sibling classes. Provide their absolute paths, comma-separated. If none, `none`.
5. **PROJECT_MODULE**: The Maven module name (e.g., `core`).

### Invocation

Use `runSubagent` with the **expert** model from [Configuration](#configuration). Replace placeholder values with actual values:

```
runSubagent(
  model: "<expert model from model-config.md>",
  prompt: "You are an expert Java code analyst. Your job is to deeply analyze a Java class and produce a comprehensive Test Scenario Catalog that covers all meaningful code paths, edge cases, and potential bugs.

**Read these files first, in order:**
1. Environment Fact Sheet at: <absolute path to /memories/session/env-facts.md>
   — This contains the project's Java version, AEM version, and available test dependencies. Internalize before reading anything else.
2. class-analysis.md at: <absolute path to skills/java-unit-test-writer/class-analysis.md>
   — This contains your full analysis protocol. Follow it phase by phase.
3. global-copilot-instructions.md at: <absolute path to instructions/global-copilot-instructions.md>
4. java-testing.instructions.md at: <absolute path to instructions/java-testing.instructions.md>
5. java-code.instructions.md at: <absolute path to instructions/java-code.instructions.md>

**Inputs:**
- CLASS_UNDER_TEST_PATH: <absolute path to the class under test>
- EXISTING_TEST_CLASS_PATH: <absolute path to existing test class, or 'none'>
- CALLER_FILE_PATHS: <comma-separated paths, or 'none'>
- RELATED_CLASS_PATHS: <comma-separated paths, or 'none'>
- PROJECT_MODULE: <module name>

**Execute all phases in class-analysis.md.** Return the complete output as specified in Phase 8.",
  description: "Expert analysis of <ClassName>"
)
```

### Process the Catalog

After the subagent returns:

1. **Save** the Test Scenario Catalog to `/memories/session/test-scenario-catalog.md` for resilience.
2. **Handle Critical Issues**: If the subagent reported critical issues (issues that prevent correct test execution, violate fundamental project rules, or indicate the class under test has structural problems that make meaningful testing impossible), present them to the user with three options via `vscode_askQuestions`:

   | Option | Label | Behavior |
   |--------|-------|----------|
   | **A** | **Auto-fix** | Apply the recommended fixes to the production code. |
   | **B** | **Manual fix** | Wait for user confirmation, then re-read the file. |
   | **C** | **Proceed anyway** | Acknowledge and test against current code. Record in [Final Report](#step-8--final-report). |

3. **Handle Suspected Logic Errors**: If the subagent reported suspected logic errors, present each one to the user with three options via `vscode_askQuestions`:

   | Option | Label | Behavior |
   |--------|-------|----------|
   | **A** | **It's a bug — fix it** | Fix production code. Use `logic-error-fix` scenarios from the catalog. |
   | **B** | **It's intentional** | Use `logic-error-current` scenarios from the catalog. |
   | **C** | **Skip this method** | Exclude the method from testing. Record in [Final Report](#step-8--final-report). |

4. **Extract the Dependency Setup** section — use it to inform mock/stub choices in Step 4.

## Step 3.5 — Baseline Coverage Check (Existing Tests Only)

> **Condition**: This step runs **only** when `EXISTING_TEST_CLASS_PATH` is not `none`. If no existing test class was found, skip directly to Step 4.

Before writing any new test code, measure the coverage that the **existing** tests already provide. This avoids unnecessary work when coverage is already at or above the target, and establishes a baseline for the iteration loop.

### Procedure

1. Run the existing test class with JaCoCo using the same Maven command as [Step 5](#step-5--measure-coverage), following the [Terminal Execution Rules](#terminal-execution-rules) and JDK Override rules.
2. Read the per-class coverage from the JaCoCo XML report (same parsing as Step 5).
3. **Evaluate**:
   - If **both** LINE ≥ coverage target **and** BRANCH ≥ coverage target → report to the user: *"Existing tests for `<ClassName>` already meet the coverage target (LINE: N%, BRANCH: N%). No additional tests needed."* **Stop** — skip Steps 4–8.
   - If existing tests **fail to compile or fail at runtime** → record the failure, continue to Step 4. The Step 6 iteration loop will handle compilation and test fixes.
   - Otherwise → record baseline coverage and continue to Step 4.
4. **Checkpoint** baseline numbers to `/memories/session/skill-progress.md`:

   ```
   ## Baseline Coverage (existing tests)
   - LINE: <line coverage %>
   - BRANCH: <branch coverage %>
   - STATUS: below target — proceeding to Step 4
   ```

## Step 4 — Write / Update Tests

Use the **Test Scenario Catalog** from Step 3 as the blueprint for writing tests. Apply all rules from [java-testing.instructions.md](../../instructions/java-testing.instructions.md) and [java-code.instructions.md](../../instructions/java-code.instructions.md).

### Update Mode (Existing Test Class)

This subsection applies when `EXISTING_TEST_CLASS_PATH` is not `none` — i.e., there is already a test class for the class under test.

- **Modify the existing test file in place** — do not create a new file or rewrite from scratch.
- **Preserve** existing test infrastructure: `@BeforeEach`/`@Before` setup methods, `@AfterEach`/`@After` teardown, helper methods, inner classes, field declarations, and `@Rule`/`@ExtendWith` annotations — unless they conflict with new tests or are broken by the refactoring.
- **Preserve** existing test methods that cover catalog scenarios marked `covered` (the `Existing coverage` field on each scenario in the catalog). Do not rewrite tests that already work correctly.
- **Enhance** existing test methods for scenarios marked `partial` — strengthen assertions, add missing cardinality variations, or update expected values to match refactored behavior.
- **Add** new test methods for scenarios marked `missing`.
- **Update** existing test methods whose covered code path was significantly refactored (method signature changed, return type changed, logic rewritten) — adapt the test to match the new behavior rather than deleting and rewriting.
- **Remove** test methods that target methods or code paths that no longer exist in the class under test (dead tests). Do not keep tests that cannot compile.

### Catalog-Driven Test Writing

- Every **HIGH** and **MEDIUM** priority scenario **whose existing coverage is `missing` or `partial`** must have a corresponding new or enhanced test method. Scenarios marked `covered` can be skipped unless the class under test was refactored and the existing test is now stale (does not compile, or asserts against outdated behavior).
- **LOW** priority scenarios should be covered if the coverage target is not yet met after HIGH and MEDIUM scenarios are implemented.
- Use the **Setup** section of each scenario to construct fixtures.
- Use the **Expected** section to write assertions — these are the specific values, properties, and state changes to verify.
- Use the **Dependency Setup** section from the catalog to wire dependencies via the Mock Avoidance Hierarchy.

### Mock Avoidance — Mandatory Pre-Check

Before introducing **any** `Mockito.mock()` or `@Mock` annotation, apply the [Mock Avoidance Hierarchy](../../instructions/java-testing.instructions.md). Use the dependency decisions from the catalog's **Dependency Setup** section. For every dependency:

1. Use AemContext / Sling testing library entities first.
2. Search the project for a real `…Impl` class and register it.
3. Create an inline makeshift implementation for simple interfaces.
4. Register a custom adapter for `.adaptTo()` needs.
5. Only if 1–4 are genuinely infeasible, use `Mockito.mock()`.

### Assert Substantive Outcomes

Every test method must assert on the **specific outputs or side effects** of the code path it exercises, as documented in the scenario's **Expected** section. Assertions must verify *values*, not just *shapes*:

- If a method populates object's (map's) properties → assert each property's key **and** value.
- If a method transforms a collection → assert element contents, not just `.size()`.
- If a method returns an object → assert its meaningful fields, not just non-null.
- If a branch changes behavior based on a condition → assert what differs in the output, not just that the method completed.
- If a method converts N entities into N resources with properties → assert the properties on each resource, not just the count.

A test that only asserts `.size()`, `assertNotNull`, or `assertDoesNotThrow` when the exercised path produces verifiable values is **incomplete** and must be strengthened.

## Terminal Execution Rules

Read and follow [references/terminal-execution.md](./references/terminal-execution.md) for all Maven invocations in this skill. That file defines the primary method (`execution_subagent`), fallback (`run_in_terminal` sync), Maven output rules, banned behaviors, and Windows terminal compatibility requirements.

Every Maven build in Steps 5, 6, and 7 **must** comply with those rules. Violations (yielding control, waiting passively, asking the user to continue) are skill failures.

## Step 5 — Measure Coverage

Run tests for only the target test class and generate the JaCoCo report per the [Terminal Execution Rules](#terminal-execution-rules) and [JDK Override](./references/terminal-execution.md) rules.

Default command — use this form when `JAVA_HOME_OVERRIDE_REQUIRED` is `YES` (from env-facts.md):

```
cmd /c "set JAVA_HOME=<JAVA_SDK_PATH>&& mvn test jacoco:report -pl core -Dtest=<TestClassName> -DfailIfNoTests=false -B -ntp 2>&1"
```

> If `JAVA_HOME_OVERRIDE_REQUIRED` is `NO`, omit the `set JAVA_HOME=<JAVA_SDK_PATH>&&` prefix.

The per-class XML report is written to:

```
core/target/site/jacoco/jacoco.xml
```

### Read Coverage for the Target Class

Search the XML for the `<class>` element whose `name` attribute matches the class under test (uses `/` as separator):

```xml
<class name="com/hpe/www/core/service/foo/MyService" ...>
  <counter type="LINE"   missed="2" covered="18" />
  <counter type="BRANCH" missed="1" covered="7"  />
</class>
```

Compute coverage percentage:

$$\text{coverage} = \frac{\text{covered}}{\text{covered} + \text{missed}} \times 100$$

**Target: the coverage target defined in the [Coverage Target](#coverage-target) section.**

## Step 6 — Iterate Until Target Is Reached

Repeat Steps 4 → 5 until **either** (a) the coverage target is met, **or** (b) all remaining uncovered paths are confirmed genuinely untestable per [Handling Genuinely Untestable Paths](#handling-genuinely-untestable-paths) — whichever comes first. Do not continue adding tests beyond that point. Every Maven re-run in this loop **must** follow the [Terminal Execution Rules](#terminal-execution-rules). Never yield control, never wait passively, never ask the user to continue.

**Checkpoint after every iteration**: update `/memories/session/skill-progress.md` with the current LINE % and BRANCH % so progress survives an interruption.

### Critical Rules Refresher

**Before writing or editing any test code in each iteration**, re-read this compact checklist. These are the rules most likely to be violated after multiple iterations when earlier instructions have been pushed out of attention:

1. **Re-read `/memories/session/env-facts.md`** — confirm the Java version, available test dependencies, AEM Mock version, AND `JAVA_HOME_OVERRIDE_REQUIRED`. Do not import classes from dependencies not listed there. Do not use Java language features above the declared version. **If `JAVA_HOME_OVERRIDE_REQUIRED` is `YES`, every Maven command in this iteration MUST include the `set JAVA_HOME=<JAVA_SDK_PATH>&&` prefix** (read `JAVA_SDK_PATH` from the same file).
2. **Consult the Test Scenario Catalog** — before adding tests to fill coverage gaps, check the catalog for scenarios that target those uncovered branches. Prefer catalog scenarios over ad-hoc test creation, since the catalog was produced by deep expert analysis.
3. **Exhaust Mock Avoidance Hierarchy** — before every `Mockito.mock()`, walk through: **(a)** AemContext / Sling testing libraries (`context.request()`, `context.resourceResolver()`, `MockResourceResolver`, etc.), **(b)** real `…Impl` class from the project registered via `context.registerService()` / `context.registerInjectActivateService()`, **(c)** inline makeshift class for simple interfaces (anonymous or `private static` inner class), **(d)** custom `AdapterFactory` or `context.registerAdapter()` for `.adaptTo()` needs. Only **(e)** `Mockito.mock()` as absolute last resort when a–d are genuinely infeasible. AEM platform classes (`SlingHttpServletRequest`, `ResourceResolver`, `Resource`, `Session`, etc.) come from AemContext — NEVER from `Mockito.mock()`.
4. **Split call chains** — capture every intermediate return value in a typed local variable. Add `assertNotNull` before calling methods on it. No `foo.getBar().getBaz()` chains.
5. **No static imports except assertions** — write `Mockito.when(...)`, `Mockito.verify(...)`, `Mockito.any()` — never `when(...)`, `verify(...)`, `any()`.
6. **Fields used in one method → local variables** — including `@Mock` fields used only in `@BeforeEach`.
7. **Minimal comments** — no Javadoc on the test class, no section separators, no obvious narration. Brief inline comments are allowed only to explain what specific condition or edge case is being tested when not obvious from the test name and setup code.
8. **No assertion messages** — no `assertNotNull(x, "message")`.

### Micro-Step Compilation

Do **not** write multiple test methods and then compile once. Instead, compile after each individual test method to catch errors immediately while context is fresh:

1. Write or modify **ONE** test method.
2. Run a **compile-only** build (no tests, no JaCoCo). Use the override form by default:
   ```
   cmd /c "set JAVA_HOME=<JAVA_SDK_PATH>&& mvn test-compile -pl core -B -ntp 2>&1"
   ```
   Omit the `set JAVA_HOME=<JAVA_SDK_PATH>&&` prefix only if `JAVA_HOME_OVERRIDE_REQUIRED` is `NO` (from env-facts.md).
3. **If compilation succeeds** → proceed to the next test method.
4. **If compilation fails** → log the error to the [Error Ledger](#error-ledger) and fix it before writing any more methods. The [Circuit Breaker](#circuit-breaker) applies.
5. After **all** test methods compile successfully, run the full test suite with JaCoCo as in [Step 5](#step-5--measure-coverage).

This prevents accumulation of multiple compilation errors that obscure each other, and makes error ledger entries precise (one error per method, not a wall of errors).

### Error Ledger

Track every build failure in `/memories/session/error-ledger.md` to detect circular reasoning. After each failed build (compilation or test execution), append a structured entry:

```markdown
### Attempt <N>
**Error class**: <compilation | test-failure | missing-dependency | mock-setup | unknown>
**Error message**: <one-line summary of the actual error>
**Fix attempted**: <what code change was made to address it>
**Result**: <still failing | fixed>
```

**Error classification guide:**

| Error Class | Symptoms |
|-------------|----------|
| `compilation` | `[ERROR] ... cannot find symbol`, `incompatible types`, syntax errors |
| `test-failure` | `BUILD SUCCESS` but test assertions fail, `AssertionError`, unexpected exceptions |
| `missing-dependency` | Import cannot be resolved, class not found at compile time, `NoClassDefFoundError` |
| `mock-setup` | `MissingMethodInvocationException`, `UnnecessaryStubbingException`, NPE inside mock wiring |
| `unknown` | Anything that doesn't fit the above categories |

After a successful build, reset the consecutive failure counter for all error classes.

### Circuit Breaker

The circuit breaker prevents the agent from going in circles when a fix approach is fundamentally wrong.

**Trigger conditions** — the circuit breaker trips when **either** of these is true:

1. **2 consecutive failures** in the **same error class** without a successful build in between.
2. **5 total failures** in a single coverage iteration (Step 6 loop), regardless of error class.

**When the circuit breaker trips:**

1. **STOP** modifying test code immediately. Do not attempt another fix.
2. **Save** the current test class to `/memories/session/stuck-test-snapshot.md`.
3. **Read** the error ledger entries for the current error class.
4. **Invoke** the [Diagnostic Subagent](#diagnostic-subagent-invocation).

**After the Diagnostic Subagent returns:**

- If diagnosis includes a fix → apply it, reset the consecutive failure counter, continue the iteration loop.
- If diagnosis says "abandon this test method" → skip the method, note it in the [Final Report](#step-8--final-report), continue with remaining gaps.
- If diagnosis is inconclusive → **escalate to the user** via `vscode_askQuestions`:

  > *"I've been unable to resolve a recurring `<error class>` error after multiple attempts. The diagnostic subagent could not identify a fix either.*
  >
  > *Error: `<one-line error summary>`*
  >
  > *What I tried: `<summary of fix attempts from error ledger>`"*

  Options:
  | Option | Label | Behavior |
  |--------|-------|----------|
  | **A** | **I'll fix it manually** | Wait for user to confirm the fix, then re-read the test class and continue. |
  | **B** | **Skip this test method** | Exclude the method, note in Final Report, continue. |
  | **C** | **Abort skill** | Stop the skill entirely. Deliver a partial Final Report. |

### Diagnostic Subagent Invocation

When the circuit breaker trips, invoke a **fresh-context expert-model subagent** to diagnose the failure. This subagent gets **only** the essential inputs — no accumulated build noise, no iterative edit history — so it can reason from first principles.

```
runSubagent(
  model: "<expert model from model-config.md>",
  prompt: "You are a build failure diagnostician. A test-writing agent has been going in circles trying to fix a recurring error. Your job is to diagnose the root cause from a clean perspective and propose a targeted fix.

**Read this protocol first:**
1. diagnostic-subagent.md at: <absolute path to skills/java-unit-test-writer/references/diagnostic-subagent.md>
   — This contains your full diagnostic protocol. Follow it phase by phase.

**Inputs:**
- ENV_FACTS_PATH: <absolute path to /memories/session/env-facts.md>
- ERROR_LEDGER_ENTRIES:
<paste the relevant error ledger entries here>
- TEST_CLASS_PATH: <absolute path to /memories/session/stuck-test-snapshot.md>
- CLASS_UNDER_TEST_PATH: <absolute path to the production class>
- FAILING_ERROR_MESSAGES:
<paste the specific compiler errors or test failure stack traces>

**Execute all phases in diagnostic-subagent.md.** Return the Diagnosis as specified in Phase 5.",
  description: "Diagnose recurring <error class> failure in <TestClassName>"
)
```

### Iteration Steps

1. Identify which lines and branches remain uncovered. The HTML report at `core/target/site/jacoco/index.html` provides a visual view; the XML counters are the authoritative source.
2. Add tests that exercise those gaps — consult the Test Scenario Catalog first, then add ad-hoc tests for remaining gaps.
3. Re-run Maven via `execution_subagent` and re-read the coverage numbers.
4. Continue until the target is met or until all meaningfully testable paths are covered.
5. When the target is met, avoid adding more tests just to increase the percentage if the test structure would violate the rules in `java-testing.instructions.md` (e.g. by creating many tiny test methods or extensive mocking).

### Handling Genuinely Untestable Paths

Some code paths cannot be exercised in a unit test by design:

- OSGi `activate` / `deactivate` lifecycle callbacks invoked only by the framework
- Catch blocks for checked exceptions that the mock/stub implementation can never throw
- Dead code guarded by framework-managed invariants (e.g. a branch that is only reachable when the OSGi container supplies a `null` service)
- Real I/O or external service calls that must not be exercised in isolation

When such paths are the only thing standing between the current coverage and the coverage target:

1. **Identify** each untestable path explicitly and confirm it cannot be reached without violating the constraints in `java-testing.instructions.md`.
2. **Set the floor** to the highest coverage achievable while respecting those constraints. Do not write tests that violate the rules just to hit a number.
3. **Document** the reason in the [Final Report](#step-8--final-report) summary you report to the user — not as a comment in the test class.

### Deduplication Pass

After coverage targets are met, review the full test class for repeated boilerplate. Extract common setup patterns, frequently used mock-wiring sequences, and repeated casts into private static utility methods per the DRY rules in `java-testing.instructions.md`. This is the right moment because you now see the full picture of which patterns repeat.

### Method Grouping Pass

**Trigger**: the test class has more than ~10 test methods.

Apply this pass as the final structural step — after the deduplication pass is complete, before the compliance review. Follow the **[Method Grouping and Section Dividers](../../instructions/java-testing.instructions.md)** rules in `java-testing.instructions.md`: one section per public method under test; methods ordered happy-path → boundary → error within each section; lifecycle methods in runtime order; cross-cutting concerns in their own sections at the end. Use the mandatory `/* --- / name / --- */` block-comment divider format with dash rows whose length exactly matches the section name character count.

### Static Analysis Pass (JetBrains MCP)

**Condition**: Run this pass after the Method Grouping Pass (or after the Deduplication Pass when the class has ≤10 methods), before the Step 6 Exit Gate.

If the JetBrains MCP server is available, use its **"Find problems in file"** tool to catch code smells the compiler won't reject: unused imports, unused variables, unused method parameters, dangling `throws` clauses, redundant casts, unnecessary `null` checks, and similar warnings.

1. Call **"Find problems in file"** with the absolute path of the test class.
2. For each problem reported, fix it in the test class.
3. Repeat until **"Find problems in file"** returns no problems.
4. After all problems are resolved, run a **compile-only** build to confirm the fixes did not introduce regressions:
   ```
   cmd /c "set JAVA_HOME=<JAVA_SDK_PATH>&& mvn test-compile -pl core -B -ntp 2>&1"
   ```
   Omit the `set JAVA_HOME=<JAVA_SDK_PATH>&&` prefix if `JAVA_HOME_OVERRIDE_REQUIRED` is `NO`.

> **JetBrains MCP unavailable**: if the tool is not present or returns an error, skip this pass entirely. This is not a blocker.

### Step 6 Exit Gate — MANDATORY

**Step 6 is NOT complete until Step 7 (Compliance Review) has run and returned a passing report.** Delivering coverage numbers to the user does NOT constitute task completion. Do NOT proceed to Step 8, do NOT summarize results, and do NOT emit any "done" or "success" message before Step 7 finishes. Checkpoint to `/memories/session/skill-progress.md` now:

```
## Step 6 Exit
- LINE: <line coverage %>
- BRANCH: <branch coverage %>
- STATUS: complete — proceeding to Step 7 compliance review (NOT YET DONE)
```

Then immediately invoke the Step 7 subagent below.

## Step 7 — Compliance Review (Subagent)

> **This step is MANDATORY and non-skippable.** It must execute every time, regardless of how clean the test class appears or how much context has been consumed during Step 6. If context pressure is a concern, keep the subagent prompt inputs minimal — but the subagent MUST be invoked.

Invoke an **expert-model subagent** to perform a full compliance review of the test class. The subagent runs in a fresh context window, free from the accumulated build output and iterative analysis that cause rule drift in long sessions.

### Why a Subagent?

Coverage-loop context accumulation pushes earlier rules out of attention; a fresh expert-model subagent re-reads all instructions from scratch and catches violations the main agent missed. In CLI environments especially, the agent has often emitted a coverage-success message and may treat the task as done — this step exists precisely to prevent that.

### Invocation

Use `runSubagent` with the **expert** model from [Configuration](#configuration). Replace the placeholder values with actual values from the current execution:

```
runSubagent(
  model: "<expert model from model-config.md>",
  prompt: "You are a test compliance reviewer. Your job is to review a Java unit test class for full compliance with the project's testing and coding standards, auto-fix any violations, and confirm the tests still pass.

**Read these files first, in order:**
1. Environment Fact Sheet at: <absolute path to /memories/session/env-facts.md>
   — This contains the project's Java version, AEM version, and available test dependencies. Internalize before reading anything else.
2. compliance-review.md at: <absolute path to skills/java-unit-test-writer/compliance-review.md>
   — This contains your full review protocol. Follow it phase by phase.
3. java-testing.instructions.md at: <absolute path to instructions/java-testing.instructions.md>
4. java-code.instructions.md at: <absolute path to instructions/java-code.instructions.md>

**Inputs:**
- TEST_CLASS_PATH: <absolute path to the test class>
- CLASS_UNDER_TEST_PATH: <absolute path to the class under test>
- TEST_CLASS_NAME: <simple class name, e.g. MyServiceTest>
- MAVEN_COMMAND: cmd /c \"mvn test jacoco:report -pl core -Dtest=<TestClassName> -DfailIfNoTests=false -B -ntp 2>&1\"
- JAVA_HOME_OVERRIDE_REQUIRED: <YES | NO — from env-facts.md>
- JAVA_SDK_PATH: <absolute path — from env-facts.md; only needed when JAVA_HOME_OVERRIDE_REQUIRED is YES>
- COVERAGE_LINE: <line coverage %>
- COVERAGE_BRANCH: <branch coverage %>
- UNTESTABLE_PATHS: <list or 'none'>
- CRITICAL_ISSUES_STATUS: <'none' | 'auto-fixed' | 'manual-fixed' | 'proceed-anyway'>
- LOGIC_ERROR_DECISIONS: <list or 'none'>
- TEST_SCENARIO_CATALOG_PATH: <absolute path to /memories/session/test-scenario-catalog.md, or 'none'>

**Execute all phases in compliance-review.md.** Auto-fix every violation found. Re-run Maven to confirm BUILD SUCCESS after fixes. Return the Final Report as specified in Phase 7 of compliance-review.md.",
  description: "Compliance review of <TestClassName>"
)
```

### If the Subagent Reports Failures

If the subagent's report indicates `Tests pass: NO`, diagnose and fix the issue. Re-invoke the subagent or fix manually and re-run Maven until `BUILD SUCCESS` is confirmed.

## Step 8 — Final Report

Present the subagent's compliance review report to the user verbatim — it already contains the violations fixed, assertion quality improvements, and the final checklist. The subagent's Phase 7 defines the authoritative report format; do not duplicate or restate its checklist here.

Additionally, call out:

1. **Final LINE % and BRANCH %** — from the subagent's report (which may differ from Step 6 if the subagent's fixes changed coverage).
2. **Untestable paths** — if the floor is below the coverage target, list each untestable path and the reason.
