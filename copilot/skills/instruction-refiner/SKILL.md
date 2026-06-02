---
name: instruction-refiner
description: "Use when: refining AI agent instructions from manual code corrections, learning from user edits, improving coding guidelines, analyzing diffs to update instruction files, updating agent or skill definitions, post-generation cleanup"
argument-hint: "Optional path, file, or folder containing the manual corrections to analyze (omit to scan all uncommitted changes)"
---

# Instruction Refiner

Analyzes the user's manual corrections to AI-generated code and distills them into improved customization files — including instruction files, rules files, agent definitions, and skill definitions — so that future generations better match the user's style and standards. Works across Copilot, Claude, and Codex harnesses.

## When to Use

- User corrected AI-generated code and wants those patterns captured as instructions
- User wants to update an instruction file, rules file, skill, or agent definition based on recent edits
- User wants to prevent a recurring AI mistake by generalizing a correction into a rule

## Step 0 — Read Skill Memos and Resilience Protocol

Use the memory tool to read `/memories/skill-memos/instruction-refiner.md`. If the file exists, internalize its advice before proceeding. If it does not exist, continue.

**Write-back rule** — whenever an unexpected problem arises during this execution and you resolve it, append a memo entry (`### Title — YYYY-MM-DD` / `**Problem**: …` / `**Fix**: …`) to the same file (create it if absent). If the file exceeds ~30 lines, consolidate old entries. See [skill-learning.instructions.md](../../instructions/skill-learning.instructions.md) for the full protocol.

**Resilience protocol** — read and follow [resilience-protocol.instructions.md](../../instructions/resilience-protocol.instructions.md). Check `/memories/session/skill-progress.md` for a prior checkpoint for this skill and argument. If one exists, offer to resume. Checkpoint your progress after every major step. Emit a brief status message to the user after every step.

## Step 1 — Identify the Active Harness

Before doing any work, determine which harness is running this skill. Do not run shell commands for this — the answer is already in your context.

Inspect the path from which this `SKILL.md` was loaded. It appears in your context as the `<file>` tag in the skills list, or as the path in the tool result that read this file.

| If the load path contains… | Harness |
|----------------------------|---------|
| `/.copilot/skills/`        | **Copilot** |
| `/.claude/skills/`         | **Claude**  |
| `/.codex/skills/`          | **Codex**   |

If the path is absent or ambiguous, ask the user:
> _"Which harness is running this session — Copilot, Claude, or Codex?"_

Write `HARNESS: copilot|claude|codex` to your session progress checkpoint and carry it forward into Steps 5 and 6. All harness-specific behavior in this skill depends on this value.

See [references/harness-map.md](references/harness-map.md) for target paths, file formats, and the Codex authoring policy.

## Step 2 — Collect the Changes

Use the following decision tree to determine the diff source. In both cases, present a brief summary of the changes found (including whether they came from uncommitted work or the last commit) and confirm with the user before proceeding.

### Case A — specific file, package, or folder provided

1. Run `git diff HEAD -- <path>` and `git diff --cached -- <path>` to find uncommitted changes.
2. **Changes found** → proceed to Step 3.
3. **No uncommitted changes** → run `git log -1 --pretty=%B` to read the last commit message.
   - If the message **semantically signals a correction or refinement** (see keyword list below) → run `git diff HEAD~1 HEAD -- <path>` and use that as the diff source. Note in the summary that the diff comes from the last commit, not uncommitted work.
   - If the message does **not** qualify → stop. Tell the user: no uncommitted changes were found for `<path>` and the last commit (`<message>`) does not appear to be a correction. Ask them to clarify what to analyze.
4. If the commit diff for the path is also empty → stop and inform the user.

### Case B — no target specified (whole repo)

1. Run `git diff HEAD` and `git diff --cached` to find all uncommitted changes.
2. **Changes found** → proceed to Step 3.
3. **No uncommitted changes** → run `git log -1 --pretty=%B` to read the last commit message.
   - If the message qualifies (see keyword list) → run `git diff HEAD~1 HEAD` and use that as the diff source. Note in the summary that the diff comes from the last commit.
   - If the message does not qualify → stop. Tell the user: no uncommitted changes were found and the last commit (`<message>`) does not appear to be a correction. Ask them to clarify what to analyze.

### Refinement keyword list

A commit message qualifies if it contains any of the following words (case-insensitive, partial/inflected-form match):

`refine`, `fix`, `correct`, `modify`, `improve`, `update`, `adjust`, `tweak`, `cleanup`, `clean up`, `rework`, `revise`, `amend`, `patch`, `polish`

