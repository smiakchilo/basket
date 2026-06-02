---
description: >
  Reviewer heuristics accumulated from real PR comment post-mortems. Each heuristic
  describes a reviewing *action* — what to look for, trace, compare, or verify — that
  would have caught a class of defect before it reached GitHub. Loaded by the
  code-reviewer skill during Phase 1 and applied throughout Pass 2 analysis.
---

# Code Review Hints

This file accumulates **reviewer heuristics** derived from real GitHub PR comments that slipped through code review. Each heuristic describes a specific reviewing action a code-reviewer agent should take — not a coding rule, but a technique for catching a class of defect during review.

Heuristics are added here by the `comment-processor` skill (step 4.1.5.B) after a PR comment is applied and confirmed by the user.

## How to Use These Hints

When performing a code review (Phase 4, Pass 2), apply each heuristic below as a dedicated check. For each one, ask: does the code under review trigger the condition described? If yes, investigate and report.

## Review Heuristics

<!-- New heuristics are appended below this line by comment-processor 4.1.5.B -->

### Over-capturing transformation guards — 2026-05-14

When a loop filters then transforms elements of a collection, check whether the filter over-captures. Pick an element that satisfies the filter but needs no transformation and trace it through the pipeline — silent corruption usually lives in the guard, not the transform.

### Interface exception suppression

When reviewing an implementation of an interface method that declares a checked exception, check whether the override catches that exception internally. If it does, verify it re-throws or wraps it  not returns a sentinel. Trace any sentinel return value to its consumers and flag every site that assumes non-null/non-empty without an explicit guard.

### Multi-level null / bounds propagation

A null-check or validation guard at one layer does not protect the layers below it. When reviewing code that dereferences values across multiple call levels, trace the full chain  a non-null wrapper can still yield a null field; a validated input can still produce an out-of-range index; a non-null collection can still be empty. For every guard, ask: what can the *next* call in the chain return that would cause an NPE, IllegalArgumentException, IndexOutOfBoundsException, or silent misbehavior?

### Exception guard consistency

When a try/catch guards a specific method call, search the same class for every other invocation of that method. Flag any call site that lacks the same protection without a clear reason why it's safe.

### Locale-sensitive string operations

When reviewing string comparison, sorting, or key-normalization code, check every `toLowerCase()` and `toUpperCase()` call for an explicit locale argument. Flag any no-arg call on a non-display string — it silently uses `Locale.getDefault()` and will produce different results on JVMs with non-English default locales.

### Javadoc / signature drift

For every method whose signature changed in the diff (parameters, return type, or throws), check whether its Javadoc was updated in the same commit. Flag any @param, @return, or @throws tag that no longer matches the actual signature.

### Volatile field snapshot on concurrent shutdown

For classes with `volatile` fields nulled on shutdown: verify every read site snapshots the field into a local before checking/using it. A raw dereference of the volatile (no local snapshot) is a latent NPE on concurrent shutdown. Also check that calls on the snapshotted object catch `RejectedExecutionException` / `IllegalStateException`.

### Async supplier capturing a scoped resource

When a `Supplier` (or lambda) is passed to a caching / memoization method that may invoke the supplier asynchronously (e.g. background stale-while-revalidate refresh), check what the supplier captures. If it captures any **scoped or short-lived resource** — a JCR `Session`, a `ResourceResolver`, a JDBC `Connection`, an HTTP request-scoped object — flag it: the resource owner (e.g. `ResourceResolver.close()`, `try-with-resources`, a Sling request lifecycle) may close the resource before the background thread runs, causing a closed-session or use-after-close error at runtime. The fix is to make the supplier self-contained — it should open (and close) its own resource internally rather than relying on the caller's scope.

### ResourceResolver property map — Closeable lifecycle

When reviewing code that stores a `Closeable` (or `AutoCloseable`) value inside `ResourceResolver#getPropertyMap()`, do **not** flag missing explicit `close()` calls on that value. Per the [Sling API contract](https://sling.apache.org/apidocs/sling12/org/apache/sling/api/resource/ResourceResolver.html#getPropertyMap--), any value in the property map that implements `Closeable` is automatically closed when the holding `ResourceResolver` is closed. The lifecycle is managed by the resolver; explicit closing is unnecessary and would be premature if the value is shared across the resolver's lifetime.
