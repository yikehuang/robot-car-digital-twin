@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Run-Twin.ps1" -Live
if errorlevel 1 pause
