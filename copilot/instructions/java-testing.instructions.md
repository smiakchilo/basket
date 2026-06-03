---
description: "Use when writing, modifying, or reviewing Java unit tests. Covers JUnit 4/5, Mockito, AEM Mocks, wcm.io, test structure, naming, fixtures, and Sling Model testing."
applyTo: "**/src/test/**/*.java"
---

# Java Unit Testing Standards

## Before Writing Tests

1. Read the code under test carefully and understand its behavior and dependencies.
2. Study existing tests in the codebase — follow the same patterns and conventions strictly.
3. For every test case (method, utility, or class), identify the following scenarios:
   - Happy path (Valid input produces expected output);
   - Empty or missing input (e.g. empty string, null, empty collection) -- unless specifically annotated with `@NonNull` or similar;
   - Edge cases (boundary conditions, empty inputs, etc.);
   - Error cases (Invalid input, network failure, timeout, etc.);
   - Concurrency cases if applicable (e.g. multiple threads accessing the same method).

## Test Structure

- **Meaningful coverage**: test branches and error handling, not getters/setters.

- **Human-readable structure**: name test methods so a reader immediately understands what is being tested. Method names must be **≤6 words and < 50 characters**. If a first attempt exceeds either limit, rethink entirely — focus on what the code does, not on which method or parameter is involved. If it still exceeds, rethink again. The `WhenCondition` clause is only permitted when it is absolutely necessary to distinguish a method from another in the same class; prefer dropping it when the scenario is self-evident from the setup code. There is no `@DisplayName` escape hatch — the method name itself must fit. The only valid reason to exceed 50 characters is if the name at 50 characters would be identical to another test method in the same class, which is effectively impossible in practice.

- **Comprehensive methods over many tiny ones**: prefer fewer, well-organized test methods to a multitude of small single-assertion methods. Group closely related cases within the same method. DO NOT create a separate method for each case unless the cases are significantly different. This improves readability and makes tests easier to maintain and refactor.

  **Merging is mandatory in two cases:**

  - **Trigger A** — Two test methods exercise the **same code path** and differ only in which assertions they make (e.g. one verifies a method call, another verifies a stored property). Merge all assertions into a single test method.
  - **Trigger B** — Two test methods call the same production code with different literal input values but the same structural setup and the same assertion structure (only the literal values differ). These must be combined into a single test method using a loop (JUnit 4) or `@ParameterizedTest` / `@MethodSource` (JUnit 5). When two methods share ≥70% identical lines and differ only in literal values, merging or parameterization is **mandatory, not optional**.

  **Pre-writing gate**: before creating a new `@Test` method, scan existing test methods for structural duplicates. If one already covers the same code path, extend it rather than writing a new method.

- Use `@ParameterizedTest` (JUnit 5) or loops when iterating over similar inputs.

- **Separate Arrange–Act–Assert** sections with blank lines.

- **DRY — aggressively extract repeated code.** When multiple test methods share the same setup boilerplate (mock wiring, resource creation, request/response preparation, type casting, etc.) or the same assertion/verification pattern, extract the common logic into `private static` utility methods. Name factory-style helpers with a `new*` prefix (e.g. `newMockService()`, `newLayoutDefinition(int)`). Name assertion-style helpers with an `assert*` prefix (e.g. `assertLoginException(request, message)`). Move repeated setup into `@Before` / `@BeforeEach` when it applies to every test.

  This extraction can happen as a **late step** — after all test methods are written and coverage is confirmed — so you see which patterns truly repeat. If multiple methods contain 80 %+ identical boilerplate, the common logic **must** be extracted.

  When multiple test methods would each need `@SuppressWarnings` for the same tightly extractable operation (e.g. an unchecked cast), isolate that operation in a single utility method that carries the annotation instead of annotating every test method individually. When only one method needs a **single** warning, place the annotation directly on the **local variable declaration** rather than on the method. When a method needs more than one suppressing inside, place the annotation on the **method** instead.

- **Helper methods belong after all `@Test` methods.** All private helper and utility methods — whether `static` or instance — must appear at the bottom of the test class, below every `@Test` (and `@ParameterizedTest`) method. The ordering within the class is: fields → lifecycle methods (`@BeforeAll`, `@BeforeEach`, `@AfterEach`, `@AfterAll`) → `@Test` / `@ParameterizedTest` methods → utility/helper methods.

