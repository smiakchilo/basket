import { readFileSync, writeFileSync } from "node:fs";
import { approveAll } from "@github/copilot-sdk";
import { joinSession } from "@github/copilot-sdk/extension";

/* --------
   Helpers
   -------- */

/** Returns true if the buffer looks like binary (contains a NUL byte). */
function isBinaryBuffer(buf) {
  for (let i = 0; i < buf.length; i++) {
    if (buf[i] === 0) return true;
  }
  return false;
}

/** Normalizes CRLF/CR → LF in-place. Returns true if the file was changed. */
function normalizeLf(filePath) {
  try {
    const raw = readFileSync(filePath);
    if (raw.length === 0 || isBinaryBuffer(raw.slice(0, 8000))) return false;
    const str = raw.toString("utf8");
    if (!str.includes("\r")) return false;
    const normalized = str.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
    if (normalized === str) return false;
    writeFileSync(filePath, normalized, "utf8");
    return true;
  } catch {
    return false;
  }
}

/**
 * Tries to extract a file path from any tool's arguments.
 * Covers the built-in `create`/`edit` tools (toolArgs.path) and common
 * MCP / IDE tool conventions (file_path, filePath, filename, etc.).
 */
function extractFilePath(toolArgs) {
  if (!toolArgs || typeof toolArgs !== "object") return null;
  const args = /** @type {Record<string,unknown>} */ (toolArgs);
  for (const key of ["path", "file_path", "filePath", "filename", "file", "target", "destination"]) {
    const v = args[key];
    if (typeof v === "string" && v.length > 0) return v;
  }
  return null;
}

/* ---------
   Extension
   --------- */

const session = await joinSession({
  onPermissionRequest: approveAll,
  hooks: {
    onSessionStart: async () => {
      await session.log("lf-normalizer extension loaded — will convert CRLF → LF on file creation.");
    },

    onPostToolUse: async (input) => {
      // Act on the built-in "create" tool and any MCP/IDE tool whose name
      // suggests file creation or writing. Broaden the match so JetBrains
      // MCP tools (e.g. create_file, write_file) are also covered.
      const name = input.toolName ?? "";
      const isFileCreation =
        name === "create" ||
        /create.?file|write.?file|new.?file|save.?file/i.test(name);

      if (!isFileCreation) return;

      const filePath = extractFilePath(input.toolArgs);
      if (!filePath) return;

      const changed = normalizeLf(filePath);
      if (changed) {
        await session.log(`lf-normalizer: converted CRLF → LF in ${filePath}`);
        return {
          additionalContext: `Note: line endings in the newly created file were normalized to LF.`,
        };
      }
    },
  },
});
