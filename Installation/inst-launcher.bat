REM          FileName: inst-launcher.bat
REM          Solution: PSC Choco Installation Launcher
REM          Author: Patrick Scherling
REM          Contact: @Patrick Scherling
REM          Primary: @Patrick Scherling
REM          Created: 2026-03-11
REM          Modified: 2026-03-11
REM
REM	         Version - 0.0.1 - (2026-03-09) - Finalized functional version 1.
REM

@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "Version=0.0.1"
set "Title=PSC Choco Installation Launcher"
title %Title%


:menu
cls
echo ===================================================
echo        %Title%
echo          Ver.:    %Version%
echo          Author:  https://github.com/PScherling
echo ===================================================
echo.
echo   [1] Create Self-Signed Certificate
echo   [2] Chocolatey auto installation
echo   [3] Chocolatey for Business auto installation
echo   [4] Chocolatey Agent Setup
echo   [5] Exit
echo.
set "choice="
set /p choice="Select an option (1-5): "

if "%choice%"=="1" goto createcert
if "%choice%"=="2" goto chocoinstall
if "%choice%"=="3" goto cbinstall
if "%choice%"=="4" goto agentsetup
if "%choice%"=="5" goto end

echo.
echo Invalid selection. Press any key...
pause >nul
goto menu

:chocoinstall
cls
echo Launching: Chocolatey-AutoInstall.ps1 (PromptAll) ...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Maximized -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','E:\ChocoInstall\Chocolatey-AutoInstall.ps1','-PromptAll')"
goto done

:createcert
cls
echo Launching: CreateSelfSignedCert.ps1 (PromptAll) ...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Maximized -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','E:\ChocoInstall\CreateSelfSignedCert.ps1','-PromptAll')"
goto done

:cbinstall
cls
echo Launching: C4B-AutoInstall.ps1 (PromptAll) ...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Maximized -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','E:\ChocoInstall\C4B-AutoInstall.ps1','-PromptAll')"
goto done

:cbinstall
cls
echo Launching: Chocolatey-AgentSetup.ps1 (PromptAll) ...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Maximized -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File','E:\ChocoInstall\Chocolatey-AgentSetup.ps1','-PromptAll')"
goto done

:done
echo.
echo Window launched. Press any key to return to menu...
pause >nul
goto menu

:end
endlocal
exit /b 0