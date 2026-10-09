@echo off
cd /d "%~dp0"
py -3 tools\restore_large_assets.py
if errorlevel 1 exit /b 1
godot --headless --path . --editor --quit
if errorlevel 1 exit /b 1
godot --path . %*
