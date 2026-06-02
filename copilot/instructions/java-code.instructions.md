---
description: "Use when writing or modifying any Java file, including test files. Covers Java coding standards, null safety, Apache Commons usage, constants, imports, and naming conventions."
applyTo: "**/*.java"
---

# Common principles for Java code

1. **Choose readable, maintainable solutions** that fit the project's idioms and conventions.
2. **Stay minimal and composable.** Avoid unnecessary abstractions; keep methods, classes, and modules small and single-purpose.
3. **No silent failures.** Fail fast with meaningful exceptions or validations; log at appropriate levels.

# Java Code Standards

## Imports

- Use import statements instead of fully qualified names (except in Javadoc). This applies everywhere a type is referenced — variable declarations, method parameters, return types, generics, and `new` expressions.

  Bad:
  ```java
  java.util.Map<String, Object> props = new java.util.HashMap<>();
  ```
  Good:
  ```java
  import java.util.HashMap;
  import java.util.Map;
  // ...
  Map<String, Object> props = new HashMap<>();
  ```

- DO NOT use static imports.

## Type Inference

- DO NOT use explicit type witnesses (e.g. `Map.<String, Object>of(...)`) when the compiler can infer the types. Only add a type witness when it is required for compilation, such as when value types are mixed.

## Constants

- **Never duplicate an inline literal.** Every string, number, or other literal value that appears more than once anywhere in the same class — across all methods, lambdas, and initializers — **must** be extracted to a `private static final` constant. "More than once" means across the whole class, not per method. This rule is absolute.

- **Name path constants with a semantic prefix** indicating their role, e.g.:
  - `PATH_` — a full resource or JCR path (e.g. `PATH_SOURCE = "/content/source"`)
  - `PROPERTY_` — a JCR property name (e.g. `PROPERTY_TITLE = "jcr:title"`)
  - `PARAM_` — a servlet request parameter name (e.g. `PARAM_USER_ID = "userId"`), etc.

  Do not use bare nouns for path constants — the prefix makes the constant's purpose immediately clear.

  ```java
  // DO
  private static final String PATH_SOURCE = "/content/source";
  private static final String PARAM_USER_ID = "userId";

  // DO NOT
  private static final String SOURCE = "/content/source";
  private static final String USER_ID = "userId";
  ```

- **Always explore for existing constants before using an inline literal.** Search classes named `Constants`, `CoreConstants`, `ApplicationConstants`, or similar across packages, **and** search framework/library classes for well-known constants. Never write a raw string when a named constant exists in the classpath.

  Common framework constants to prefer over literals:
  - `JcrResourceConstants.SLING_RESOURCE_TYPE_PROPERTY` — not `"sling:resourceType"`
  - `JcrConstants.JCR_PRIMARYTYPE` — not `"jcr:primaryType"`
  - `JcrConstants.NT_UNSTRUCTURED` — not `"nt:unstructured"`
  - `ResourceResolver.SUBSERVICE` — not `"sling.service.subservice"`
  - and so on. Always search for a matching constant before inlining a string literal, even if the constant is not in the same package or module.

  This also applies to project-specific constant holders. Always search for a matching constant in classes like `CoreConstants` (e.g. `CoreConstants.PN_NAME`, `CoreConstants.PN_TEXT`, `CoreConstants.NN_FIELD`) and `ApplicationConstants` (e.g. `ApplicationConstants.SLASH`) for property names, node names, and common literals before inlining a string.

## Method Visibility

Always use the least visibility required for a method. Do not use `public` or `protected` when `private` or package-private suffices.

```java
// DO — lifecycle methods on OSGi components
@Activate
private void activate(Config config) { ... }

@Deactivate
private void deactivate() { ... }

// DO — Sling Model post-construct
@PostConstruct
private void init() { ... }
```
This applies to all methods: helpers, event handlers, OSGi lifecycle callbacks, Sling Model init methods, etc.

## Resource Management

**Use try-with-resources for `AutoCloseable` results.** When a method returns an `AutoCloseable` type (e.g. `ResourceResolver`, `InputStream`), capture it in a try-with-resources — even when the opening call may also throw an exception.

