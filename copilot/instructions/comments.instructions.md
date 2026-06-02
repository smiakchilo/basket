---
description: "Use when writing or generating Javadoc or comments for Java classes, interfaces, methods, constructors, and fields. Covers opening verbs, tag ordering, nullability conventions, coverage scope, method-type patterns, and inline/block comment conventions."
applyTo: "**/*.java, **/*.js, **/*.mjs, **/*.cjs, **/*.ts, **/*.tsx"
---

# Javadoc Style Guide

## Common Principles

- Present tense, start with a verb: "Retrieves the user name" — never "This method returns..."
- 1–3 sentences. Explain _why_, constraints, side effects — not obvious facts.
- Always use `@param`, `@return`, `@throws`.
- No trailing period on the last sentence. Periods separate multiple sentences only.
- **Tone**: formal, active, imperative. Describe what a method *does*, not what it *is*.
- Classes/interfaces: declarative third-person ("Represents a base for a Sling injector"). Methods: imperative action verb ("Retrieves the raw type").

## Formatting

**`/**` comments must always span multiple lines** — the opening `/**`, every content line prefixed with ` * `, and the closing ` */` must each be on their own line. Single-line `/** ... */` is forbidden.

```java
// WRONG
/** Default (instantiation-blocking) constructor */

// RIGHT
/**
 * Default (instantiation-blocking) constructor
 */
```

## Composition

Structure: **opening sentence → optional body `<p>` paragraphs → tag section** (no blank line before first tag).

```java
/**
 * Attempts to cast the given value to the provided {@code Type}. Designed for use with Sling injectors
 * @param value An arbitrary value
 * @param type  A {@code Type} reference. Usually reflects the type of Java class member
 * @return A {@link Injectable} instance containing the transformed value; can contain {@code null} if type casting
 * was not possible
 */
public static Injectable toType(Object value, Type type) {
```

---

## `{@code}` vs `{@link}` Usage

- `{@link X}` — **navigable project/library class/method/field** the reader would click through to.
- `{@code X}` — everything else: standard-library types (`java.*`, `javax.*`), variable/parameter names, keywords (`null`, `true`, `false`), literal values.
- **First-mention rule**: only the first occurrence of a project/third-party type in the **entire Javadoc block** — including all `@param`, `@return`, and `@throws` tags — uses `{@link}`; every subsequent occurrence of that same type anywhere in the same block **must** use `{@code}`. This applies even when the repeat is in a different tag than the first mention.

  <!-- WRONG — ResourceChange already introduced with {@link} in the opening sentence -->
  ```
  * Resolves path samples and produces a collection of {@link ResourceChange} notifications
  * @return A non-null, possibly empty collection of {@link ResourceChange} instances
  ```
  <!-- CORRECT -->
  ```
  * Resolves path samples and produces a collection of {@link ResourceChange} notifications
  * @return A non-null, possibly empty collection of {@code ResourceChange} instances
  ```

```java
/**
 * Retrieves {@link Option} objects matching the provided filter. Each {@code Option} is validated against the
 * given {@code Predicate} before inclusion.
 * <p>If the filter is {@code null}, all options are returned as an unmodifiable {@code List}
 * @param resolver {@link ResourceResolver} instance used to access the repository. The {@code ResourceResolver}
 *                 must have read access to the target path
 * @param filter   A nullable {@code Predicate} applied to each candidate
 * @return A non-null {@code List} of {@code Option} instances; might be empty
 * @throws IllegalStateException If the {@code ResourceResolver} is already closed
 */
public List<Option> getOptions(ResourceResolver resolver, Predicate<Option> filter) {
```

---

## Opening Verbs by Method Category

| Category | Verb(s) | Example |
|---|---|---|
| Simple accessor | `Gets` | `Gets the {@code title} part of this item` |
| Computed getter | `Retrieves` | `Retrieves the raw type of a parametrized type entity` |
| Boolean predicate | `Gets whether`, `Checks whether` | `Gets whether the given string represents a pattern` |
| Factory / builder | `Creates`, `Gets a builder for` | `Creates a {@link ValueMapResource} for the provided {@code title} and {@code value}` |
| Void action / servlet | `Processes`, `Outputs`, `Extracts` | `Processes HTTP GET requests and outputs a {@link SimpleDataSource}` |
| Transformation / cast | `Attempts to`, `Converts`, `Transforms` | `Attempts to cast the given value to the provided {@code Type}` |
| Internal delegation | `Called by` + cross-reference | `Called by {@code CastUtil#toType} to adapt the value` |
| Side-effect mutator | `Turns on`, `Sets` | `Turns on {@code selected} flag for this option` |

---

## Vocabulary

- **`nullable`** / **`non-null`** — nullability: `A nullable {@code Resource} instance`, `A non-null list of {@link Option} objects`
- **`arbitrary`** — unconstrained input: `An arbitrary non-null value`
- **`provided`** / **`given`** — caller-supplied arguments: `the provided {@code title}`
- **`underlying`** — wrapped/delegated object: `the underlying resource`
- **`instance`** — concrete runtime object: `Sling {@link ResourceResolver} instance`
- **`collection`** — generic groupings: `collection of Sling models`
- Articles: **"the"** for specific contextual items, **"a"/"an"** for generic instances. Omit with plural/mass nouns.

