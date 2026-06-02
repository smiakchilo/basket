---
description: "Use when writing or modifying JavaScript, TypeScript, or ES module source code. Covers quality and safety standards."
applyTo: "**/*.js, **/*.mjs, **/*.cjs, **/*.ts, **/*.tsx"
---

# JavaScript / TypeScript Code Standards

## Quality Standards

- Async operations must always have error handlers — `.catch()` on promise chains or `try/catch` around `await` calls.
- Clean up event listeners when the component or module is destroyed (e.g. in SPA lifecycle hooks, `disconnectedCallback`, or equivalent unmount logic).
- Wrap module-level code in an IIFE or ES module to avoid polluting the global scope.
- Do not call `querySelectorAll` (or equivalent DOM queries) inside loops or event handlers that fire repeatedly — cache the result in a variable outside the loop.
