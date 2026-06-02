<#
.SYNOPSIS
    Count and rank occurrences of patterns or fields in a log file.

.DESCRIPTION
    Streams a log file and groups entries by a specified field or regex
    capture group, then outputs a frequency table sorted by count (descending).
    Useful for finding top error types, busiest loggers, most-hit URLs,
    or most common HTTP status codes.

.PARAMETER Path
    Path to the log file.

.PARAMETER GroupBy
    Field to group by. Available fields depend on the log format:
      aem-error:    Level, Logger, Thread, Pod, ExceptionClass
      httpd-access: Status, Method, Path, ClientIP, Pod, UserAgent
      dispatcher:   Status, Method, Path, Host, Farm, Action, Severity, Duration

.PARAMETER CustomPattern
    A regex with a named capture group called 'Key' to use for grouping
    instead of a predefined field. Example: '(?<Key>com\.\w+\.\w+)'

.PARAMETER MaxResults
    Maximum number of groups to show. Default: 30.

.PARAMETER Format
    Log format override. Auto-detected if omitted.

.PARAMETER LevelFilter
    Optional: only count entries at these log levels (AEM error format only).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [string]$GroupBy,
    [string]$CustomPattern,
    [int]$MaxResults = 30,
    [string]$Format,
    [string[]]$LevelFilter
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $GroupBy -and -not $CustomPattern) {
    Write-Error "Specify either -GroupBy or -CustomPattern."
    return
}

# --- Auto-detect format ---
if (-not $Format) {
    $detected = & "$scriptDir\detect-format.ps1" -Path $Path
    $Format = $detected.Format
}

# --- Build extraction regex for the field ---
$fieldPatterns = @{
    'aem-error' = @{
        Level          = '\*(?<Key>[A-Z]+)\*'
        Logger         = '^\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3}\s\[[^\]]+\]\s\*[A-Z]+\*\s\[.+\]\s(?<Key>\S+\.\S+)'
        Thread         = '^\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3}\s\[[^\]]+\]\s\*[A-Z]+\*\s\[(?<Key>.+)\]\s\S+\.\S+'
        Pod            = '^\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3}\s\[(?<Key>[^\]]+)\]'
        ExceptionClass = '(?<Key>\S+(?:Exception|Error|Throwable))\b'
    }
    'httpd-access' = @{
        Status    = '"\s(?<Key>\d{3})\s'
        Method    = '"(?<Key>[A-Z]+)\s'
        Path      = '"[A-Z]+\s(?<Key>[^\s?"]+)'
        ClientIP  = '^\S+\s(?<Key>\d+\.\d+\.\d+\.\d+)'
        Pod       = '^(?<Key>\S+)\s\d'
        UserAgent = '"(?<Key>[^"]*)"$'
    }
    'dispatcher' = @{
        Status   = '"\s(?<Key>\d{3})\s'
        Method   = '"(?<Key>[A-Z]+)\s'
        Path     = '"[A-Z]+\s(?<Key>[^"]+)"'
        Host     = '\]\s(?<Key>\S+)$'
        Farm     = '\[(?<Key>[^\]]+/\d+)\]'
        Action   = '\[(?<Key>action[^\]]+)\]'
        Severity = '\[(?<Key>[A-Z])\]\s\['
        Duration = '\s(?<Key>\d+)ms\s'
    }
}

$extractPattern = $null
if ($CustomPattern) {
    $extractPattern = $CustomPattern
} elseif ($fieldPatterns.ContainsKey($Format) -and $fieldPatterns[$Format].ContainsKey($GroupBy)) {
    $extractPattern = $fieldPatterns[$Format][$GroupBy]
} else {
    $available = if ($fieldPatterns.ContainsKey($Format)) { $fieldPatterns[$Format].Keys -join ', ' } else { '(unknown format)' }
    Write-Error "Unknown GroupBy field '$GroupBy' for format '$Format'. Available: $available"
    return
}

# --- Level filter setup ---
$entryStartPattern = switch ($Format) {
    'aem-error'    { '^\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3}\s\[' }
    'httpd-access' { '^\S+\s\d+\.\d+\.\d+\.\d+' }
    'dispatcher'   { '^\[' }
}

$levelSet = $null
if ($LevelFilter) {
    $levelSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($l in $LevelFilter) { $null = $levelSet.Add($l) }
}

