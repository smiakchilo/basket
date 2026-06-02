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
  cpSync,
  mkdirSync,
} from 'fs';
import { join, resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import { spawnSync } from 'child_process';

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
 * Reads a project-list file and returns an array of non-blank, non-comment lines.
 * Returns null if the file does not exist.
 */
function readProjectList(filePath) {
  if (!existsSync(filePath)) return null;
  return readFileSync(filePath, 'utf8')
    .split(/\r?\n/)
    .map(l => l.trim())
    .filter(l => l && !l.startsWith('#'));
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

let anyInstalled = false;

// Step 1 — .copilot-projects → {project}/.github
{
  const listFile = join(BASKET, '.copilot-projects');
  const projects = readProjectList(listFile);
  if (!projects) {
    console.log('Step 1: .copilot-projects not found — skipped.');
  } else if (projects.length === 0) {
    console.log('Step 1: .copilot-projects is empty — skipped.');
  } else {
    console.log('Step 1: Installing into copilot projects (.github) ...');
    for (const projectPath of projects) {
      if (!existsSync(projectPath)) {
        console.warn(`  warn: project path not found — ${projectPath}`);
        continue;
      }
      console.log(`  project: ${projectPath}`);
      copyDir(
        join(BASKET, 'copilot'),
        join(projectPath, '.github'),
        `.github ← copilot/`,
      );
      anyInstalled = true;
    }
  }
}
console.log();

// Step 2 — .claude-projects → {project}/.claude
{
  const listFile = join(BASKET, '.claude-projects');
  const projects = readProjectList(listFile);
  if (!projects) {
    console.log('Step 2: .claude-projects not found — skipped.');
  } else if (projects.length === 0) {
    console.log('Step 2: .claude-projects is empty — skipped.');
  } else {
    console.log('Step 2: Installing into claude projects (.claude) ...');
    for (const projectPath of projects) {
      if (!existsSync(projectPath)) {
        console.warn(`  warn: project path not found — ${projectPath}`);
        continue;
      }
      console.log(`  project: ${projectPath}`);
      copyDir(
        join(BASKET, 'claude'),
        join(projectPath, '.claude'),
        `.claude ← claude/`,
      );
      copyDir(
        join(BASKET, 'copilot', 'skills'),
        join(projectPath, '.claude', 'skills'),
        `.claude/skills ← copilot/skills/ (overlay)`,
      );
      copyDir(
        join(BASKET, 'claude', 'skills'),
        join(projectPath, '.claude', 'skills'),
        `.claude/skills ← claude/skills/ (overlay)`,
      );
      anyInstalled = true;
    }
  }
}
console.log();

// Step 3 — .codex-projects → {project}/.codex
{
  const listFile = join(BASKET, '.codex-projects');
  const projects = readProjectList(listFile);
  if (!projects) {
    console.log('Step 3: .codex-projects not found — skipped.');
  } else if (projects.length === 0) {
    console.log('Step 3: .codex-projects is empty — skipped.');
  } else {
    console.log('Step 3: Installing into codex projects (.codex) ...');
    for (const projectPath of projects) {
      if (!existsSync(projectPath)) {
        console.warn(`  warn: project path not found — ${projectPath}`);
        continue;
      }
      console.log(`  project: ${projectPath}`);
      copyDir(
        join(BASKET, 'codex'),
        join(projectPath, '.codex'),
        `.codex ← codex/`,
      );
      copyDir(
        join(BASKET, 'copilot', 'skills'),
        join(projectPath, '.codex', 'skills'),
        `.codex/skills ← copilot/skills/ (overlay)`,
      );
      copyDir(
        join(BASKET, 'codex', 'skills'),
        join(projectPath, '.codex', 'skills'),
        `.codex/skills ← codex/skills/ (overlay)`,
      );
      anyInstalled = true;
    }
  }
}
console.log();

if (!anyInstalled) {
  console.error('ERROR: No projects were installed. Create at least one of .copilot-projects, .claude-projects, or .codex-projects with valid project paths.');
  process.exit(1);
}

console.log('Install complete.\n');
console.log('Next steps:');
console.log('  • Edit files under copilot/instructions/ or copilot/skills/');
console.log('  • Run "node export.mjs" (or "npm run export") to regenerate claude/ and codex/');
console.log('  • Add project paths to .copilot-projects, .claude-projects, or .codex-projects');
console.log('  • Commit and push — others clone and run "node install.mjs"');
