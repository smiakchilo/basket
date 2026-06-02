---
name: skill-optimizer
description: "Use when: refining a .md file (instructions, skill, agent, or reference); fixing contradictions, ambiguities, or repetitions in a markdown file; optimizing structure or token efficiency of a prompt, skill, or instruction file; correcting broken numbering. Trigger: 'optimize this file', 'refine instructions', 'clean up this skill', 'fix numbering', '/skill-optimizer'."
argument-hint: "Path or attachment of the .md file to refine"
---

# Skill Optimizer

Refines a `.md` file — instructions, skill, agent definition, or reference doc — by systematically fixing contradictions, ambiguities, repetitions, structure, token bloat, and numbering.

## Step 0 — Read Skill Memos

Use the memory tool to read `/memories/skill-memos/skill-optimizer.md`. If the file exists, internalize its advice before proceeding.

**Write-back rule** — if an unexpected problem arises during execution and you resolve it, append a memo entry (`### Title — YYYY-MM-DD` / `**Problem**: …` / `**Fix**: …`) to the same file (create if absent). Consolidate if the file exceeds ~30 lines.

## Step 1 — Read the File

Read the full target file before making any changes. Identify its type (instruction, skill, agent, reference) — this informs which checks matter most.

If no file is provided or the path is ambiguous, ask the user to clarify before proceeding.

## Step 2 — Apply Checks in Order

Apply all five checks sequentially. For each issue found, note it before editing.

### 2.1 Contradiction Check

Identify statements that conflict with each other.

- Quote both conflicting passages.
- Resolve by keeping the more specific or more restrictive rule, unless the user's intent clearly favors the other.
- Mark the changed line with `<!-- refined: reason -->`.

### 2.2 Ambiguity Check

Identify phrases with more than one plausible interpretation that could cause inconsistent behavior.

- Rewrite to remove ambiguity. Do not add new meaning — clarify only.
- Mark changed lines with `<!-- refined: reason -->`.

### 2.3 Repetition Check

Identify content repeated verbatim or by sense (same idea expressed differently in multiple places).

- Keep the clearest, most complete expression; remove the rest.
- If the deleted passage appeared in a different section, add a brief reference to where the kept version lives.

### 2.4 Structure and Token Optimization

Restructure to reduce token usage without dropping any unique idea or instruction:

| Technique | When to apply |
|---|---|
| Table over prose list | 3+ items with parallel structure |
| Merge sections | Two short sections address the same concept |
| Remove filler | Hedging, redundant preambles, "Note that…" openers |
| Short imperatives | Replace explanatory paragraphs when the instruction is self-evident |

### 2.5 Numbering Correction

Correct all numbered sections, subsections, and list items:

- Natural integers starting at 1: `1, 2, 3, …`
- Subitems use dotted notation: `2.1, 2.2, 2.3, …`
- No fractional numbers (`3.5`) — renumber to fit between existing integers
- No literal indices (`2a, 2b`) — convert to `2.1, 2.2`
- Full numbering must be gapless and in order

### 2.6 File Reference Check

Scan the file for all file references: markdown links (`[text](path)`), inline code paths, and bare relative paths.

For each reference:
- Resolve the path relative to the directory of the file being reviewed.
- Check whether the file exists using `file_search` or `list_dir`.
- Report broken references (file not found) as issues. Do **not** auto-delete or silently drop them — flag them for the user to resolve.
- Skip references that point outside the current folder (i.e., paths starting with `../` or absolute paths). Those are out of scope.

## Step 3 — Recurse into Subfolder Files (skills and agents only)

Skip this step for instruction files and plain reference docs.

After completing all Step 2 checks on the primary file, collect every file reference that:
1. Points to a file **within** the same folder or a subfolder (e.g., `./references/xxx.md`, `./assets/xxx.md`, `./scripts/xxx.ps1`).
2. The referenced file actually exists (confirmed in check 2.6).
3. Is a `.md` file (only markdown files are optimized; scripts and other assets are skipped).

For each qualifying file, re-run Steps 1–2 on it in turn. Apply the same set of checks. Save each file after its pass. Report a brief summary of what was changed per file.

Do **not** recurse into files referenced from those files (one level of recursion only).

## Step 4 — Output

Produce the complete revised file content and save it (overwrite the original file). Do not summarize — output the full file, ready to use.

If any decision required a judgment call (e.g., resolving a contradiction), the inline `<!-- refined: reason -->` comment already marks it. After saving, briefly list the issues found and resolved — including any broken file references and any subfolder files that were also optimized — so the user can review the judgment calls.
