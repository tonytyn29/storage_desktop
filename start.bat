@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1
title MTG Game Advisor

:: ============================================================
::  MTG Game Advisor - Windows Startup Script
::  Auto-detects Python, installs deps, launches server
:: ============================================================

echo ==================================================
echo   MTG Game Advisor - Startup
echo ==================================================
echo.

:: ----- Step 1: Kill existing instance on port 5000 -----
echo [startup] Checking for existing instances on port 5000...
for /f "tokens=5" %%a in ('netstat -aon 2^>nul ^| findstr ":5000 " ^| findstr "LISTENING"') do (
    echo [startup] Stopping previous instance ^(PID %%a^)...
    taskkill /F /PID %%a >nul 2>&1
)
timeout /t 1 /nobreak >nul

:: ----- Step 2: Change to script directory -----
cd /d "%~dp0"
echo [startup] Working directory: %CD%

:: ----- Step 3: Find Python -----
set "PYTHON_CMD="

:: Try 'python' first
python --version >nul 2>&1
if !errorlevel! equ 0 (
    set "PYTHON_CMD=python"
    goto :found_python
)

:: Try 'python3'
python3 --version >nul 2>&1
if !errorlevel! equ 0 (
    set "PYTHON_CMD=python3"
    goto :found_python
)

:: Try 'py' (Windows Python Launcher)
py -3 --version >nul 2>&1
if !errorlevel! equ 0 (
    set "PYTHON_CMD=py -3"
    goto :found_python
)

:: Try common install paths
for %%P in (
    "%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
    "%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
    "%LOCALAPPDATA%\Programs\Python\Python311\python.exe"
    "%LOCALAPPDATA%\Programs\Python\Python310\python.exe"
    "C:\Python313\python.exe"
    "C:\Python312\python.exe"
    "C:\Python311\python.exe"
    "C:\Python310\python.exe"
) do (
    if exist %%P (
        set "PYTHON_CMD=%%~P"
        goto :found_python
    )
)

:: Python not found
echo.
echo [ERROR] Python not found!
echo.
echo Please install Python from https://www.python.org/downloads/
echo Make sure to check "Add Python to PATH" during installation.
echo.
pause
exit /b 1

:found_python
:: Show Python version
for /f "tokens=*" %%v in ('!PYTHON_CMD! --version 2^>^&1') do set "PY_VER=%%v"
echo [startup] Found: !PY_VER! (!PYTHON_CMD!)

:: ----- Step 4: Check & install dependencies -----
echo [startup] Checking dependencies...

!PYTHON_CMD! -c "import flask; import flask_socketio; import requests" >nul 2>&1
if !errorlevel! neq 0 (
    echo [startup] Installing missing dependencies...
    !PYTHON_CMD! -m pip install flask flask-socketio requests --quiet --disable-pip-version-check
    if !errorlevel! neq 0 (
        echo.
        echo [ERROR] Failed to install dependencies.
        echo Try running manually: !PYTHON_CMD! -m pip install flask flask-socketio requests
        echo.
        pause
        exit /b 1
    )
    echo [startup] Dependencies installed successfully.
) else (
    echo [startup] All dependencies OK.
)

:: ----- Step 5: Open browser after delay -----
echo [startup] Browser will open in 6 seconds...
start /b cmd /c "timeout /t 6 /nobreak >nul && start http://localhost:5000"

:: ----- Step 6: Launch server -----
echo.
echo ==================================================
echo   Server starting on http://localhost:5000
echo   Close this window to stop the server.
echo ==================================================
echo.

!PYTHON_CMD! app.py

:: ----- If server exits -----
echo.
echo [startup] Server has stopped.
if !errorlevel! neq 0 (
    echo [startup] Exit code: !errorlevel!
    echo.
    echo If you see errors above, common fixes:
    echo   1. Run: !PYTHON_CMD! -m pip install flask flask-socketio requests
    echo   2. Make sure no other program uses port 5000
    echo   3. Check that Player.log exists ^(MTGA must be installed^)
)
echo.
pause
exit /b 0
