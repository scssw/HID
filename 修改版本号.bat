@echo off
chcp 65001 >nul
title Hiddify Version Updater
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\change_version.ps1" %*

echo.
pause
