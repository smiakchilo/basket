<#
.SYNOPSIS
    Pre-collects all Phase 1 code-review data (branch info, commits, diffs) and writes
    it to a structured file in .reviews/ that the code-reviewer skill can use directly,
    bypassing the worker subagent entirely and preserving the full expert context budget.

.DESCRIPTION
    Mirrors the data-collection steps in Phase 1 of the code-reviewer SKILL.md:
      1.1  Identify current branch
      1.2  Detect parent branch
      1.3  List new commits
      1.4  Get the full diff (stat + per-file)
    Instruction-file collection (steps 2.1-2.3) is intentionally NOT performed here —
    the expert subagent handles the cache check itself.

    Output file: .reviews/.phase1-data.md  (in the current git repo root)
    The file follows the same section layout the worker subagent would produce, so the
    orchestrator can feed it directly to the expert prompt with no transformation.

.PARAMETER Since
    Optional starting commit hash (Mode C). When supplied, uses <hash>..HEAD as the
    revision range instead of auto-detecting the parent branch.

.PARAMETER Context
    Number of unified diff context lines. Defaults to 10.  Use a higher value (e.g. 20)
    to give the expert more surrounding code for tricky files.

.EXAMPLE
    # Full branch review (Mode A)
    .\collect-diff.ps1

.EXAMPLE
    # Since a specific commit (Mode C)
    .\collect-diff.ps1 -Since 4d0deaec

.EXAMPLE
    # More context lines
    .\collect-diff.ps1 -Context 20
#>

[CmdletBinding()]
param(
    [string] $Since    = '',
    [int]    $Context  = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\get-filename.ps1"
. "$PSScriptRoot\get-parent-branch.ps1"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Invoke-Git {
    param([string[]] $Arguments)
    # Wrap in try/catch: PowerShell 5.1 throws NativeCommandError on stderr
    # under $ErrorActionPreference = 'Stop', even with 2>&1.
    try {
        $result = & git @Arguments 2>&1
        if ($LASTEXITCODE -ne 0) { return $null }
        return ($result | Out-String).Trim()
    } catch {
        return $null
    }
}

function Write-Section {
    param([System.IO.StreamWriter] $Writer, [string] $Heading, [string] $Content)
    $Writer.WriteLine('')
    $Writer.WriteLine("## $Heading")
    $Writer.WriteLine('')
    if ([string]::IsNullOrWhiteSpace($Content)) {
        $Writer.WriteLine('_(no output)_')
    } else {
        $Writer.WriteLine($Content)
    }
}

# ---------------------------------------------------------------------------
# Step 1.1 — Identify current branch
# ---------------------------------------------------------------------------

$branch = Invoke-Git 'rev-parse', '--abbrev-ref', 'HEAD'
if ($branch -eq 'HEAD' -or [string]::IsNullOrWhiteSpace($branch)) {
    $branch = Invoke-Git 'branch', '--show-current'
}
if ([string]::IsNullOrWhiteSpace($branch)) {
    $branch = Invoke-Git 'log', '-1', '--format=%D'
}
if ([string]::IsNullOrWhiteSpace($branch)) {
    Write-Error 'Could not determine current branch. Are you in a git repository?'
    exit 1
}

Write-Host "Branch: $branch"

# ---------------------------------------------------------------------------
# Step 1.2 — Detect parent branch / revision range
# ---------------------------------------------------------------------------

$revRange = $null

if (-not [string]::IsNullOrWhiteSpace($Since)) {
    # Mode C: explicit starting commit
    $commitType = Invoke-Git 'cat-file', '-t', $Since
    if ($commitType -ne 'commit') {
        Write-Error "Commit '$Since' not found in this repository."
        exit 1
    }
    $revRange = "$Since..HEAD"
    $parentLabel = $Since
    Write-Host "Mode C — since commit: $Since"
} else {
    # Mode A: auto-detect parent
    $parentResult = Get-ParentBranch
    $revRange     = $parentResult.RevRange
    $parentLabel  = $parentResult.ParentLabel
}

Write-Host "Base: $parentLabel"

# ---------------------------------------------------------------------------
# Step 1.3 — List commits
# ---------------------------------------------------------------------------

Write-Host 'Collecting commits...'
$commits = Invoke-Git 'log', '--oneline', $revRange
Write-Host $commits

# ---------------------------------------------------------------------------
# Step 1.4 — Diff stat and per-file diffs
# ---------------------------------------------------------------------------

Write-Host 'Collecting diff stat...'
$diffStat = Invoke-Git 'diff', $revRange, '--stat'

Write-Host 'Collecting per-file diffs...'
$changedFiles = Invoke-Git 'diff', $revRange, '--name-only'
$fileCount = if ([string]::IsNullOrWhiteSpace($changedFiles)) { 0 } else { ($changedFiles -split "`r?`n" | Where-Object { $_.Trim() -ne '' }).Count }
Write-Host "Affected files: $fileCount"
$perFileDiffs = [System.Text.StringBuilder]::new()

$skipExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.svg', '.ico', '.webp',
                    '.pdf', '.zip', '.jar', '.class', '.bin', '.exe', '.dll')

