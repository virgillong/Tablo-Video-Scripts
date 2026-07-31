@echo off
setlocal enabledelayedexpansion

REM get directory where script is running
set "rootDir=%~dp0"
echo "rootDir: !rootDir!"

REM normalize so that rootDir equals value of menu.bat in main script
REM do this by setting it up one directory level and adding backslash
for %%I in ("%~dp0..") do set "rootDir=%%~fI\")

REM Call PowerShell script 
:again

REM powershell -ExecutionPolicy Bypass -File "%rootDir%\etc\ffmpegEncode.ps1" -Encoder  "FFmpeg"
pwsh -ExecutionPolicy Bypass -File "!rootDir!\etc\videoJoin.ps1" -Encoder  "FFmpeg"

exit /b
