---
description: "Use when writing or modifying JavaScript, TypeScript, or ES module source code. Covers comment style conventions."
applyTo: "**/*.js, **/*.mjs, **/*.cjs, **/*.ts, **/*.tsx"
---

# JavaScript / TypeScript Code Standards

## Comments

- Use `//` comments inside function bodies.
- Use `/* */` block comments outside function bodies (e.g., above variables or between declarations).
- To insert a logical section break between top-level declarations, use the following pattern, where the number of dashes equals the number of characters in the section name:

```js
/* ------------
   Section name
   ------------ */
```

Do **not** use the `// ----` banner style for section separators:

```js
// ---------------------------------------------------------------------------
// Section name   ← DO NOT use this style
// ---------------------------------------------------------------------------
```

## Quality Standards

- Async operations must always have error handlers — `.catch()` on promise chains or `try/catch` around `await` calls.
- Clean up event listeners when the component or module is destroyed (e.g. in SPA lifecycle hooks, `disconnectedCallback`, or equivalent unmount logic).
- Wrap module-level code in an IIFE or ES module to avoid polluting the global scope.
- Do not call `querySelectorAll` (or equivalent DOM queries) inside loops or event handlers that fire repeatedly — cache the result in a variable outside the loop.
