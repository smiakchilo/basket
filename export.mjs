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
const SKILLS_DIR = join(ROOT, 'copilot', 'skills');
const CLAUDE_DIR        = join(ROOT, 'claude');
const CLAUDE_RULES_DIR  = join(CLAUDE_DIR, 'rules');
const CLAUDE_SKILLS_DIR = join(CLAUDE_DIR, 'skills');
const CODEX_DIR             = join(ROOT, 'codex');
const CODEX_SKILLS_DIR      = join(CODEX_DIR, 'skills');
const CODEX_SKILLS_REFS_DIR = join(CODEX_SKILLS_DIR, 'references');

/* -------
   Helpers
   ------- */

function ensureDir(dir) {
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

/**
 * Parses a Markdown file with optional YAML frontmatter delimited by {@code ---}.
 * <p>{@code applyTo} values contain unquoted glob patterns (e.g. {@code **\/*.java}) which
 * js-yaml misreads as YAML aliases because {@code *} is the alias prefix. {@code applyTo}
 * is extracted with a plain regex before the remainder is handed to js-yaml
 * @param content Raw file content as a string
 * @return An object with {@code frontmatter} and {@code body} properties; {@code body} is everything after the closing {@code ---}
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
 * Normalises an {@code applyTo} value (string or array) into an array of glob strings.
 * Handles comma-separated strings for multi-glob {@code applyTo} entries.
 * @param applyTo An {@code applyTo} value from a frontmatter object; nullable
 * @return A non-null array of glob strings; might be empty
 */
function normalizeGlobs(applyTo) {
  if (!applyTo) return [];
  if (Array.isArray(applyTo)) return applyTo.map(String);
  return String(applyTo).split(',').map(s => s.trim()).filter(Boolean);
}

/**
 * Checks whether an instruction applies to all files (always-on) — i.e. its {@code frontmatter}
 * has no {@code applyTo} field, or {@code applyTo} is {@code **} (the Copilot global wildcard).
 * @param frontmatter Parsed frontmatter object from a Copilot instruction file
 * @return True or false
 */
function isAlwaysOn(frontmatter) {
  const globs = normalizeGlobs(frontmatter.applyTo);
  return globs.length === 0 || globs.every(g => g === '**');
}

/**
 * Checks whether an instruction targets skill workflow files — i.e. its {@code applyTo}
 * globs match the representative path {@code skills/foo/SKILL.md}. Such instructions are
 * routed to {@code codex/skills/references/} instead of being inlined in {@code AGENTS.md}.
 * @param frontmatter Parsed frontmatter object from a Copilot instruction file
 * @return True or false
 */
function isSkillTargeted(frontmatter) {
  if (isAlwaysOn(frontmatter)) return false;
  const globs = normalizeGlobs(frontmatter.applyTo);
  return globs.length > 0 && matchesAnyGlob('skills/foo/SKILL.md', globs);
}

/**
 * Converts a glob pattern to a RegExp. Handles {@code **}, {@code *}, and {@code ?}.
 * Only the subset of glob syntax present in the instruction applyTo fields is supported.
 * @param glob A glob string following shell-style glob conventions (e.g. {@code **&#47;*.java})
 * @return A RegExp that matches paths conforming to the glob
 */
function globToRegex(glob) {
  const escaped = glob
    .replace(/[.+^${}()|[\]\\]/g, '\\$&') // escape regex specials except * and ?
    .replace(/\\\./g, '\\.')               // keep escaped dots
    .replace(/\*\*\//g, '\u0001')          // placeholder for **/ (glob dir wildcard)
    .replace(/\*\*/g, '\u0002')            // placeholder for ** not followed by /
    .replace(/\*/g, '[^/]*')               // * -> any segment chars
    .replace(/\?/g, '[^/]')                // ? -> single non-slash char
    .replace(/\u0001/g, '(?:.*\/)?')       // **/ -> optional any-depth path prefix
    .replace(/\u0002/g, '.*');             // ** -> any chars (trailing wildcard)
  return new RegExp(`^${escaped}$`);
}

/**
 * Returns true if {@code filePath} matches at least one of the provided glob patterns.
 * @param filePath A posix-style relative file path
 * @param globs Array of glob strings
 * @return True if any glob matches
 */
function matchesAnyGlob(filePath, globs) {
  return globs.some(g => globToRegex(g).test(filePath));
}

function readInstructions() {
  // The global file uses a plain .md name (no .instructions.md suffix) so it
  // must be loaded explicitly.  It is always prepended so it appears first in
  // every exported output
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

/* ---------------
   Skills export
   --------------- */

/**
 * Rewrites {@code .github/memories/} path references to the destination-specific memories
 * folder (e.g. {@code .claude/memories/} or {@code .codex/memories/}).
 * @param content Raw Markdown file content
 * @param destPrefix The destination folder prefix, e.g. {@code .claude} or {@code .codex}
 * @return Rewritten content string
 */
function rewriteMemoryPaths(content, destPrefix) {
  return content.replace(/\.github\/memories\//g, `${destPrefix}/memories/`);
}

/**
 * Rewrites all references to {@code copilot/instructions/} files in a skill Markdown body
 * so they point at their Claude equivalents:
 * {@code global-copilot-instructions.md → CLAUDE.md} (depth-relative) and
 * {@code X.instructions.md → rules/X.md} (depth-relative).
 * Both Markdown link targets and plain-text path hints (e.g. in subagent prompt templates)
 * are rewritten. Non-instruction links are untouched.
 * @param content Raw Markdown file content
 * @return Rewritten content string
 */
function rewriteLinksForClaude(content, _depth) {
  // Markdown links: [text](PREFIX/instructions/global-copilot-instructions.md) → [text](PREFIX/CLAUDE.md)
  content = content.replace(
    /(\[[^\]]*\])\(([^)]*\/)instructions\/global-copilot-instructions\.md\)/g,
    '$1($2CLAUDE.md)',
  );
  // Markdown links: [text](PREFIX/instructions/X.instructions.md) → [text](PREFIX/rules/X.md)
  content = content.replace(
    /(\[[^\]]*\])\(([^)]*\/)instructions\/([\w-]+)\.instructions\.md\)/g,
    '$1($2rules/$3.md)',
  );
  // Plain text: instructions/global-copilot-instructions.md → CLAUDE.md
  content = content.replace(/\binstructions\/global-copilot-instructions\.md/g, 'CLAUDE.md');
  // Plain text: instructions/X.instructions.md → rules/X.md
  content = content.replace(/\binstructions\/([\w-]+)\.instructions\.md/g, 'rules/$1.md');
  content = rewriteMemoryPaths(content, '.claude');
  return content;
}

