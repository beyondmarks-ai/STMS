@echo off
setlocal
cd /d "%~dp0"
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0edge-client-setup.ps1"
if errorlevel 1 (
  echo.
  echo Edge gateway setup failed. Read the message above.
  pause
)
