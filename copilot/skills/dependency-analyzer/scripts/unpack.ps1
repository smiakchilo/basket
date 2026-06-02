<#
.SYNOPSIS
    Unpack a JAR file to .dependency-sources/ under the project root.

.PARAMETER JarPath
    Path to the JAR file to unpack.

.PARAMETER ProjectDir
    Root directory of the project.

.PARAMETER GroupId
    Maven groupId for organizing unpacked files.

.PARAMETER ArtifactId
    Maven artifactId for organizing unpacked files.

.PARAMETER Version
    Maven version for organizing unpacked files.

.OUTPUTS
    String — absolute path to the unpacked directory.
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

# Skip if already unpacked
if (Test-Path $targetDir) {
    $existingFiles = Get-ChildItem -Path $targetDir -Recurse -File | Select-Object -First 1
    if ($existingFiles) {
        Write-Host "Already unpacked at: $targetDir" -ForegroundColor Green
        Write-Output $targetDir
        exit 0
    }
}

# Create target directory
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

# Unpack using jar (preferred) or .NET ZipFile
$jarExe = Get-Command 'jar' -ErrorAction SilentlyContinue
if ($jarExe) {
    Push-Location $targetDir
    try {
        $jarAbsPath = (Resolve-Path $JarPath).Path
        & jar xf "$jarAbsPath" 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "jar xf failed with exit code $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }
} else {
    # Fallback: use .NET ZipFile
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($JarPath, $targetDir)
}

# Remove META-INF — usually not useful for source analysis
$metaInf = Join-Path $targetDir 'META-INF'
if (Test-Path $metaInf) {
    Remove-Item -Path $metaInf -Recurse -Force -ErrorAction SilentlyContinue
}

$fileCount = (Get-ChildItem -Path $targetDir -Recurse -File).Count
Write-Host "Unpacked $fileCount files to: $targetDir" -ForegroundColor Green
Write-Output $targetDir
