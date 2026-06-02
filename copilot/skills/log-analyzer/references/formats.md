# Log Format Reference

## Format 1: AEM Error Log (`aem-error`)

### Pattern

```
DD.MM.YYYY HH:mm:ss.SSS [pod-name] *LEVEL* [thread-name] logger.class.name message text
```

### Example

```
23.04.2026 00:00:30.000 [cm-p149356-e1522219-aem-author-d77d46ffc-zngs2] *INFO* [sling-default-4-Registered Service.5615] com.adobe.granite.taskmanagement.impl.jcr.TaskArchiveService archiving tasks at: 'Thu Apr 23 00:00:30 UTC 2026'
```

### Regex (named groups)

```
^(?<Timestamp>\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3})\s\[(?<Pod>[^\]]+)\]\s\*(?<Level>[A-Z]+)\*\s\[(?<Thread>.+)\]\s(?<Logger>\S+\.\S+)\s(?<Message>.*)$
```

> **Nested brackets:** The Thread field can contain nested `[…]` when the thread
> is an HTTP request processing thread, e.g.
> `[93.159.26.119 [1776925919335] GET /path HTTP/1.1]`.
> The greedy `.+` in the Thread group backtracks to the last `]` that precedes
> a Logger token containing a dot, correctly handling both simple and nested cases.

### Fields

| Group     | Description                          | Example                                                       |
|-----------|--------------------------------------|---------------------------------------------------------------|
| Timestamp | `DD.MM.YYYY HH:mm:ss.SSS`           | `23.04.2026 00:00:30.000`                                    |
| Pod       | Kubernetes pod name                  | `cm-p149356-e1522219-aem-author-d77d46ffc-zngs2`             |
| Level     | Log level (INFO, WARN, ERROR, DEBUG, TRACE) | `INFO`                                                |
| Thread    | Thread name                          | `sling-default-4-Registered Service.5615`                    |
| Logger    | Fully qualified logger class name    | `com.adobe.granite.taskmanagement.impl.jcr.TaskArchiveService` |
| Message   | Free-form message text               | `archiving tasks at: 'Thu Apr 23 00:00:30 UTC 2026'`        |

### Timestamp Parsing

```powershell
[datetime]::ParseExact($ts, 'dd.MM.yyyy HH:mm:ss.fff', [System.Globalization.CultureInfo]::InvariantCulture)
```

### Multiline Continuation

Stack traces and multiline messages appear as continuation lines that do **not** match the entry-start pattern. A continuation line is any line that does NOT start with `\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3}`.

Entry-start anchor regex: `^\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3}\s`

---

## Format 2: Apache HTTPD Access Log (`httpd-access`)

### Pattern

```
pod-name client-ip - DD/Mon/YYYY:HH:mm:ss +0000 "METHOD path HTTP/1.1" status size "referer" "user-agent"
```

### Example

```
cm-p149356-e1522218-aem-publish-85d8cddd8-qwqqr 35.187.15.33 - 26/Nov/2025:23:58:12 +0000 "GET /services/hpe/asset.json?id=f92c2931 HTTP/1.1" 200 346 "https://www.hpe.com/page.html" "Mozilla/5.0 ..."
```

### Regex (named groups)

```
^(?<Pod>\S+)\s(?<ClientIP>\S+)\s-\s(?<Timestamp>\d{2}/[A-Za-z]{3}/\d{4}:\d{2}:\d{2}:\d{2}\s[+\-]\d{4})\s"(?<Method>[A-Z]+)\s(?<Path>[^\s"]+)\s(?<Protocol>[^"]+)"\s(?<Status>\d{3})\s(?<Size>\d+|-)\s"(?<Referer>[^"]*)"\s"(?<UserAgent>[^"]*)"$
```

### Fields

