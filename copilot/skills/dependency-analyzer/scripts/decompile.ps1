<#
.SYNOPSIS
    Decompile a compiled JAR using CFR (version auto-detected from tools/ folder).

.PARAMETER JarPath
    Path to the compiled JAR file to decompile.

.PARAMETER ProjectDir
    Root directory of the project (target dir base).

.PARAMETER GroupId
    Maven groupId for organizing decompiled files.

.PARAMETER ArtifactId
    Maven artifactId for organizing decompiled files.

.PARAMETER Version
    Maven version for organizing decompiled files.

.OUTPUTS
    String — absolute path to the decompiled sources directory.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$JarPath,

    [Parameter(Mandatory)]
    [string]$ProjectDir,

    [Parameter(Mandatory)]
    [string]$GroupId,

    [Parameter(Mandatory)]
    [string]$ArtifactId,

    [Parameter(Mandatory)]
    [string]$Version
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$targetDir = Join-Path $ProjectDir '.dependency-sources' $GroupId "$ArtifactId-$Version"

# Skip if already decompiled
if (Test-Path $targetDir) {
    $javaFiles = Get-ChildItem -Path $targetDir -Recurse -Filter '*.java' | Select-Object -First 1
    if ($javaFiles) {
        Write-Host "Already decompiled at: $targetDir" -ForegroundColor Green
        Write-Output $targetDir
        exit 0
    }
}

# Locate CFR JAR — discover whichever version is in the tools/ folder
$skillDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$toolsDir = Join-Path $skillDir 'tools'
$cfrJar = Get-ChildItem -Path $toolsDir -Filter 'cfr-*.jar' | Select-Object -First 1

if (-not $cfrJar) {
    Write-Error "No CFR JAR (cfr-*.jar) found in: $toolsDir"
    exit 1
}

$cfrVersion = $cfrJar.BaseName -replace '^cfr-', ''

# Verify java is available
$javaExe = Get-Command 'java' -ErrorAction SilentlyContinue
if (-not $javaExe) {
    Write-Error "Java not found in PATH. A JRE/JDK is required for decompilation."
    exit 1
}

# Create target directory
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

# Run CFR
Write-Host "Decompiling $JarPath with CFR $cfrVersion..." -ForegroundColor Cyan
$jarAbsPath = (Resolve-Path $JarPath).Path
$cfrAbsPath = (Resolve-Path $cfrJar.FullName).Path

& java -jar "$cfrAbsPath" "$jarAbsPath" --outputdir "$targetDir" --silent true 2>&1 | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Error "CFR decompilation failed with exit code $LASTEXITCODE"
    exit 1
}

# Remove summary file if CFR generates one
$summaryFile = Join-Path $targetDir 'summary.txt'
if (Test-Path $summaryFile) {
    Remove-Item -Path $summaryFile -Force -ErrorAction SilentlyContinue
}

$javaCount = (Get-ChildItem -Path $targetDir -Recurse -Filter '*.java').Count
Write-Host "Decompiled $javaCount Java files to: $targetDir" -ForegroundColor Green
Write-Output $targetDir
