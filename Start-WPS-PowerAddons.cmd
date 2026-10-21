@echo off
setlocal
set "APP=%~dp0WPS-PowerAddons.ps1"
if not exist "%APP%" (
  echo WPS-PowerAddons.ps1 is niet gevonden in de toepassingsmap.
  pause
  exit /b 1
)
where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo Windows PowerShell 5.1 kon niet worden gestart.
  pause
  exit /b 1
)
start "" powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%APP%"
if errorlevel 1 (
  echo WPS-PowerAddons kon niet worden gestart.
  pause
  exit /b 1
)
endlocal
