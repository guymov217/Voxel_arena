@echo off
rem WRECKSMITH - the store screenshots, made from the game itself on this PC: 1920x1080 PNGs in docs\store\screenshots
rem (the title, your gladiator, the forge, and the fights caught at a hard blow, from the stands' side and from the
rem player's own camera). Double-click this file. It needs Godot 4.7 (the GODOT variable, this folder, the one above,
rem D:\godot, C:\godot, Downloads, the Desktop, or godot on the PATH) and a PC with a graphics card: a few minutes with
rem one, an hour or more without (this is how it is made on a machine with no GPU).
rem   make_screenshots.bat               all of them
rem   make_screenshots.bat 03_clash      one scene (the names are in tests\steamshots.gd; "menu", "forge" and "yard" too)
rem The first run imports the project (a minute or two). Then pick the best eight to ten (Steam wants at least five)
rem and upload them under Steamworks > Store Page > Screenshots; the old files here are replaced by the new ones.
setlocal EnableDelayedExpansion
cd /d "%~dp0\.."

set "G="
if not "%GODOT%"=="" if exist "%GODOT%" set "G=%GODOT%"
if "!G!"=="" for %%d in ("%CD%" "%CD%\.." "D:\godot" "C:\godot" "%USERPROFILE%\Downloads" "%USERPROFILE%\Desktop") do (
	if "!G!"=="" for %%f in ("%%~d\Godot_v4.7*win64*.exe") do if "!G!"=="" if exist "%%~ff" set "G=%%~ff"
)
if "!G!"=="" for /d %%d in ("%USERPROFILE%\Downloads\Godot*" "%USERPROFILE%\Desktop\Godot*") do (
	if "!G!"=="" for %%f in ("%%~d\Godot_v4.7*win64*.exe") do if "!G!"=="" if exist "%%~ff" set "G=%%~ff"
)
if "!G!"=="" for /f "delims=" %%f in ('where godot 2^>nul') do if "!G!"=="" set "G=%%~f"
if "!G!"=="" (
	echo Could not find Godot 4.7. Download Godot 4.7.2 ^(Windows, 64-bit, the plain build^) from
	echo https://godotengine.org/download/windows/ , unzip it and put Godot_v4.7.2-stable_win64.exe
	echo in the project folder. Or drag that exe onto this window now and press Enter:
	set /p "G=> "
	set "G=!G:"=!"
)
if not exist "!G!" (
	echo "!G!" is not there. Put Godot_v4.7.2-stable_win64.exe in the project folder and run again.
	pause
	exit /b 1
)
echo Godot: !G!

if not exist ".godot\global_script_class_cache.cfg" (
	echo First run: importing the project. This takes a minute or two, please wait...
	"!G!" --headless --path . --import >nul 2>&1
	echo Done.
)
set "SHOT_DIR=%CD%\docs\store\screenshots"
if not exist "%SHOT_DIR%" mkdir "%SHOT_DIR%"
if not "%~1"=="" set "SHOT_ONLY=%~1"
echo Saving into %SHOT_DIR%
"!G!" --path . --resolution 1920x1080 -- --probe steamshots
echo.
echo Done. The pictures are in %SHOT_DIR%
pause
endlocal