| Group     | Description                | Example                                              |
|-----------|----------------------------|------------------------------------------------------|
| Pod       | Kubernetes pod name        | `cm-p149356-e1522218-aem-publish-85d8cddd8-qwqqr`   |
| ClientIP  | Client IP address          | `35.187.15.33`                                       |
| Timestamp | `DD/Mon/YYYY:HH:mm:ss ±HHMM` | `26/Nov/2025:23:58:12 +0000`                      |
| Method    | HTTP method                | `GET`                                                |
| Path      | Request path + query       | `/services/hpe/asset.json?id=f92c2931`               |
| Protocol  | HTTP protocol version      | `HTTP/1.1`                                           |
| Status    | HTTP status code           | `200`                                                |
| Size      | Response body size (bytes) | `346`                                                |
| Referer   | Referer header             | `https://www.hpe.com/page.html`                      |
| UserAgent | User-Agent header          | `Mozilla/5.0 ...`                                    |

### Timestamp Parsing

```powershell
[datetime]::ParseExact($ts, 'dd/MMM/yyyy:HH:mm:ss zzz', [System.Globalization.CultureInfo]::InvariantCulture)
```

### Multiline Continuation

None. Each entry is a single line.

---

## Format 3: Apache Dispatcher Log (`dispatcher`)

### Pattern

```
[DD/Mon/YYYY:HH:mm:ss +0000] [I] [pod-name] "METHOD path" status timems [farm/N] [actionXXX] hostname
```

### Example

```
[26/Nov/2025:23:58:13 +0000] [I] [cm-p149356-e1522218-aem-publish-85d8cddd8-vssrl] "GET /content/dam/hpe/shared-publishing/images-norend/9xx/998473628-1-1.jpg.hpetransform/bounded-resize:width=150/image.orig" 404 21ms [hpe_publishfarm/0] [actionnone] www.hpe.com
```

### Regex (named groups)

```
^\[(?<Timestamp>\d{2}/[A-Za-z]{3}/\d{4}:\d{2}:\d{2}:\d{2}\s[+\-]\d{4})\]\s\[(?<Severity>[A-Z])\]\s\[(?<Pod>[^\]]+)\]\s"(?<Method>[A-Z]+)\s(?<Path>[^"]+)"\s(?<Status>\d{3})\s(?<Duration>\d+)ms\s\[(?<Farm>[^\]]+)\]\s\[(?<Action>[^\]]+)\]\s(?<Host>\S+)$
```

### Fields

| Group     | Description                     | Example                                                        |
|-----------|---------------------------------|----------------------------------------------------------------|
| Timestamp | `DD/Mon/YYYY:HH:mm:ss ±HHMM`  | `26/Nov/2025:23:58:13 +0000`                                  |
| Severity  | Single-letter severity (I/W/E/D/T) | `I`                                                        |
| Pod       | Kubernetes pod name             | `cm-p149356-e1522218-aem-publish-85d8cddd8-vssrl`             |
| Method    | HTTP method                     | `GET`                                                          |
| Path      | Request path                    | `/content/dam/hpe/.../image.orig`                              |
| Status    | HTTP status code                | `404`                                                          |
| Duration  | Response time in milliseconds   | `21`                                                           |
| Farm      | Dispatcher farm configuration   | `hpe_publishfarm/0`                                            |
| Action    | Dispatcher action taken         | `actionnone`                                                   |
| Host      | Virtual host / hostname         | `www.hpe.com`                                                  |

### Timestamp Parsing

```powershell
[datetime]::ParseExact($ts, 'dd/MMM/yyyy:HH:mm:ss zzz', [System.Globalization.CultureInfo]::InvariantCulture)
```

### Multiline Continuation

None. Each entry is a single line.

---

## Detection Strategy

To auto-detect the format, read the first 10 non-empty lines of the file and test each against the entry-start anchors in this order (most specific first):

1. **AEM error**: `^\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3}\s\[`
2. **Dispatcher**: `^\[\d{2}/[A-Za-z]{3}/\d{4}:\d{2}:\d{2}:\d{2}\s[+\-]\d{4}\]\s\[[A-Z]\]`
3. **HTTPD access**: `^\S+\s\d+\.\d+\.\d+\.\d+\s-\s\d{2}/[A-Za-z]{3}/\d{4}:`

The first pattern that matches the majority of non-empty sample lines determines the format.
