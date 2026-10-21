# Offline Claude Code installer for Windows. Works from a clone of this repo
# with no network access: it uses the binaries mirror.sh stored under
# releases\ instead of downloads.claude.ai.
#
# Usage: .\install.ps1 [latest|stable|VERSION]

param(
    [Parameter(Position=0)]
    [ValidatePattern('^(stable|latest|\d+\.\d+\.\d+(-[^\s]+)?)$')]
    [string]$Target = "latest"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not [Environment]::Is64BitProcess) {
    Write-Error "Claude Code does not support 32-bit Windows. Please use a 64-bit version of Windows."
    exit 1
}

$ReleasesDir = Join-Path $PSScriptRoot "releases"

if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
    $platform = "win32-arm64"
} else {
    $platform = "win32-x64"
}

if ($Target -eq "latest" -or $Target -eq "stable") {
    $pointer = Join-Path $ReleasesDir $Target
    if (-not (Test-Path $pointer)) {
        Write-Error "No $Target version mirrored. Run mirror.sh first."
        exit 1
    }
    $version = (Get-Content -Raw $pointer).Trim()
} else {
    $version = $Target
}

$platformDir = Join-Path (Join-Path $ReleasesDir $version) $platform
$checksumFile = Join-Path $platformDir "checksum"
if (-not (Test-Path $checksumFile)) {
    Write-Error "Claude Code $version for $platform is not in this mirror."
    exit 1
}
$checksum = (Get-Content -Raw $checksumFile).Trim()

Write-Output "Setting up Claude Code $version..."

# `claude install` always contacts downloads.claude.ai, even for a pinned
# version, so lay out the native install the same way it does: the binary in
# ~\.local\share\claude\versions\<version>, and ~\.local\bin\claude.exe.
$versionsDir = Join-Path $env:USERPROFILE ".local\share\claude\versions"
$binDir = Join-Path $env:USERPROFILE ".local\bin"
New-Item -ItemType Directory -Force -Path $versionsDir, $binDir | Out-Null

$binaryPath = Join-Path $versionsDir $version
$tmpPath = "$binaryPath.tmp"
$parts = Get-ChildItem -Path $platformDir -Filter "claude.part-*" | Sort-Object Name
$out = [System.IO.File]::Create($tmpPath)
try {
    foreach ($part in $parts) {
        $in = [System.IO.File]::OpenRead($part.FullName)
        try { $in.CopyTo($out) } finally { $in.Dispose() }
    }
} finally {
    $out.Dispose()
}

$actual = (Get-FileHash -Path $tmpPath -Algorithm SHA256).Hash.ToLower()
if ($actual -ne $checksum) {
    Remove-Item -Force $tmpPath
    Write-Error "Checksum verification failed (is the clone complete?)"
    exit 1
}
Move-Item -Force $tmpPath $binaryPath

$exePath = Join-Path $binDir "claude.exe"
try {
    Copy-Item -Force $binaryPath $exePath
} catch {
    Write-Error "Could not replace $exePath. Close any running Claude Code sessions (including VS Code) and try again."
    exit 1
}

# No network for updates, so turn off the auto-updater.
$claudeDir = Join-Path $env:USERPROFILE ".claude"
$settingsPath = Join-Path $claudeDir "settings.json"
New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
if (Test-Path $settingsPath) {
    $settings = Get-Content -Raw $settingsPath | ConvertFrom-Json
} else {
    $settings = [pscustomobject]@{}
}
if (-not ($settings.PSObject.Properties.Name -contains "env")) {
    $settings | Add-Member -NotePropertyName env -NotePropertyValue ([pscustomobject]@{})
}
$settings.env | Add-Member -Force -NotePropertyName DISABLE_AUTOUPDATER -NotePropertyValue "1"
$settings | ConvertTo-Json -Depth 32 | Set-Content -Encoding UTF8 $settingsPath

# Put ~\.local\bin on the user PATH.
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if (-not $userPath) { $userPath = "" }
if (($userPath -split ";") -notcontains $binDir) {
    [Environment]::SetEnvironmentVariable("Path", (($userPath.TrimEnd(";") + ";" + $binDir).TrimStart(";")), "User")
    $env:Path = "$env:Path;$binDir"
    Write-Output "Added $binDir to your PATH. Open a new terminal to use it."
}

& $exePath --version

Write-Output ""
Write-Output "$([char]0x2705) Installation complete!"
Write-Output ""