- **Keep helper signatures minimal.** Private helper methods (factories, builders, assertion utilities) must only accept parameters they actually use. If a parameter is no longer referenced in the method body, remove it. Similarly, do not assign a method's return value to a local variable if that variable is never read — call the method as a statement instead.

- **Only stub what the tests actually exercise.** Do not pre-emptively stub methods "for realism" if no test depends on that behavior. If a stub is only needed by some tests, set it up in those tests rather than in `@BeforeEach`.

- If every test method contains the same setup, move it to `@Before` / `@BeforeEach`.

- **Minimal comments only.** No Javadoc on the test class, no obvious narration (e.g. `// set up request`, `// call the method`, `// verify result`). A brief inline comment **is allowed** when it explains **what specific condition or edge case** is being tested and that context is not already obvious from the test method name and setup code — for example, `// two resources with the same title to verify unique ID generation` or `// null child forces the fallback branch`. Before adding a comment, verify it adds to human readability rather than restating what the code already shows.

- **DO NOT create class-wide fields for single-method usage.**
  If a variable (including `@Mock` fields) is referenced only inside one method (e.g. `@BeforeEach setUp()`), it **must** be declared as a local variable inside that method, not as a class field.
  Audit every `@Mock` field and every other class-level variable: if it appears only in one method, inline it.

  Bad — field used only in `setUp()`:
  ```java
  @Mock
  private ServiceFactory serviceFactory; // ✗ only used in setUp()

  @BeforeEach
  void setUp() {
      when(serviceFactory.getService(any())).thenThrow(new LoginException());
      context.registerService(ServiceFactory.class, serviceFactory);
  }
  ```

  Good — local mock inside the only method that needs it:
  ```java
  @BeforeEach
  void setUp() {
      ServiceFactory serviceFactory = Mockito.mock(ServiceFactory.class); // ✓
      when(serviceFactory.getService(any())).thenThrow(new LoginException());
      context.registerService(ServiceFactory.class, serviceFactory);
  }
  ```

## General Rules

- **NEVER modify any `pom.xml` file.** When writing or updating tests, work only with source files under `src/test/`. If a dependency appears to be missing, use whatever is already on the classpath — do not add, remove, or change any dependency declaration, plugin configuration, or build property.

- **DO NOT** use real I/O or external services.

- **DO NOT** use reflective access unless absolutely necessary.

- **DO NOT** use fully qualified names in code; use imports instead.

- **DO NOT** use static imports **except** for assertion methods (`org.junit.Assert.*`, `org.junit.jupiter.api.Assertions.*`, and similar assertion libraries). **DO NOT** use static imports for Mockito methods (`Mockito.*`), AEM Mocks methods, or any other utility methods. 

- **DO NOT** test framework-guaranteed behavior. If an OSGi component is registered with a specific event topic or filter, do not write tests that send events with a wrong topic — the framework guarantees the component will never receive them. Only test the logic the class itself implements.

- **DO NOT** use `@MockitoSettings(strictness = Strictness.LENIENT)`. If Mockito reports unnecessary stubbings, remove the stub rather than suppressing the warning. Lenient mode hides setup problems.

- **Never call a method that itself sets up Mockito stubs inside a `thenReturn()` argument expression.** Extract the inner stub setup to a separate statement before the outer `when()` call.
  Bad:
  ```java
  when(service.getConfig()).thenReturn(buildConfig()); // ✗ buildConfig() calls when(...).thenReturn(...) internally
  ```
  Good:
  ```java
  Config config = buildConfig(); // ✓ inner stubs complete first
  when(service.getConfig()).thenReturn(config);
  ```

