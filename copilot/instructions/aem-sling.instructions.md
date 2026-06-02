---
description: "Use when working with AEM components, Apache Sling, OSGi services, Sling Models, JCR nodes, or Adobe Granite APIs. Covers Sling Model annotations, OSGi Declarative Services, and AEM-specific idioms."
applyTo: "**/*.java"
---

# AEM / Sling / OSGi Conventions

## Sling Models

- Use `@Model` with explicit `adaptables` and `adapters`.
- **DO NOT use `@Inject`** on fields or setter methods. Use specific injector annotations that convey intent:
  - `@ValueMapValue` — JCR properties
  - `@ChildResource` — child resources
  - `@ScriptVariable` — HTL bindings (e.g., `currentPage`, `resource`)
  - `@ResourcePath` — resource paths
  - `@SlingObject` — Sling objects (`ResourceResolver`, `SlingHttpServletRequest`)
  - `@OSGiService` — OSGi service references
  - `@Self` — the adaptable itself
- `@Inject` is acceptable **only** on constructor parameters where a specific injector annotation is not applicable.
- Use `@PostConstruct` for initialization logic.
- Prefer `defaultInjectionStrategy = OPTIONAL` at the model level only when most fields are optional; otherwise annotate individual fields with `@Optional`.

## OSGi Declarative Services

- Use OSGi DS annotations: `@Component`, `@Activate`, `@Deactivate`, `@Modified`, `@Reference`.
- Use `@Designate` with `@ObjectClassDefinition` for component configuration.
- Prefer constructor injection or `@Activate`-annotated methods for configuration binding.
- **No mutable instance fields in `@Component` services without synchronization.** OSGi services are singletons shared across threads; any field written after activation must be `volatile`, `AtomicXxx`, or guarded by `synchronized`.
- Verify `@Reference` cardinality and policy match actual usage: use `MANDATORY` only when the service is guaranteed to be present; use `DYNAMIC` policy when the service may come and go at runtime.

## OSGi Service Utilities

- When resolving `BundleContext` via `FrameworkUtil.getBundle(...)` inside a utility or helper class, always pass the **utility's own class** (e.g. `FrameworkUtil.getBundle(MyUtil.class)`), not the target service interface or any other class passed in by the caller. Service interfaces often live in API-only bundles that carry no `BundleContext`; the utility's own bundle is always reliably loaded in the running OSGi container.

  ```java
  // DO
  Bundle bundle = FrameworkUtil.getBundle(ServiceUtil.class);

  // DO NOT — serviceClass may be from an API bundle with no BundleContext
  Bundle bundle = FrameworkUtil.getBundle(serviceClass);
  ```

## General AEM Patterns

- Prefer `SlingHttpServletRequest` adaptations over direct JCR `Session` access.
- Use `PageManager`, `TagManager`, and other AEM APIs through proper service references or request adaptation.

## Security

- **JCR-SQL2 / XPath injection**: Never concatenate user-supplied values into query strings. Use parameterized `Query` API (`query.bindValue(...)`) or restrict input to a known-safe allowlist.
- **Service users**: Use the minimal-privilege sub-service user for `ResourceResolverFactory.getServiceResourceResolver(...)`. Never use the `admin` sub-service or a user with write access when only read is required.
- **Path traversal**: Validate and normalize any resource path derived from user input before passing it to `ResourceResolver.getResource(...)` or JCR `Session.getNode(...)`.

## OSGi Configuration Files

- The PID in the filename (e.g. `com.example.MyService.cfg.json`) must match the fully-qualified class name of the `@Component` or the `pid` attribute of `@Designate`.
- Property names in the config file must exactly match the method names defined in the `@ObjectClassDefinition` interface.
- Configuration files committed to source control must not contain localhost URLs, hardcoded credentials, or debug flags intended only for local development.
