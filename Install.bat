@echo off
:: ============================================================
::  AMD Phoenix Driver Installer - Windows Server 2025
::  Cift tiklayarak calistirin - otomatik admin ister
:: ============================================================

:: Admin kontrolu
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Yonetici olarak baslatiliyor...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0Install.ps1"
pause
