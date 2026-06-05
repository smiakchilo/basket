---
description: "Merge a new idea into a skill, instruction, or reference document. Checks for duplication and contradictions before inserting, then validates the full document."
argument-hint: "The idea to merge (target file defaults to the active editor)"
agent: "agent"
---

# Merge Idea

Integrate a user-supplied idea into an existing `.md` document — skill definition,
instruction file, or reference doc — while preserving document integrity.

## Input

- **Idea**: the prompt argument (free text describing the rule, guideline, or concept).
- **Target file**: the file currently open in the editor. If no file is open or the
  open file is not a `.md` customization file, ask the user to specify the target.

## Scope

If the target is a **skill** (`SKILL.md`), include every `.md` file in the skill's
folder and subfolders in the analysis scope. The idea may belong in a reference or
sub-document rather than the main skill file.

For **instruction** or **reference** files, the scope is the single target file.

## Process

### 1 — Read

Read the target file (and in-scope sub-documents for skills) in full. Build a mental
inventory of every rule, guideline, and concept it contains — noting the section each
lives under.

### 2 — Gate: Duplication

Ask: *"Does the document already express this idea — identically, in substance, or
as a special case of a broader rule?"*

- **Exact or near-duplicate found** → Report to the user. Quote the existing passage
  and explain how it covers the idea. Suggest:
  - rewording the existing passage to make the coverage clearer, or
  - promoting a buried mention to a more prominent position.
  Stop here unless the user asks to proceed.

- **Partial overlap** → Report which parts are already covered and which are new.
  Propose merging only the genuinely new parts into the existing passage. Proceed
  to Gate 2 with the delta only.

- **No overlap** → proceed.

### 3 — Gate: Contradiction

Ask: *"Does the idea conflict with, weaken, or deviate from any existing rule in
the document?"*

- **Direct contradiction** → Report both statements. Do not silently pick a winner.
  Offer options:
  1. Replace the existing rule with the new idea.
  2. Narrow the existing rule (add an exception for the new idea).
  3. Narrow the new idea to coexist with the existing rule.
  4. Drop the new idea.
  Wait for the user's choice before proceeding.

- **Tension without contradiction** (the two rules could coexist but pull in
  different directions) → Flag the tension, explain the risk, and propose wording
  that resolves it. Proceed after user confirmation.

- **No conflict** → proceed.

### 4 — Placement

Determine where the idea belongs:

1. **Existing section** — if the idea naturally extends a section's scope, append it
   there. Match the section's style (imperative mood, table row, list item, etc.).
2. **New section** — if no existing section is a natural fit, create a new heading.
   Place it in logical reading order relative to surrounding sections.
3. **Sub-document** (skills only) — if the idea is detailed reference material that
   would bloat the main skill file, place it in the appropriate reference file
   (create one if needed).

### 5 — Merge

Write the idea into the chosen location. Match:
- Heading level and naming conventions of the document.
- Prose style (imperative vs declarative, sentence fragments vs full sentences).
- Formatting patterns (tables, lists, code fences) used by neighboring content.

### 6 — Validation Pass

Re-read the entire document top to bottom. Check for:

| Check | Action if found |
|---|---|
| Contradiction introduced | Resolve inline; flag to user if judgment call needed |
| Duplication introduced | Merge into a single authoritative statement |
| Ambiguity | Rewrite to remove the second interpretation |
| Structural inconsistency | Adjust heading levels, numbering, or formatting |
| Unnecessary wordiness | Tighten without dropping meaning |

### 7 — Save and Report

Save the file. Report to the user:
- Where the idea was placed (section and file).
- Any passages that were amended to accommodate it.
- Any judgment calls made during the validation pass.
