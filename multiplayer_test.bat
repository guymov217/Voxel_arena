@echo off
rem WRECKSMITH: an online game on this one computer, no command line needed.
rem Double-click this file. It finds Godot 4.7, imports the project if that was never done,
rem asks what to try, and opens the windows. The bout starts by itself once the guest is in.
setlocal EnableDelayedExpansion
cd /d "%~dp0"
title WRECKSMITH multiplayer test

rem ---- 1. Find Godot 4.7 (the editor exe). 4.7 first, wherever it is; an older 4.x only as a
rem         last resort (the game is made for 4.7 and an older one shows a wall of errors).
set "G="
if not "%GODOT%"=="" if exist "%GODOT%" set "G=%GODOT%"
for %%v in (4.7 4.6 4.5) do (
	if "!G!"=="" for %%f in ("%~dp0Godot_v%%v*win64*.exe" "%~dp0..\Godot_v%%v*win64*.exe" "%USERPROFILE%\Downloads\Godot_v%%v*win64*.exe" "%USERPROFILE%\Desktop\Godot_v%%v*win64*.exe" "%USERPROFILE%\Downloads\Godot*\Godot_v%%v*win64*.exe") do (
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
echo.

rem ---- 2. Import the project once (the engine must index the game's scripts before it can run
rem         them; without it every window shows "Identifier not declared" and a black screen).
if not exist ".godot\global_script_class_cache.cfg" (
	echo First run: importing the project. This takes a minute or two, please wait...
	"!G!" --headless --path . --import >nul 2>&1
	echo Done.
	echo.
)

rem ---- 3. What to try
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

rem ---- 4. Open the windows: the host first, then the guests join it. The host starts the
rem         co-op campaign by itself when the first guest is in.
echo.
echo Opening the host window...
start "WRECKSMITH host" "!G!" --path . --position 40,60 --resolution 1100x650 -- --host --start --name Host %EXTRA%
timeout /t 4 /nobreak >nul
for /l %%i in (1,1,%N%) do (
	echo Opening guest %%i...
	start "WRECKSMITH guest %%i" "!G!" --path . --position 480,180 --resolution 1100x650 -- --join 127.0.0.1 --name "Guest %%i" %BOT% %EXTRA%
	timeout /t 2 /nobreak >nul
)
echo.
echo The bout starts in the host window a moment after the guest joins. Click a window to play in it.
echo Close this window when done.
pause
endlocal
