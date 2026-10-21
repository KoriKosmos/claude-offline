@echo off
rem Offline Claude Code installer for Windows, for systems where PowerShell
rem scripts are blocked. Plain cmd only: no PowerShell needed.
rem
rem Usage: install.cmd [latest^|stable^|VERSION]

setlocal EnableExtensions EnableDelayedExpansion

set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=latest"

rem PROCESSOR_ARCHITEW6432 is set when a 32-bit cmd runs on 64-bit Windows.
set "ARCH=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "ARCH=%PROCESSOR_ARCHITEW6432%"
if /i "%ARCH%"=="ARM64" (
    set "PLATFORM=win32-arm64"
) else if /i "%ARCH%"=="AMD64" (
    set "PLATFORM=win32-x64"
) else (
    echo Claude Code does not support 32-bit Windows. Please use a 64-bit version of Windows. 1>&2
    exit /b 1
)

set "RELEASES=%~dp0releases"

set "VERSION=%TARGET%"
set "POINTER="
if /i "%TARGET%"=="latest" set "POINTER=%RELEASES%\latest"
if /i "%TARGET%"=="stable" set "POINTER=%RELEASES%\stable"
if defined POINTER (
    if not exist "!POINTER!" (
        echo No %TARGET% version mirrored. Run mirror.sh first. 1>&2
        exit /b 1
    )
    for /f "usebackq delims=" %%v in ("!POINTER!") do set "VERSION=%%v"
)

set "PDIR=%RELEASES%\%VERSION%\%PLATFORM%"
if not exist "%PDIR%\checksum" (
    echo Claude Code %VERSION% for %PLATFORM% is not in this mirror. 1>&2
    exit /b 1
)
for /f "usebackq delims=" %%c in ("%PDIR%\checksum") do set "CHECKSUM=%%c"

echo Setting up Claude Code %VERSION%...

rem `claude install` always contacts downloads.claude.ai, even for a pinned
rem version, so lay out the native install the same way it does: the binary
rem in ~\.local\share\claude\versions\<version>, and ~\.local\bin\claude.exe.
set "VERSIONS_DIR=%USERPROFILE%\.local\share\claude\versions"
set "BIN_DIR=%USERPROFILE%\.local\bin"
if not exist "%VERSIONS_DIR%" mkdir "%VERSIONS_DIR%"
if not exist "%BIN_DIR%" mkdir "%BIN_DIR%"

set "BINARY=%VERSIONS_DIR%\%VERSION%"
set "TMPBIN=%BINARY%.tmp"

rem Join the parts in name order: copy /b part-aa+part-ab+... dest
set "SRC="
pushd "%PDIR%"
for /f "delims=" %%p in ('dir /b /on claude.part-*') do set "SRC=!SRC!+%%p"
copy /b /y !SRC:~1! "%TMPBIN%" >nul
set "COPY_RC=%ERRORLEVEL%"
popd
if not "%COPY_RC%"=="0" (
    echo Could not join the binary parts in %PDIR% 1>&2
    exit /b 1
)

rem certutil prints the hash on its second line; older Windows puts spaces
rem between the bytes, so strip them.
set "ACTUAL="
for /f "skip=1 delims=" %%h in ('certutil -hashfile "%TMPBIN%" SHA256') do (
    if not defined ACTUAL set "ACTUAL=%%h"
)
set "ACTUAL=%ACTUAL: =%"
if /i not "%ACTUAL%"=="%CHECKSUM%" (
    del /f "%TMPBIN%" >nul 2>&1
    echo Checksum verification failed ^(is the clone complete?^) 1>&2
    exit /b 1
)
move /y "%TMPBIN%" "%BINARY%" >nul

copy /b /y "%BINARY%" "%BIN_DIR%\claude.exe" >nul
if errorlevel 1 (
    echo Could not replace %BIN_DIR%\claude.exe. Close any running Claude Code sessions ^(including VS Code^) and try again. 1>&2
    exit /b 1
)

rem No network for updates, so turn off the auto-updater. An existing
rem settings.json can't be edited safely from cmd, so only say what to add.
if not exist "%USERPROFILE%\.claude" mkdir "%USERPROFILE%\.claude"
set "SETTINGS=%USERPROFILE%\.claude\settings.json"
if exist "%SETTINGS%" (
    findstr /c:"DISABLE_AUTOUPDATER" "%SETTINGS%" >nul || (
        echo Note: add "DISABLE_AUTOUPDATER": "1" under "env" in %SETTINGS% to stop update checks.
    )
) else (
    > "%SETTINGS%" echo {"env": {"DISABLE_AUTOUPDATER": "1"}}
)

rem Put ~\.local\bin on the user PATH. reg query shows the raw value, so
rem entries like %%USERPROFILE%%\... stay unexpanded. Not setx PATH: it cuts
rem values over 1024 characters.
set "USERPATH="
for /f "skip=2 tokens=2,*" %%a in ('reg query HKCU\Environment /v Path 2^>nul') do set "USERPATH=%%b"
rem Substitution is case-insensitive: if removing the entry changes the
rem string, it's already there.
set "HAS_BIN="
set "CHK=;!USERPATH!;"
if /i not "!CHK:;%BIN_DIR%;=!"=="!CHK!" set "HAS_BIN=1"
if /i not "!CHK:;%%USERPROFILE%%\.local\bin;=!"=="!CHK!" set "HAS_BIN=1"
if not defined HAS_BIN (
    if defined USERPATH (
        if "!USERPATH:~-1!"==";" (set "NEWPATH=!USERPATH!%BIN_DIR%") else (set "NEWPATH=!USERPATH!;%BIN_DIR%")
    ) else (
        set "NEWPATH=%BIN_DIR%"
    )
    reg add HKCU\Environment /v Path /t REG_EXPAND_SZ /d "!NEWPATH!" /f >nul
    rem reg doesn't tell running programs the environment changed; setx
    rem does. Set and remove a throwaway variable so new terminals see PATH.
    setx CLAUDE_OFFLINE_PATH_REFRESH 1 >nul
    reg delete HKCU\Environment /v CLAUDE_OFFLINE_PATH_REFRESH /f >nul 2>&1
    echo Added %BIN_DIR% to your PATH. Open a new terminal to use it.
)

"%BIN_DIR%\claude.exe" --version

echo.
echo Installation complete!
echo.
endlocal
