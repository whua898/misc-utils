@echo off
chcp 65001 >nul
title Unsloth Studio Web UI
echo ========================================
echo   Unsloth Studio - Web UI
echo ========================================
echo.
echo Note: Installing to D: drive to save C: space
echo.
echo Activating environment...
call "D:\Users\wh898\.unsloth\studio\unsloth_studio\Scripts\activate.bat"
echo.
echo Starting Unsloth Studio Web UI...
echo.
echo Browser will open at: http://127.0.0.1:8888
echo Default admin account:
echo   Username: unsloth
echo   Password: See D:\Users\wh898\.unsloth\studio\auth\.bootstrap_password
echo.
echo Press Ctrl+C to stop the server
echo ========================================
echo.
set USERPROFILE=D:\Users\wh898
start http://127.0.0.1:8888
unsloth studio -H 0.0.0.0 -p 8888
