# BASKET

This is B.A.S.K.E.T. -- Blueprint Agentic Starting Kit for Exadel Toolbox. It contains agents, skills, and instructions for AEM development with **GitHub Copilot**, **Claude Code**, and **Codex CLI**.

Maintain your instructions and skills in one place (`copilot/`) and export them automatically to the formats each harness expects.

## How it works

```
copilot/instructions/   ← source of truth (edit these)
copilot/skills/         ← skill workflows (edit these)
        │
        ▼  npm run export
claude/rules/           ← generated Claude Code rules
claude/CLAUDE.md        ← generated Claude Code entry point
codex/AGENTS.md         ← generated Codex CLI instructions
```

`export.mjs` reads every `.instructions.md` file, strips the Copilot-specific frontmatter, and writes the appropriate format for Claude Code and Codex CLI. Re-run it whenever you change anything under `copilot/`.

`setup.mjs` wires the repo into your home directory so each AI harness can find its config without manual copying.

## Prerequisites

- **Node.js ≥ 18**
- **npm** (bundled with Node)
- **GitHub CLI (gh)** 

## First-time setup (new machine)

```bash
# 1. Clone the repo
git clone <repo-url> basket
cd basket

# 2. Install dependencies
npm install

# 3. Wire everything up (export + symlinks/junctions)
node setup.mjs
```

`setup.mjs` does the following:

| Step | What it creates |
|------|----------------|
| 1 | Runs `export.mjs` to seed `claude/` and `codex/` |
| 2 | `~/.copilot` → `<basket>/copilot/` |
| 3 | `~/.claude/rules` → `<basket>/claude/rules/` |
| 4 | `~/.claude/skills` → `<basket>/copilot/skills/` |
| 5 | Copies `claude/CLAUDE.md` → `~/.claude/CLAUDE.md` |

It is safe to re-run: existing links that already point to the correct target are skipped, and any conflicting file or directory is renamed to `<name>.bak` before being replaced.

> **Windows note:** directory links are created as junctions, which do not require administrator privileges.

## Everyday workflow

```bash
# Edit an instruction
# e.g. copilot/instructions/java-code.instructions.md

# Regenerate derived outputs
npm run export

# Commit and push — teammates clone and run node setup.mjs
git add -A && git commit -m "..."
```

## Project layout

```
basket/
├── export.mjs                        # Translates copilot/ → claude/ and codex/
├── setup.mjs                         # One-command machine setup
├── package.json
├── copilot/
│   ├── instructions/
│   │   ├── global-copilot-instructions.md  # Always-on system prompt (all harnesses)
│   │   └── *.instructions.md               # Path-scoped rules (Java, HTL, etc.)
│   └── skills/
│       └── <skill-name>/
│           └── SKILL.md                    # Skill workflow (Claude Code / Copilot)
├── claude/                           # Generated — do not edit manually
│   ├── CLAUDE.md
│   └── rules/
└── codex/                            # Generated — do not edit manually
    └── AGENTS.md
```

## Adding a new instruction

1. Create `copilot/instructions/<name>.instructions.md` with a YAML frontmatter block:

   ```markdown
   ---
   description: "Short description shown in the Copilot UI"
   applyTo: "**/*.java"
   ---

   Your rule content here.
   ```

2. Run `npm run export`.

## Adding a new skill

1. Create a directory under `copilot/skills/<skill-name>/` and add a `SKILL.md` file.
2. Run `npm run export` — the skill name will appear in `claude/CLAUDE.md`.

## Scripts

| Command | Description |
|---------|-------------|
| `npm run export` | Regenerate `claude/` and `codex/` from `copilot/` |
| `npm run setup` | Alias for `node setup.mjs` (export + symlinks) |
