<#
.SYNOPSIS
    Search a log file for a pattern with surrounding context lines.

.DESCRIPTION
    Uses Select-String for efficient streaming search on huge files.
    For AEM error logs (multiline format), merges continuation lines
    (stack traces) into the matching entry so stack traces are never
    truncated mid-way.

.PARAMETER Path
    Path to the log file.

.PARAMETER Pattern
    Regex pattern to search for.

.PARAMETER ContextBefore
    Number of context lines before each match. Default: 3.

.PARAMETER ContextAfter
    Number of context lines after each match. Default: 5.

.PARAMETER MaxResults
    Maximum number of matches to return. Default: 50.

.PARAMETER Format
    Log format override. If omitted, auto-detected via detect-format.ps1.

.PARAMETER CaseSensitive
    Enable case-sensitive matching. Default: case-insensitive.

.PARAMETER MergeMultiline
    For multiline formats, merge continuation lines into the matching entry.
    Default: true for AEM error logs, false for others.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string]$Pattern,

    [int]$ContextBefore = 3,
    [int]$ContextAfter = 5,
    [int]$MaxResults = 50,
    [string]$Format,
    [switch]$CaseSensitive,
    [Nullable[bool]]$MergeMultiline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# --- Auto-detect format if not specified ---
if (-not $Format) {
    $detected = & "$scriptDir\detect-format.ps1" -Path $Path
    $Format = $detected.Format
    $isMultiline = $detected.Multiline
    $entryStartPattern = $detected.EntryStartPattern
} else {
    # Look up from known formats
    switch ($Format) {
        'aem-error' {
            $isMultiline = $true
            $entryStartPattern = '^\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3}\s\['
        }
        default {
            $isMultiline = $false
            $entryStartPattern = $null
        }
    }
}

if ($null -ne $MergeMultiline) {
    $isMultiline = $MergeMultiline
}

# --- Simple path: no multiline merging needed ---
if (-not $isMultiline) {
    $selectParams = @{
        LiteralPath = $Path
        Pattern     = $Pattern
        Context     = @($ContextBefore, $ContextAfter)
    }
    if (-not $CaseSensitive) {
        # Select-String is case-insensitive by default
    } else {
        $selectParams['CaseSensitive'] = $true
    }

    $results = Select-String @selectParams | Select-Object -First $MaxResults

    foreach ($r in $results) {
        Write-Output "--- Match at line $($r.LineNumber) ---"
        if ($r.Context.PreContext) {
            $r.Context.PreContext | ForEach-Object { Write-Output "  $_" }
        }
        Write-Output "> $($r.Line)"
        if ($r.Context.PostContext) {
            $r.Context.PostContext | ForEach-Object { Write-Output "  $_" }
        }
        Write-Output ""
    }
    return
}

# --- Multiline path: merge stack traces into matching entries ---
# Strategy: use Select-String to find matching line numbers, then use
# StreamReader to collect complete log entries around those lines.

$matchLineNums = Select-String -LiteralPath $Path -Pattern $Pattern |
    Select-Object -First ($MaxResults * 2) -ExpandProperty LineNumber

if (-not $matchLineNums -or $matchLineNums.Count -eq 0) {
    Write-Output "No matches found for pattern: $Pattern"
    return
}

# Collect unique entry blocks. For each match line, we need to:
# 1. Find the entry-start line at or before the match
# 2. Collect all continuation lines until the next entry-start
# 3. Include ContextBefore entries before the matched entry

$reader = [System.IO.StreamReader]::new($Path, [System.Text.Encoding]::UTF8, $true)
try {
    $lineNum = 0
    $entries = [System.Collections.Generic.List[PSCustomObject]]::new()
    $currentEntry = $null
    $currentStartLine = 0
    $matchSet = [System.Collections.Generic.HashSet[int]]::new([int[]]$matchLineNums)
    $entryContainsMatch = $false
    $resultCount = 0

    # Ring buffer for context-before entries
    $contextBuffer = [System.Collections.Generic.Queue[PSCustomObject]]::new()

    while ($null -ne ($line = $reader.ReadLine())) {
        $lineNum++

        $isEntryStart = $line -match $entryStartPattern

        if ($isEntryStart) {
            # Flush previous entry if it contained a match
            if ($currentEntry -and $entryContainsMatch) {
                # Emit context-before entries
                foreach ($ctxEntry in $contextBuffer) {
                    Write-Output "  [line $($ctxEntry.StartLine)] $($ctxEntry.Lines[0])"
                    for ($i = 1; $i -lt $ctxEntry.Lines.Count; $i++) {
                        Write-Output "  $($ctxEntry.Lines[$i])"
                    }
                }
                $contextBuffer.Clear()

                Write-Output "--- Match in entry at line $currentStartLine ---"
                foreach ($eLine in $currentEntry) {
                    Write-Output "> $eLine"
                }
                Write-Output ""
                $resultCount++
                if ($resultCount -ge $MaxResults) { break }
            } elseif ($currentEntry) {
                # Non-matching entry — add to context buffer
                $contextBuffer.Enqueue([PSCustomObject]@{
                    StartLine = $currentStartLine
                    Lines     = [string[]]$currentEntry
                })
                while ($contextBuffer.Count -gt $ContextBefore) {
                    $null = $contextBuffer.Dequeue()
                }
            }

            # Start new entry
            $currentEntry = [System.Collections.Generic.List[string]]::new()
            $currentEntry.Add($line)
            $currentStartLine = $lineNum
            $entryContainsMatch = $matchSet.Contains($lineNum)
        } else {
            # Continuation line
            if ($currentEntry) {
                $currentEntry.Add($line)
            }
            if ($matchSet.Contains($lineNum)) {
                $entryContainsMatch = $true
            }
        }
    }

    # Flush last entry
    if ($currentEntry -and $entryContainsMatch -and $resultCount -lt $MaxResults) {
        foreach ($ctxEntry in $contextBuffer) {
            Write-Output "  [line $($ctxEntry.StartLine)] $($ctxEntry.Lines[0])"
            for ($i = 1; $i -lt $ctxEntry.Lines.Count; $i++) {
                Write-Output "  $($ctxEntry.Lines[$i])"
            }
        }
        Write-Output "--- Match in entry at line $currentStartLine ---"
        foreach ($eLine in $currentEntry) {
            Write-Output "> $eLine"
        }
        Write-Output ""
    }

} finally {
    $reader.Close()
    $reader.Dispose()
}