```java
// DO NOT
try {
    SomeUtil.openResource(args);
    // ...
} catch (SomeException e) { ... }

// DO
try (ResourceResolver resolver = SomeUtil.openResource(args)) {
    // ...
} catch (SomeException e) { ... }
```

## Apache Commons

**Before writing any utility logic, explore what already exists** in Apache Commons (lang3, collections4, io) and other libraries declared in the POM. Never hand-write logic that a library method already provides. This includes null-safe wrappers, collection/iterator utilities, and I/O helpers.

Prefer null-safe Apache Commons methods over manual null checks: <!-- refined: consolidated three separate examples into one DO/DO NOT block -->
```java
// DO NOT — manual null guards
if (name != null && name.endsWith("@DefaultValue")) { ... }
if (myString == null || myString.trim().isEmpty()) { ... }
boolean mapIsEmpty = map == null || map.isEmpty();

// DO — null-safe Apache Commons wrappers
if (StringUtils.endsWith(name, "@DefaultValue")) { ... }
if (StringUtils.isBlank(myString)) { ... }
boolean mapIsEmpty = MapUtils.isEmpty(map);
```

Use constants from Apache Commons when applicable instead of defining your own. This applies everywhere the literal appears — variable assignments, method arguments, comparisons, and any other expression context:
```java
// DO NOT
String myString = "";
someMethod(" ", otherArg);
if ("\n".equals(value)) { ... }

// DO
String myString = StringUtils.EMPTY;
someMethod(StringUtils.SPACE, otherArg);
if (StringUtils.LF.equals(value)) { ... }
```

## Lombok

When Lombok is present in the classpath, use its annotations instead of hand-writing constructors, getters, setters, or builders:

- `@Getter` / `@Setter` instead of manual accessor methods.
- `@RequiredArgsConstructor`, `@AllArgsConstructor`, or `@NoArgsConstructor` instead of explicit constructors.
- `@Builder` instead of manually implemented builder patterns.
- `@Value` for immutable data classes instead of writing `final` fields with a constructor and getters.
- `@Slf4j` / `@Log` for logger field injection instead of a manual `static final Logger` declaration.

When a Lombok-generated accessor (e.g., `@Getter`) would override a parent class or interface method that carries a behavioral contract (e.g., "never null", "always positive", "idempotent"), verify that the generated implementation upholds that contract for every possible object state — including partially-initialised instances created via minimal constructors, factory methods, or deserialization. If the generated accessor cannot meet the contract, replace it with an explicit `@Override` that enforces the contract (e.g., `return StringUtils.defaultIfBlank(field, getId())`).

## Line Wrapping

When a method call with arguments is too long to fit on one line, put **each** argument on its own line, with the closing parenthesis on the last argument's line:

```java
myClass.myLongMethodName(
    "First argument",
    "Second argument",
    42);
```
The only exception for the above rule is when the method has varargs that **semantically represent a map of key-value entries**. In this case, put pairs of varargs arguments that represent a single map entry on the same line:

```java
Map<String, String> myMap = Map.of(
    "First key", "First value",
    "Second key", "Second value",
    "Third key", "Third value");

myClass.initializeResourceWithProperties(
    "First property", "First value",
    "Second property", "Second value",
    "Third property", "Third value");
```

When a method has positional parameters **before** the trailing map-entry varargs, those positional parameters each go on their own line — only the varargs pairs are grouped:

```java
// DO
context.create().resource(
    parent,
    "childName",
    "prop1", "value1",
    "prop2", "value2");

// DO NOT — positional args grouped with varargs pairs
context.create().resource(
    parent, "childName",
    "prop1", "value1",
    "prop2", "value2");
```
Apply the same rule to method declarations:

```java
public String myLongMethodName(
    String firstArgument,
    String secondArgument,
    long someValue) throws Exception {
```

When a method call chain is too long to fit on one line, move **every** chained call to its own line, prefixed with `.` — including the very first call. Do not keep the first chained call on the same line as the receiver or assignment target:

```java
// DO
someObject
    .firstMethod()
    .secondMethod(argument)
    .thirdMethod();

// DO NOT — first call on the receiver line
someObject.firstMethod()
    .secondMethod(argument)
    .thirdMethod();
```