if (-not [string]::IsNullOrWhiteSpace($changedFiles)) {
    foreach ($file in ($changedFiles -split "`r?`n" | Where-Object { $_.Trim() -ne '' })) {
        $file = $file.Trim()
        $ext = [System.IO.Path]::GetExtension($file).ToLower()
        if ($skipExtensions -contains $ext) {
            [void] $perFileDiffs.AppendLine("### $file")
            [void] $perFileDiffs.AppendLine('')
            [void] $perFileDiffs.AppendLine('_(binary or image file — skipped)_')
            [void] $perFileDiffs.AppendLine('')
            continue
        }
        $fileDiff = Invoke-Git 'diff', $revRange, "--unified=$Context", '--', $file
        [void] $perFileDiffs.AppendLine("### $file")
        [void] $perFileDiffs.AppendLine('')
        [void] $perFileDiffs.AppendLine('```diff')
        [void] $perFileDiffs.AppendLine($fileDiff)
        [void] $perFileDiffs.AppendLine('```')
        [void] $perFileDiffs.AppendLine('')
    }
}

# ---------------------------------------------------------------------------
# Determine output path
# ---------------------------------------------------------------------------

$repoRoot = Invoke-Git 'rev-parse', '--show-toplevel'
if ([string]::IsNullOrWhiteSpace($repoRoot)) {
    $repoRoot = (Get-Location).Path
}
$dataDir = Join-Path (Join-Path $repoRoot '.reviews') 'data'
if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Force -Path $dataDir | Out-Null
}

# ---------------------------------------------------------------------------
# Write structured output
# ---------------------------------------------------------------------------

$headHash    = Invoke-Git 'rev-parse', '--short', 'HEAD'
$fileName    = New-ReviewFileName -Branch $branch -CommitHash $headHash
$outputPath  = Join-Path $dataDir $fileName
$displayTime = Get-Date -Format 'yyyy-MM-dd HH:mm'

$writer = [System.IO.StreamWriter]::new($outputPath, $false, [System.Text.Encoding]::UTF8)
try {
    $writer.WriteLine("<!-- Code review Phase 1 data — generated $displayTime -->")
    $writer.WriteLine("<!-- Branch: $branch | Range: $revRange | HEAD: $headHash -->")

    Write-Section $writer 'Branch Info' "Branch: ``$branch``  `nParent / range: ``$parentLabel``  `nHEAD: ``$headHash``"
    Write-Section $writer 'Commits'         $commits
    Write-Section $writer 'Diff Stat'       $diffStat
    Write-Section $writer 'Per-File Diffs'  $perFileDiffs.ToString()

    # Instruction sections are left empty — the expert subagent fills them
    # using the cache check (SKILL.md Phase 1 steps 2.1–2.3).
    $writer.WriteLine('')
    $writer.WriteLine('## Instruction Summaries')
    $writer.WriteLine('')
    $writer.WriteLine('_(populated by expert subagent from instruction cache)_')
    $writer.WriteLine('')
    $writer.WriteLine('## Instruction Files (Full)')
    $writer.WriteLine('')
    $writer.WriteLine('_(populated by expert subagent for cache-miss files)_')
} finally {
    $writer.Close()
}

Write-Host ''
Write-Host "Phase 1 data written to: $outputPath"
Write-Host "File size: $([System.IO.FileInfo]::new($outputPath).Length) bytes"
Write-Host ''
Write-Host 'To use in a review, tell the code-reviewer skill:'
Write-Host "  ""review this branch using pre-collected diff"""
Write-Host ''
Write-Host 'Note: filename encodes the current HEAD hash. Re-run after new commits.'
