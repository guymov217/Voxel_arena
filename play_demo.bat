@echo off
rem The demo edition (what the free Steam demo ships): campaign bouts 1 to 8, the demos arena
rem modes and training, the forge and the yard. Same game, the "demo" feature on (see docs/DEMO.md).
rem Set GODOT to your Godot 4.7 exe, or put godot.exe on the PATH:
rem   set GODOT=D:\godot\Godot_v4.7.2-stable_win64.exe
rem   play_demo.bat
setlocal
if "%GODOT%"=="" set GODOT=godot
cd /d "%~dp0"
start "WRECKSMITH Demo" "%GODOT%" --path . -- --demo
endlocal
