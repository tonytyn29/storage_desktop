@echo off
chcp 65001 >nul
title MTG Game Advisor

:: Kill existing instance on port 5000
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":5000 " ^| findstr "LISTENING"') do (
    echo Stopping previous instance (PID %%a)...
    taskkill /F /PID %%a >nul 2>&1
)

timeout /t 1 /nobreak >nul

cd /d "D:\Projects_New\Tool - MTGlog"

echo ==================================================
echo   MTG Game Advisor
echo ==================================================
echo.
echo Starting server...
echo Close this window to stop the server.
echo.

:: Open browser after 8 seconds
start /b cmd /c "timeout /t 8 /nobreak >nul && start http://localhost:5000"

python app.py
pause
