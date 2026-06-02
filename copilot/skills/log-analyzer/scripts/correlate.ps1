<#
.SYNOPSIS
    Follow a thread name, request ID, or correlation token across log files.

.DESCRIPTION
    Searches one or more log files for entries matching a correlation key
    (thread name, request ID, session ID, pod name, etc.), collects all
    matching entries with their complete multiline bodies, and outputs
    them in chronological order. When multiple files are specified,
    entries are merged and sorted by timestamp.

.PARAMETER Path
    One or more log file paths. Accepts wildcards.

.PARAMETER ThreadName
    Thread name to follow (exact match within the [thread] field).

.PARAMETER RequestId
    Request/correlation ID to search for anywhere in the log entry.

.PARAMETER PodName
    Pod name to filter by (exact match within the [pod] field).

.PARAMETER Pattern
    Generic regex pattern to correlate on (alternative to Thread/Request/Pod).

.PARAMETER MaxResults
    Maximum entries to return across all files. Default: 100.

.PARAMETER Format
    Log format override. Auto-detected per file if omitted.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$Path,

    [string]$ThreadName,
    [string]$RequestId,
    [string]$PodName,
    [string]$Pattern,
    [int]$MaxResults = 100,
    [string]$Format
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Validate: at least one correlation key ---
$correlationKeys = @($ThreadName, $RequestId, $PodName, $Pattern) | Where-Object { $_ }
if ($correlationKeys.Count -eq 0) {
    Write-Error "Specify at least one of: -ThreadName, -RequestId, -PodName, -Pattern"
    return
}

# --- Resolve file paths (expand wildcards) ---
$resolvedFiles = @()
foreach ($p in $Path) {
    $resolved = Resolve-Path -LiteralPath $p -ErrorAction SilentlyContinue
    if (-not $resolved) {
        $resolved = Resolve-Path -Path $p -ErrorAction SilentlyContinue
    }
    if ($resolved) {
        $resolvedFiles += $resolved.Path
    } else {
        Write-Warning "Path not found: $p"
    }
}

if ($resolvedFiles.Count -eq 0) {
    Write-Error "No valid log files found."
    return
}

# --- Build search pattern based on correlation key type ---
function BuildSearchPattern($fmt, $threadName, $requestId, $podName, $genericPattern) {
    $patterns = @()

    if ($threadName) {
        switch ($fmt) {
            'aem-error' { $patterns += "\[$([regex]::Escape($threadName))\]" }
            default     { $patterns += [regex]::Escape($threadName) }
        }
    }

    if ($requestId) {
        $patterns += [regex]::Escape($requestId)
    }

    if ($podName) {
        switch ($fmt) {
            'aem-error'    { $patterns += "^\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3}\s\[$([regex]::Escape($podName))\]" }
            'httpd-access' { $patterns += "^$([regex]::Escape($podName))\s" }
            'dispatcher'   { $patterns += "\[$([regex]::Escape($podName))\]" }
            default        { $patterns += [regex]::Escape($podName) }
        }
    }

    if ($genericPattern) {
        $patterns += $genericPattern
    }

    # Combine with AND logic (all patterns must match the entry)
    return $patterns
}

# --- Timestamp extraction ---
$culture = [System.Globalization.CultureInfo]::InvariantCulture

function ExtractTimestamp($line, $fmt) {
    switch ($fmt) {
        'aem-error' {
            if ($line -match '^(\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3})') {
                try {
                    return [datetime]::ParseExact($Matches[1], 'dd.MM.yyyy HH:mm:ss.fff', $culture)
                } catch { return $null }
            }
        }
        'httpd-access' {
            if ($line -match '(\d{2}/[A-Za-z]{3}/\d{4}:\d{2}:\d{2}:\d{2}\s[+\-]\d{4})') {
                try {
                    return [datetime]::ParseExact($Matches[1], 'dd/MMM/yyyy:HH:mm:ss zzz', $culture)
                } catch { return $null }
            }
        }
        'dispatcher' {
            if ($line -match '\[(\d{2}/[A-Za-z]{3}/\d{4}:\d{2}:\d{2}:\d{2}\s[+\-]\d{4})\]') {
                try {
                    return [datetime]::ParseExact($Matches[1], 'dd/MMM/yyyy:HH:mm:ss zzz', $culture)
                } catch { return $null }
            }
        }
    }
    return $null
}