## Annotation Ordering

Place generic, language-level annotations (`@SuppressWarnings`, `@Deprecated`, `@Serial`, `@FunctionalInterface`, etc.) **below** more specific annotations that convey package-level, business-logic, or functionality-specific meaning.

```java
// DO
@Test
@ValueSource(strings = {"on", "true"})
@SuppressWarnings("unchecked")
void shouldFlushCache(String value) { ... }

// DO NOT
@SuppressWarnings("unchecked")
@Test
@ValueSource(strings = {"on", "true"})
void shouldFlushCache(String value) { ... }
```

## Java Version Detection & Compliance

**Before writing or modifying Java code, detect the project's Java version.** Check these sources in order of reliability:

1. `maven.compiler.source` / `maven.compiler.release` / `maven.compiler.target` property in the nearest `pom.xml`.
2. `<source>` / `<target>` / `<release>` configuration of `maven-compiler-plugin`.
3. `sourceCompatibility` / `targetCompatibility` in `build.gradle` or `build.gradle.kts`.

**NEVER use language features, API methods, or library replacements that require a Java version higher than the detected version.** When in doubt, use the older-compatible alternative.

### Java 8 (baseline)

- Use `Optional`, `Stream`, lambdas, method references, `CompletableFuture`.
- Use `Map.put()` / map-builder utilities (e.g., Guava `ImmutableMap.of()`, `ImmutableMap.builder()`) for creating unmodifiable maps.
- Use `Collections.unmodifiableList(Arrays.asList(...))` for unmodifiable lists.
- Use `Collections.unmodifiableSet(new HashSet<>(Arrays.asList(...)))` for unmodifiable sets.

### Java 9+ additions (use only when version ≥ 9)

- Use `List.of()`, `Set.of()`, `Map.of()`, `Map.ofEntries()` **instead of** Guava `ImmutableList.of()`, `ImmutableSet.of()`, `ImmutableMap.of()`, and instead of `Collections.unmodifiable*` wrappers.
- Use `Optional.ifPresentOrElse()`, `Optional.or()`, `Optional.stream()`.
- Use `InputStream.transferTo(OutputStream)` instead of manual byte-copy loops or Apache Commons `IOUtils.copy()`.
- Use `takeWhile()` / `dropWhile()` on streams.
- Use the `ProcessHandle` API instead of platform-specific process management.

### Java 10+ additions (use only when version ≥ 10)

- Use `var` for local variables when the type is obvious from the right-hand side. Do **not** use `var` when the inferred type is ambiguous or when it reduces readability.
- Use `List.copyOf()`, `Set.copyOf()`, `Map.copyOf()` for defensive copies of collections.
- Use `Collectors.toUnmodifiableList()`, `toUnmodifiableSet()`, `toUnmodifiableMap()`.
- Use `Optional.orElseThrow()` (no-arg) instead of `Optional.get()`.

### Java 11+ additions (use only when version ≥ 11)

- Use `String.isBlank()`, `String.strip()`, `String.lines()`, `String.repeat()`.
  - Prefer `String.isBlank()` over `StringUtils.isBlank()` when the value is already known to be non-null.
  - Prefer `String.strip()` over `String.trim()` (Unicode-aware).
- Use `var` in lambda parameters: `(var x, var y) -> ...`.
- Use `Files.readString()` / `Files.writeString()` instead of manual reader/writer boilerplate.
- Use `HttpClient` (java.net.http) instead of legacy `HttpURLConnection`.
- Use `Predicate.not()` for negated method references: `.filter(Predicate.not(String::isBlank))`.

### Java 14+ additions (use only when version ≥ 14)

- Use `switch` expressions (with `->` arms and `yield`). Do **not** use the classic `switch` with fall-through and `break` when a switch expression is clearer.
- Use records for simple immutable data carriers **if version ≥ 16** (preview in 14–15).

### Java 15+ additions (use only when version ≥ 15)

- Use text blocks (`"""`) for multi-line strings (SQL, JSON, HTML, etc.) instead of string concatenation or `String.join()`. 

