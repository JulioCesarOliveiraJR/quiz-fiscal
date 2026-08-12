@echo off
chcp 65001 >nul
title Publicar cards - FaculMaria

echo.
echo   Publicando os cards do vault no site...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publicar.ps1" %*

echo.
echo   ----------------------------------------------------------
echo   Terminou. Pode fechar esta janela.
echo.
pause
