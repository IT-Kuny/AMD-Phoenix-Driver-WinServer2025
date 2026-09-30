@echo off
:: ============================================================
::  AMD Phoenix Driver Installer - Windows Server 2025
::  Double-click to run - auto-elevates to Administrator
:: ============================================================

:: Check for admin rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0Install.ps1" %*
pause