### Java 16+ additions (use only when version ≥ 16)

- Use `record` types for immutable value objects instead of classes with manual `equals`/`hashCode`/`toString`.
- Use `instanceof` pattern matching: `if (obj instanceof String s)` — do **not** cast after `instanceof` manually.
- Use `Stream.toList()` instead of `.collect(Collectors.toList())`.

### Java 17+ additions (use only when version ≥ 17)

- Use sealed classes/interfaces (`sealed`, `permits`) where appropriate.
- Use pattern matching in `switch` (preview in 17, finalized in 21):
  - Only use pattern-matching `switch` if version ≥ 21 or preview features are explicitly enabled.

### Java 21+ additions (use only when version ≥ 21)

- Use pattern matching for `switch` with guarded patterns (`case String s when s.length() > 5`).
- Use record patterns in `switch` and `instanceof`: `case Point(int x, int y)`.
- Use sequenced collections: `SequencedCollection`, `SequencedMap` — `getFirst()`, `getLast()`, `reversed()`.
- Use `String` templates only if preview features are enabled (still preview in 21).
- Use virtual threads (`Thread.ofVirtual()`) for I/O-heavy concurrency when appropriate.

### Summary — common replacements by version

| Java 8 (or unknown)                                      | Java 9+                              | Java 11+                   | Java 16+                           |
|-----------------------------------------------------------|---------------------------------------|-----------------------------|-------------------------------------|
| `ImmutableMap.of(k, v)`                                   | `Map.of(k, v)`                        | —                           | —                                   |
| `ImmutableList.of(a, b)`                                  | `List.of(a, b)`                       | —                           | —                                   |
| `Collections.unmodifiableList(Arrays.asList(...))`        | `List.of(...)`                        | —                           | —                                   |
| `.collect(Collectors.toList())`                           | —                                     | —                           | `.toList()`                         |
| `(MyType) obj` after `instanceof`                         | —                                     | —                           | `instanceof MyType t`               |
| `StringUtils.isBlank(s)` (nullable)                       | —                                     | `s.isBlank()` (non-null)    | —                                   |
| Manual data class                                         | —                                     | —                           | `record`                            |
| Classic `switch` with `break`                             | —                                     | —                           | `switch` expression (14+)           |
| String concatenation for multi-line                       | —                                     | Text blocks `"""` (15+)     | —                                   |

## Nesting Depth in Expressions

Limit nested method calls and constructor invocations to **at most one level** of nesting. If an expression would require deeper nesting, extract intermediate results into local variables.

```java
// GOOD — no nesting
foo.bar("baz");

// ACCEPTABLE — one level of nesting
foo.bar(new Baz());
foo.bar(baz.bat());

// BAD — two or more levels of nesting
foo.bar(baz(new Bat()));

// Refactored:
Bat bat = new Bat();
Baz baz = baz(bat);
foo.bar(baz);
```

## Logging

- Use `log.error()` / `log.warn()` only for genuinely unexpected failures — unrecoverable states, data corruption, or security events.
- Use `log.info()` for significant lifecycle events (startup, shutdown, major state transitions). Do **not** log at `info` on hot code paths (loops, per-request methods, scheduled jobs that run frequently).
- Use `log.debug()` for routine conditions: resource not found, optional value absent, retries.
- When a `catch` block logs and does not re-throw, log at `warn` or below unless the exception is genuinely unexpected.

## API Design

- Collections returned from `public` methods must be defensively copied or wrapped as unmodifiable (e.g. `Collections.unmodifiableList(...)`, `List.copyOf(...)`, `List.of(...)`). Never expose a mutable internal collection unless directly intended to mutate by design.

## Data Normalization

- **Always pass an explicit locale to `toLowerCase()` and `toUpperCase()`.** For identifiers, keys, codes, and any non-display string, use `Locale.ROOT`. The no-arg forms use `Locale.getDefault()`, which varies across JVM instances and can silently change sort order, map lookups, and comparisons — especially on non-English server locales.

