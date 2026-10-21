# Offline Claude Code installer for Windows. Works from a clone of this repo
# with no network access: it uses the binaries mirror.sh stored under
# releases\ instead of downloads.claude.ai.
#
# Usage: powershell -ExecutionPolicy Bypass -File .\install.ps1 [latest|stable|VERSION]
#
# Uses only cmdlets and native commands (no .NET calls), so it also runs in
# Constrained Language Mode. If PowerShell scripts are blocked outright, use
# install.cmd instead.

param(
    [Parameter(Position=0)]
    [ValidatePattern('^(stable|latest|\d+\.\d+\.\d+(-[^\s]+)?)$')]
    [string]$Target = "latest"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# PROCESSOR_ARCHITEW6432 is set when 32-bit PowerShell runs on 64-bit Windows.
$arch = $env:PROCESSOR_ARCHITECTURE
if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
switch ($arch) {
    "ARM64" { $platform = "win32-arm64" }
    "AMD64" { $platform = "win32-x64" }
    default {
        Write-Error "Claude Code does not support 32-bit Windows. Please use a 64-bit version of Windows."
        exit 1
    }
}

$ReleasesDir = Join-Path $PSScriptRoot "releases"

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

# Join the parts with cmd's `copy /b`: fast, and needs no .NET.
$parts = @(Get-ChildItem -Path $platformDir -Filter "claude.part-*" | Sort-Object Name | ForEach-Object { $_.Name })
Push-Location $platformDir
try {
    & cmd /c copy /b /y ($parts -join "+") $tmpPath | Out-Null
    $copyExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($copyExitCode -ne 0) {
    Write-Error "Could not join the binary parts in $platformDir"
    exit 1
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
    $settings = New-Object -TypeName PSObject
}
if (@($settings.PSObject.Properties | Where-Object { $_.Name -eq "env" }).Count -eq 0) {
    $settings | Add-Member -NotePropertyName env -NotePropertyValue (New-Object -TypeName PSObject)
}
$settings.env | Add-Member -Force -NotePropertyName DISABLE_AUTOUPDATER -NotePropertyValue "1"
$settings | ConvertTo-Json -Depth 32 | Set-Content -Encoding UTF8 $settingsPath

# Put ~\.local\bin on the user PATH. Read and write the raw registry value
# with reg.exe so entries like %USERPROFILE%\... stay unexpanded.
$userPath = ""
$query = & reg query "HKCU\Environment" /v Path 2>$null
foreach ($line in $query) {
    if ($line -match '^\s+Path\s+REG_\w+\s+(.*)$') { $userPath = $Matches[1] }
}
$entries = $userPath -split ";" | Where-Object { $_ -ne "" }
if (($entries -notcontains $binDir) -and ($entries -notcontains "%USERPROFILE%\.local\bin")) {
    $newPath = (@($entries) + $binDir) -join ";"
    & reg add "HKCU\Environment" /v Path /t REG_EXPAND_SZ /d $newPath /f | Out-Null
    # reg.exe doesn't tell running programs the environment changed; setx
    # does. Set and remove a throwaway variable so new terminals see PATH.
    & setx CLAUDE_OFFLINE_PATH_REFRESH 1 | Out-Null
    & reg delete "HKCU\Environment" /v CLAUDE_OFFLINE_PATH_REFRESH /f 2>$null | Out-Null
    $env:Path = "$env:Path;$binDir"
    Write-Output "Added $binDir to your PATH. Open a new terminal to use it."
}

& $exePath --version

Write-Output ""
Write-Output "$([char]0x2705) Installation complete!"
Write-Output ""