/**
 * Creates a Codex link-rewrite function that routes instruction references to their correct
 * destinations. Instructions whose {@code applyTo} targets the SKILL.md glob pattern are
 * written as standalone files under {@code codex/skills/references/} and linked accordingly
 * (depth-relative). All other instruction references are inlined in {@code AGENTS.md} and
 * their Markdown links are stripped to display text; plain-text paths are replaced with
 * {@code "AGENTS.md"}. Non-instruction links are untouched.
 * @param skillTargetedNames Set of instruction names whose applyTo targets SKILL.md files
 * @return A rewrite function {@code (content: string, depth: number) =&gt; string}
 */
function makeCodexRewriteFn(skillTargetedNames) {
  return function rewriteLinksForCodex(content, depth = 1) {
    const upToSkillsDir = '../'.repeat(depth);
    // Markdown links: X.instructions.md → depth-relative references/ or display text
    content = content.replace(
      /\[([^\]]*)\]\([^)]*\/instructions\/([\w-]+)\.instructions\.md\)/g,
      (match, text, name) =>
        skillTargetedNames.has(name)
          ? `[${text}](${upToSkillsDir}references/${name}.md)`
          : text,
    );
    // Markdown links: global instruction → display text only
    content = content.replace(
      /\[([^\]]*)\]\([^)]*\/instructions\/global-copilot-instructions\.md\)/g,
      '$1',
    );
    // Plain text: X.instructions.md → depth-relative references/ or AGENTS.md
    content = content.replace(
      /\binstructions\/([\w-]+)\.instructions\.md/g,
      (match, name) =>
        skillTargetedNames.has(name)
          ? `${upToSkillsDir}references/${name}.md`
          : 'AGENTS.md',
    );
    // Plain text: global instruction path → AGENTS.md
    content = content.replace(/\binstructions\/global-copilot-instructions\.md/g, 'AGENTS.md');
    content = rewriteMemoryPaths(content, '.codex');
    return content;
  };
}

/**
 * Recursively copies all {@code .md} files from {@code srcDir} into {@code destDir},
 * applying {@code rewriteFn} to each file's content before writing. Subdirectories are
 * traversed recursively. Non-{@code .md} files are silently skipped.
 * @param srcDir Absolute path to the source directory
 * @param destDir Absolute path to the destination directory
 * @param rewriteFn Function {@code (content: string) => string} applied to each file
 * @param logPrefix Relative prefix shown in console output (e.g. {@code "claude/skills/foo"})
 */