- **Normalize identifiers used as storage keys at the point of ingestion** — in the constructor or factory method — not inline at each read, write, or delete call site. Applying normalization (e.g. locale format, case, encoding) in multiple places independently creates format mismatches between code paths and leads to stale or mismatched data.

  ```java
  // DO — normalize once in the constructor
  this.locales = rawLocales.stream()
          .map(l -> Locale.forLanguageTag(l).toLanguageTag().toLowerCase())
          .collect(Collectors.toUnmodifiableList());

  // DO NOT — normalize inline at each use site
  map.get(locale.toLanguageTag().toLowerCase()); // in one method
  unusedLocales.remove(locale);                  // raw value in another
  ```

## Collectors

- **Always supply a merge function to `Collectors.toMap`** when key uniqueness cannot be guaranteed — user-provided input (multifields, request parameters), JCR query results, and config-driven collections can all contain duplicates. The two-argument form throws `IllegalStateException` on the first duplicate key.

  ```java
  // DO — last entry wins (or choose first/throw/log as appropriate)
  .collect(Collectors.toMap(
          keyFn,
          valueFn,
          (existing, replacement) -> replacement));

  // DO NOT — crashes on duplicate keys
  .collect(Collectors.toMap(keyFn, valueFn));
  ```

## Early Returns and Finalization

- **Perform all finalization steps on every exit path.** When a method has multiple return points (early returns, guard clauses), ensure that cleanup actions — cache invalidation, resource release, state synchronization, event publication — are executed before *every* return, not just the main one. Asymmetric early returns are a common source of cache-consistency and resource-leak bugs.

  ```java
  // DO — refresh on both paths
  if (CollectionUtils.isEmpty(items)) {
      store(accessor -> helper.deleteAll());
      refresh();
      return;
  }
  store(accessor -> helper.update(items));
  refresh();

  // DO NOT — finalization skipped on the early-return path
  if (CollectionUtils.isEmpty(items)) {
      store(accessor -> helper.deleteAll());
      return; // cache never cleared
  }
  store(accessor -> helper.update(items));
  refresh();
  ```

## Constructors and Invalid State

- **Constructors must not silently accept invalid state.** If a constructor parameter can be null, blank, or otherwise invalid in a way that makes the resulting object non-functional or causes downstream failures, the constructor is the wrong entry point. Instead, provide a static factory method that validates the input and either:
  - Returns `null` — when the caller should treat absence as a valid outcome (e.g. "no collection selected").
  - Throws an appropriate exception — when invalid input is a programming error that should never reach this point.

  Trace back to the call site to determine which is correct: if the calling code already handles a missing/absent result gracefully, return `null`; if invalid input should never reach this point, throw.

  ```java
  // DO NOT — constructor accepts blank id; object is non-functional but no error is raised
  new AuthorableCollection(map.get(FIELD_COLLECTION))

  // DO — factory validates and signals intent clearly
  static AuthorableCollection from(String path) {
      return StringUtils.isNotBlank(path) ? new AuthorableCollection(path) : null;
  }
  // caller:
  AuthorableCollection collection = AuthorableCollection.from(map.get(FIELD_COLLECTION));
  if (collection == null) {
      continue; // or fall through to default-collection logic
  }
  ```

## Comparable Implementation

- **`compareTo()` must include a unique-field tie-breaker.** When earlier sort criteria (ranking, title, etc.) may not discriminate all distinct instances, add a final comparison on a unique field (ID, path, UUID). Without it, `compareTo() == 0` is returned for distinct objects that happen to share all ranked fields — causing `TreeSet` and `TreeMap` to silently discard one of them.

  ```java
  // DO — ID as final tie-breaker ensures no two distinct objects compare as equal
  default int compareTo(@NotNull MyEntity other) {
      if (this.getRanking() != other.getRanking()) {
          return Integer.compare(other.getRanking(), this.getRanking());
      }
      int titleCmp = StringUtils.compareIgnoreCase(this.getTitle(), other.getTitle());
      return titleCmp != 0 ? titleCmp : StringUtils.compare(this.getId(), other.getId());
  }

  // DO NOT — two entities with the same ranking and title compare as equal
  default int compareTo(@NotNull MyEntity other) {
      if (this.getRanking() != other.getRanking()) {
          return Integer.compare(other.getRanking(), this.getRanking());
      }
      return StringUtils.compareIgnoreCase(this.getTitle(), other.getTitle());
  }
  ```

