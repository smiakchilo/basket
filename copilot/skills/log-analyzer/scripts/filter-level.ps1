<#
.SYNOPSIS
    Filter AEM error log entries by log level.

.DESCRIPTION
    Streams through an AEM error log file and outputs complete log entries
    (including multiline stack traces) that match the specified log level(s).
    Uses StreamReader for memory-efficient processing of huge files.

.PARAMETER Path
    Path to the AEM error log file.

.PARAMETER Level
    One or more log levels to include. Valid: ERROR, WARN, INFO, DEBUG, TRACE.

.PARAMETER ExcludeLevel
    One or more log levels to exclude (applied after -Level).

.PARAMETER MaxResults
    Maximum number of matching entries to return. Default: 50.

.PARAMETER NoStackTrace
    If set, only output the first line of each matching entry (skip continuation lines).

.PARAMETER Format
    Log format override. Default: auto-detected.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [ValidateSet('ERROR', 'WARN', 'INFO', 'DEBUG', 'TRACE')]
    [string[]]$Level,

    [ValidateSet('ERROR', 'WARN', 'INFO', 'DEBUG', 'TRACE')]
    [string[]]$ExcludeLevel,

    [int]$MaxResults = 50,
    [switch]$NoStackTrace,
    [string]$Format
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Validate format ---
if (-not $Format) {
    $detected = & "$scriptDir\detect-format.ps1" -Path $Path
    if ($detected.Format -ne 'aem-error') {
        Write-Warning "Log level filtering is designed for AEM error logs. Detected format: $($detected.Format)"
        Write-Warning "For dispatcher logs, use severity letters (I/W/E/D/T) with search-context.ps1 instead."
        return
    }
}

$entryStartPattern = '^\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3}\s\['

# Build level match pattern: *ERROR* or *WARN* etc.
$levelSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($l in $Level) { $null = $levelSet.Add($l) }

$excludeSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
if ($ExcludeLevel) {
    foreach ($l in $ExcludeLevel) { $null = $excludeSet.Add($l) }
}

$levelRegex = '\*([A-Z]+)\*'

$reader = [System.IO.StreamReader]::new($Path, [System.Text.Encoding]::UTF8, $true)
try {
    $currentEntry = [System.Collections.Generic.List[string]]::new()
    $currentStartLine = 0
    $entryLevel = $null
    $resultCount = 0
    $lineNum = 0

    while ($null -ne ($line = $reader.ReadLine())) {
        $lineNum++
        $isEntryStart = $line -match $entryStartPattern

        if ($isEntryStart) {
            # Flush previous entry if it matches
            if ($currentEntry.Count -gt 0 -and $entryLevel -and
                $levelSet.Contains($entryLevel) -and
                -not $excludeSet.Contains($entryLevel)) {

                Write-Output "[line $currentStartLine] $($currentEntry[0])"
                if (-not $NoStackTrace) {
                    for ($i = 1; $i -lt $currentEntry.Count; $i++) {
                        Write-Output "  $($currentEntry[$i])"
                    }
                }
                Write-Output ""
                $resultCount++
                if ($resultCount -ge $MaxResults) { break }
            }

            # Start new entry
            $currentEntry.Clear()
            $currentEntry.Add($line)
            $currentStartLine = $lineNum

            # Extract level
            if ($line -match $levelRegex) {
                $entryLevel = $Matches[1]
            } else {
                $entryLevel = $null
            }
        } else {
            # Continuation line
            if ($currentEntry.Count -gt 0) {
                $currentEntry.Add($line)
            }
        }
    }

    # Flush last entry
    if ($resultCount -lt $MaxResults -and $currentEntry.Count -gt 0 -and
        $entryLevel -and $levelSet.Contains($entryLevel) -and
        -not $excludeSet.Contains($entryLevel)) {

        Write-Output "[line $currentStartLine] $($currentEntry[0])"
        if (-not $NoStackTrace) {
            for ($i = 1; $i -lt $currentEntry.Count; $i++) {
                Write-Output "  $($currentEntry[$i])"
            }
        }
        Write-Output ""
    }

    Write-Output "--- filter-level summary: $resultCount entries at level(s) $($Level -join ', ') ---"

} finally {
    $reader.Close()
    $reader.Dispose()
}
