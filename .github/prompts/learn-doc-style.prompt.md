---
description: "Scan Java files in a folder or package, analyse their Javadoc style (composition, vocabulary, grammar, tags), and produce an .instructions.md file that an agent can use to write new Javadocs in the same style"
argument-hint: "Folder or package path to scan (leave blank to use current file's package)"
agent: "agent"
---

# Javadoc Style Learner

## Goal

Analyse every Javadoc comment found in the target Java source folder and distil the
observations into a single `.instructions.md` file that a coding agent can later
follow when writing **new** Javadoc for any Java class.

## Input

The user will provide a **folder path** as the prompt argument.
If no argument is supplied, derive the folder from the file currently open in the
editor (use its parent directory).

## Process

### 1 — Collect

Read **all** `.java` files in the target folder (recurse into sub-packages).
For each file, extract every Javadoc block: class-level, constructor-level,
method-level, and field-level.

### 2 — Analyse

For the collected Javadocs, evaluate each of the following dimensions.
Be precise — use concrete examples verbatim from the source files.

| Dimension | What to look for |
|-----------|-----------------|
| **Composition** | Overall structure: opening sentence → body paragraphs → tag section. Use of `<p>`, `{@code}`, `{@link}`, `{@inheritDoc}`, HTML markup. Blank-line conventions between description and tags. |
| **Tone & voice** | Formal vs conversational, active vs passive, imperative vs declarative, person (first/third). |
| **Opening verbs** | List the verbs used to start descriptions (e.g. "Retrieves", "Creates", "Checks whether"). Note which verb maps to which method category (getters, factories, boolean checks, etc.). |
| **Vocabulary** | Recurring nouns, adjectives, qualifiers, and phrases (e.g. "collection of", "instance", "nullable"). |
| **Grammar** | Sentence endings (period or not), capitalisation after `@param name`, article usage, fragment vs full-sentence style in tags. |
| **Tag usage & order** | Which tags appear (`@param`, `@return`, `@throws`, `@see`, `@since`, `@deprecated`, `@param <T>`, etc.), their ordering, and phrasing conventions. |
| **Null documentation** | How nullability is expressed (`nullable`, `non-null`, `{@code null}`, annotation-based). |
| **Coverage scope** | Which member visibilities are documented (public, protected, package-private, private). Fields, constructors, constants. |
| **Method-type patterns** | Distinct patterns for: getters, setters, factories, boolean checkers, overrides (`{@inheritDoc}`), utility/helper methods, generic-type methods, private constructors. |

### 3 — Merge with existing instructions

The target file is:
`c:\Users\Velwetowl\.copilot\instructions\javadoc-style.instructions.md`

**If the file does not exist** — skip to Step 4 (fresh creation).

**If the file already exists**, follow the incremental-merge protocol below:

1. **Read & internalise** — Read the existing instructions file in full. Build a
   mental inventory of every rule it already contains: the heading it lives under,
   the constraint it expresses, and the examples that back it.

2. **Diff each new observation** — For every observation produced in Step 2, ask:

   > *"Does the existing instructions file already contain a rule that covers this
   > observation — either identically or in substance?"*

   - **Already covered** → skip it entirely. Do not add a duplicate or a
     near-duplicate.
   - **Partially covered** — the existing rule captures the gist but misses a
     nuance, a new verb, or a new example → amend the existing rule in place
     (append the new detail / example).
   - **Genuinely new** → draft a new rule and place it under the appropriate
     heading, following the style of the surrounding rules.

3. **Log decisions** — While merging, keep a short internal tally of how many
   observations were skipped (already present), amended, and added. Report this
   summary to the user before saving.

### 4 — Produce / update the instructions file

Generate (or update) the `.instructions.md` file with:

- YAML frontmatter containing:
  - a `description` field (keyword-rich, starting with
    "Use when writing or generating Javadoc …").
  - `applyTo: "**/*.java"` so the instructions auto-attach whenever a Java file
    is being edited.
- A structured body that turns every observation from Step 2 into a clear,
  actionable rule an agent can follow.  
  - Use imperative mood ("Start the opening sentence with …", "Always end …").
  - Include 2–4 verbatim examples per rule, taken directly from the scanned
    sources, inside fenced Java code blocks.
  - Group rules under headings that match the dimensions above.

### 5 — Consolidation pass

After the merge/creation is complete, perform a **full clean-up pass** on the
entire instructions file. Use a subagent with a clean context to avoid
accumulated bias.

The consolidation pass must:

1. **Re-read** the complete file from top to bottom.
2. **Detect repetitions** — find rules that say the same thing in different words
   or under different headings. Merge them into a single, authoritative rule and
   keep the best examples from each.
3. **Resolve contradictions** — if two rules conflict, prefer the one backed by
   more (or more recent) source examples. Flag any unresolvable conflicts to the
   user.
4. **Simplify structure** — collapse headings that contain only one rule into the
   nearest related heading. Ensure the heading hierarchy is consistent
   (no orphan `###` under `#`).
5. **Tighten language** — remove filler, redundant qualifiers, and overly long
   explanations. Every rule should be 1–2 sentences plus examples.
6. **Verify example freshness** — every example must still be a verbatim quote
   from a scanned source file. Remove or replace any that were mangled during
   edits.

### 6 — Save

Save the file to: `c:\Users\Velwetowl\.copilot\instructions\comments.instructions.md`.

## Output quality checks

Before saving, verify the instructions file:

- [ ] Every rule is backed by at least one real example from the scanned code.
- [ ] No rule contradicts another.
- [ ] No two rules express the same constraint (even under different headings).
- [ ] The file is self-contained — an agent reading only this file (plus the base
      `documentation.instructions.md`) can produce Javadoc indistinguishable from
      the originals.
- [ ] Frontmatter `description` is present and keyword-rich.
- [ ] If this was an incremental update, the merge tally has been reported to the
      user (N skipped / N amended / N added).
