REM          FileName: launcher.bat
REM          Solution: PSC Choco Tools Launcher
REM          Author: Patrick Scherling
REM          Contact: @Patrick Scherling
REM          Primary: @Patrick Scherling
REM          Created: 2026-03-09
REM          Modified: 2026-03-11
REM
REM	         Version - 0.0.1 - (2026-03-09) - Finalized functional version 1.
REM          Version - 0.0.2 - (2026-03-11) - Adapting header section in 'Update software packages'
REM

@echo off
setlocal EnableExtensions EnableDelayedExpansion
title PSC Choco Tools Launcher
set "Version=0.0.2"
:menu
cls
echo ===================================================
echo        PSC Choco Tools Launcher
echo          Ver.:    %Version%
echo          Author:  https://github.com/PScherling
echo ===================================================
echo.
echo   [1] Create new Chocolatey package
echo   [2] Update software packages
echo   [3] Exit
echo.
set "choice="
set /p choice="Select an option (1-3): "

if "%choice%"=="1" goto create
if "%choice%"=="2" goto update
if "%choice%"=="3" goto end

echo.
echo Invalid selection. Press any key...
pause >nul
goto menu

:create
cls
echo Launching: CreateNewChocoPackage.ps1 (PromptAll) ...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Maximized -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','E:\ChocoManage\CreateNewChocoPackage.ps1','-PromptAll')"
goto done

:update
cls
echo ============================================
echo        Update Software Packages
echo          Ver.:    %Version%
echo          Author:  https://github.com/PScherling
echo ============================================
echo.
echo   [1] ALL
echo   [2] API
echo   [3] WEB
echo   [4] LOCAL
echo   [5] Back
echo.
set "mode="
set /p mode="Select update mode (1-5): "

if "%mode%"=="5" goto menu

set "UpdateOption="
if "%mode%"=="1" set "UpdateOption=ALL"
if "%mode%"=="2" set "UpdateOption=API"
if "%mode%"=="3" set "UpdateOption=WEB"
if "%mode%"=="4" set "UpdateOption=LOCAL"

if not defined UpdateOption (
  echo.
  echo Invalid selection. Press any key...
  pause >nul
  goto update
)

echo.
echo Launching: UpdateSoftwarePackages.ps1 -UpdateOption %UpdateOption% ...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Maximized -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','E:\ChocoManage\UpdateSoftwarePackages.ps1','-UpdateOption','%UpdateOption%','-PromptAll')"
goto done

:done
echo.
echo Window launched. Press any key to return to menu...
pause >nul
goto menu

:end
endlocal
exit /b 0
