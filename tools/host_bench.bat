@echo off
rem WRECKSMITH: can this computer host a full room (8 fighters on the sand)? No network and no players needed: about a minute.
rem Double-click this file. It finds Godot 4.7 by itself (put Godot_v4.7.2-stable_win64.exe in the game's folder), plays fights of 2, 4,
rem 6 and 8 fighters as fast as the computer goes and says what a step costs: the game has 8.3 ms for it. Close other programs first.
rem The answer is also kept in host_check.txt, in the game's folder.
setlocal EnableDelayedExpansion
cd /d "%~dp0\.."
title WRECKSMITH host check

rem ---- 1. Find Godot 4.7: the console build first (it shows the run as it goes), then the plain one.
set "G="
if not "%GODOT%"=="" if exist "%GODOT%" set "G=%GODOT%"
for %%v in (4.7 4.6 4.5) do (
	if "!G!"=="" for %%f in ("%CD%\Godot_v%%v*win64_console.exe" "%CD%\..\Godot_v%%v*win64_console.exe" "%USERPROFILE%\Downloads\Godot_v%%v*win64_console.exe" "%USERPROFILE%\Desktop\Godot_v%%v*win64_console.exe" "%CD%\Godot_v%%v*win64*.exe" "%CD%\..\Godot_v%%v*win64*.exe" "%USERPROFILE%\Downloads\Godot_v%%v*win64*.exe" "%USERPROFILE%\Desktop\Godot_v%%v*win64*.exe" "%USERPROFILE%\Downloads\Godot*\Godot_v%%v*win64*.exe") do (
		if "!G!"=="" if exist "%%~f" set "G=%%~f"
	)
)
if "!G!"=="" (
	echo Could not find Godot 4.7. Download Godot 4.7.2 ^(Windows, 64-bit, the plain build^) from
	echo https://godotengine.org/download/windows/ , unzip it and put Godot_v4.7.2-stable_win64.exe
	echo in the game's folder. Or drag that exe onto this window now and press Enter:
	set /p "G=> "
	set "G=!G:"=!"
)
if not exist "!G!" (
	echo "!G!" is not there. Put Godot_v4.7.2-stable_win64.exe in the game's folder and run again.
	pause
	exit /b 1
)
echo Godot: !G!
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

rem ---- 3. The check.
if exist host_check.txt del host_check.txt
echo Playing fights of 2, 4, 6 and 8 fighters as fast as this computer goes. About a minute, please wait...
if not defined CONSOLE echo ^(This Godot build shows nothing here while it runs: the answer comes at the end.^)
echo.
"!G!" --headless --fixed-fps 120 --path . -- --probe host_bench
echo.
if not defined CONSOLE if exist host_check.txt type host_check.txt
if exist host_check.txt echo.
if exist host_check.txt echo The answer is also in host_check.txt, in the game's folder.
pause
endlocal