# --- Process each file ---
$allEntries = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($filePath in $resolvedFiles) {
    $fileName = Split-Path -Leaf $filePath

    # Detect format for this file
    $fileFmt = $Format
    if (-not $fileFmt) {
        $detected = & "$scriptDir\detect-format.ps1" -Path $filePath
        $fileFmt = $detected.Format
    }

    $isMultiline = ($fileFmt -eq 'aem-error')
    $entryStartPattern = switch ($fileFmt) {
        'aem-error'    { '^\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3}\s\[' }
        'httpd-access' { '^\S+\s\d+\.\d+\.\d+\.\d+' }
        'dispatcher'   { '^\[' }
        default        { '^.' }
    }

    $searchPatterns = BuildSearchPattern $fileFmt $ThreadName $RequestId $PodName $Pattern

    $reader = [System.IO.StreamReader]::new($filePath, [System.Text.Encoding]::UTF8, $true)
    try {
        $currentEntry = [System.Collections.Generic.List[string]]::new()
        $currentStartLine = 0
        $entryText = ''
        $lineNum = 0

        while ($null -ne ($line = $reader.ReadLine())) {
            $lineNum++
            $isEntryStart = $line -match $entryStartPattern

            if ($isEntryStart -or -not $isMultiline) {
                # Flush previous entry
                if ($currentEntry.Count -gt 0) {
                    $entryText = $currentEntry -join "`n"
                    $allMatch = $true
                    foreach ($sp in $searchPatterns) {
                        if ($entryText -notmatch $sp) {
                            $allMatch = $false
                            break
                        }
                    }
                    if ($allMatch) {
                        $ts = ExtractTimestamp $currentEntry[0] $fileFmt
                        $allEntries.Add([PSCustomObject]@{
                            Timestamp = $ts
                            File      = $fileName
                            Line      = $currentStartLine
                            Text      = $entryText
                        })
                    }
                }

                $currentEntry.Clear()
                $currentEntry.Add($line)
                $currentStartLine = $lineNum

                # For single-line formats, also check immediately
                if (-not $isMultiline) {
                    # Will be flushed on next iteration
                }
            } else {
                $currentEntry.Add($line)
            }

            if ($allEntries.Count -ge $MaxResults * 2) {
                # Safety: stop collecting if we have way more than needed
                break
            }
        }

        # Flush last entry
        if ($currentEntry.Count -gt 0) {
            $entryText = $currentEntry -join "`n"
            $allMatch = $true
            foreach ($sp in $searchPatterns) {
                if ($entryText -notmatch $sp) {
                    $allMatch = $false
                    break
                }
            }
            if ($allMatch) {
                $ts = ExtractTimestamp $currentEntry[0] $fileFmt
                $allEntries.Add([PSCustomObject]@{
                    Timestamp = $ts
                    File      = $fileName
                    Line      = $currentStartLine
                    Text      = $entryText
                })
            }
        }

    } finally {
        $reader.Close()
        $reader.Dispose()
    }

    Write-Output "Processed: $fileName ($fileFmt) — $($allEntries.Count) matching entries so far"
}

# --- Sort by timestamp and output ---
Write-Output ""
Write-Output "=== Correlation results ==="

$correlationDesc = @()
if ($ThreadName) { $correlationDesc += "Thread=$ThreadName" }
if ($RequestId) { $correlationDesc += "RequestId=$RequestId" }
if ($PodName) { $correlationDesc += "Pod=$PodName" }
if ($Pattern) { $correlationDesc += "Pattern=$Pattern" }
Write-Output "Keys: $($correlationDesc -join ', ')"
Write-Output "Files: $($resolvedFiles.Count) | Total matches: $($allEntries.Count)"
Write-Output ""

$sorted = $allEntries |
    Sort-Object { if ($_.Timestamp) { $_.Timestamp } else { [datetime]::MinValue } } |
    Select-Object -First $MaxResults

$entryNum = 0
foreach ($entry in $sorted) {
    $entryNum++
    $tsDisplay = if ($entry.Timestamp) { $entry.Timestamp.ToString('yyyy-MM-dd HH:mm:ss.fff') } else { '(no timestamp)' }
    Write-Output "[$entryNum] $tsDisplay | $($entry.File):$($entry.Line)"
    Write-Output $entry.Text
    Write-Output ""
}

Write-Output "--- correlate: showed $entryNum of $($allEntries.Count) total matches ---"
