# Maven Repository Layout Reference

## Local Repository (`~/.m2/repository`)

Artifacts are stored at:

```
~/.m2/repository/<groupId-as-path>/<artifactId>/<version>/<artifactId>-<version>[-<classifier>].<extension>
```

**Group ID path conversion**: dots become directory separators.

| Group ID | Path |
|----------|------|
| `org.apache.commons` | `org/apache/commons` |
| `com.google.guava` | `com/google/guava` |

**Examples**:

| Artifact | Local Path |
|----------|------------|
| `commons-lang3-3.12.0.jar` | `~/.m2/repository/org/apache/commons/commons-lang3/3.12.0/commons-lang3-3.12.0.jar` |
| `commons-lang3-3.12.0-sources.jar` | `~/.m2/repository/org/apache/commons/commons-lang3/3.12.0/commons-lang3-3.12.0-sources.jar` |
| `guava-32.1.3-jre.jar` | `~/.m2/repository/com/google/guava/guava/32.1.3-jre/guava-32.1.3-jre.jar` |

## Maven Central URL Template

Base URL: `https://repo1.maven.org/maven2/`

```
https://repo1.maven.org/maven2/<groupId-as-path>/<artifactId>/<version>/<artifactId>-<version>[-<classifier>].jar
```

**Examples**:

| Artifact | URL |
|----------|-----|
| Main JAR | `https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/3.12.0/commons-lang3-3.12.0.jar` |
| Sources | `https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/3.12.0/commons-lang3-3.12.0-sources.jar` |
| Javadoc | `https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/3.12.0/commons-lang3-3.12.0-javadoc.jar` |
| POM | `https://repo1.maven.org/maven2/org/apache/commons/commons-lang3/3.12.0/commons-lang3-3.12.0.pom` |

## Classifiers

| Classifier | Contents | Extension |
|------------|----------|-----------|
| *(none)* | Compiled classes | `.jar` |
| `sources` | Java source files | `.jar` |
| `javadoc` | Javadoc HTML | `.jar` |
| `tests` | Test classes | `.jar` |
| `test-sources` | Test source files | `.jar` |

## Limitations

- **Maven Central only**: The HTTP fallback path in the fetch script targets `repo1.maven.org`. Private/enterprise repos require Maven CLI (`dependency:copy`) which respects `settings.xml` mirrors and credentials.
- **SNAPSHOTs**: Snapshot versions use timestamped filenames in remote repos (e.g., `1.0-20231015.123456-1.jar`). The fetch script does not handle snapshot timestamp resolution — use Maven CLI for snapshots.
