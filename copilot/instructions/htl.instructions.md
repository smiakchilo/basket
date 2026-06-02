---
description: "Use when writing or modifying HTL (Sightly) templates for AEM components. Covers HTL block statements, expression language, use-objects, and XSS context."
applyTo: "**/jcr_root/**/*.html"
---

# HTL (Sightly) Standards

- Prefer Sling Models via `data-sly-use` over `WCMUsePojo` or server-side JavaScript use-objects.
- Use the appropriate display context for XSS safety (`uri`, `attribute`, `html`, `text`, etc.). Do not use `unsafe` unless the value is trusted and no other context fits.
- Prefer `data-sly-test` for conditionals, `data-sly-list` / `data-sly-repeat` for iteration.
- Keep logic out of templates: delegate to Sling Models. Templates should focus on markup structure.
- Use `data-sly-template` and `data-sly-call` for reusable template fragments.
- Use `data-sly-resource` for including other components with proper resource types.
- Specify the display context explicitly when the default (`text`) does not fit.
- Use `data-sly-unwrap` to render contents without the host element when only the inner markup is needed.
- Follow the project's existing HTL patterns for component structure and naming.
