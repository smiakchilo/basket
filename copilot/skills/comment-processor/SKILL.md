---
name: comment-processor
description: "Use when: processing PR comments, reviewing PR feedback, fetching GitHub pull request comments, handling Copilot review comments, triaging PR review suggestions, applying PR fixes. Fetches review and conversation comments from the GitHub PR associated with the current branch, evaluates each with the expert model, presents analysis for user verdict, applies approved fixes, and extracts lessons — delegating instruction file targeting and writing to the instruction-refiner skill."
argument-hint: "Optional: 'all' to include resolved comments (default: unresolved only)"
---

# PR Comment Processor

Fetches PR comments (review comments and conversation comments) from the GitHub pull request associated with the current branch, evaluates each comment's relevance and proposed fix using the expert model, presents a structured analysis to the user for approval, applies approved fixes, and extracts generalized lessons into instruction/skill files.

## When to Use

- User wants to process or triage PR review comments (especially Copilot-generated ones)
- User wants to evaluate and selectively apply suggestions from a PR review
- User says "process PR comments", "check PR feedback", "handle Copilot review", or similar

## Design Principles

1. **Never auto-apply** _(highest priority — overrides all other considerations)_. Every fix requires explicit user approval before any code change. Comments are always processed one at a time — there is no batch approval or batch skip.
2. **Evaluate, don't parrot.** The expert model assesses whether each comment is valid, relevant, and whether the proposed fix has unintended cross-effects — it does not blindly trust the reviewer.
3. **Learn from fixes.** Each applied fix is an opportunity to improve instruction files so the same mistake is prevented in future generations.

> Constraints 2 and 3 are secondary — they guide quality but do not block the core apply/skip flow.

## Step 0 — Setup, Memos & Resilience

### 0.1 Read Skill Memos

Use the memory tool to read `/memories/skill-memos/comment-processor.md`. If the file exists, internalize its advice before proceeding. If it does not exist, continue.

**Write-back rule** — whenever an unexpected problem arises during this execution and you resolve it, append a memo entry (`### Title — YYYY-MM-DD` / `**Problem**: …` / `**Fix**: …`) to the same file (create it if absent). If the file exceeds ~30 lines, consolidate old entries. See [Skill Learning — Persistent Memos](../../instructions/skill-learning.instructions.md) for the full protocol.


### 0.2 Resilience Protocol

Read and follow [Resilience Protocol](../../instructions/resilience-protocol.instructions.md). Check `/memories/session/comment-processor-progress.md` for a prior checkpoint matching this task. If one exists, offer to resume. Checkpoint your progress after completing each numbered step (Step 0, Step 1, Step 2, etc.). Emit a brief status message to the user after every step.

### 0.3 Model Configuration

Read `$HOME/.copilot/model-config.md` to obtain the **expert** model name. Use it for all `runSubagent` calls in Steps 3 and 6.

### 0.4 Verify GitHub CLI

Run:

```
gh --version
```

If `gh` is not found or not authenticated:
1. Inform the user that the GitHub CLI is required.
2. Provide install instructions: `winget install --id GitHub.cli` (Windows) or `brew install gh` (macOS).
3. After install: `gh auth login`.
4. Stop execution until the user confirms `gh` is ready.

## Step 1 — Identify the PR

### 1.1 Get Current Branch

```
git rev-parse --abbrev-ref HEAD
```

If this returns `HEAD` (detached state), try:
```
git branch --show-current
```

If still empty, inform the user and stop.

### 1.2 Find Associated PR

```
gh pr view --json number,title,url,headRefName,state
```

This automatically finds the PR for the current branch. If no PR is found:
- Inform the user: no open PR exists for this branch.
- Stop execution.

If the PR state is `MERGED` or `CLOSED`, warn the user and ask whether to proceed anyway.

Store the PR number, title, URL, and owner/repo (extract from URL or use `gh repo view --json nameWithOwner -q .nameWithOwner`).

**Status**: _"Step 1 complete — found PR #{number}: {title}. Moving to Step 2: fetching comments."_

## Step 2 — Fetch Comments

### 2.1 Determine Comment Scope

