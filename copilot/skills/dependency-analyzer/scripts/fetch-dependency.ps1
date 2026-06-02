<#
.SYNOPSIS
    Fetch a Maven dependency JAR (sources or compiled) from local .m2 or remote.

.DESCRIPTION
    Cascading fetch strategy:
    A) Check local .m2 for -sources.jar
    B) mvn dependency:copy for sources
    C) HTTP fallback to Maven Central for sources
    D) Repeat A-C for main (compiled) JAR if sources unavailable

.PARAMETER GroupId
    Maven groupId (e.g. org.apache.commons).

.PARAMETER ArtifactId
    Maven artifactId (e.g. commons-lang3).

.PARAMETER Version
    Maven version (e.g. 3.12.0).

.PARAMETER ProjectDir
    Project directory (for running mvn commands with proper settings).

.PARAMETER M2Repo
    Path to local Maven repository. Defaults to ~/.m2/repository.

.OUTPUTS
    PSCustomObject with JarPath, IsSources, FetchMethod properties.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$GroupId,

    [Parameter(Mandatory)]
    [string]$ArtifactId,

    [Parameter(Mandatory)]
    [string]$Version,

    [string]$ProjectDir = '.',

    [string]$M2Repo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $M2Repo) {
    $M2Repo = Join-Path $HOME '.m2' 'repository'
}

# Convert groupId to path segments
$groupPath = $GroupId -replace '\.', [IO.Path]::DirectorySeparatorChar
$artifactBase = Join-Path $M2Repo $groupPath $ArtifactId $Version

function Get-MavenCentralUrl {
    param([string]$Classifier)
    $gPath = $GroupId -replace '\.', '/'
    $fileName = if ($Classifier) { "$ArtifactId-$Version-$Classifier.jar" } else { "$ArtifactId-$Version.jar" }
    return "https://repo1.maven.org/maven2/$gPath/$ArtifactId/$Version/$fileName"
}

function Try-LocalM2 {
    param([string]$Classifier)
    $fileName = if ($Classifier) { "$ArtifactId-$Version-$Classifier.jar" } else { "$ArtifactId-$Version.jar" }
    $localPath = Join-Path $artifactBase $fileName
    if (Test-Path $localPath) {
        return $localPath
    }
    return $null
}

function Try-MavenCopy {
    param([string]$Classifier)
    $artifact = "${GroupId}:${ArtifactId}:${Version}"
    if ($Classifier) { $artifact += ":jar:$Classifier" }
    $tempDir = Join-Path ([IO.Path]::GetTempPath()) "dep-fetch-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

    try {
        $mvnArgs = "dependency:copy -Dartifact=$artifact -DoutputDirectory=`"$tempDir`" -B -ntp 2>&1"
        if ($env:OS -match 'Windows') {
            $output = cmd /c "cd /d `"$ProjectDir`" && mvn $mvnArgs" 2>&1 | Out-String
        } else {
            $output = bash -c "cd '$ProjectDir' && mvn $mvnArgs" 2>&1 | Out-String
        }

        if ($output -match 'BUILD SUCCESS') {
            $jars = Get-ChildItem -Path $tempDir -Filter '*.jar' | Select-Object -First 1
            if ($jars) {
                # Copy to local .m2 for future use
                if (-not (Test-Path $artifactBase)) {
                    New-Item -ItemType Directory -Force -Path $artifactBase | Out-Null
                }
                $destPath = Join-Path $artifactBase $jars.Name
                Copy-Item -Path $jars.FullName -Destination $destPath -Force
                return $destPath
            }
        }
    } catch {
        Write-Verbose "Maven dependency:copy failed: $_"
    } finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $null
}

function Try-HttpDownload {
    param([string]$Classifier)
    $url = Get-MavenCentralUrl -Classifier $Classifier
    $fileName = if ($Classifier) { "$ArtifactId-$Version-$Classifier.jar" } else { "$ArtifactId-$Version.jar" }

    if (-not (Test-Path $artifactBase)) {
        New-Item -ItemType Directory -Force -Path $artifactBase | Out-Null
    }
    $destPath = Join-Path $artifactBase $fileName

    try {
        Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing -ErrorAction Stop
        if ((Get-Item $destPath).Length -gt 0) {
            return $destPath
        }
    } catch {
        Write-Verbose "HTTP download failed for $url : $_"
        Remove-Item -Path $destPath -ErrorAction SilentlyContinue
    }
    return $null
}

function Fetch-Jar {
    param([string]$Classifier, [bool]$IsSources)

    # Step A: Local .m2
    $path = Try-LocalM2 -Classifier $Classifier
    if ($path) {
        return [PSCustomObject]@{ JarPath = $path; IsSources = $IsSources; FetchMethod = 'local-m2' }
    }

    # Step B: Maven dependency:copy
    Write-Host "Not in local .m2. Trying mvn dependency:copy..." -ForegroundColor Yellow
    $path = Try-MavenCopy -Classifier $Classifier
    if ($path) {
        return [PSCustomObject]@{ JarPath = $path; IsSources = $IsSources; FetchMethod = 'maven-copy' }
    }

    # Step C: HTTP download from Maven Central
    Write-Host "Maven copy failed. Trying direct download from Maven Central..." -ForegroundColor Yellow
    $path = Try-HttpDownload -Classifier $Classifier
    if ($path) {
        return [PSCustomObject]@{ JarPath = $path; IsSources = $IsSources; FetchMethod = 'maven-central-http' }
    }

    return $null
}

# --- Main ---

# Try sources JAR first
Write-Host "Fetching sources JAR for ${GroupId}:${ArtifactId}:${Version}..." -ForegroundColor Cyan
$result = Fetch-Jar -Classifier 'sources' -IsSources $true

if ($result) {
    $result
    exit 0
}

# Fall back to main (compiled) JAR
Write-Host "Sources JAR not available. Fetching compiled JAR..." -ForegroundColor Yellow
$result = Fetch-Jar -Classifier '' -IsSources $false

if ($result) {
    $result
    exit 0
}

Write-Error "Failed to fetch ${GroupId}:${ArtifactId}:${Version} from any source (local .m2, Maven CLI, Maven Central HTTP)."
exit 1
