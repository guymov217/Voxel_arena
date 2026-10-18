@echo off
rem How many fighters this computer can host smoothly (no network, no players needed).
rem Set GODOT to your Godot 4.7 exe, or put godot.exe on the PATH:
rem   set GODOT=D:\godot\Godot_v4.7.2-stable_win64.exe
rem Then double-click this file (about a minute). Close other programs first.
setlocal
if "%GODOT%"=="" set GODOT=godot
cd /d "%~dp0\.."
"%GODOT%" --headless --fixed-fps 120 --path . -- --probe host_bench
echo.
pause
endlocal
