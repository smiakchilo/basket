<#
.SYNOPSIS
    Extract log entries within a time window.

.DESCRIPTION
    Streams a log file and outputs entries whose timestamps fall within
    the specified start and end times. Auto-detects log format and
    parses timestamps accordingly. For multiline formats (AEM error),
    complete entries including stack traces are emitted.

.PARAMETER Path
    Path to the log file.

.PARAMETER Start
    Start of the time window (inclusive). For AEM logs: "DD.MM.YYYY HH:mm:ss"
    For HTTPD/Dispatcher: "DD/Mon/YYYY:HH:mm:ss" or any [datetime]-parseable string.

.PARAMETER End
    End of the time window (inclusive). Same format as -Start.

.PARAMETER MaxResults
    Maximum entries to return. Default: 100.

.PARAMETER Format
    Log format override. If omitted, auto-detected.

.PARAMETER LevelFilter
    Optional: only include entries at these log levels (AEM error format only).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string]$Start,

    [Parameter(Mandatory)]
    [string]$End,

    [int]$MaxResults = 100,
    [string]$Format,
    [string[]]$LevelFilter
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Auto-detect format ---
if (-not $Format) {
    $detected = & "$scriptDir\detect-format.ps1" -Path $Path
    $Format = $detected.Format
}

# --- Format-specific configuration ---
switch ($Format) {
    'aem-error' {
        $entryStartPattern = '^\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3}\s\['
        $tsPattern = '^(\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3})'
        $tsFormat = 'dd.MM.yyyy HH:mm:ss.fff'
        $isMultiline = $true
    }
    'httpd-access' {
        $entryStartPattern = '^\S+\s\d+\.\d+\.\d+\.\d+'
        $tsPattern = '(\d{2}/[A-Za-z]{3}/\d{4}:\d{2}:\d{2}:\d{2}\s[+\-]\d{4})'
        $tsFormat = 'dd/MMM/yyyy:HH:mm:ss zzz'
        $isMultiline = $false
    }
    'dispatcher' {
        $entryStartPattern = '^\['
        $tsPattern = '^\[(\d{2}/[A-Za-z]{3}/\d{4}:\d{2}:\d{2}:\d{2}\s[+\-]\d{4})\]'
        $tsFormat = 'dd/MMM/yyyy:HH:mm:ss zzz'
        $isMultiline = $false
    }
    default {
        Write-Error "Unsupported format: $Format"
        return
    }
}

$levelRegex = '\*([A-Z]+)\*'
$levelSet = $null
if ($LevelFilter) {
    $levelSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($l in $LevelFilter) { $null = $levelSet.Add($l) }
}

$culture = [System.Globalization.CultureInfo]::InvariantCulture

# --- Parse boundary times ---
function ParseTimestamp([string]$raw, [string]$fmt) {
    try {
        return [datetime]::ParseExact($raw.Trim(), $fmt, $culture)
    } catch {
        # Fallback: try common subset formats
        $fallbacks = @('dd.MM.yyyy HH:mm:ss', 'dd.MM.yyyy', 'dd/MMM/yyyy:HH:mm:ss', 'yyyy-MM-dd HH:mm:ss')
        foreach ($fb in $fallbacks) {
            try { return [datetime]::ParseExact($raw.Trim(), $fb, $culture) } catch {}
        }
        # Last resort: let PowerShell parse it
        return [datetime]::Parse($raw.Trim(), $culture)
    }
}

$startTime = ParseTimestamp $Start $tsFormat
$endTime = ParseTimestamp $End $tsFormat

Write-Output "=== Timeline: $startTime -> $endTime ($Format) ==="
Write-Output ""

$reader = [System.IO.StreamReader]::new($Path, [System.Text.Encoding]::UTF8, $true)
try {
    $currentEntry = [System.Collections.Generic.List[string]]::new()
    $currentStartLine = 0
    $entryTime = $null
    $entryLevel = $null
    $inRange = $false
    $pastRange = $false
    $resultCount = 0
    $lineNum = 0

    while ($null -ne ($line = $reader.ReadLine())) {
        $lineNum++

        $isEntryStart = $line -match $entryStartPattern

        if ($isEntryStart -or -not $isMultiline) {
            # Flush previous entry if in range
            if ($currentEntry.Count -gt 0 -and $inRange) {
                # Check level filter
                $levelOk = $true
                if ($levelSet -and $entryLevel) {
                    $levelOk = $levelSet.Contains($entryLevel)
                }
                if ($levelOk) {
                    Write-Output "[line $currentStartLine] $($currentEntry[0])"
                    for ($i = 1; $i -lt $currentEntry.Count; $i++) {
                        Write-Output "  $($currentEntry[$i])"
                    }
                    Write-Output ""
                    $resultCount++
                    if ($resultCount -ge $MaxResults) { break }
                }
            }

            # Start new entry
            $currentEntry.Clear()
            $currentEntry.Add($line)
            $currentStartLine = $lineNum
            $inRange = $false
            $entryLevel = $null

            # Parse timestamp
            if ($line -match $tsPattern) {
                try {
                    $entryTime = [datetime]::ParseExact($Matches[1].Trim(), $tsFormat, $culture)
                    if ($entryTime -ge $startTime -and $entryTime -le $endTime) {
                        $inRange = $true
                    } elseif ($entryTime -gt $endTime) {
                        $pastRange = $true
                        break
                    }
                } catch {
                    # Skip unparseable timestamps
                }
            }

            # Extract level for AEM logs
            if ($Format -eq 'aem-error' -and $line -match $levelRegex) {
                $entryLevel = $Matches[1]
            }

            # For single-line formats, flush immediately
            if (-not $isMultiline -and $inRange) {
                $levelOk = $true
                if ($levelSet -and $entryLevel) {
                    $levelOk = $levelSet.Contains($entryLevel)
                }
                if ($levelOk) {
                    Write-Output "[line $currentStartLine] $line"
                    $resultCount++
                    if ($resultCount -ge $MaxResults) { break }
                }
                $currentEntry.Clear()
            }
        } else {
            # Continuation line (multiline format)
            if ($currentEntry.Count -gt 0) {
                $currentEntry.Add($line)
            }
        }
    }

    # Flush last entry
    if (-not $pastRange -and $currentEntry.Count -gt 0 -and $inRange -and $resultCount -lt $MaxResults) {
        $levelOk = $true
        if ($levelSet -and $entryLevel) {
            $levelOk = $levelSet.Contains($entryLevel)
        }
        if ($levelOk) {
            Write-Output "[line $currentStartLine] $($currentEntry[0])"
            for ($i = 1; $i -lt $currentEntry.Count; $i++) {
                Write-Output "  $($currentEntry[$i])"
            }
            Write-Output ""
        }
    }

    Write-Output "--- timeline: $resultCount entries in window ---"

} finally {
    $reader.Close()
    $reader.Dispose()
}