$levelRegex = '\*([A-Z]+)\*'

# --- Stream and count ---
$counts = @{}
$totalEntries = 0
$matchedEntries = 0
$isMultiline = ($Format -eq 'aem-error')

$reader = [System.IO.StreamReader]::new($Path, [System.Text.Encoding]::UTF8, $true)
try {
    $currentEntryFirstLine = $null
    $currentEntryLines = if ($GroupBy -eq 'ExceptionClass') {
        [System.Collections.Generic.List[string]]::new()
    } else { $null }
    $lineNum = 0

    while ($null -ne ($line = $reader.ReadLine())) {
        $lineNum++
        $isEntryStart = $line -match $entryStartPattern

        if ($isEntryStart) {
            # For ExceptionClass grouping, check accumulated lines of previous entry
            if ($GroupBy -eq 'ExceptionClass' -and $currentEntryLines -and $currentEntryLines.Count -gt 0) {
                $foundKey = $false
                foreach ($eLine in $currentEntryLines) {
                    if ($eLine -match $extractPattern) {
                        $key = $Matches['Key']
                        if ($counts.ContainsKey($key)) { $counts[$key]++ } else { $counts[$key] = 1 }
                        $matchedEntries++
                        $foundKey = $true
                        break
                    }
                }
                $currentEntryLines.Clear()
            }

            $totalEntries++
            $currentEntryFirstLine = $line

            # Level filter
            if ($levelSet -and $Format -eq 'aem-error') {
                if ($line -match $levelRegex) {
                    $lvl = $Matches[1]
                    if (-not $levelSet.Contains($lvl)) {
                        $currentEntryFirstLine = $null
                        if ($currentEntryLines) { $currentEntryLines.Clear() }
                        continue
                    }
                }
            }

            # For non-ExceptionClass fields, extract from entry-start line
            if ($GroupBy -ne 'ExceptionClass') {
                if ($line -match $extractPattern) {
                    $key = $Matches['Key']
                    if ($counts.ContainsKey($key)) { $counts[$key]++ } else { $counts[$key] = 1 }
                    $matchedEntries++
                }
            } else {
                # Also check the first line for ExceptionClass
                $currentEntryLines.Add($line)
            }
        } else {
            # Continuation line — only relevant for ExceptionClass grouping
            if ($currentEntryLines -and $currentEntryFirstLine) {
                $currentEntryLines.Add($line)
            }
        }
    }

    # Flush last entry for ExceptionClass
    if ($GroupBy -eq 'ExceptionClass' -and $currentEntryLines -and $currentEntryLines.Count -gt 0) {
        foreach ($eLine in $currentEntryLines) {
            if ($eLine -match $extractPattern) {
                $key = $Matches['Key']
                if ($counts.ContainsKey($key)) { $counts[$key]++ } else { $counts[$key] = 1 }
                $matchedEntries++
                break
            }
        }
    }

} finally {
    $reader.Close()
    $reader.Dispose()
}

# --- Output ---
Write-Output "=== Frequency: GroupBy=$GroupBy, Format=$Format ==="
Write-Output "Total entries scanned: $totalEntries | Matched: $matchedEntries | Unique keys: $($counts.Count)"
Write-Output ""

$sorted = $counts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First $MaxResults

# Calculate column widths
$maxKeyLen = ($sorted | ForEach-Object { $_.Key.Length } | Measure-Object -Maximum).Maximum
if ($maxKeyLen -lt 10) { $maxKeyLen = 10 }
if ($maxKeyLen -gt 120) { $maxKeyLen = 120 }

Write-Output ("{0,-8} {1,-$maxKeyLen} {2,7}" -f 'Count', 'Key', 'Pct')
Write-Output ("{0,-8} {1,-$maxKeyLen} {2,7}" -f '-----', ('─' * [Math]::Min($maxKeyLen, 120)), '------')

foreach ($item in $sorted) {
    $pct = if ($matchedEntries -gt 0) { [math]::Round(($item.Value / $matchedEntries) * 100, 1) } else { 0 }
    $displayKey = if ($item.Key.Length -gt 120) { $item.Key.Substring(0, 117) + '...' } else { $item.Key }
    Write-Output ("{0,-8} {1,-$maxKeyLen} {2,6:F1}%" -f $item.Value, $displayKey, $pct)
}
