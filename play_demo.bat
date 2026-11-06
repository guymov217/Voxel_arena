@echo off
rem The demo edition (what the free Steam demo ships): campaign bouts 1 to 8, the demo's arena
rem modes and training, the forge and the yard. Same game, the "demo" feature on (see docs/DEMO.md).
rem Double-click this file. It finds Godot 4.7 by itself (the GODOT variable, this folder, the one
rem above it, D:\godot, C:\godot, Downloads, the Desktop, or godot on the PATH), and asks for it if
rem it is nowhere: drag Godot_v4.7.2-stable_win64.exe onto the window then. It imports the project
rem the first time.
setlocal EnableDelayedExpansion
cd /d "%~dp0"
title WRECKSMITH demo

set "G="
if not "%GODOT%"=="" if exist "%GODOT%" set "G=%GODOT%"
if "!G!"=="" for %%d in ("%~dp0." "%~dp0.." "D:\godot" "C:\godot" "%USERPROFILE%\Downloads" "%USERPROFILE%\Desktop") do (
	if "!G!"=="" for %%f in ("%%~d\Godot_v4.7*win64*.exe") do if "!G!"=="" if exist "%%~ff" set "G=%%~ff"
)
if "!G!"=="" for /d %%d in ("%USERPROFILE%\Downloads\Godot*" "%USERPROFILE%\Desktop\Godot*") do (
	if "!G!"=="" for %%f in ("%%~d\Godot_v4.7*win64*.exe") do if "!G!"=="" if exist "%%~ff" set "G=%%~ff"
)
if "!G!"=="" for /f "delims=" %%f in ('where godot 2^>nul') do if "!G!"=="" set "G=%%~f"
if "!G!"=="" (
	echo Could not find Godot 4.7. Download Godot 4.7.2 ^(Windows, 64-bit, the plain build^) from
	echo https://godotengine.org/download/windows/ , unzip it and put Godot_v4.7.2-stable_win64.exe
	echo in this folder. Or drag that exe onto this window now and press Enter:
	set /p "G=> "
	set "G=!G:"=!"
)
if not exist "!G!" (
	echo "!G!" is not there. Put Godot_v4.7.2-stable_win64.exe next to this file and run again.
	pause
	exit /b 1
)
echo Godot: !G!

rem The project imported once (without it the game's scripts are not indexed: a black screen).
if not exist ".godot\global_script_class_cache.cfg" (
	echo First run: importing the project. This takes a minute or two, please wait...
	"!G!" --headless --path . --import >nul 2>&1
	echo Done.
)
start "WRECKSMITH Demo" "!G!" --path . -- --demo
endlocal
