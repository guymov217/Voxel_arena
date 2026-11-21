@echo off
rem WRECKSMITH: all of multiplayer, played out and checked by the game itself, no command line needed.
rem Double-click this file. Three games of this project (a host and two friends) go through every part of multiplayer by the
rem game's own screens, and say at the end what worked and what did not. The report is e2e_report.txt, in this folder.
setlocal EnableDelayedExpansion
cd /d "%~dp0"
title WRECKSMITH multiplayer: all of it

rem ---- 1. Find Godot 4.7: the console build first (it shows the run as it goes), then the plain one.
set "G="
if not "%GODOT%"=="" if exist "%GODOT%" set "G=%GODOT%"
for %%v in (4.7 4.6 4.5) do (
	if "!G!"=="" for %%f in ("%~dp0Godot_v%%v*win64_console.exe" "%~dp0..\Godot_v%%v*win64_console.exe" "%USERPROFILE%\Downloads\Godot_v%%v*win64_console.exe" "%USERPROFILE%\Desktop\Godot_v%%v*win64_console.exe" "%~dp0Godot_v%%v*win64*.exe" "%~dp0..\Godot_v%%v*win64*.exe" "%USERPROFILE%\Downloads\Godot_v%%v*win64*.exe" "%USERPROFILE%\Desktop\Godot_v%%v*win64*.exe" "%USERPROFILE%\Downloads\Godot*\Godot_v%%v*win64*.exe") do (
		if "!G!"=="" if exist "%%~f" set "G=%%~f"
	)
)
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
echo "!G!" | find "4.4" >nul && (
	echo.
	echo That is Godot 4.4. The game needs 4.7.2: download it from godotengine.org and put it in this folder.
	pause
	exit /b 1
)
set "CONSOLE="
echo "!G!" | find /i "console" >nul && set "CONSOLE=1"
echo.

rem ---- 2. Import the project once (the engine must index the game's scripts before it can run them).
if not exist ".godot\global_script_class_cache.cfg" (
	echo First run: importing the project. This takes a minute or two, please wait...
	"!G!" --headless --path . --import >nul 2>&1
	echo Done.
	echo.
)

rem ---- 3. How to watch it
echo  1. Watch all of it in three windows ^(about 6 minutes^)
echo  2. Watch the short version ^(about 3 minutes^)
echo  3. Watch it over a pretend poor connection ^(120 ms, 3%% lost^)
echo  4. Without windows ^(the same, no picture^)
echo.
choice /c 1234 /n /m "Pick 1-4: "
set "pick=%errorlevel%"
set "ARGS="
if "%pick%"=="1" set "ARGS=--visible"
if "%pick%"=="2" set "ARGS=--visible --quick"
if "%pick%"=="3" set "ARGS=--visible --lag 120 --loss 3"
echo.
echo Running. Leave the windows alone: they play by themselves.
if not defined CONSOLE echo ^(This Godot build shows nothing here while it runs: the report comes at the end.^)
echo.
"!G!" --headless --path . -- --probe e2e_run !ARGS!
set "code=%errorlevel%"
echo.
if not defined CONSOLE if exist e2e_report.txt type e2e_report.txt
if exist e2e_report.txt echo The whole report is in e2e_report.txt, in this folder.
if "%code%"=="0" (
	echo ALL OK.
) else (
	echo SOMETHING FAILED: read the lines marked FAIL, in the report.
)
pause
endlocal
