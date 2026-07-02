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
| 1 | `.copilot-projects` exists | For each registered path, copies `copilot/` → `{project}/.github/` |
| 2 | `.claude-projects` exists | For each registered path, copies `claude/` → `{project}/.claude/`, then overlays `copilot/skills/` and `claude/skills/` into `{project}/.claude/skills/` |
| 3 | `.codex-projects` exists | For each registered path, copies `codex/` → `{project}/.codex/`, then overlays `copilot/skills/` and `codex/skills/` into `{project}/.codex/skills/` |

At least one of the three project-list files must exist and contain a valid path, otherwise `install.mjs` exits with an error. It is safe to re-run: copies overwrite matching files while leaving destination-only files untouched. A destination file that is newer than its source is skipped (with a warning) rather than overwritten.

### Registering projects

Each harness has its own project-list file in the basket root. List one absolute project path per line; blank lines and lines starting with `#` are ignored:

```
C:/Projects/my-aem-project
C:/Projects/another-project
# lines starting with # are ignored
```

| File | Installs into | Contents copied |
|------|---------------|-----------------|
| `.copilot-projects` | `{project}/.github/` | Everything under `copilot/` (instructions, skills, agents) |
| `.claude-projects` | `{project}/.claude/` | Everything under `claude/`, plus `copilot/skills/` and `claude/skills/` overlaid into `.claude/skills/` |
| `.codex-projects` | `{project}/.codex/` | Everything under `codex/`, plus `copilot/skills/` and `codex/skills/` overlaid into `.codex/skills/` |

You can register the same project in multiple files if you use more than one harness there.

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
├── install.mjs                       # One-command install (copies into registered projects)
├── .copilot-projects                 # Optional: project paths for GitHub Copilot (.github)
├── .claude-projects                  # Optional: project paths for Claude Code (.claude)
├── .codex-projects                   # Optional: project paths for Codex CLI (.codex)
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
| `npm run install` | Alias for `node install.mjs` (export + copy into registered projects) |
