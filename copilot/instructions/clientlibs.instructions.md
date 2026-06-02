---
description: "Use when writing or modifying AEM client libraries: JavaScript, TypeScript, CSS, or LESS files for AEM component clientlibs."
applyTo: **/clientlibs/**/*.js, **/clientlibs/**/*.ts, **/clientlibs/**/*.css, **/clientlibs/**/*.less, **/clientlib/**/*.js, **/clientlib/**/*.ts, **/clientlib/**/*.css, **/clientlib/**/*.less
---

# AEM Client Library Standards

## JavaScript / TypeScript

- Wrap code in IIFEs or modules to avoid polluting the global namespace.
- Use `"use strict"` in IIFE-based files.
- Prefer vanilla DOM APIs and Coral/Spectrum component APIs over jQuery for new code.
- Follow the existing patterns in the project for event delegation and component initialization.

## CSS / LESS

- Scope styles to the component's root CSS class to avoid style leaking.
- Use LESS variables and mixins from the project's shared library where available.
- Follow BEM or the project's existing naming convention for CSS classes.

## General

- Maintain correct ordering in `js.txt` and `css.txt` manifests.
- Keep clientlib categories specific; avoid catch-all categories.