---

## Grammar

- No trailing period unless another sentence or `<p>` follows.
- Capitalise the first word after `@param someName`, `@throws SomeException`.
- Tag content: full noun phrases or sentences, not bare fragments.
- Use conditional clauses: "If the path is invalid, an empty list is returned"
- **Align** `@param` descriptions to the same column when multiple params exist.

---

## Tag Order

`@param` (declaration order) → `@param <T>` → `@return` (omit for `void`) → `@throws` (one per exception) → `@see`

```java
/**
 * Creates a page representing an EToolbox List under the given JCR path
 * @param resourceResolver Sling {@link ResourceResolver} instance used to create the list
 * @param path             JCR path of the page
 * @return {@link Page} containing the list of entries
 * @throws WCMException If invalid data is provided or {@link PageManager} is not available.
 * @throws PersistenceException If page creation fails.
 */
public static Page createPage(ResourceResolver resourceResolver, String path) throws WCMException, PersistenceException {
```

For class-level generics, place `@param <T>` before `@see`. When `@see` is the only tag, place it directly after the description with no blank line.

```java
/**
 * Represents a base for a Sling injector
 * @param <T> The type of annotation handled by this injector
 * @see Injector
 */
abstract class BaseInjector<T extends Annotation> implements Injector {
```

---

## Null Documentation

Document nullability in both Javadoc and code annotations (`@Nonnull`, `@CheckForNull`).

- `@param`: prefix `A nullable` or `A non-null` — `A nullable {@code Resource} instance`
- `@return`: prefix `A nullable` or `A non-null` — `A non-null list of {@link Option} objects; might be empty`
- Conditional null: append "or null" — `{@code SlingHttpServletRequest} object if appropriate type, or null`
- Inline: `An "empty" object is either {@code null}, or an empty array`

---

## Coverage Scope

| Visibility | Document? | Notes |
|---|---|---|
| `public`, `protected` | Always | Especially important for abstract methods |
| Package-private, `private` | Project-dependent | Follow project scope guidelines. If not found, learn from existing code. If cannot decide, ask user |
| Constants (`static final`) | No | Names are self-documenting |
| Private instance fields | No | |
| Fields with `@ValueMapValue` etc. | No | Annotation documents the intent |

---

## Method-Type Patterns

### Simple Accessor

Single sentence. `@return` with nullability prefix.

```java
/**
 * Gets the value
 * @return A nullable object
 */
public Object getValue() {
```

### Boolean Predicate

Open with "Gets whether" / "Checks whether". `@return` is always `True or false`.

```java
/**
 * Gets whether the given value is "empty" — {@code null}, an empty array, iterable, or map
 * @param value Arbitrary object
 * @return True or false
 */
public static boolean isEmpty(Object value) {
```

### Factory / Builder

Open with "Creates" or "Gets a builder for". `@return` names the created type.

### Override

Use 
```java
/**
 * {@inheritDoc}
 */
 ```
  — no additional text.

### Private Constructor

Exactly one sentence, no tags: for a utility class that should not be instantiated — `Default (instantiation-blocking) constructor`; for a class that is only instantiated via factory methods — `Default (instantiation-restricting) constructor`.

### Property assignment method inside a builder

In the `@return` tag, use exactly the phrase "This builder".

### Servlet / Void Action

Open with "Processes". Describe request-response contract. `@param` for request/response only.

```java
/**
 * Processes {@code GET} requests to populate a {@link DataSource} with child pages under the root path
 * @param request  {@code SlingHttpServletRequest} instance
 * @param response {@code SlingHttpServletResponse} instance
 */
@Override
protected void doGet(@Nonnull SlingHttpServletRequest request, @Nonnull SlingHttpServletResponse response) {
```

### Internal Helper

Open with "Called by {@code ClassName#method} to…" when a single caller exists. Explain the helper's specific role.

---

## Comments

- All comment text, regardless of style or location, must begin with a capital letter.
- **Exception, log, and assertion messages** (string literals passed to `new SomeException(...)`, `log.info(...)`, `throw`, etc.) must use sentence case — capitalize the first word of each sentence or clause, including the first word after a colon that introduces a new clause.

  ```java
  // DO
  throw new IllegalStateException("Configuration is missing: Required property was not set");
  log.warn("Skipping resource: Path not found");

  // DO NOT
  throw new IllegalStateException("configuration is missing: required property was not set");
  log.warn("skipping resource: path not found");
  ```

- Inline comments inside method bodies **must always** use `//`. **Never** use `/* ... */` inside a method body.
- Use `/* */` block comments outside method bodies only (e.g., above fields or between members).
- To insert a logical section break between members of a class, use the following pattern, where the number of dashes equals the number of characters in the section name:

```java
/* ------------
   Section name
   ------------ */
```

Examples:

```java
// DO — inline comment inside a method
void myMethod() {
    // Compute the final result
    int result = compute();
}

// DO NOT — block comment inside a method
void myMethod() {
    /* compute the final result */
    int result = compute();
}

// DO NOT — comment starting with lowercase
void myMethod() {
    // compute the final result
    int result = compute();
}
```
