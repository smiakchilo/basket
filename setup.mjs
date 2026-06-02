/**
 * install.mjs — One-command setup for a new machine.
 *
 * Usage:
 *   node install.mjs [--basket-root <absolute-path>]
 *
 * What it does:
 *   1. Seeds claude/ and codex/ by running export.mjs
 *   2. ~/.copilot          → <basket>/copilot/        (junction on Windows, symlink on POSIX)
 *   3. ~/.claude/rules     → <basket>/claude/rules/   (junction / symlink)
 *   4. ~/.claude/skills    → <basket>/copilot/skills/ (junction / symlink)
 *   5. ~/.claude/CLAUDE.md ← <basket>/claude/CLAUDE.md (file copy)
 *
 * Safe to re-run: existing links are skipped if they already point to the right target.
 * Existing conflicting files/dirs are renamed to <name>.bak before being replaced.
 *
 * Requires Node.js ≥ 18. No admin/sudo needed on any platform.
 */

import {
  existsSync,
  lstatSync,
  readlinkSync,
  symlinkSync,
  renameSync,
  rmdirSync,
  rmSync,
  cpSync,
  unlinkSync,
  copyFileSync,
  mkdirSync,
} from 'fs';
import { join, resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import { spawnSync } from 'child_process';
import os from 'os';

const HOME = os.homedir();

/* -------
   Helpers
   ------- */

function getBasketRoot() {
  const idx = process.argv.indexOf('--basket-root');
  if (idx !== -1 && process.argv[idx + 1]) {
    return resolve(process.argv[idx + 1]);
  }
  return resolve(dirname(fileURLToPath(import.meta.url)));
}

function ensureDir(dir) {
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

/** lstat-based existence check: true even for broken symlinks / junctions. */
function exists(p) {
  try { lstatSync(p); return true; } catch { return false; }
}

function isLink(p) {
  try {
    if (lstatSync(p).isSymbolicLink()) return true;
    /* On Windows, junctions show as plain directories via lstat but readlinkSync
       succeeds on them — use that to detect junctions. */
    if (process.platform === 'win32') { readlinkSync(p); return true; }
    return false;
  } catch { return false; }
}

/**
 * Creates a directory junction (Windows) or symlink (POSIX) from `link` → `target`.
 * - Skips if link already points to the correct target.
 * - Renames any conflicting path to <path>.bak before creating the link.
 */
function linkDir(target, link, label) {
  const resolvedTarget = resolve(target);

  if (isLink(link)) {
    let current;
    try { current = resolve(readlinkSync(link)); } catch { /* ignore */ }
    if (current === resolvedTarget) {
      console.log(`  skip (already linked): ${label}`);
      return;
    }
    // Remove the existing link — renaming junctions on Windows fails when the path
    // is held open (e.g. by VS Code). Junctions hold no data so no backup is needed.
    if (process.platform === 'win32') {
      rmdirSync(link);
    } else {
      unlinkSync(link);
    }
    console.log(`  removed existing link: ${link}`);
  } else if (exists(link)) {
    const bak = `${link}.bak`;
    if (process.platform === 'win32') {
      /* renameSync fails on Windows when the directory is held open by a file
         watcher (e.g. VS Code). MoveFile fails; RemoveDirectory does not.
         Copy the tree to .bak first, then remove the original. */
      cpSync(link, bak, { recursive: true });
      rmSync(link, { recursive: true, force: true });
    } else {
      renameSync(link, bak);
    }
    console.log(`  backed up: ${link} → ${bak}`);
  }

  const type = process.platform === 'win32' ? 'junction' : 'dir';
  symlinkSync(resolvedTarget, link, type);
  console.log(`  linked: ${label}`);
}

function copyFile(src, dest, label) {
  if (!existsSync(src)) {
    console.warn(`  warn: source not found, skipping — ${src}`);
    return;
  }
  if (exists(dest)) {
    const bak = `${dest}.bak`;
    renameSync(dest, bak);
    console.log(`  backed up: ${dest} → ${bak}`);
  }
  copyFileSync(src, dest);
  console.log(`  copied: ${label}`);
}

/* ----
   Main
   ---- */

const BASKET = getBasketRoot();
console.log(`Basket root: ${BASKET}`);
console.log(`Platform:    ${process.platform}\n`);

// Step 1 — Seed derived folders
console.log('Step 1: Seeding claude/ and codex/ via export.mjs ...');
const exportResult = spawnSync(process.execPath, [join(BASKET, 'export.mjs')], {
  cwd: BASKET,
  stdio: 'inherit',
});
if (exportResult.status !== 0) {
  console.error('\nexport.mjs failed — aborting install.');
  process.exit(1);
}
console.log();

// Step 2 — ~/.copilot → basket/copilot/
console.log('Step 2: Linking ~/.copilot ...');
linkDir(
  join(BASKET, 'copilot'),
  join(HOME, '.copilot'),
  '~/.copilot → copilot/',
);
console.log();

// Step 3 — ~/.claude/rules → basket/claude/rules/
console.log('Step 3: Linking ~/.claude/rules ...');
ensureDir(join(HOME, '.claude'));
linkDir(
  join(BASKET, 'claude', 'rules'),
  join(HOME, '.claude', 'rules'),
  '~/.claude/rules → claude/rules/',
);
console.log();

// Step 4 — ~/.claude/skills → basket/copilot/skills/
console.log('Step 4: Linking ~/.claude/skills ...');
linkDir(
  join(BASKET, 'copilot', 'skills'),
  join(HOME, '.claude', 'skills'),
  '~/.claude/skills → copilot/skills/',
);
console.log();

// Step 5 — ~/.claude/CLAUDE.md  (copy, not link — Claude Code reads the file directly)
console.log('Step 5: Copying claude/CLAUDE.md → ~/.claude/CLAUDE.md ...');
ensureDir(join(HOME, '.claude'));
copyFile(
  join(BASKET, 'claude', 'CLAUDE.md'),
  join(HOME, '.claude', 'CLAUDE.md'),
  '~/.claude/CLAUDE.md',
);
console.log();

console.log('Setup complete.\n');
console.log('Next steps:');
console.log('  • Edit files under copilot/instructions/ or copilot/skills/');
console.log('  • Run "node export.mjs" (or "npm run export") to regenerate claude/ and codex/');
console.log('  • Commit and push — others clone and run "node install.mjs"');
