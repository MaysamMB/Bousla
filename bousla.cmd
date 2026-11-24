@echo off
rem Bousla commands for Windows. Usage: bousla help
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\bousla.ps1" %*
exit /b %ERRORLEVEL%
