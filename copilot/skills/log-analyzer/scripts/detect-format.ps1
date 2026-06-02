<#
.SYNOPSIS
    Auto-detect the log format of a file by sampling the first N lines.

.DESCRIPTION
    Reads the first lines of a log file using streaming (Get-Content -TotalCount)
    and matches them against known format anchors. Returns the detected format name,
    the matching regex, and a parsed sample line.

.PARAMETER Path
    Path to the log file.

.PARAMETER SampleSize
    Number of lines to read for detection. Default: 20.

.OUTPUTS
    PSCustomObject with properties: Format, EntryStartPattern, FullPattern, SampleParsed
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [int]$SampleSize = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Error "File not found: $Path"
    return
}

# --- Format definitions (most specific first) ---
$formats = @(
    @{
        Name              = 'aem-error'
        EntryStartPattern = '^\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3}\s\['
        FullPattern       = '^(?<Timestamp>\d{2}\.\d{2}\.\d{4}\s\d{2}:\d{2}:\d{2}\.\d{3})\s\[(?<Pod>[^\]]+)\]\s\*(?<Level>[A-Z]+)\*\s\[(?<Thread>.+)\]\s(?<Logger>\S+\.\S+)\s(?<Message>.*)'
        Multiline         = $true
    },
    @{
        Name              = 'dispatcher'
        EntryStartPattern = '^\[\d{2}/[A-Za-z]{3}/\d{4}:\d{2}:\d{2}:\d{2}\s[+\-]\d{4}\]\s\[[A-Z]\]'
        FullPattern       = '^\[(?<Timestamp>\d{2}/[A-Za-z]{3}/\d{4}:\d{2}:\d{2}:\d{2}\s[+\-]\d{4})\]\s\[(?<Severity>[A-Z])\]\s\[(?<Pod>[^\]]+)\]\s"(?<Method>[A-Z]+)\s(?<Path>[^"]+)"\s(?<Status>\d{3})\s(?<Duration>\d+)ms\s\[(?<Farm>[^\]]+)\]\s\[(?<Action>[^\]]+)\]\s(?<Host>\S+)'
        Multiline         = $false
    },
    @{
        Name              = 'httpd-access'
        EntryStartPattern = '^\S+\s\d+\.\d+\.\d+\.\d+\s-\s\d{2}/[A-Za-z]{3}/\d{4}:'
        FullPattern       = '^(?<Pod>\S+)\s(?<ClientIP>\S+)\s-\s(?<Timestamp>\d{2}/[A-Za-z]{3}/\d{4}:\d{2}:\d{2}:\d{2}\s[+\-]\d{4})\s"(?<Method>[A-Z]+)\s(?<RequestPath>[^\s"]+)\s(?<Protocol>[^"]+)"\s(?<Status>\d{3})\s(?<Size>\d+|-)\s"(?<Referer>[^"]*)"\s"(?<UserAgent>[^"]*)"'
        Multiline         = $false
    }
)

# --- Read sample lines ---
$sampleLines = Get-Content -LiteralPath $Path -TotalCount $SampleSize -ErrorAction Stop |
    Where-Object { $_.Trim().Length -gt 0 }

if (-not $sampleLines -or $sampleLines.Count -eq 0) {
    Write-Error "File is empty or has no non-empty lines in the first $SampleSize lines."
    return
}

# --- Try each format ---
foreach ($fmt in $formats) {
    $matchCount = 0
    $sampleMatch = $null

    foreach ($line in $sampleLines) {
        if ($line -match $fmt.EntryStartPattern) {
            $matchCount++
            if (-not $sampleMatch -and $line -match $fmt.FullPattern) {
                $sampleMatch = $Matches.Clone()
                $sampleMatch.Remove(0)
            }
        }
    }

    # Require majority of non-empty sample lines to match
    if ($matchCount -gt ($sampleLines.Count / 2)) {
        [PSCustomObject]@{
            Format            = $fmt.Name
            EntryStartPattern = $fmt.EntryStartPattern
            FullPattern       = $fmt.FullPattern
            Multiline         = $fmt.Multiline
            Confidence        = [math]::Round(($matchCount / $sampleLines.Count) * 100)
            SampleParsed      = $sampleMatch
        }
        return
    }
}

Write-Warning "Could not detect log format from the first $SampleSize lines of: $Path"
[PSCustomObject]@{
    Format            = 'unknown'
    EntryStartPattern = $null
    FullPattern       = $null
    Multiline         = $null
    Confidence        = 0
    SampleParsed      = $null
}
