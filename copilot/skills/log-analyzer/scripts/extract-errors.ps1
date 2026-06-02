<#
.SYNOPSIS
    Extract ERROR entries with full stack traces from AEM error logs.

.DESCRIPTION
    Streams through an AEM error log and collects every ERROR-level entry,
    including all continuation lines (stack traces, caused-by chains).
    Optionally filters by logger name or message pattern.

.PARAMETER Path
    Path to the AEM error log file.

.PARAMETER MessagePattern
    Optional regex to further filter ERROR entries by message content.

.PARAMETER LoggerPattern
    Optional regex to filter by logger class name.

.PARAMETER MaxResults
    Maximum number of error entries to return. Default: 30.

.PARAMETER IncludeSuppressed
    Include "Suppressed:" sections in stack traces. Default: true.

.PARAMETER Tail
    If set, return the LAST N errors instead of the first N.
    Uses a ring buffer — still streams the whole file but keeps only the last N.

.PARAMETER Summary
    If set, output a summary table of error types instead of full entries.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [string]$MessagePattern,
    [string]$LoggerPattern,
    [int]$MaxResults = 30,
    [switch]$IncludeSuppressed,
    [switch]$Tail,
    [switch]$Summary
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$entryStartPattern = '^\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3}\s\['
$fullPattern = '^(?<Timestamp>\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3})\s\[(?<Pod>[^\]]+)\]\s\*(?<Level>[A-Z]+)\*\s\[(?<Thread>.+)\]\s(?<Logger>\S+\.\S+)\s(?<Message>.*)'

# For summary mode, collect counts
$errorCounts = @{}
$totalErrors = 0

# For tail mode, use a ring buffer
$ringBuffer = if ($Tail) { [System.Collections.Generic.Queue[string]]::new() } else { $null }

$reader = [System.IO.StreamReader]::new($Path, [System.Text.Encoding]::UTF8, $true)
try {
    $currentEntry = [System.Collections.Generic.List[string]]::new()
    $currentStartLine = 0
    $isError = $false
    $matchesFilters = $false
    $resultCount = 0
    $lineNum = 0
    $currentLogger = ''
    $currentMessage = ''
    $exceptionClass = ''

    while ($null -ne ($line = $reader.ReadLine())) {
        $lineNum++
        $isEntryStart = $line -match $entryStartPattern

        if ($isEntryStart) {
            # Flush previous entry
            if ($currentEntry.Count -gt 0 -and $isError -and $matchesFilters) {
                $totalErrors++

                # Extract exception class from stack trace for summary
                $exClass = ''
                for ($i = 1; $i -lt [Math]::Min($currentEntry.Count, 5); $i++) {
                    if ($currentEntry[$i] -match '^\s*(?:Caused by:\s*)?(\S+(?:Exception|Error|Throwable)\b)') {
                        $exClass = $Matches[1]
                        break
                    }
                }
                if (-not $exClass -and $currentMessage -match '(\S+(?:Exception|Error)\b)') {
                    $exClass = $Matches[1]
                }
                if (-not $exClass) { $exClass = $currentLogger }

                if ($Summary) {
                    $key = "$exClass"
                    if ($errorCounts.ContainsKey($key)) {
                        $errorCounts[$key]++
                    } else {
                        $errorCounts[$key] = 1
                    }
                } elseif ($Tail) {
                    $entryText = "[line $currentStartLine] $($currentEntry -join "`n")"
                    $ringBuffer.Enqueue($entryText)
                    while ($ringBuffer.Count -gt $MaxResults) {
                        $null = $ringBuffer.Dequeue()
                    }
                } else {
                    Write-Output "[line $currentStartLine] $($currentEntry[0])"
                    for ($i = 1; $i -lt $currentEntry.Count; $i++) {
                        $entryLine = $currentEntry[$i]
                        if (-not $IncludeSuppressed -and $entryLine -match '^\s*Suppressed:') {
                            continue
                        }
                        Write-Output "  $entryLine"
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

            # Check if ERROR
            if ($line -match $fullPattern) {
                $isError = $Matches['Level'] -eq 'ERROR'
                $currentLogger = $Matches['Logger']
                $currentMessage = $Matches['Message']

                # Apply filters
                $matchesFilters = $isError
                if ($matchesFilters -and $LoggerPattern) {
                    $matchesFilters = $currentLogger -match $LoggerPattern
                }
                if ($matchesFilters -and $MessagePattern) {
                    $matchesFilters = $currentMessage -match $MessagePattern
                }
            } else {
                $isError = $false
                $matchesFilters = $false
            }
        } else {
            # Continuation line
            if ($currentEntry.Count -gt 0) {
                $currentEntry.Add($line)
                # Check message pattern against continuation lines too
                if ($isError -and -not $matchesFilters -and $MessagePattern -and $line -match $MessagePattern) {
                    $matchesFilters = $true
                }
            }
        }
    }

    # Flush last entry
    if ($currentEntry.Count -gt 0 -and $isError -and $matchesFilters) {
        $totalErrors++
        if ($Summary) {
            $exClass = ''
            for ($i = 1; $i -lt [Math]::Min($currentEntry.Count, 5); $i++) {
                if ($currentEntry[$i] -match '^\s*(?:Caused by:\s*)?(\S+(?:Exception|Error|Throwable)\b)') {
                    $exClass = $Matches[1]
                    break
                }
            }
            if (-not $exClass) { $exClass = $currentLogger }
            if ($errorCounts.ContainsKey($exClass)) {
                $errorCounts[$exClass]++
            } else {
                $errorCounts[$exClass] = 1
            }
        } elseif ($Tail) {
            $entryText = "[line $currentStartLine] $($currentEntry -join "`n")"
            $ringBuffer.Enqueue($entryText)
            while ($ringBuffer.Count -gt $MaxResults) {
                $null = $ringBuffer.Dequeue()
            }
        } elseif ($resultCount -lt $MaxResults) {
            Write-Output "[line $currentStartLine] $($currentEntry[0])"
            for ($i = 1; $i -lt $currentEntry.Count; $i++) {
                Write-Output "  $($currentEntry[$i])"
            }
            Write-Output ""
        }
    }

    # Output summary or tail
    if ($Summary) {
        Write-Output "=== ERROR Summary: $totalErrors total errors ==="
        Write-Output ""
        $errorCounts.GetEnumerator() |
            Sort-Object Value -Descending |
            Select-Object -First $MaxResults |
            ForEach-Object {
                Write-Output ("  {0,6}x  {1}" -f $_.Value, $_.Key)
            }
    } elseif ($Tail) {
        Write-Output "=== Last $($ringBuffer.Count) errors (of $totalErrors total) ==="
        Write-Output ""
        foreach ($entry in $ringBuffer) {
            Write-Output $entry
            Write-Output ""
        }
    } else {
        Write-Output "--- extract-errors: showed $resultCount of $totalErrors total ERROR entries ---"
    }

} finally {
    $reader.Close()
    $reader.Dispose()
}
