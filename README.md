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

`install.mjs` copies the generated files into your home directory and any registered projects so each AI harness can find its config without manual setup.

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

# 3. Copy everything into place
node install.mjs
```

`install.mjs` does the following:

| Step | Condition | What it does |
|------|-----------|-------------|
| 0 | always | Runs `export.mjs` to regenerate `claude/` and `codex/` |
| 1 | `~/.copilot` exists | Copies `copilot/` → `~/.copilot/` (overwrite) |
| 2 | `~/.claude` exists | Copies `claude/` + `copilot/agents/` + `copilot/skills/` → `~/.claude/` |
| 3 | `.codex-projects` exists | For each registered project path (see below) |

It is safe to re-run: copies overwrite matching files while leaving destination-only files untouched.

### Registering projects for Codex CLI

Create a `.codex-projects` file in the basket root, one absolute project path per line:

```
C:/Projects/my-aem-project
C:/Projects/another-project
# lines starting with # are ignored
```

For each listed path, if a `.codex/` folder already exists under it, `install.mjs` will:

- Copy `codex/AGENTS.md` → `{project}/.codex/AGENTS.md`
- Copy `copilot/agents/` → `{project}/.codex/agents/`
- Copy `copilot/skills/` → `{project}/.codex/skills/`
- Seed each `*--AGENTS.md` file from `codex/` into the matching project subdirectory
  (e.g. `core--src--test--AGENTS.md` → `{project}/core/src/test/AGENTS.md`; skipped if that directory doesn't exist)

## Everyday workflow

```bash
# Edit an instruction
# e.g. copilot/instructions/java-code.instructions.md

# Regenerate derived outputs
npm run export

# Commit and push — teammates clone and run node install.mjs
git add -A && git commit -m "..."
```

## Project layout

```
basket/
├── export.mjs                        # Translates copilot/ → claude/ and codex/
├── install.mjs                       # One-command machine install (file copies)
├── .codex-projects                   # Optional: list of project paths for Codex CLI
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
| `npm run install` | Alias for `node install.mjs` (export + copy into home / projects) |
