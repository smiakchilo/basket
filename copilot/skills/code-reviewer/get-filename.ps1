<#
.SYNOPSIS
    Single source of truth for code-review filename formatting.

.DESCRIPTION
    Both the Phase 1 data files (.reviews/data/) and the final review report files
    (.reviews/) share the same filename stem:

        <normalized-branch>__<short-commit-hash>__<yyyyMMdd-HHmm>.md

    Normalization rules applied to the branch name:
      - Strip the leading "<type>/" prefix if present  (feature/EAK-651 -> EAK-651)
      - Replace any remaining characters that are illegal in Windows/Linux filenames
        ( / \ : * ? " < > | ) with a hyphen

        Dot-source this file wherever the filename format is needed:
            . "$PSScriptRoot\get-filename.ps1"

.FUNCTIONS
    Get-NormalizedBranchName  -Branch <string>
    New-ReviewFileName        -Branch <string> -CommitHash <string> [-Timestamp <string>]
#>

function Get-NormalizedBranchName {
    <#
    .SYNOPSIS
        Strips the type-prefix and sanitizes a git branch name for use in a filename.
    .PARAMETER Branch
        Raw git branch name, e.g. "feature/EAK-651" or "EAK-651-my-fix".
    .OUTPUTS
        Sanitized string safe for use in a filename, e.g. "EAK-651" or "EAK-651-my-fix".
    #>
    param([Parameter(Mandatory)][string] $Branch)

    $normalized = $Branch -replace '^[^/]+/', ''          # strip leading type-prefix
    $normalized = $normalized -replace '[/\\:*?"<>|]', '-' # sanitize remaining chars
    return $normalized
}

function New-ReviewFileName {
    <#
    .SYNOPSIS
        Produces the canonical filename for a code-review file (report or data).
    .PARAMETER Branch
        Raw git branch name.
    .PARAMETER CommitHash
        Short commit hash (output of "git rev-parse --short HEAD").
    .PARAMETER Timestamp
        Optional. Timestamp string in yyyyMMdd-HHmm format.
        Defaults to the current local time when omitted.
    .OUTPUTS
        Filename string including the .md extension, e.g.:
          EAK-651__4d0deaec__20260501-1030.md
    #>
    param(
        [Parameter(Mandatory)][string] $Branch,
        [Parameter(Mandatory)][string] $CommitHash,
        [string] $Timestamp = ''
    )

    if ([string]::IsNullOrWhiteSpace($Timestamp)) {
        $Timestamp = Get-Date -Format 'yyyyMMdd-HHmm'
    }

    $safeBranch = Get-NormalizedBranchName -Branch $Branch
    return "${safeBranch}__${CommitHash}__${Timestamp}.md"
}