## Null Safety

Whenever you encounter a method call whose return value is used **without an explicit null check**, ask two questions:

1. **Can this method return null?**
2. **If it does, what happens to the calling code?**

Trace the return value from the call site to every subsequent use. If *any* use would throw a `NullPointerException` (or produce silent wrong behavior) when the value is null, flag it.

### Sources of Potential Null Returns

#### Deserialization Libraries (Gson, Jackson, etc.)

- `Gson.fromJson(content, type)` returns `null` when the input is `"null"`, empty, or whitespace.
- `ObjectMapper.readValue(...)` can return `null` for `"null"` JSON input.
- **Rule**: Always null-check or fallback-guard deserialization results before using them as collections, iterating, or passing to constructors.

```java
// BAD — null crashes new HashMap<>()
Map<String, String> entries = gson.fromJson(content, type);
Map<String, String> copy = new HashMap<>(entries);

// GOOD
Map<String, String> raw = gson.fromJson(content, type);
Map<String, String> entries = raw != null ? raw : Map.of();
```

#### Sling & AEM APIs

These methods are commonly used in AEM code and frequently return `null`:

| Call | Returns null when |
|------|------------------|
| `resource.adaptTo(T.class)` | The resource cannot be adapted to the requested type |
| `resourceResolver.getResource(path)` | Path does not exist in the repository |
| `page.getContentResource()` | Page has no `jcr:content` node |
| `valueMap.get(key, String.class)` | Key absent **and** no default supplied |
| `request.getParameter(name)` | Parameter absent from the request |
| `session.getNode(path)` | Node does not exist (also throws `PathNotFoundException`) |
| `PageManager.getPage(path)` | Path is not a CQ Page |
| `TagManager.resolve(tagId)` | Tag does not exist |

**Rule**: Never chain directly off these calls. Always check for null before accessing methods on the result.

```java
// BAD
resource.adaptTo(ValueMap.class).get("title", String.class);

// GOOD
ValueMap vm = resource.adaptTo(ValueMap.class);
if (vm != null) {
    String title = vm.get("title", String.class);
    ...
}
```

#### Java Standard Library

- `Map.get(key)` returns `null` for absent keys (use `getOrDefault` or `containsKey` check).
- `System.getProperty(name)`, `System.getenv(name)` return `null` when the property/variable is absent.
- `Class.getResourceAsStream(name)` returns `null` when the resource is not found.
- `Matcher.group(name)` returns `null` for non-participating groups.
- `Queue.poll()` / `Deque.peek()` return `null` on empty collections.

#### Custom / Project Methods

- Any method returning a reference type that is **not annotated `@NotNull`** must be treated as potentially null at the call site.
- A missing `@Nullable` annotation is not proof of non-null. Check the implementation.

### Vulnerable Call Patterns

#### Method chaining without null guards

```java
// RISKY — any step can return null
page.getContentResource().getValueMap().get("title", String.class);
```

Decompose chains and null-check each step that can return null.

#### Passing to constructors that dereference immediately

```java
// RISKY — HashMap constructor calls result.size() → NPE if result is null
Map<String, T> copy = new HashMap<>(readEntries(resource));
```

#### Stream operations on a potentially null collection

```java
// RISKY — .stream() on null throws NPE
readEntries(resource).stream().filter(...).collect(...);
```

Use `Optional.ofNullable(...).map(Collection::stream).orElse(Stream.empty())` or null-check first.

#### Direct field/method access after an unchecked return

```java
// RISKY
String lang = resource.getValueMap().get("jcr:language", String.class);
if (lang.isEmpty()) { ... }   // NPE if lang is null
```

Use `StringUtils.isEmpty(lang)` (null-safe) or check for null first.

#### Assigning to a collection and immediately iterating

```java
// RISKY
List<T> items = getItems();   // can return null
for (T item : items) { ... }  // NPE
```

### AEM-Specific Null Propagation Patterns

#### adaptTo() chains

