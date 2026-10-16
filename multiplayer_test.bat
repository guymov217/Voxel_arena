@echo off
rem WRECKSMITH: an online game on this one computer, no command line needed.
rem Double-click this file. It finds Godot by itself, asks what to try, and opens the windows.
setlocal EnableDelayedExpansion
cd /d "%~dp0"
title WRECKSMITH multiplayer test

rem ---- 1. Find Godot 4.7 (the editor exe): next to this file, in the parent folder, in
rem         Downloads, on the Desktop, or wherever GODOT points.
set "G="
if not "%GODOT%"=="" if exist "%GODOT%" set "G=%GODOT%"
if "!G!"=="" for %%f in ("%~dp0Godot_v4*win64*.exe" "%~dp0..\Godot_v4*win64*.exe" "%USERPROFILE%\Downloads\Godot_v4*win64*.exe" "%USERPROFILE%\Desktop\Godot_v4*win64*.exe" "%USERPROFILE%\Downloads\Godot*\Godot_v4*win64*.exe") do (
	if "!G!"=="" if exist "%%~f" set "G=%%~f"
)
if "!G!"=="" (
	echo Could not find Godot. Drag the Godot 4.7 exe ^(Godot_v4.7.2-stable_win64.exe^) onto this window
	echo and press Enter:
	set /p "G=> "
	set "G=!G:"=!"
)
if not exist "!G!" (
	echo "!G!" is not there. Download Godot 4.7.2 from godotengine.org, put it next to this file, run again.
	pause
	exit /b 1
)
echo Godot: !G!
echo.

rem ---- 2. What to try
echo  1. Two windows, both played by you ^(Alt+Tab between them^)
echo  2. Host + a bot guest: you play the host, the bot fights beside you
echo  3. Like 2, over a pretend poor connection ^(120 ms, 3%% loss^)
echo  4. Host + two bot guests
echo.
choice /c 1234 /n /m "Pick 1-4: "
set "pick=%errorlevel%"
set "N=1"
set "BOT="
set "EXTRA="
if "%pick%"=="2" set "BOT=--bot"
if "%pick%"=="3" set "BOT=--bot" & set "EXTRA=--lag 120 --loss 3"
if "%pick%"=="4" set "BOT=--bot" & set "N=2"

rem ---- 3. Open the windows: the host first, then the guests join it.
echo.
echo Opening the host window...
start "WRECKSMITH host" "!G!" --path . --position 40,60 --resolution 1100x650 -- --host --name Host %EXTRA%
timeout /t 4 /nobreak >nul
for /l %%i in (1,1,%N%) do (
	echo Opening guest %%i...
	start "WRECKSMITH guest %%i" "!G!" --path . --position 480,180 --resolution 1100x650 -- --join 127.0.0.1 --name "Guest %%i" %BOT% %EXTRA%
	timeout /t 2 /nobreak >nul
)
echo.
echo Both windows should now be in one room. In the HOST window press
echo "Start the co-op campaign" ^(or "Into the yard together"^). Close this window when done.
pause
endlocal