function copySkillMd(srcDir, destDir, rewriteFn, logPrefix, depth = 1) {
  ensureDir(destDir);
  for (const entry of readdirSync(srcDir, { withFileTypes: true })) {
    const srcPath  = join(srcDir,  entry.name);
    const destPath = join(destDir, entry.name);
    const entryLog = `${logPrefix}/${entry.name}`;
    if (entry.isDirectory()) {
      copySkillMd(srcPath, destPath, rewriteFn, entryLog, depth + 1);
    } else if (entry.isFile() && entry.name.endsWith('.md')) {
      writeFileSync(destPath, rewriteFn(readFileSync(srcPath, 'utf8'), depth), 'utf8');
      console.log(`  ${entryLog}`);
    }
  }
}

/**
 * Exports all skills to {@code claude/skills/}, rewriting instruction file references
 * to their Claude-equivalent paths (see {@link rewriteLinksForClaude}).
 * @param skillNames Sorted array of skill directory names from {@code copilot/skills/}
 */
function exportClaudeSkills(skillNames) {
  ensureDir(CLAUDE_SKILLS_DIR);
  for (const name of skillNames) {
    copySkillMd(
      join(SKILLS_DIR, name),
      join(CLAUDE_SKILLS_DIR, name),
      rewriteLinksForClaude,
      `claude/skills/${name}`,
    );
  }
}

/**
 * Exports all skills to {@code codex/skills/}, rewriting instruction file references
 * for Codex. SKILL.md-targeted instructions are routed to {@code codex/skills/references/}
 * and linked with a depth-relative path; all other instruction references are resolved to
 * {@code AGENTS.md}.
 * @param skillNames Sorted array of skill directory names from {@code copilot/skills/}
 * @param instructions Parsed instruction objects from {@link readInstructions}
 */
function exportCodexSkills(skillNames, instructions) {
  const skillTargetedNames = new Set(
    instructions.filter(i => isSkillTargeted(i.frontmatter)).map(i => i.name),
  );
  ensureDir(CODEX_SKILLS_DIR);
  for (const name of skillNames) {
    copySkillMd(
      join(SKILLS_DIR, name),
      join(CODEX_SKILLS_DIR, name),
      makeCodexRewriteFn(skillTargetedNames),
      `codex/skills/${name}`,
    );
  }
}

/**
 * Writes SKILL.md-targeted instructions as standalone reference files under
 * {@code codex/skills/references/}. These instructions are excluded from the profile
 * {@code AGENTS.md} files and are linked by skill files via depth-relative paths.
 * @param instructions Parsed instruction objects from {@link readInstructions}
 */
function exportCodexSkillReferenceInstructions(instructions) {
  ensureDir(CODEX_SKILLS_REFS_DIR);
  for (const { name, body } of instructions.filter(
    i => i.name !== 'global-copilot-instructions' && isSkillTargeted(i.frontmatter),
  )) {
    writeFileSync(join(CODEX_SKILLS_REFS_DIR, `${name}.md`), body.trimEnd() + '\n', 'utf8');
    console.log(`  codex/skills/references/${name}.md`);
  }
}

/* -------------
   Claude export
   ------------- */

function exportClaude(instructions, skillNames) {
  ensureDir(CLAUDE_RULES_DIR);

  const alwaysOnNames = [];

  for (const { name, frontmatter, body } of instructions) {
    // The global instruction becomes CLAUDE.md, not a rules file
    if (name === 'global-copilot-instructions') continue;

    const ruleFm = {};
    if (frontmatter.description) ruleFm.description = rewriteMemoryPaths(frontmatter.description, '.claude');

    const scopedGlobs = normalizeGlobs(frontmatter.applyTo).filter(g => g !== '**');
    if (scopedGlobs.length > 0) {
      // path-scoped: translate applyTo → paths
      ruleFm.paths = scopedGlobs.length === 1 ? scopedGlobs[0] : scopedGlobs;
    } else {
      alwaysOnNames.push(name);
    }

    const out = `---\n${yaml.dump(ruleFm).trimEnd()}\n---\n\n${rewriteMemoryPaths(body, '.claude').trimEnd()}\n`;
    writeFileSync(join(CLAUDE_RULES_DIR, `${name}.md`), out, 'utf8');
    console.log(`  claude/rules/${name}.md`);
  }

  // CLAUDE.md — always-on entry point
  const global = instructions.find(i => i.name === 'global-copilot-instructions');

  const claudeLines = [
    '<!-- Auto-generated by export.mjs — do not edit manually -->',
    '<!-- Source: copilot/instructions/global-copilot-instructions.md -->',
    '',
    global ? global.body.trimEnd() : '',
    '',
    '## Available Skills',
    '',
    skillNames.length
      ? skillNames.map(s => `- [${s}](skills/${s}/SKILL.md)`).join('\n')
      : '_No skills found._',
    '',
    '## Always-On Rules',
    '',
    'The following rules apply to all files (no path restriction):',
    '',
    alwaysOnNames.map(n => `- [${n}](rules/${n}.md)`).join('\n'),
    '',
  ];

  writeFileSync(join(CLAUDE_DIR, 'CLAUDE.md'), claudeLines.join('\n'), 'utf8');
  console.log('  claude/CLAUDE.md');
}