- **Exhaust the [Mock Avoidance Hierarchy](#mock-avoidance-hierarchy) before every `Mockito.mock()`.** Consider in order: AemContext/Sling testing libraries → real `…Impl` from the project → inline makeshift implementation → custom `AdapterFactory`. Only after all four are ruled out is `Mockito.mock()` acceptable.

- **DO NOT** add string messages to assertion calls (e.g. `assertNotNull(x, "message")`). Assertion messages add noise; clear test names and obvious assertion targets are sufficient.

- **Use descriptive exception messages in tests.** String literals passed as exception messages (e.g. `new IllegalArgumentException(...)`) must be meaningful and readable — never a placeholder like `"test"`, `"error"`, or `"value"`.

- **Test callback wiring, not manual invocation.** When a method accepts callback parameters (e.g. an `onFailure` consumer), verify that the callback was actually passed to the underlying API using `ArgumentCaptor`, rather than capturing the main lambda and manually invoking it in a try-catch to trigger the error path. Use `Mockito.doAnswer` to simulate the real calling code's behavior when you need to exercise how callbacks interact.

- When testing that a method does **not** throw an exception, use `Assertions.assertDoesNotThrow(() -> ...)` instead of just calling the method. This makes the intent explicit.

- **Name local variables after the test scenario state, not the expected assertion outcome.** The variable name should answer "what does this represent in the test setup?" rather than "what do I expect it to be?".

  ```java
  // DO — name reflects the scenario state (target resource exists)
  Resource existingTarget = provider.getResource(resolveContext, PATH_SOURCE, mockResourceContext, null);
  assertNotNull(existingTarget);

  // DO NOT — name reflects the expected assertion result
  Resource exactMatch = provider.getResource(resolveContext, PATH_SOURCE, mockResourceContext, null);
  assertNotNull(exactMatch);
  ```

- **Extract method results to local variables before further calls.** When a method return value is used in more than one assertion, chained call, or helper method, assign it to a typed local variable first. If the value may be null, add a null check (or `assertNotNull` in test code) before calling methods on it. This rule applies equally to test methods, custom `assert*` helpers, and factory/lookup utilities — not only to inline assertions.
  Bad:
  ```java
  Assertions.assertNotNull(node.getChild("items"));
  Assertions.assertEquals(1, node.getChild("items").childCount()); // ✗ called twice, no null guard on chain
  ```
  Good:
  ```java
  ResourceNode items = node.getChild("items"); // ✓ captured once
  Assertions.assertNotNull(items);
  Assertions.assertEquals(1, items.childCount());
  ```

  Bad — utility helper chains without null guard:
  ```java
  private static Tag firstAnchorOf(Tag parent) {
      return parent.childAt(0).as(Tag.class); // ✗ NPE if childAt(0) returns null
  }
  ```
  Good — null-safe with local variable:
  ```java
  private static Tag firstAnchorOf(Tag parent) {
      Node node = parent.childAt(0);
      return node != null ? node.as(Tag.class) : null;
  }
  ```

- **Guard custom assertion helpers against null.** When a custom `assert*` utility receives an argument that may be null (e.g. the result of a lookup or helper), add `Assertions.assertNotNull(...)` as the first statement before asserting on its properties.
  Bad:
  ```java
  private static void assertAnchor(Tag anchor, String expectedId) {
      Assertions.assertEquals(expectedId, anchor.get("id")); // ✗ NPE if anchor is null
  }
  ```
  Good:
  ```java
  private static void assertAnchor(Tag anchor, String expectedId) {
      Assertions.assertNotNull(anchor);
      Assertions.assertEquals(expectedId, anchor.get("id"));
  }
  ```
- **Read primitives from `ValueMap` using primitive defaults.** When reading a boolean, int, long, double, etc. from a `ValueMap`, always pass a primitive literal as the default to `get()` so the return type is inferred as a primitive rather than a boxed type. This avoids both unboxing warnings and the need for a null check. Assign the result to a primitive local variable before asserting.

  Bad:
  ```java
  assertTrue(wrapper.getValueMap().get("composite", Boolean.FALSE)); // ✗ boxed, potential unboxing warning
  Boolean composite = wrapper.getValueMap().get("composite", Boolean.FALSE); // ✗ boxed, requires null check
  ```
  Good:
  ```java
  boolean composite = wrapper.getValueMap().get("composite", false); // ✓ primitive default → primitive result
  assertTrue(composite);
  ```

- **Use the most specific assertion.** Prefer `assertEquals` / `assertNotEquals` over boolean-wrapper assertions.
  Bad:
  ```java
  assertFalse(expected.equals(actual));  // ✗ hides intent
  ```
  Good:
  ```java
  assertNotEquals(expected, actual);     // ✓ clear intent, better failure message
  ```

- **Narrow `throws` declarations.** Only declare checked exceptions that the test body actually throws or that a called API forces. Do not add `throws Exception` or list unreachable checked exceptions as a blanket catch-all.

- **Do not assert what is already proven.** If earlier assertions logically imply a fact, do not add a redundant assertion for it. When verifying a filtered or reduced result, assert the expected size and the expected entries — that is sufficient. Do not additionally assert the absence of every excluded entry.

  Bad:
  ```java
  Map<String, Object> result = filter(data, new String[]{"title"});
  assertEquals("My Title", result.get("title"));
  assertNull(result.get("description")); // ✗ redundant — size assertion already proves this
  assertNull(result.get("count"));       // ✗ redundant
  ```
  Good:
  ```java
  Map<String, Object> result = filter(data, new String[]{"title"});
  assertEquals(1, result.size()); // ✓ proves no other keys exist
  assertEquals("My Title", result.get("title"));
  ```

- **Only add `@RunWith(MockitoJUnitRunner.class)` (JUnit 4) or `@ExtendWith(MockitoExtension.class)` (JUnit 5) when the class has `@Mock`, `@Spy`, or `@Captor` field annotations that require the runner to inject them.** When all mocks are created manually with `Mockito.mock()`, omit the runner/extension — even if Mockito is otherwise used. Remove it if it was added unnecessarily.

- **Maven Surefire enables Java assertions (`-ea`) by default.** `assert` statements in production code are live during test execution. Any `assert` guarding a service or resource (e.g. `assert settingsService != null`) will throw `AssertionError` if that dependency is not registered in the test context. Always register every OSGi service that production code guards with `assert`.

### Naming Convention

`should[ExpectedBehavior]` or `should[ExpectedBehavior]When[StateUnderTest]`.
Use the shorter form unless the `When` suffix is needed to disambiguate.
**Do not** prefix with the method-under-test name (e.g. `remoteServiceCall_shouldXxx` is wrong, just `shouldXxx`).
Keep behavior descriptions concise — use direct verbs and omit words already implied by the test class name. E.g. `shouldExecuteWhenPathMatches` over `shouldSubmitExecutionWhenPathMatchesDistributedService`. In a class named `ResourceFactoryTest`, for example, words like "Build", "Resource", or "Factory" are already implied — `shouldIncludeExternalChildren` is correct, `shouldBuildResourceWithExternalChildrenIncluded` is not.
Describe the *observable behavior*, not the implementation mechanism that produces it. E.g. `shouldCollectFlatProperties` — not `shouldCollectFlatPropertiesWithSystemPropertiesExcluded` (the exclusion of system properties is an implementation detail, not the testable behavior).
Drop `When` conditions that merely restate what the expected behavior already implies. E.g. `shouldCreateResource` — not `shouldCreateResourceWhenItDoesNotExist` (creation implies non-existence). Similarly, `shouldUpdateExistingResource` — not `shouldUpdateExistingResourceWhenItAlreadyExists`.
Do **not** enumerate all possible return variants in the name using `OrNull`, `OrEmpty`, `OrFalse`, etc. — name the primary behavior only. E.g. `shouldReturnRelayResource` — not `shouldReturnRelayResourceOrNull`.
Do **not** append input conditions with `BasedOn…` or `DependingOn…` — these describe the mechanism, not the behavior. E.g. `shouldReturnRelayResource` — not `shouldReturnRelayResourceBasedOnPathAndTarget`.

### Grouping Example

Instead of separate methods for each minor use case like this:
```java
@Test
public void shouldCheckValidUser() {
    // Arrangement for valid user
    // Assertion
}
@Test
public void shouldCheckInvalidUser() {
    // Arrangement for invalid user
    // Assertion
}
```

...group them together when they are closely related:
```java
@Test
public void shouldCheckUserValidity() {
    // Arrangement for valid user
    // Assertion

    // Arrangement for invalid user
    // Assertion
}
```

Or use parameterized tests:
```java
@ParameterizedTest
@ValueSource(strings = {"one,two,three", "one;two;three"})
public void shouldParseSettings(String settings) {
    // test code
}
```

## Mock Avoidance Hierarchy

Every `Mockito.mock()` call is a liability. Mocks hide integration bugs, drift from real behavior over time, and make tests brittle. **Treat every mock as a last and dire resort.** Before writing `Mockito.mock(...)`, stop and walk through the following hierarchy top-to-bottom. Use the **first** level that can satisfy the dependency:

1. **AemContext / Sling testing libraries** — Use `context.request()`, `context.resourceResolver()`, `MockResourceResolver`, `MockSlingHttpServletRequest`, and other real implementations provided by AemContext and the Sling testing libraries. These are not mocks — they are functional implementations.

2. **Real `…Impl` class from the project** — Search the codebase for a concrete implementation of the interface. Register it with `context.registerService(Interface.class, new ConcreteImpl())` or `context.registerInjectActivateService(new ConcreteImpl(), props)`. A real class exercised in a test catches real bugs.

3. **Inline makeshift implementation** — If the dependency is an interface with a small surface area (1–3 methods used by the code under test), create an anonymous class or a `private static` inner class right in the test file that implements the interface with minimal real logic. This is still vastly preferable to a mock because it preserves type safety and makes the test's intent explicit.

   ```java
   private static class StubLinkHandler implements LinkHandler {
       @Override
       public String resolveLink(String path) {
           return path; // passthrough — enough for the code under test
       }
   }
   ```

4. **Custom `AdapterFactory`** — If the code under test calls `.adaptTo(CustomType.class)`, create a lightweight `AdapterFactory` implementation in the test class and register it with `context.registerService(AdapterFactory.class, factory)`. This makes `adaptTo()` work naturally without mocking the adaptation target or the adaptable.

   ```java
   context.registerAdapter(Resource.class, CustomModel.class,
       (resource) -> new CustomModel(resource));
   ```

5. **`Mockito.mock()` — absolute last resort** — Only when levels 1–4 are genuinely infeasible: the dependency is a complex third-party class whose constructor is inaccessible, the class has deep internal state that cannot be replicated, or the test specifically needs `Mockito.verify()` to confirm an interaction when there is no observable state change. **Every mock must be justified by the inability to use levels 1–4.**

This hierarchy is **mandatory**. It is not a suggestion or a preference. When reviewing test code, every `Mockito.mock()` and `@Mock` annotation must be traceable to a genuine inability to use a higher level in the hierarchy.

## AEM / Sling Mocks

Use the version of AEM Mocks and JUnit declared in the project POM. Refer to [wcm.io AEM Mocks](https://wcm.io/testing/aem-mock/junit5/apidocs) for available methods and further information.

### AemContext setup

`AemContext` (wcm.io) **is** the AEM test environment — it is not a mock. Always declare it as `public final`:

```java
@Rule
public final AemContext context = AemContextBuilder().resourceResolverType(ResourceResolverType.JCR_MOCK).build();
```

Choose the resolver type based on what the test needs:

- **`JCR_MOCK`** (default) — use when neither JCR operations (querying, persisting nodes) nor `javax.jcr` classes are needed.
- **`JCR_OAK`** — use when JCR operations or `javax.jcr` classes are required (e.g. obtaining a `Session`, running JCR queries).

### AemContext entities to use

Use the following `AemContext` accessors and helpers instead of mocking. **Never mock or spy on any of these** — `AemContext` provides functional implementations backed by `MockResourceResolver`, `MockSlingHttpServletRequest`, `MockSlingScriptHelper`, and other Sling testing library classes.

| Need | How to obtain |
|---|---|
| `SlingHttpServletRequest` | `context.request()` |
| `SlingHttpServletResponse` | `context.response()` |
| `ResourceResolver` | `context.resourceResolver()` |
| `javax.jcr.Session` | `context.resourceResolver().adaptTo(Session.class)` — requires `JCR_OAK` |
| `Resource` / resource tree | `context.create().resource(path, props)` or `context.load().json(...)` |
| OSGi service | `context.registerService(Interface.class, impl)` or `context.registerInjectActivateService(impl)` |
| `.adaptTo(CustomType.class)` support | `context.registerAdapter(Adaptable.class, CustomType.class, fn)` |
| Independent `ResourceResolver` | `MockResourceResolverFactory` / `MockResourceResolver` — **not** `Mockito.spy(context.resourceResolver())` |

When building resource trees, create child resources via the parent `Resource` reference — `context.create().resource(parent, "childName", ...)` — rather than concatenating path strings.

After creating resources programmatically (via `context.create().resource(...)` or similar), call `context.resourceResolver().commit();` to persist the pending changes before the code under test runs. 

If the code under test calls an AEM class method in a non-standard way (e.g. a `Session` that throws on commit), mocking that specific class at the **test-method level** is acceptable. Do not promote such mocks to class-level fields.

For all remaining mock-vs-real decisions, follow the [Mock Avoidance Hierarchy](#mock-avoidance-hierarchy).

**Project-own `@Component` services are not auto-registered.** Sling Testing Mocks scans OSGi descriptors only from JAR files on the classpath — it does **not** scan classpath directories like `target/classes/OSGI-INF/`. Any service declared with `@Component` in the project under test must be registered explicitly in `setUp()`:

```java
context.registerService(Injector.class, new MyCustomInjector());
```

### Troubleshooting

If you encounter a "Invalid namespace prefix" error with `ResourceResolverType.JCR_OAK`, register the namespace in the set-up method:

```java
Session session = context.resourceResolver().adaptTo(Session.class);
assertNotNull(session);
session.getWorkspace().getNamespaceRegistry().registerNamespace("granite", "http://www.adobe.com/jcr/granite/1.0");
```

**`resourceResolver.resolve(null)` returns `/`, not a non-existing resource.** In Sling Testing Mocks, resolving a `null` path returns the root node, which passes any `resourceExists()` check. When production code calls `resourceExists(resolver, path)` and `path` is an `@ValueMapValue` that was not set in the test, the "resource not found" early return is bypassed. Ensure either that all authored path properties are set to a non-existent-but-valid path string in the test fixture, or that the production code null-checks the path before resolving.

## Fixtures

- Provide fixtures under `src/test/resources`; use `context.load().json(...)`.
- Prefer existing JSON fixtures when they can be reused, even if they contain more data than a particular test requires. DO NOT create multiple mostly-similar fixtures. Fewer files in the code base is better. 

## Sling Model Testing

Adapt from a resource instead of using constructors or reflection:
```java
Resource myResource = new VirtualMapResource(
    context.resourceResolver(),
    "/content/myResource",
    "my/resource/type",
    new ValueMapDecorator(Collections.singletonMap("text", "Hello world")));
MyModel model = myResource.adaptTo(MyModel.class);
```

**`@Source("injector-name")` is a hard requirement regardless of injection strategy.** When a Sling Model field is annotated with `@Source("some-injector")`, Sling Models throws `IllegalArgumentException` if no injector with that name is registered — even when `DefaultInjectionStrategy.OPTIONAL` is set. OPTIONAL guards against a missing *value*, not a missing *injector*. A missing named injector causes the entire model creation to fail and `adaptTo()` to return `null`. Register every custom injector the model uses explicitly in `setUp()`:

```java
context.registerService(Injector.class, new RTModelInjector());
```

**When `adaptTo()` returns `null`, use `ModelFactory.createModel()` to reveal the true cause.** `adaptTo()` swallows the underlying exception silently. `ModelFactory.createModel()` throws it, exposing the full message and cause chain:

```java
ModelFactory modelFactory = context.getService(ModelFactory.class);
MyModel model = modelFactory.createModel(context.request(), MyModel.class); // throws with details on failure
```

## Method Grouping and Section Dividers

When a test class has more than ~10 test methods, organize test methods into named sections to make the class navigable and reviewable.

**Section names** must be human-readable captions describing what the grouped tests exercise — not cited method signatures. Use noun phrases or gerunds that answer *"what is this group of tests about?"*:

| Good (caption) | Bad (method name) |
|---|---|
| `Activation` | `activate()` |
| `Resource retrieval` | `getResource()` |
| `Error handling` | `onError() and onSuppressedError()` |
| `Lifecycle` | `start() / stop()` |
| `Configuration update` | `update()` |

**How to group**:

1. Identify the natural sections of the class under test — typically one section per public method or closely related group of methods. Large methods may be split by scenario category.
2. Within each section, order methods:
   - Happy-path cases first (target exists, mapping succeeds, normal return, etc.)
   - Boundary/edge cases next (exact root path, empty collection, self-mapping, etc.)
   - Error/fallback paths last (target missing, parent fallback, exception thrown, etc.)
3. Put lifecycle sections (`Activation`, `Deactivation`, `Configuration update`) in the order they occur at runtime.
4. Put cross-cutting concerns (e.g. user-resolver mapping) in their own sections at the end.

**Section divider format** — mandatory per `java-code.instructions.md`:

```java
/* ----------------
   Section name here
   ---------------- */
```

Rules:
- Use a `/* ... */` block comment, never `//`.
- The number of dashes on each dash-row equals **exactly** the character count of the section name (count carefully — spaces and punctuation included).
- The section name line is indented 3 spaces to align with the `/* ` prefix.
- Place the divider immediately before the first `@Test` of the section, with a blank line separating it from both the previous method and the next `@Test`.

**Dash-count verification** — count the section name characters explicitly before writing the dashes. Off-by-one errors are easy to introduce and easy to catch:
- `Resource retrieval` → 18 chars → 18 dashes
- `Error handling` → 14 chars → 14 dashes
- `Activation` → 10 chars → 10 dashes

**Note on the "Minimal comments only" rule**: The prohibition on section separators in the [Test Structure](#test-structure) section targets trivial narration comments like `/* getResource tests */`. It does **not** prohibit proper structural dividers in the format above, which are a code-organization tool, not narration. Proper dividers are always appropriate when the class has multiple logical groups.