@echo off
setlocal enabledelayedexpansion

REM get directory where script is running
set "rootDir=%~dp0"
echo "rootDir: !rootDir!"

REM normalize so that rootDir equals value of menu.bat in main script
REM do this by setting it up one directory level and adding backslash
for %%I in ("%~dp0..") do set "rootDir=%%~fI\"


:: Get the directory that contains the script (no trailing slash)
set "scriptDir=%~dp0"
if "%scriptDir:~-1%"=="\" (
    set "scriptDir=%scriptDir:~0,-1%"
)
:: Get the parent directory
for %%A in ("%scriptDir%\..\..") do set "curDrv=%%~fA"
:: Remove trailing backslash
if "%curDrv:~-1%"=="\" set "curDrv=%curDrv:~0,-1%"

if not defined xamppDirCur (
    set "xamppDirCur=d:\xampp\xampp-8.2"
)

REM for /f "tokens=1,2 delims==" %%A in ('powershell -NoProfile -ExecutionPolicy Bypass -File "%rootDir%etc\chkApache.ps1"'
REM    ) do (
REM	set "%%A=%%B"
REM   )

REM Call PowerShell script 
:again
REM powershell -ExecutionPolicy Bypass -File "%rootDir%\etc\chkEnabled.ps1"

for /f "tokens=1,2,3,4,* delims=|" %%A in ('
    powershell -ExecutionPolicy Bypass -File "%rootDir%\etc\chkEnabled.ps1"
') do (
    set exitCode=%%A
    set Status=%%B
    set Htdocs=%%C
    set xamppDirCur=%%D
    set xamppService=%%E
)

echo .
echo "*****************************"
echo "exitCode= !exitCode!"
echo "Status= !Status!"
echo "Htdocs= !Htdocs!"
echo "xamppDirCur= !xamppDirCur!"
echo "xamppService= !xamppService!"
echo "*****************************"


:EXIT
pause
goto again


exit /b