/* ------------
   Codex export
   ------------ */

/**
 * Defines the AEM-module-aligned Codex profiles. Each profile specifies a list of
 * representative file paths used to auto-select matching instructions via their
 * {@code applyTo} glob patterns. The empty-string name maps to the base {@code AGENTS.md}
 */
const CODEX_PROFILES = [
  {
    name: '',
    description: 'Generic conventions',
    samplePaths: [
      '.dependency-sources/META-INF/MANIFEST.MF',
      'copilot/skills/foo/SKILL.md',
    ],
  },
  {
    name: 'core',
    description: 'AEM core module — Java main sources',
    samplePaths: [
      'src/main/java/com/example/Foo.java',
    ],
  },
  {
    name: 'core--src--test',
    description: 'AEM core module — Java test sources',
    samplePaths: [
      'src/test/java/com/example/FooTest.java',
    ],
  },
  {
    name: 'ui.apps',
    description: 'AEM ui.apps module — HTL templates, clientlibs, JS/CSS',
    samplePaths: [
      'src/main/content/jcr_root/apps/x/clientlibs/foo.js',
      'src/main/content/jcr_root/apps/x/clientlibs/foo.css',
      'src/main/content/jcr_root/apps/x/components/foo.html',
    ],
  },
  {
    name: 'ui.frontend',
    description: 'AEM ui.frontend module — standalone JS/TS sources',
    samplePaths: [
      'src/foo.js',
      'src/foo.ts',
      'src/foo.mjs',
    ],
  },
];

function exportCodex(instructions, skillNames) {
  ensureDir(CODEX_DIR);

  for (const profile of CODEX_PROFILES) {
    const fileName = profile.name ? `${profile.name}--AGENTS.md` : 'AGENTS.md';

    // Collect always-on instructions first, then scoped instructions whose
    // applyTo globs match at least one of the profile's representative paths.
    // SKILL.md-targeted instructions are excluded — they go to codex/skills/references/.
    const included = instructions.filter(i => {
      if (isSkillTargeted(i.frontmatter)) return false;
      if (isAlwaysOn(i.frontmatter)) return true;
      const globs = normalizeGlobs(i.frontmatter.applyTo);
      return profile.samplePaths.some(p => matchesAnyGlob(p, globs));
    });

    const parts = [
      '<!-- Auto-generated by export.mjs — do not edit manually -->',
      `<!-- Profile: ${profile.description} -->`,
      '',
    ];

    for (const { name, frontmatter, body } of included) {
      const title = frontmatter.description
        ? frontmatter.description.replace(/\. .*$/, '').replace(/\.$/, '')
        : name;
      parts.push(rewriteMemoryPaths(body, '.codex').trimEnd(), '', '---', '');
    }

    if (profile.name === '') {
      parts.push(
        '## Available Skills',
        '',
        ...(skillNames.length
          ? skillNames.map(s => `- [${s}](skills/${s}/SKILL.md)`)
          : ['_No skills found._']),
        '',
      );
    }

    writeFileSync(join(CODEX_DIR, fileName), parts.join('\n'), 'utf8');
    console.log(`  codex/${fileName}`);
  }
}

/* ----
   Main
   ---- */

console.log('Exporting copilot/ → claude/ and codex/...\n');

const instructions = readInstructions();
console.log(`Found ${instructions.length} instruction files.\n`);

const skillNames = getSkillNames();
console.log(`Found ${skillNames.length} skills.\n`);

exportClaude(instructions, skillNames);
console.log();
exportCodex(instructions, skillNames);
console.log();
exportCodexSkillReferenceInstructions(instructions);
console.log();

console.log('Exporting skills...\n');
exportClaudeSkills(skillNames);
console.log();
exportCodexSkills(skillNames, instructions);

// Copy model-config.md into each harness root so skills can reach it via ../../model-config.md
const modelConfigSrc = join(ROOT, 'copilot', 'model-config.md');
if (existsSync(modelConfigSrc)) {
  const src = readFileSync(modelConfigSrc);
  writeFileSync(join(CLAUDE_DIR, 'model-config.md'), src);
  writeFileSync(join(CODEX_DIR,  'model-config.md'), src);
  console.log('\n  claude/model-config.md');
  console.log('  codex/model-config.md');
}

console.log('\nDone.');
