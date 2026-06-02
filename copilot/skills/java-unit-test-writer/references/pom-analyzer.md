# POM Analyzer — Worker Subagent Protocol

> **Purpose**: This document is read by a **worker-model subagent** invoked during the Environment Fact Sheet blocking step of the java-unit-test-writer skill. The subagent extracts the project's AEM version and all test-scoped dependencies from the Maven POM.

## Steps

1. Read the module `pom.xml` (typically at `<project-root>/core/pom.xml` or the nearest `pom.xml`).
   If there is a `<parent>` reference, also read the parent `pom.xml` to resolve inherited properties and dependency versions.

2. Extract the AEM version:
   a. Look for `com.adobe.aem:aem-sdk-api` or `com.adobe.aem:uber-jar` in `dependencies` or `dependencyManagement`.
   b. If `aem-sdk-api` is found → `AEM_VERSION` is `AEMaaCS`.
   c. If `uber-jar` is found → `AEM_VERSION` is the version string (e.g. `6.5.x` or `6.6.x`).
   d. If neither is found → `AEM_VERSION` is `unknown`.

3. Extract ALL test-scoped dependencies. For each, record:
   - `groupId:artifactId`
   - version (resolved — follow property references like `${mockito.version}` to their value)

4. From the test-scoped dependencies, identify specifically:
   - `JUNIT_VERSION`: `4` if `junit:junit` is present; `5` if `org.junit.jupiter:junit-jupiter` is present; `both` if both are present.
   - `AEM_MOCK_GAV`: the `groupId:artifactId:version` of any `io.wcm` AEM mock dependency (e.g. `io.wcm:io.wcm.testing.aem-mock.junit5:5.x.x`)
   - `SLING_MOCK_GAV`: the `groupId:artifactId:version` of any `org.apache.sling` mock dependency, or `none`
   - `MOCKITO_GAV`: the `groupId:artifactId:version` of `org.mockito:mockito-core` or `org.mockito:mockito-junit-jupiter`, or `none`

5. Return exactly this JSON:
   ```json
   {
     "aem_version": "<AEMaaCS or version string or unknown>",
     "junit_version": "<4 | 5 | both>",
     "aem_mock_gav": "<groupId:artifactId:version or none>",
     "sling_mock_gav": "<groupId:artifactId:version or none>",
     "mockito_gav": "<groupId:artifactId:version or none>",
     "test_dependencies": ["<groupId:artifactId:version>", ...]
   }
   ```
