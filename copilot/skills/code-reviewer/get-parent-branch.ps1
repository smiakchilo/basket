<#
.SYNOPSIS
    Single source of truth for detecting the parent branch of the current Git branch.

.DESCRIPTION
    Tries four strategies in order and returns the first valid result:

      Strategy A — Upstream tracking branch:
          git rev-parse --abbrev-ref @{upstream}

      Strategy B — Branch-tip walk (first-parent log):
          Walks the first-parent ancestry of HEAD and returns the branch ref
          on the first decorated commit that belongs to a different branch.
          Prefers local branch refs over remote-tracking refs.

      Strategy C — Nearest common ancestor among well-known base branches
          (main, master, develop, dev). Picks the most recent merge-base.

      Strategy D — Reflog-based detection:
          git reflog show --no-abbrev HEAD | grep "checkout: moving from"

    When run directly (not dot-sourced), calls Get-ParentBranch and prints the result.
    Dot-source this file wherever parent-branch detection is needed:
        . "$PSScriptRoot\get-parent-branch.ps1"

.FUNCTIONS
    Get-ParentBranch
#>

function Get-ParentBranch {
    <#
    .SYNOPSIS
        Detects the parent branch of the current Git branch.
    .OUTPUTS
        PSCustomObject with two properties:
          RevRange    — Git revision range, e.g. "origin/main..HEAD" or "abc12345..HEAD"
          ParentLabel — Human-readable description, e.g. "main (merge-base abc12345)"
    .NOTES
        Throws a terminating error if all four strategies fail.
    #>

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

    # Strategy A — upstream tracking branch
    $upstream = Invoke-Git 'rev-parse', '--abbrev-ref', '@{upstream}'
    if (-not [string]::IsNullOrWhiteSpace($upstream)) {
        Write-Host "Parent (upstream): $upstream"
        return [PSCustomObject]@{
            RevRange    = "$upstream..HEAD"
            ParentLabel = $upstream
        }
    }

    # Strategy B — walk first-parent log to find the first commit decorated with another branch
    $currentBranch = Invoke-Git 'rev-parse', '--abbrev-ref', 'HEAD'
    $remoteNames   = @((Invoke-Git 'remote') -split "`r?`n" |
                        Where-Object { $_.Trim() -ne '' } |
                        ForEach-Object { $_.Trim() })

    $logOutput = Invoke-Git 'log', '--first-parent', '--format=%H %D', 'HEAD'
    if (-not [string]::IsNullOrWhiteSpace($logOutput)) {
        foreach ($line in ($logOutput -split "`r?`n")) {
            $line = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            $spaceIdx = $line.IndexOf(' ')
            if ($spaceIdx -lt 0) { continue }   # no decoration on this commit

            $hash       = $line.Substring(0, $spaceIdx)
            $decoration = $line.Substring($spaceIdx + 1).Trim()
            if ([string]::IsNullOrWhiteSpace($decoration)) { continue }

            $localRef  = $null
            $remoteRef = $null

            foreach ($ref in ($decoration -split ',')) {
                $ref = $ref.Trim()
                if ([string]::IsNullOrWhiteSpace($ref)) { continue }
                if ($ref -match '^HEAD' -or $ref -match '^tag:') { continue }
                if ($ref -eq $currentBranch) { continue }

                # Determine whether this is a remote-tracking ref by checking if its
                # first path component is a known remote name (e.g. "origin").
                $firstComponent = ($ref -split '/', 2)[0]
                if ($remoteNames -contains $firstComponent) {
                    # Skip if this remote-tracking ref just tracks the current branch.
                    $localPart = ($ref -split '/', 2)[-1]
                    if ($localPart -eq $currentBranch) { continue }
                    if ($null -eq $remoteRef) { $remoteRef = $ref }
                } else {
                    if ($null -eq $localRef) { $localRef = $ref }
                }
            }

            $parentRef = if ($null -ne $localRef) { $localRef } elseif ($null -ne $remoteRef) { $remoteRef } else { $null }
            if ($null -ne $parentRef) {
                Write-Host "Parent (branch-tip): $parentRef"
                return [PSCustomObject]@{
                    RevRange    = "$hash..HEAD"
                    ParentLabel = $parentRef
                }
            }
        }
    }

    # Strategy C — nearest common ancestor among well-known base branches
    $candidates = @('main', 'master', 'develop', 'dev')
    $bestHash   = $null
    $bestBase   = $null
    foreach ($base in $candidates) {
        $hash = Invoke-Git 'merge-base', '--fork-point', $base, 'HEAD'
        if (-not [string]::IsNullOrWhiteSpace($hash)) {
            if ($null -eq $bestHash) {
                $bestHash = $hash
                $bestBase = $base
            } else {
                # Prefer the most recent (closest) merge-base
                Invoke-Git 'merge-base', '--is-ancestor', $bestHash, $hash | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $bestHash = $hash
                    $bestBase = $base
                }
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($bestHash)) {
        $label = "$bestBase (merge-base $($bestHash.Substring(0, 8)))"
        Write-Host "Parent (merge-base): $label"
        return [PSCustomObject]@{
            RevRange    = "$bestHash..HEAD"
            ParentLabel = $label
        }
    }

    # Strategy D — reflog-based detection
    $reflogLine = Invoke-Git 'reflog', 'show', '--no-abbrev', 'HEAD' |
        Select-String 'checkout: moving from' |
        Select-Object -First 1
    if ($null -ne $reflogLine) {
        $fromBranch = ($reflogLine -replace '.*checkout: moving from (\S+) to.*', '$1').Trim()
        if (-not [string]::IsNullOrWhiteSpace($fromBranch)) {
            Write-Host "Parent (reflog): $fromBranch"
            return [PSCustomObject]@{
                RevRange    = "$fromBranch..HEAD"
                ParentLabel = "$fromBranch (reflog)"
            }
        }
    }

    Write-Error 'Could not detect a parent branch. Use -Since <commit> to specify the revision range explicitly.'
    exit 1
}

# ---------------------------------------------------------------------------
# Standalone execution
# ---------------------------------------------------------------------------

if ($MyInvocation.InvocationName -ne '.') {
    $result = Get-ParentBranch
    Write-Host "RevRange:    $($result.RevRange)"
    Write-Host "ParentLabel: $($result.ParentLabel)"
}
