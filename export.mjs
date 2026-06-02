/**
 * export.mjs — Translates copilot/ instructions into claude/ and codex/ derived outputs.
 *
 * Usage:
 *   node export.mjs
 *
 * Run this whenever you edit files under copilot/instructions/ or copilot/skills/.
 * Output directories (claude/ and codex/) are fully regenerated each run.
 */

import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import yaml from 'js-yaml';

const ROOT = dirname(fileURLToPath(import.meta.url));
const INSTRUCTIONS_DIR = join(ROOT, 'copilot', 'instructions');
const SKILLS_DIR       = join(ROOT, 'copilot', 'skills');
const CLAUDE_DIR       = join(ROOT, 'claude');
const CLAUDE_RULES_DIR = join(CLAUDE_DIR, 'rules');
const CODEX_DIR        = join(ROOT, 'codex');

/* -------
   Helpers
   ------- */

function ensureDir(dir) {
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

/**
 * Parses a Markdown file with optional YAML frontmatter delimited by `---`.
 * <p>`applyTo` values contain unquoted glob patterns (e.g. `**\/*.java`) which
 * js-yaml misreads as YAML aliases because `*` is the alias prefix. `applyTo`
 * is extracted with a plain regex before the remainder is handed to js-yaml.
 * @param content Raw file content as a string
 * @return An object with `frontmatter` and `body` properties; `body` is everything after the closing `---`
 */
function parseFrontmatter(content) {
  const match = content.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/);
  if (!match) return { frontmatter: {}, body: content };

  const fmRaw = match[1];

  // Pull out `applyTo` before YAML parsing
  const applyToMatch = fmRaw.match(/^applyTo:\s*(.+)$/m);
  const applyToRaw   = applyToMatch ? applyToMatch[1].trim() : null;

  // Strip applyTo so js-yaml doesn't choke on unquoted glob asterisks
  const fmSafe = fmRaw.replace(/^applyTo:.*$/m, '').trim();

  let frontmatter = {};
  try {
    frontmatter = yaml.load(fmSafe) ?? {};
  } catch {
    // Last-resort: pull description out manually
    const d = fmRaw.match(/^description:\s*"([^"]*)"/m)
           ?? fmRaw.match(/^description:\s*'([^']*)'/m)
           ?? fmRaw.match(/^description:\s*(.+)$/m);
    if (d) frontmatter.description = d[1];
  }

  // Re-attach applyTo, stripping any surrounding quotes added by some editors
  if (applyToRaw) {
    frontmatter.applyTo = applyToRaw.replace(/^["']|["']$/g, '');
  }

  return { frontmatter, body: match[2] };
}

/**
 * Normalises an `applyTo` value (string or array) into an array of glob strings.
 * Handles comma-separated strings for multi-glob `applyTo` entries.
 * @param applyTo An `applyTo` value from a frontmatter object; nullable
 * @return A non-null array of glob strings; might be empty
 */
function normalizeGlobs(applyTo) {
  if (!applyTo) return [];
  if (Array.isArray(applyTo)) return applyTo.map(String);
  return String(applyTo).split(',').map(s => s.trim()).filter(Boolean);
}

/**
 * Checks whether an instruction applies to all files (always-on) — i.e. its `frontmatter`
 * has no `applyTo` field, or `applyTo` is `**` (the Copilot global wildcard).
 * @param frontmatter Parsed frontmatter object from a Copilot instruction file
 * @return True or false
 */
function isAlwaysOn(frontmatter) {
  const globs = normalizeGlobs(frontmatter.applyTo);
  return globs.length === 0 || globs.every(g => g === '**');
}

function readInstructions() {
  // The global file uses a plain .md name (no .instructions.md suffix) so it
  // must be loaded explicitly.  It is always prepended so it appears first in
  // every exported output.
  const GLOBAL_FILE = 'global-copilot-instructions.md';
  const globalPath  = join(INSTRUCTIONS_DIR, GLOBAL_FILE);

  const regularFiles = readdirSync(INSTRUCTIONS_DIR)
    .filter(f => f.endsWith('.instructions.md'))
    .sort()
    .map(file => {
      const raw = readFileSync(join(INSTRUCTIONS_DIR, file), 'utf8');
      const { frontmatter, body } = parseFrontmatter(raw);
      return { file, name: file.replace('.instructions.md', ''), frontmatter, body };
    });

  if (!existsSync(globalPath)) return regularFiles;

  const raw = readFileSync(globalPath, 'utf8');
  const { frontmatter, body } = parseFrontmatter(raw);
  return [
    { file: GLOBAL_FILE, name: 'global-copilot-instructions', frontmatter, body },
    ...regularFiles,
  ];
}

function getSkillNames() {
  if (!existsSync(SKILLS_DIR)) return [];
  return readdirSync(SKILLS_DIR, { withFileTypes: true })
    .filter(e => e.isDirectory())
    .map(e => e.name)
    .sort();
}

/* -------------
   Claude export
   ------------- */

function exportClaude(instructions) {
  ensureDir(CLAUDE_RULES_DIR);

  const alwaysOnNames = [];

  for (const { name, frontmatter, body } of instructions) {
    // The global instruction becomes CLAUDE.md, not a rules file
    if (name === 'global-copilot-instructions') continue;

    const ruleFm = {};
    if (frontmatter.description) ruleFm.description = frontmatter.description;

    const scopedGlobs = normalizeGlobs(frontmatter.applyTo).filter(g => g !== '**');
    if (scopedGlobs.length > 0) {
      // path-scoped: translate applyTo → paths
      ruleFm.paths = scopedGlobs.length === 1 ? scopedGlobs[0] : scopedGlobs;
    } else {
      alwaysOnNames.push(name);
    }

    const out = `---\n${yaml.dump(ruleFm).trimEnd()}\n---\n\n${body.trimEnd()}\n`;
    writeFileSync(join(CLAUDE_RULES_DIR, `${name}.md`), out, 'utf8');
    console.log(`  claude/rules/${name}.md`);
  }

  // CLAUDE.md — always-on entry point
  const global = instructions.find(i => i.name === 'global-copilot-instructions');
  const skills = getSkillNames();

  const claudeLines = [
    '<!-- Auto-generated by export.mjs — do not edit manually -->',
    '<!-- Source: copilot/instructions/global-copilot-instructions.md -->',
    '',
    global ? global.body.trimEnd() : '',
    '',
    '## Available Skills',
    '',
    skills.length
      ? skills.map(s => `- \`${s}\``).join('\n')
      : '_No skills found._',
    '',
    '## Always-On Rules',
    '',
    'The following rules apply to all files (no path restriction):',
    '',
    alwaysOnNames.map(n => `- ${n}`).join('\n'),
    '',
  ];

  writeFileSync(join(CLAUDE_DIR, 'CLAUDE.md'), claudeLines.join('\n'), 'utf8');
  console.log('  claude/CLAUDE.md');
}

/* ------------
   Codex export
   ------------ */

function exportCodex(instructions) {
  ensureDir(CODEX_DIR);

  const alwaysOn = instructions.filter(i => isAlwaysOn(i.frontmatter));

  const parts = [
    '<!-- Auto-generated by export.mjs — do not edit manually -->',
    '<!-- Source: copilot/instructions/ (always-on subset) -->',
    '',
    '# Coding Standards and Conventions',
    '',
    '_Always-on rules exported for use with Codex CLI and similar tools._',
    '_Path-scoped rules (Java, HTL, clientlibs, etc.) are omitted here; apply them in context._',
    '',
  ];

  for (const { name, frontmatter, body } of alwaysOn) {
    // Use first sentence of description as section title, fall back to file name
    const title = frontmatter.description
      ? frontmatter.description.replace(/\. .*$/, '').replace(/\.$/, '')
      : name;
    parts.push(`## ${title}`, '', body.trimEnd(), '', '---', '');
  }

  const content = parts.join('\n');
  console.log('  codex/AGENTS.md');
  writeFileSync(join(CODEX_DIR, 'AGENTS.md'), content, 'utf8');
}

/* ----
   Main
   ---- */

console.log('Exporting copilot/ → claude/ and codex/...\n');

const instructions = readInstructions();
console.log(`Found ${instructions.length} instruction files.\n`);

exportClaude(instructions);
console.log();
exportCodex(instructions);
console.log('\nDone.');
