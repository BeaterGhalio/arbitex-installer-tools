@echo off
REM ============================================================================
REM ARBITEX VPS - Installer Launcher
REM Bypasses PowerShell Execution Policy restrictions
REM ============================================================================

REM Cambia directory
cd /d "%~dp0"

REM Verifica che sia admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo ==========================================
    echo ERROR: This script requires Administrator rights!
    echo ==========================================
    echo.
    echo Right-click on this file and select:
    echo "Run as administrator"
    echo.
    pause
    exit /b 1
)

REM Esegui PowerShell con Execution Policy bypassata
echo.
echo ==========================================
echo ARBITEX VPS - Installation Wizard
echo ==========================================
echo.

REM Bypass: -ExecutionPolicy Bypass bypassa temporaneamente la policy
REM         -NoProfile non carica il profilo PowerShell
REM         -File specifica lo script da eseguire
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0arbitex_main.ps1"

if %errorlevel% neq 0 (
    echo.
    echo ==========================================
    echo Installation completed with status: %errorlevel%
    echo ==========================================
    pause
)

exit /b 0