Examples that qualify: `"Fixed test output"`, `"Refined instructions"`, `"Improve naming conventions"`, `"Minor cleanup"`.
If the message matches **only** purely unrelated keywords (e.g. `"Add new feature"`, `"Initial commit"`) it does **not** qualify — only look at HEAD, do not walk further back.

## Step 3 — Load Model Configuration

Read `$HOME/.copilot/model-config.md` (i.e. `~/.copilot/model-config.md`) to obtain the **expert** model name. Use that model for all `runSubagent` calls in Steps 4–6.

## Step 4 — Interpret the Corrections

> **Model routing**: Delegate this step and Steps 5–6 to a `runSubagent` call using the **expert** model obtained in Step 3. Pass the full diff and all context gathered so far as the subagent prompt. The subagent should return its analysis and proposed changes as structured text; the orchestrating agent then presents results to the user per the confirmation rules in Step 6.

For each change, determine:
- **What pattern was corrected** (naming, structure, style, API usage, test approach, etc.).
- **Why** the user likely made the change (infer intent from context).
- **A generalized rule** that would prevent the same kind of output in the future.

> **IMPORTANT**: If the intent behind a change is ambiguous or you cannot confidently map it to an instruction, **stop and ask the user** before proceeding. Never guess.

### Confirmation protocol

For each correction, follow this strict sequence:

1. **Open question first** — present your interpretation of the correction in plain language and ask an open-ended question: *"I believe the correction is: [description]. Did I get this right? Feel free to add comments, clarifications, or corrections."* Do **not** offer numbered choices or yes/no options at this stage.
2. **Wait for the user's response.** If the user corrects or refines your interpretation, update your understanding and repeat the open question with the revised interpretation until the user confirms.
3. **Only after the user approves the interpretation**, proceed to ask any narrower follow-up questions (placement, scope, wording, etc.). These may be closed questions with options.

Never skip the open question. Never jump straight to logistics (where to place, how to phrase) before the user has confirmed that you understood the correction itself.

## Step 5 — Locate the Best Customization File

Use the `HARNESS` value from Step 1 to determine where to search. Always explicitly list the contents of each location if it exists. After listing, identify the most relevant file based on the change's context.

Customization files include:
- **Instruction files** — coding rules and style guidelines (`*.instructions.md` for Copilot; `*.md` under `rules/` for Claude; `AGENTS.md` sections for Codex).
- **Prompt files** (`*.prompt.md`) — reusable prompt templates (Copilot only).
- **Agent files** (`*.agent.md`) — agent mode definitions (Copilot only).
- **Skill files** (`SKILL.md`) — step-by-step workflow definitions invoked as named skills.

For the full directory paths to search per harness, see **[references/harness-map.md — Target Paths](references/harness-map.md)**.

### Scope heuristic

Applies to all harnesses:

- Correction is **project-specific** → prefer project-level file.
- Correction is **language/framework-generic** → prefer user-level file (n/a for Codex).
- Correction reveals a flaw in **how a skill drives a workflow** → update the relevant `SKILL.md`.
- Correction reveals a flaw in **how an agent is described or triggered** → update the relevant agent definition.
- If no file exists at the appropriate level, ask the user whether to create one and at which level.

### Redundancy check — why an existing rule was not followed

After locating the relevant customization files, read them and cross-reference each derived rule (from Step 4) against the existing instructions. If a correction maps to a rule that **already exists**, do **not** simply report "this is already covered." Instead:

1. **Stop and think deeply** about *why* the existing instruction failed to prevent the mistake. Generate one or more hypotheses from the following (non-exhaustive) list:
   - **Phrasing is too vague or abstract** — the rule lacks a concrete example or uses ambiguous language that the model can interpret multiple ways.
   - **Buried in a long file** — the instruction file is so large that the rule gets diluted or falls outside the model's effective attention window.
   - **Poor structural placement** — the rule is in a section the model does not associate with the code context (e.g., a naming rule hidden in a "Testing" section).
   - **Contradicted or overshadowed** — another instruction elsewhere conflicts with or weakens this rule.
   - **Wrong scope / path key mismatch** — the instruction file exists but its `applyTo` (Copilot) or `paths` (Claude) pattern does not match the files where the correction was needed.
   - **Missing emphasis** — the rule is stated once without signaling its importance, so the model treats it as low-priority.
   - **No negative example** — the rule says what to do but not what to avoid; the model doesn't recognize the anti-pattern.
   - **Instruction file not loaded** — the `description` field doesn't match the task context, so the agent never discovers or loads the file.

2. **Present the diagnosis to the user**: state which existing rule covers the correction, quote the relevant text, and list each hypothesis with a brief explanation of why it may apply.

