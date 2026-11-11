@echo off
chcp 65001 >nul
rem Portable kit entry point: hardware -> machine class -> window and flags -> server start.
rem All user-facing text is printed by start.ps1 (UTF-8 with BOM, so Windows PowerShell 5.1
rem reads it correctly). This file is intentionally ASCII-only: cmd.exe parses .bat in the OEM
rem code page, and a UTF-8 Cyrillic comment here breaks the parser before chcp takes effect
rem (measured 11.11: "START.bat" ran its own rem-lines as commands).
rem
rem   double click               : ask for the .gguf path and do everything
rem   START.bat model.gguf       : same without the question
rem   START.bat model.gguf -DryRun : print the launch line and start nothing
rem   START.bat model.gguf -Yes  : start without confirmation
rem
rem A model path can be dropped onto the shortcut. No models are bundled.
setlocal
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"
if not exist "%PS%" (
  echo [FAIL] Windows PowerShell 5.1 not found: "%PS%"
  echo        start.ps1 can be run by any shell that reads .ps1 files
  pause
  exit /b 2
)
set "PS1=%~dp0start.ps1"
if not exist "%PS1%" set "PS1=%~dp0kit\start.ps1"
if not exist "%PS1%" (
  echo [FAIL] start.ps1 not found next to START.bat or in kit\
  pause
  exit /b 2
)
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"
echo.
echo (kit finished with code %RC%)
pause
endlocal & exit /b %RC%
