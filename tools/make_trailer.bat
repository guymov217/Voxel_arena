@echo off
rem The launch trailer, rendered from the game on this PC: docs\store\trailer.mp4 (1920x1080, 30 fps).
rem Needs: Godot 4.7 (set GODOT below, or godot.exe on the PATH), ffmpeg on the PATH
rem (https://ffmpeg.org, the "full" build has ffprobe too), Python 3 with Pillow (pip install pillow).
rem Then double-click this file. 20-40 minutes with a graphics card; shots already made are kept,
rem so a run that was stopped carries on. Work files go to ..\trailer_work beside the project.
setlocal
if "%GODOT%"=="" set GODOT=D:\godot\Godot_v4.7.2-stable_win64_console.exe
if not exist "%GODOT%" set GODOT=godot
cd /d "%~dp0\.."
where python >nul 2>nul || (echo Python 3 not found: install it from python.org and tick "Add to PATH" & pause & exit /b 1)
where ffmpeg >nul 2>nul || (echo ffmpeg not found: install it and add its bin folder to the PATH & pause & exit /b 1)
python tools\make_trailer.py
echo.
pause
endlocal