3. **Propose a concrete fix** for the most likely cause (e.g., rewrite the rule with an example, split the file, move the rule to a better section, correct the path key, add a "DO NOT" counterpart). If multiple hypotheses are equally plausible, present each fix option separately and let the user choose.

4. **Wait for the user's approval** before making any changes.

## Step 6 — Draft Improvements

1. Read the target customization file (or start a new one).
2. Understand its existing structure, sections, and tone.
3. Before writing, verify the target directory exists (see **[harness-map.md — Safe-Write Guard](references/harness-map.md)**). If the directory is missing, warn the user and stop. Do not create parent directories silently.
4. Draft new rules or amend existing ones based on the file type and **active harness** (from Step 1). For file format templates, see **[harness-map.md — File Formats](references/harness-map.md)**. Key behavioral rules by file type:

   **For Copilot instruction files (`*.instructions.md`):**
   - YAML frontmatter keys: `description:` (string) and `applyTo:` (glob string; omit for always-on).
   - **Never use `paths:` in a Copilot instructions file** — it is a Claude-only key.
   - **Be generic**: generalize specific corrections into broader, reusable rules.
   - **Add examples** when the rule would be unclear without one. Keep examples minimal (before → after).
   - **Preserve structure**: match the file's existing organization. If adding a new topic, create a clearly labeled section.

   **For Claude rules files (`rules/*.md`):**
   - YAML frontmatter keys: `description:` (block scalar) and `paths:` (quoted string; omit for always-on).
   - **Never use `applyTo:` in a Claude rules file** — it is a Copilot-only key.
   - Follow the same style guidance as Copilot instruction files: generic, with examples, imperative voice.

   **For Codex `AGENTS.md`:**
   - **No YAML frontmatter** — these are plain Markdown files.
   - If the file carries an `<!-- Auto-generated by export.mjs -->` header, consult the Codex Authoring Policy in [references/harness-map.md](references/harness-map.md) before editing directly.

   **For skill files (`SKILL.md`):**
   - Amend the step that corresponds to the flawed behavior.
   - If the skill is missing a capability the user expects, add a new step or expand an existing one.
   - Update `description` and `argument-hint` in the YAML frontmatter if the skill's scope changes.

   **For agent files (`*.agent.md`) — Copilot only:**
   - Update the agent's `description` if its purpose or invocation triggers are wrong.
   - Add or remove tools, constraints, or behavioral guidance to reflect the user's intent.

5. If there is more than one proposed change, present and confirm them **one at a time** following the confirmation protocol from Step 4. Never present a list of all changes at once.

## Step 7 — Verify the Instructions

After the user approves and the instruction file is updated:

1. **Memorize** the current (user-corrected) state of a representative code file.
2. Use a subagent to **re-generate** that code file from scratch, with the updated instruction set active.
3. **Compare** the regenerated output against the memorized content.
4. If the output still diverges from the user's corrections:
   - Identify which rules are too vague or missing.
   - Propose further instruction amendments.
   - Repeat (up to 3 iterations).
5. **Always restore** the code file to the user's last manual version after verification — never leave regenerated content in place.

## Step 8 — Finalize

- Summarize all instruction changes made.
- List the files modified.
- Note any changes you were unsure about, for the user to review.

## Constraints

- **DO NOT** modify the user's source code permanently — only read diffs and temporarily regenerate for verification.
- **DO NOT** commit or push anything.
- **DO NOT** guess the user's intent — ask when unclear.
- **DO NOT** add instructions that contradict existing ones without flagging the conflict.
- **DO NOT** remove existing instructions unless the user explicitly asks.
- **ALWAYS** restore code files to the user's version after verification.
- **Never write `applyTo:` to a Claude rules file** (`~/.claude/rules/*.md`) — Claude uses `paths:`, not `applyTo:`.
- **Never write `paths:` to a Copilot instructions file** (`*.instructions.md`) — Copilot uses `applyTo:`, not `paths:`.
- **Never add YAML frontmatter to a Codex `AGENTS.md`** — these files are plain Markdown.
- **Prefer basket source + `export.mjs`** over direct edits to Codex `AGENTS.md` files when the basket repo is accessible. Direct edits are overwritten on the next install.

## Output Format

Return a structured summary:

```
## Instruction Refiner — Summary

### Changes Analyzed
- <file>: <brief description of correction>

### Rules Derived
1. <Rule> — derived from <change description>

### Customization File Updated
- Path: <path to file>
- Type: <instruction | prompt | agent | skill>
- Sections modified: <list>

### Verification Result
- <Pass/Fail> — <notes>

### Open Questions
- <Any unresolved ambiguities>
```