Check the user's argument:
- **Default (no argument or empty)**: fetch only unresolved/pending review comments.
- **`all`**: fetch all comments including resolved ones.

### 2.2 Fetch Review Comments (Inline Code Comments)

```
gh api repos/{owner}/{repo}/pulls/{number}/comments --paginate
```

For each comment, extract:
- `id`, `body`, `path` (file), `line` / `original_line`, `side`, `diff_hunk`
- `user.login`, `user.type` (identify bots: login contains `[bot]` or `copilot`, or type is `Bot`)
- `created_at`, `updated_at`
- `in_reply_to_id` (thread relationship)
- `subject_type` (if present, indicates whether it's a line comment or file comment)

### 2.3 Fetch Conversation Comments (PR-Level)

```
gh api repos/{owner}/{repo}/issues/{number}/comments --paginate
```

For each comment, extract:
- `id`, `body`
- `user.login`, `user.type`
- `created_at`

### 2.4 Filter and Group

1. **Filter**: if scope is default (unresolved only), use the PR review threads endpoint to check resolution status:
   ```
   gh api graphql -f query='
     query($owner:String!, $repo:String!, $number:Int!) {
       repository(owner:$owner, name:$repo) {
         pullRequest(number:$number) {
           reviewThreads(first:100) {
             nodes {
               isResolved
               comments(first:50) {
                 nodes { id databaseId body path line originalLine }
               }
             }
           }
         }
       }
     }
   ' -f owner={owner} -f repo={repo} -F number={number}
   ```
   Keep only comments from threads where `isResolved` is `false`. For conversation comments, keep all (they have no resolution state).

2. **Classify commenters**: tag each comment as `copilot`, `bot`, or `human` based on user login and type.

3. **Group by file**: collect all review comments for the same `path` into a group. Conversation comments form their own group ("PR-level").

4. **Thread ordering**: within each file group, sort by line number. Link reply chains via `in_reply_to_id`.

If no comments remain after filtering, inform the user and stop.

**Status**: _"Step 2 complete — fetched {N} review comments across {M} files and {K} conversation comments. {B} from Copilot, {H} from humans. Moving to Step 3: expert evaluation."_

## Step 3 — Expert Evaluation

Process comments **one file group at a time** to manage context. For each group, delegate to a `runSubagent` call using the **expert** model.

### Subagent Prompt Template

Provide the subagent with:
1. **The comment(s)** — full body text, commenter identity, file path, line numbers, diff hunk.
2. **The referenced file** — read the current version of the file from the workspace. If the file is large, read only the relevant section (±50 lines around the commented line).
3. **Surrounding context** — if the comment references other files, classes, or methods, read those too.
4. **Project instruction files** — list which instruction files exist (the subagent can read them if needed for cross-referencing).

### Subagent Task

For each comment, the subagent must return a structured analysis:

```
### Comment #{id} — {commenter} on {path}:{line}

**Original comment**: (quoted text)

**Understanding**: What the reviewer is asking for and why. One to three sentences.

**Relevance**: HIGH | MEDIUM | LOW | NOISE
- HIGH: Valid concern that affects correctness, security, performance, or maintainability.
- MEDIUM: Valid suggestion but impact is minor or stylistic.
- LOW: Technically correct but not worth changing in this context.
- NOISE: False positive, misunderstanding, or not applicable.

**Relevance rationale**: Why this score.

**Proposed fix evaluation**: (if the comment suggests a change)
- Correctness: Does the proposed fix actually solve the issue?
- Completeness: Does it handle all edge cases?
- Cross-effects: Would this change break or require updates to other files? List specific files and why.

**Amended fix**: (if the proposed fix needs adjustment)
- What to change and why it differs from the original suggestion.
- Include the specific code change (before → after) with enough context to apply.

**No-fix rationale**: (if relevance is LOW or NOISE) Why no action is recommended.
```

### Error Handling

If the subagent fails or returns malformed output for a file group, log the error, skip that group, and continue with the next. Report skipped groups in the summary.

**Status**: _"Step 3 complete — evaluated {N} comments. {H} HIGH, {M} MEDIUM, {L} LOW, {X} NOISE. Moving to Step 4: presenting results."_

## Step 4 — Per-Comment Interactive Loop

### 4.0 Opening Summary

Before entering the loop, present a brief orientation table so the user knows what is coming:

```
| # | Source | File | Line | Relevance | One-line summary |
|---|--------|------|------|-----------|-----------------|
```

Where:
- **Source**: `Copilot` / `bot` / `human (username)`
- **File**: file path (or "PR-level" for conversation/PR-level comments)
- **Line**: line number (or `—`)
- **Relevance**: HIGH / MEDIUM / LOW / NOISE

Then say: _"I will walk through each comment one at a time. Let me start with comment #1."_

### 4.1 Process Each Comment Individually

Process comments in relevance order (HIGH first, then MEDIUM, LOW, NOISE). For **each** comment, follow this strict sequence — do not move to the next comment until the current one is fully resolved.

#### 4.1.1 Present the Comment

Show the full expert analysis for this comment:

```
---
**Comment #{n} of {total}** — {Source} on {file}:{line}

**Original comment**:
> {quoted comment body}

**Understanding**: {what the reviewer is asking and why}

**Relevance**: {HIGH | MEDIUM | LOW | NOISE}
{relevance rationale}
```

If relevance is HIGH or MEDIUM, also show:

```
**Proposed fix evaluation**:
- Correctness: {…}
- Completeness: {…}
- Cross-effects: {list of affected files, or "none identified"}

**Amended fix** (before → after):
{code block}
```

If relevance is LOW or NOISE, show only:

```
**No-fix rationale**: {why no action is recommended}
```

#### 4.1.2 Open Question

After presenting the analysis, ask an **open-ended question**. Do **not** offer numbered choices or yes/no options at this stage. Example:

> _"This is my reading of comment #{n}. Do you agree with the analysis? Feel free to correct my understanding, ask for clarification, or tell me what you'd like to do."_

#### 4.1.3 Handle the User's Response

Wait for the user's reply and handle all cases:

| User says | Action |
|-----------|--------|
| Corrects understanding, asks for more detail, or provides new context | Update your interpretation (re-read the file, trace cross-effects, or incorporate the new information as needed), re-present the analysis, and re-ask the open question. Loop until the user confirms the understanding is correct. |
| Approves the fix — as-is or with modifications | If with modifications: ask one focused follow-up to clarify, then confirm the final version with the user. Proceed to **4.1.4 Apply**. |
| Skips / rejects | Record as skipped/rejected. Proceed to **4.1.5 Lesson Check** (even skipped comments may yield lessons). |

Never assume the user's intent. If the response is ambiguous, ask a clarifying question before acting.

#### 4.1.4 Apply the Fix

Apply the approved fix immediately (do not batch with other comments):

1. Read the target file (or the relevant section).
2. Apply the amended fix (or the user-modified version).
3. If the Step 3 analysis identified **cross-effects**, present each affected file and the required change, and ask the user whether to apply it before touching that file.
4. After the change is applied, confirm: _"Applied. The change is: {one-line description}."_
5. Ask: _"Want me to run a build/test to verify before continuing? (Specify the command or I'll use the project default.)"_ Apply verification only if the user says yes.

#### 4.1.5 Lesson Check (mandatory after every applied fix)

**This step is not optional.** Every time a fix is applied (step 4.1.4 completes successfully), you MUST immediately execute **both** lesson-extraction sequences below (A then B) before advancing to the next comment. Do NOT skip or defer either — even if the fix is "obvious" or "simple". If a comment was skipped or rejected (not applied), skip this section entirely.

##### 4.1.5.A — Coding Lesson

Derive a **coding rule** — broad and transferable — that prevents writing the same class of defect in the first place.

###### 4.1.5.A.1 Formulate a Generic Lesson

Derive a lesson that is **broad and transferable**, not specific to the exact code that was fixed. The lesson must be a general code-quality principle that would prevent an entire *class* of similar defects in any codebase.

**Critical rule — never write a narrow lesson.** The test: if someone who has never seen this codebase reads the rule, would it help them avoid similar problems when writing code? If yes, it is generic enough.

**Correct vs. incorrect examples:**

| Situation | Wrong (too narrow) | Correct (generic) |
|-----------|-------------------|-------------------|
| `gson.toJson()` return not null-checked before use | "Check `gson.toJson()` for null" | "For every method call whose return value is consumed without an explicit null check, trace whether the method contract allows null (even if rarely). Follow the value to every use site and assess whether a null there causes an NPE, silent data loss, or incorrect branching. Apply the same discipline to edge-case return values: could the result be negative, zero, empty, or `NaN`? Does the consumer handle it?" |
| Index computed and used without bounds validation | "Check array bounds before accessing index" | "Whenever an integer value — especially one derived from arithmetic, user input, or an external source — is used to index into a collection, array, or string, verify that every possible value it can hold falls within the valid range. Also consider overflow or underflow in the arithmetic that produces the index, and whether the collection can be empty." |
| A method that can throw an unchecked runtime exception is called without any error handling | "Wrap call to X in try-catch" | "Identify every call site where an unchecked exception (e.g., `NumberFormatException`, `IllegalStateException`, `ArithmeticException`) can realistically be thrown. Trace what happens if it propagates: does it terminate a request thread, corrupt shared state, or surface a raw stack trace to the user? Decide whether it should be caught locally, declared in the method signature, or documented — and flag any site that silently swallows it with an empty catch block." |
| A shared mutable field accessed from multiple places without synchronization | "Synchronize field X" | "When reviewing state that is read or written from multiple contexts (threads, event handlers, async callbacks), verify that every access is properly synchronized or that the type is inherently thread-safe. Consider visibility (stale reads) as well as atomicity (check-then-act races). The absence of an explicit thread annotation is not evidence of safety." |

###### 4.1.5.A.2 Present and Confirm

Present the candidate lesson and ask:

> _"This fix reveals the following general coding principle:_
>
> **Rule**: '{rule}'
>
> _I'd place it in {target instruction file}. Does this capture the right generic principle, or would you adjust the scope, wording, or target file? (Say 'skip' to discard it.)"_

Wait for the user's response. Update the rule and re-ask if needed. Apply once the user confirms. Only discard if the user explicitly says skip/no.

###### 4.1.5.A.3 Invoke instruction-refiner

Invoke the `instruction-refiner` skill with:
- `rule_text`: the user-confirmed rule text from 4.1.5.A.2.
- `rule_type`: `"coding rule"`.
- `suggested_target_file`: the target instruction file proposed in 4.1.5.A.2 (hint only — instruction-refiner applies its own scope heuristic and redundancy check).

instruction-refiner handles harness detection, file targeting, redundancy analysis, and writing. Do not perform any of those steps here.

##### 4.1.5.B — Reviewer Lesson

Derive a **reviewer heuristic** — what the code-reviewer agent should actively *do* during a code review to catch the same class of issue before it reaches GitHub. This is not a coding rule but a reviewing action: what to search, trace, compare, verify, or reason about.

###### 4.1.5.B.1 Formulate a Reviewer Heuristic

Derive a heuristic that describes the **reviewing technique** a code-reviewer agent should apply. It must answer: "What should I do — what to look at, trace, compare, or verify — to surface this class of defect during review?"

**Critical rule — the heuristic is a reviewing action, not a restatement of the coding rule.** Do NOT copy or paraphrase 4.1.5.A. The heuristic must describe what a reviewer *does*, not what a programmer *should write*. Do NOT default to "find similar usages elsewhere" if a more direct analytical technique applies (data-flow tracing, trust-boundary analysis, return-value contract inspection, lifecycle reasoning, and many others are all valid).

**The test for quality:** if someone who has never seen this codebase read this heuristic, would it prompt them to catch the same class of defect during review? If yes, it is generic enough.

**Correct vs. incorrect examples** (illustrating different reviewing techniques — not an exhaustive list):

| Situation | Wrong (restates coding rule or too vague) | Correct (specific reviewing action) |
|-----------|------------------------------------------|--------------------------------------|
| Code creates a resource but omits a property that all similar creation sites consistently set | "Ensure all required properties are set when creating a resource." | "When you see a non-trivial resource-creation call, search 3–5 similar creation sites in the codebase and compare their property sets. If those sites consistently set a property this site omits, flag the discrepancy and verify whether the omission breaks a contract or convention." |
| A value from user input or an external source is used immediately without validation | "Always validate input before use." | "When reviewing any value that crosses a trust boundary (user input, external API response, config file, env variable), trace it from entry point to consumption. If it reaches a sensitive operation — persistence, rendering, path construction, deserialization — without explicit validation or sanitization in between, flag the gap regardless of whether it appears to work in the common case." |
| A new async call is added but the caller does not await or handle the result | "Always await async calls." | "When you see a method call that returns a Future, Promise, Mono, or similar deferred type, verify that the caller either awaits it or explicitly handles its completion and failure paths. An un-awaited call that silently discards the result is a latent bug; the absence of a visible await or callback is the signal to investigate." |

These examples illustrate different reviewing techniques — cross-codebase consistency checking, data-flow / trust-boundary tracing, and return-value contract inspection. Derive whatever technique is most natural for the issue at hand.

###### 4.1.5.B.2 Present and Confirm

Present the candidate heuristic and ask:

> _"This fix also reveals the following reviewer heuristic for the code-reviewer agent:_
>
> **Heuristic**: '{heuristic}'
>
> _I'd place it in `skills/code-reviewer/references/code-review-hints.md`. Does this capture the right reviewing technique, or would you adjust the scope, wording, or target file? (Say 'skip' to discard it.)"_

Wait for the user's response. Update the heuristic and re-ask if needed. Apply once the user confirms. Only discard if the user explicitly says skip/no.

###### 4.1.5.B.3 Invoke instruction-refiner

Invoke the `instruction-refiner` skill with:
- `rule_text`: the user-confirmed heuristic text from 4.1.5.B.2.
- `rule_type`: `"reviewer heuristic for the code-reviewer agent"`.
- `suggested_target_file`: `code-reviewer/references/code-review-hints.md` (hint only — instruction-refiner may override based on its scope heuristic).

instruction-refiner handles harness detection, file targeting, redundancy analysis, and writing. Do not perform any of those steps here.

#### 4.1.6 Checkpoint and Advance

After completing a comment (apply + mandatory lesson, or skip):

**Gate**: if the comment was applied and either lesson check (4.1.5.A or 4.1.5.B) has not yet been completed, do NOT advance. Complete both before proceeding.

1. Checkpoint progress to `/memories/session/comment-processor-progress.md` — record last completed comment number, how many lessons were captured so far, and key state.
2. Emit: _"Comment #{n} done ({applied/skipped}). {L} lesson(s) captured so far. Moving to comment #{n+1}."_
3. Begin the next comment at **4.1.1**.

### 4.2 Loop Completion

When all comments have been processed, emit:

_"Step 4 complete — {A} applied, {R} rejected, {D} deferred. {L} lessons captured. Moving to Step 5: summary."_

## Step 5 — Summary & Cleanup

### 5.1 Final Summary

Present a structured summary:

```
## PR Comment Processor — Summary

**PR**: #{number} — {title}
**URL**: {url}

### Comments Processed
- Total fetched: {N}
- Evaluated: {E} ({H} HIGH, {M} MEDIUM, {L} LOW, {X} NOISE)
- Applied: {A}
- Rejected: {R}
- Deferred: {D}
- Skipped (errors): {S}

### Files Modified
- {path}: {description of changes}

### Lessons Captured
- {target file}: {rule summary}

### Notes
- {any warnings, skipped groups, or unresolved items}
```

### 5.2 Cleanup

Delete `/memories/session/comment-processor-progress.md` to allow the next invocation to start fresh.

## Constraints

- **Never auto-apply** — every code change requires explicit user approval.
- **Never push** — do not run `git push`, `git commit`, or any destructive git operation.
- **Respect context budget** — process one file group at a time; summarize and checkpoint between groups.
- **Preserve user code** — if a fix conflicts with the user's intent, always defer to the user.
- **No credentials in memos** — never store tokens, passwords, or full paths with usernames in skill memos.
