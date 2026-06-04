# Diagnostic Subagent Protocol

> **Purpose**: This document is read by an **expert-model subagent** invoked when the circuit breaker trips during the coverage iteration loop (Step 6). The subagent runs in a **clean context window** — free from accumulated build output, iterative edits, and attention drift — to diagnose why the build keeps failing and propose a targeted fix.

## When This Subagent Is Invoked

The main agent's circuit breaker triggers this subagent after:

- **2 consecutive failures** in the same error class (compilation, test-failure, missing-dependency, mock-setup), or
- **5 total failures** in a single coverage iteration, regardless of error class.

The main agent has already tried and failed to fix the problem. Repeating the same approach will not work. The subagent's job is to **step back, reason from first principles, and find the root cause**.

## Inputs

The calling agent provides these values in the subagent prompt:

| Variable | Description |
|----------|-------------|
| `ENV_FACTS_PATH` | Absolute path to `.github/memories/session/env-facts.md` — the project's fundamental environment facts |
| `ERROR_LEDGER_ENTRIES` | The full content of `.github/memories/session/error-ledger.md` (or the relevant entries) |
| `TEST_CLASS_PATH` | Absolute path to the current test class (snapshot saved before invocation) |
| `CLASS_UNDER_TEST_PATH` | Absolute path to the production class being tested |
| `FAILING_ERROR_MESSAGES` | The specific compiler errors or test failure stack traces |

## Phase 1 — Load Environment Facts

Read the file at `ENV_FACTS_PATH`. This contains the project's ground truth:

- Java version and SDK path for this project
- AEM version
- Available test dependencies (JUnit version, AEM Mock version, Mockito version)
- All test-scoped dependency artifact IDs

**Internalize these facts before analyzing anything.** Many circular failures stem from the agent forgetting what tools are available (e.g., using Mockito when AEM Mocks provides the same capability, or importing a class from a dependency that isn't in the POM).

## Phase 2 — Analyze the Error Ledger

Read the `ERROR_LEDGER_ENTRIES`. For each entry, note:

1. **What error class** was it? (compilation, test-failure, missing-dependency, mock-setup)
2. **What fix was attempted?**
3. **Did the fix change the error, or was it the exact same error?**

Look for patterns:

- **Same error, same fix repeated** → the agent was stuck in a loop. The fix approach is fundamentally wrong.
- **Same error, different fixes tried** → the agent explored but in the wrong direction. The root cause is misidentified.
- **Error changes each time** → the agent is making progress but introducing new issues. Look for a cascading dependency problem.

## Phase 3 — Read Source Code

1. Read the **test class** at `TEST_CLASS_PATH`.
2. Read the **class under test** at `CLASS_UNDER_TEST_PATH`.
3. Focus on the area of code related to the failing error — the specific method, import, or dependency that the error points to.

## Phase 4 — Root Cause Analysis

Using the environment facts, error patterns, and source code, determine the root cause. Check these common causes in order:

### 4a. Missing or Wrong Dependency

- Is the test importing a class that isn't available in any test-scoped dependency listed in env-facts?
- Is the agent using a version-specific API that doesn't exist in the declared dependency version?
- **Fix**: identify the correct class/API from the available dependencies, or flag that a dependency is genuinely missing.

### 4b. Wrong Mock Strategy

- Is the test using `Mockito.mock()` for a class that AEM Mocks / Sling Mocks provides natively?
- Is the test mocking a final class, a static method, or a class that Mockito cannot proxy?
- Is a mock returning `null` where the production code expects a real object with state?
- **Fix**: recommend the correct level of the Mock Avoidance Hierarchy. Provide the specific AEM Mock API call if applicable.

### 4c. Java Version Mismatch

- Is the test using language features (records, text blocks, `var`, sealed classes) not available in the project's Java version?
- Is a dependency compiled for a higher Java version than the project uses?
- **Fix**: rewrite the code using features available in the project's declared Java version.

### 4d. Incorrect Test Setup

- Is a Sling Model not being adapted correctly? (missing resource type registration, missing injector)
- Is an OSGi service not being registered properly in the AEM context?
- Is a `ResourceResolver` or `Session` being used after being closed?
- **Fix**: provide the correct setup code referencing the AEM Mock documentation for the version in env-facts.

### 4e. Structural Issue

- Is a circular dependency between test helper methods causing a compilation issue?
- Is the test class in the wrong package, causing visibility issues?
- **Fix**: describe the structural change needed.

## Phase 5 — Produce Diagnosis

Return a structured diagnosis in exactly this format:

```
## Diagnosis

### Root Cause
<One sentence describing the fundamental problem>

### Error Class
<compilation | test-failure | missing-dependency | mock-setup | java-version | structural>

### Why Previous Fixes Failed
<One sentence explaining why the approaches in the error ledger did not work>

### Recommended Fix
<Specific code change — include the exact import, method call, or code block to use.
Reference the correct dependency/API from env-facts if applicable.>

### Alternative Approach
<If the recommended fix might not work, provide a fallback approach.
If no alternative exists, write 'none'.>

### Should Abandon
<YES — if the test method is fundamentally untestable given the project's dependencies and constraints.
NO — if the fix should resolve the issue.
Include a one-sentence justification.>
```

## Constraints

- **Do not suggest adding new dependencies** unless the test is genuinely impossible without them. Work with what's in the POM.
- **Do not suggest Mockito** if AEM Mocks or Sling Mocks can solve the problem. Check env-facts for available mock libraries first.
- **Do not suggest Java features** above the project's declared Java version.
- **Be specific.** "Use AEM Mocks instead" is not helpful. "Use `context.request()` to get a `MockSlingHttpServletRequest` instead of `Mockito.mock(SlingHttpServletRequest.class)`" is helpful.
- **Reference env-facts** for every dependency-related recommendation. If a class comes from `io.wcm:io.wcm.testing.aem-mock.junit5:5.x`, say so.
