/**
 * install.mjs — One-command install for a new machine.
 *
 * Usage:
 *   node install.mjs [--basket-root <absolute-path>]
 *
 * Safe to re-run: copies overwrite existing files; destination-only files are untouched.
 * Requires Node.js ≥ 18. No admin/sudo needed
 */

import {
  existsSync,
  readFileSync,
  copyFileSync,
  cpSync,
  mkdirSync,
  readdirSync,
  statSync,
} from 'fs';
import { join, resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import { spawnSync } from 'child_process';
import os from 'os';

const HOME = os.homedir();

const BASKET = (() => {
  const idx = process.argv.indexOf('--basket-root');
  if (idx !== -1 && process.argv[idx + 1]) return resolve(process.argv[idx + 1]);
  return resolve(dirname(fileURLToPath(import.meta.url)));
})();

console.log(`Basket root: ${BASKET}`);
console.log(`Platform:    ${process.platform}\n`);

/* -------
   Helpers
   ------- */

function ensureDir(dir) {
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

/**
 * Copies a directory tree into dest, overwriting matching files.
 * Silently skips if src does not exist.
 */
function copyDir(src, dest, label) {
  if (!existsSync(src)) {
    console.log(`  skip (source absent): ${label}`);
    return;
  }
  ensureDir(dest);
  cpSync(src, dest, { recursive: true, force: true });
  console.log(`  copied: ${label}`);
}

/**
 * Copies a single file, creating parent directories as needed.
 * Silently skips if src does not exist.
 */
function copyOne(src, dest, label) {
  if (!existsSync(src)) {
    console.log(`  skip (source absent): ${label}`);
    return;
  }
  ensureDir(dirname(dest));
  copyFileSync(src, dest);
  console.log(`  copied: ${label}`);
}

/* ----
   Main
   ---- */

// Step 0 — Regenerate derived outputs
console.log('Step 0: Regenerating claude/ and codex/ via export.mjs ...');
const exportResult = spawnSync(process.execPath, [join(BASKET, 'export.mjs')], {
  cwd: BASKET,
  stdio: 'inherit',
});
if (exportResult.status !== 0) {
  console.error('\nexport.mjs failed — aborting.');
  process.exit(1);
}
console.log();

// Step 1 — ~/.copilot
const copilotHome = join(HOME, '.copilot');
if (existsSync(copilotHome)) {
  console.log('Step 1: Updating ~/.copilot ...');
  copyDir(
    join(BASKET, 'copilot'),
    copilotHome,
    '~/.copilot ← copilot/',
  );
} else {
  console.log('Step 1: ~/.copilot not found — skipped.');
}
console.log();

// Step 2 — ~/.claude
const claudeHome = join(HOME, '.claude');
if (existsSync(claudeHome)) {
  console.log('Step 2: Updating ~/.claude ...');
  copyDir(
    join(BASKET, 'claude'),
    claudeHome,
    '~/.claude ← claude/',
  );
  copyDir(
    join(BASKET, 'copilot', 'agents'),
    join(claudeHome, 'agents'),
    '~/.claude/agents ← copilot/agents/',
  );
  copyDir(
    join(BASKET, 'copilot', 'skills'),
    join(claudeHome, 'skills'),
    '~/.claude/skills ← copilot/skills/',
  );
  // Copy loose files directly under copilot/ (non-directories)
  for (const entry of readdirSync(join(BASKET, 'copilot'))) {
    const src = join(BASKET, 'copilot', entry);
    if (statSync(src).isFile()) {
      copyOne(src, join(claudeHome, entry), `~/.claude/${entry} ← copilot/${entry}`);
    }
  }
} else {
  console.log('Step 2: ~/.claude not found — skipped.');
}
console.log();

// Step 3 — Codex projects
const codexProjectsFile = join(BASKET, '.codex-projects');
if (!existsSync(codexProjectsFile)) {
  console.log('Step 3: .codex-projects not found — skipped.');
} else {
  console.log('Step 3: Installing into codex projects ...');

  const projectPaths = readFileSync(codexProjectsFile, 'utf8')
    .split(/\r?\n/)
    .map(l => l.trim())
    .filter(l => l && !l.startsWith('#'));

  // Collect seeding candidates: codex/*--AGENTS.md (skip plain AGENTS.md)
  const seedFiles = readdirSync(join(BASKET, 'codex'))
    .filter(f => f.endsWith('--AGENTS.md'));

  for (const projectPath of projectPaths) {
    const dotCodex = join(projectPath, '.codex');
    if (!existsSync(dotCodex)) {
      console.log(`  skip (no .codex/): ${projectPath}`);
      continue;
    }

    console.log(`  project: ${projectPath}`);

    // codex/AGENTS.md → {project}/.codex/AGENTS.md
    copyOne(
      join(BASKET, 'codex', 'AGENTS.md'),
      join(dotCodex, 'AGENTS.md'),
      '.codex/AGENTS.md',
    );

    // agents/ and skills/
    copyDir(
      join(BASKET, 'copilot', 'agents'),
      join(dotCodex, 'agents'),
      '.codex/agents ← copilot/agents/',
    );
    copyDir(
      join(BASKET, 'copilot', 'skills'),
      join(dotCodex, 'skills'),
      '.codex/skills ← copilot/skills/',
    );

    // Seed *--AGENTS.md → project subdirectories
    for (const seedFile of seedFiles) {
      // e.g. "core--src--test--AGENTS.md" → segments ["core","src","test"]
      const parts = seedFile.split('--');
      const segments = parts.slice(0, -1); // drop trailing "AGENTS.md"
      if (segments.length === 0) continue;

      const targetDir = join(projectPath, ...segments);
      if (!existsSync(targetDir)) {
        console.log(`    skip (dir absent): ${segments.join('/')}/AGENTS.md`);
        continue;
      }
      copyOne(
        join(BASKET, 'codex', seedFile),
        join(targetDir, 'AGENTS.md'),
        `${segments.join('/')}/AGENTS.md`,
      );
    }
  }
}
console.log();

console.log('Install complete.\n');
console.log('Next steps:');
console.log('  • Edit files under copilot/instructions/ or copilot/skills/');
console.log('  • Run "node export.mjs" (or "npm run export") to regenerate claude/ and codex/');
console.log('  • Commit and push — others clone and run "node install.mjs"');