`adaptTo()` is one of the most common sources of null in AEM code. Flag any use where the result is not checked:

```java
// RISKY
ValueMap vm = resource.adaptTo(ValueMap.class);
return vm.get(PROPERTY_TITLE, StringUtils.EMPTY);

// SAFE
ValueMap vm = resource.adaptTo(ValueMap.class);
return vm != null ? vm.get(PROPERTY_TITLE, StringUtils.EMPTY) : StringUtils.EMPTY;
```

#### Page.getContentResource()

A page without a `jcr:content` node is structurally valid in the JCR. Always check:

```java
Resource content = page.getContentResource();
if (content == null) {
    return;
}
```

#### ResourceResolver.getResource() in loops

When iterating over paths from config or query results, each path may not exist:

```java
for (String path : configuredPaths) {
    Resource r = resolver.getResource(path);
    if (r == null) {
        log.debug("Resource not found: {}", path);
        continue;
    }
    // safe to use r here
}
```

### Safe Remediation Patterns

| Situation | Preferred fix |
|-----------|---------------|
| Deserialization result may be null | `result != null ? result : Collections.emptyMap()` or `Objects.requireNonNullElse(result, Map.of())` (Java 9+) |
| Map.get() result used as a string | `StringUtils.defaultString(map.get(key))` or `map.getOrDefault(key, StringUtils.EMPTY)` |
| Collection may be null before iteration | `CollectionUtils.emptyIfNull(collection)` |
| Optional wrapping | `Optional.ofNullable(x).orElse(fallback)` |
| Fail-fast on unexpected null | `Objects.requireNonNull(x, "Descriptive message")` |
| Chained call result | Decompose into local variables, check each |

**Prefer Apache Commons null-safe utilities** (`StringUtils`, `CollectionUtils`, `MapUtils`, `ObjectUtils`) over manual `!= null` checks wherever the library provides an equivalent.

### Null Safety Review Checklist

When reviewing a method that calls external code (libraries, Sling APIs, JCR APIs, or project helpers):

- [ ] Does this method's return value get used without a null check?
- [ ] Is the return value passed to a constructor, stream, or enhanced for-loop?
- [ ] Is a chained call made on the result without an intermediate null guard?
- [ ] Does the method's Javadoc or `@Nullable`/`@NotNull` annotation clarify nullability?
- [ ] If the method is from a third-party library (Gson, Sling, JCR), consult the library's contract — many standard APIs explicitly document null return conditions.

## String Identifier Normalization

Normalize string identifiers (locale codes, tags, enum-like strings) from external sources at construction time. Normalize values from any second source at the point of comparison and storage — never rely on both sides happening to use the same format by convention.

## Exception Propagation in Interface Implementations

Never silently catch a checked exception declared by an interface and return a sentinel value (null, -1, empty) instead. Doing so converts a diagnosable failure into a ghost value that crashes or misbehaves downstream. Propagate the exception, or wrap it  never swallow it.

## Javadoc and Signature Sync

When a method signature changes  parameters added, removed, or retyped; return type changed; `throws` clause widened or narrowed  update the Javadoc in the same change. Stale `@param`, `@return`, and `@throws` tags are a contract lie that misleads every caller.

## Volatile Field Access in Concurrent Contexts

When a `volatile` field can be nulled or invalidated by a concurrent path (e.g., a `@Deactivate` / shutdown method), always snapshot it into a local variable and use the local exclusively — never re-read the volatile after the null check. If the snapshotted object can still become invalid between the check and use, also catch the resulting exception (`RejectedExecutionException`, `IllegalStateException`, etc.) at the call site.

```java
// BAD — volatile field re-read after check; null or shutdown can race in between
if (scheduler != null && !scheduler.isShutdown()) {
    scheduler.submit(task);  // scheduler may be null or shut down here
}

// GOOD — snapshot once, guard once, catch residual race
ScheduledExecutorService s = scheduler;
if (s == null || s.isShutdown()) {
    return;
}
try {
    s.submit(task);
} catch (RejectedExecutionException e) {
    LOG.debug("Scheduler shut down concurrently; ignoring task");
}
```
