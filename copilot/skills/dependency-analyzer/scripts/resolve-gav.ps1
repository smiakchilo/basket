<#
.SYNOPSIS
    Resolve the groupId, artifactId, and version (GAV) of a Maven dependency
    from the project's POM hierarchy, including transitive dependencies.

.PARAMETER ProjectDir
    Root directory of the Maven project.

.PARAMETER ArtifactId
    Known or partial artifactId to search for.

.PARAMETER GroupId
    Known or partial groupId to narrow the search.

.PARAMETER ClassName
    Fully-qualified class name to search for in dependency tree output.

.OUTPUTS
    PSCustomObject with GroupId, ArtifactId, Version, Scope, Source properties.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectDir,

    [string]$ArtifactId,
    [string]$GroupId,
    [string]$ClassName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Helpers ---

function Find-PomFiles {
    param([string]$RootDir)
    $poms = @()
    $rootPom = Join-Path $RootDir 'pom.xml'
    if (Test-Path $rootPom) {
        $poms += $rootPom
        [xml]$xml = Get-Content $rootPom -Raw
        $ns = @{}
        if ($xml.project.xmlns) {
            $ns = @{ m = $xml.project.xmlns }
        }
        # Discover modules
        $modules = if ($ns.Count -gt 0) {
            $xml | Select-Xml -XPath '//m:modules/m:module' -Namespace $ns | ForEach-Object { $_.Node.InnerText }
        } else {
            $xml | Select-Xml -XPath '//modules/module' | ForEach-Object { $_.Node.InnerText }
        }
        foreach ($mod in $modules) {
            $modPom = Join-Path $RootDir $mod 'pom.xml'
            if (Test-Path $modPom) { $poms += $modPom }
        }
    }
    return $poms
}

function Resolve-Properties {
    param([xml]$Xml, [string]$Value)
    if (-not $Value) { return $Value }
    $result = $Value
    while ($result -match '\$\{(.+?)\}') {
        $propName = $Matches[1]
        $propNode = $Xml.project.properties
        if ($propNode -and $propNode.$propName) {
            $result = $result -replace [regex]::Escape("`${$propName}"), $propNode.$propName
        } else {
            # Check parent properties
            $parentProps = $Xml.project.parent
            if ($parentProps -and $propName -eq 'project.version' -and $parentProps.version) {
                $result = $result -replace [regex]::Escape("`${$propName}"), $parentProps.version
            } else {
                break
            }
        }
    }
    return $result
}

function Search-PomDependencies {
    param([string]$PomPath, [string]$SearchArtifactId, [string]$SearchGroupId)
    [xml]$xml = Get-Content $PomPath -Raw
    $results = @()

    # Search in <dependencies> and <dependencyManagement><dependencies>
    $depSections = @()
    if ($xml.project.dependencies) { $depSections += $xml.project.dependencies }
    if ($xml.project.dependencyManagement -and $xml.project.dependencyManagement.dependencies) {
        $depSections += $xml.project.dependencyManagement.dependencies
    }

    foreach ($section in $depSections) {
        foreach ($dep in $section.dependency) {
            if (-not $dep) { continue }
            $g = Resolve-Properties -Xml $xml -Value $dep.groupId
            $a = Resolve-Properties -Xml $xml -Value $dep.artifactId
            $v = Resolve-Properties -Xml $xml -Value $dep.version
            $s = if ($dep.scope) { $dep.scope } else { 'compile' }

            $match = $false
            if ($SearchArtifactId -and $a -like "*$SearchArtifactId*") { $match = $true }
            if ($SearchGroupId -and $g -like "*$SearchGroupId*") {
                if (-not $SearchArtifactId -or $match) { $match = $true }
            }
            if (-not $SearchArtifactId -and -not $SearchGroupId) { continue }

            if ($match) {
                $results += [PSCustomObject]@{
                    GroupId    = $g
                    ArtifactId = $a
                    Version    = $v
                    Scope      = $s
                    Source     = "POM: $PomPath"
                }
            }
        }
    }
    return $results
}

# --- Main ---

if (-not $ArtifactId -and -not $GroupId -and -not $ClassName) {
    Write-Error "At least one of -ArtifactId, -GroupId, or -ClassName must be specified."
    exit 1
}

if (-not (Test-Path (Join-Path $ProjectDir 'pom.xml'))) {
    Write-Error "No pom.xml found in $ProjectDir"
    exit 1
}

# Phase 1: Direct POM search (fast path)
if ($ArtifactId -or $GroupId) {
    $poms = Find-PomFiles -RootDir $ProjectDir
    $found = @()
    foreach ($pom in $poms) {
        $found += Search-PomDependencies -PomPath $pom -SearchArtifactId $ArtifactId -SearchGroupId $GroupId
    }
    if ($found.Count -gt 0) {
        # Deduplicate, prefer entries with a version
        $deduped = $found | Sort-Object -Property @{Expression={if($_.Version){'0'}else{'1'}}}, GroupId, ArtifactId -Unique
        $deduped | ForEach-Object { $_ }
        exit 0
    }
}

# Phase 2: Full dependency tree (handles transitive deps)
Write-Host "Direct POM search found nothing. Running mvn dependency:tree..." -ForegroundColor Yellow

$searchPattern = if ($ArtifactId) { $ArtifactId }
                 elseif ($GroupId) { $GroupId }
                 elseif ($ClassName) {
                     # Convert class name to a package prefix guess
                     $parts = $ClassName -split '\.'
                     if ($parts.Count -ge 3) { ($parts[0..2] -join '.') } else { $ClassName }
                 }
                 else { '' }

$mvnCmd = "cd /d `"$ProjectDir`" && mvn dependency:tree -B -ntp -Dincludes=*$searchPattern* 2>&1"
if ($env:OS -match 'Windows') {
    $output = cmd /c $mvnCmd 2>&1 | Out-String
} else {
    $output = bash -c "cd '$ProjectDir' && mvn dependency:tree -B -ntp -Dincludes='*$searchPattern*' 2>&1" | Out-String
}

# Parse dependency:tree output lines like:
#   [INFO] +- com.example:my-lib:jar:1.2.3:compile
#   [INFO] |  \- org.other:transitive:jar:4.5.6:runtime
$treePattern = '[\+\|\\\-\s]+([\w\.\-]+):([\w\.\-]+):([\w]+):([\w\.\-]+):([\w]+)'
$treeResults = @()

foreach ($line in ($output -split "`n")) {
    if ($line -match $treePattern) {
        $treeResults += [PSCustomObject]@{
            GroupId    = $Matches[1]
            ArtifactId = $Matches[2]
            Version    = $Matches[4]
            Scope      = $Matches[5]
            Source     = 'dependency:tree'
        }
    }
}

if ($treeResults.Count -eq 0) {
    Write-Error "Dependency not found in POM hierarchy or dependency tree. Verify the artifact coordinates."
    exit 1
}

# If searching by ClassName, filter further
if ($ClassName -and -not $ArtifactId -and -not $GroupId) {
    $classPackage = ($ClassName -split '\.' | Select-Object -SkipLast 1) -join '.'
    $filtered = $treeResults | Where-Object { $_.GroupId -like "*$($classPackage.Split('.')[0..1] -join '.')*" }
    if ($filtered.Count -gt 0) { $treeResults = $filtered }
}

$treeResults | ForEach-Object { $_ }
