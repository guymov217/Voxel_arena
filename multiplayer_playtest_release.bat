@echo off
rem WRECKSMITH: the same playtest as multiplayer_playtest.bat, in a RELEASE build (what a player runs): a few seconds of making it, then the game and its friends.
rem The editor's own exe (what the other playtest runs) is a debug build and costs a step 15 to 20% more (the diagnostic test's report): a room that runs in slow motion there
rem runs better in this one, and what you read off F3 here is what a player's game does. Needs Godot's export templates for 4.7 (Editor, Manage Export Templates, Download;
rem or tools\package.bat --install-templates). The build is made again at every start, in build\play, from the scripts as they are now. hitches.txt is in that folder too.
rem (multiplayer_playtest.bat's own words follow.)
rem WRECKSMITH: try multiplayer by yourself, with friends who are not there. No command line needed.
rem Double-click this file. It finds Godot 4.7, imports the project if that was never done, asks what to try and opens ONE
rem window: you, the host of a room. The friends are games of this project opened without a window, which join your room and
rem play; F6 brings one in, F7 sends the newest away, F8 cuts his line.
setlocal EnableDelayedExpansion
cd /d "%~dp0"
title WRECKSMITH multiplayer playtest (release build)

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

rem ---- 2b. The release build: the project's pack beside a copy of Godot's release template and the native core's library.
set "T="
for /d %%d in ("%APPDATA%\Godot\export_templates\4.7*") do if exist "%%~d\windows_release_x86_64.exe" set "T=%%~d\windows_release_x86_64.exe"
if "!T!"=="" (
	echo Godot's export templates for 4.7 are not installed. In Godot: Editor, Manage Export Templates, Download and Install,
	echo or run tools\package.bat --install-templates. Then run this again.
	pause
	exit /b 1
)
echo Making the release build ^(a few seconds^)...
if not exist build\play mkdir build\play
del /q build\play\play.pck build\play\play.exe 2>nul
"!G!" --headless --path . --export-pack "Windows Desktop" build\play\play.pck >nul 2>&1
if not exist build\play\play.pck (
	echo The game's pack was not made. Run tools\diagnose.bat or open the project once in the editor, then try again.
	pause
	exit /b 1
)
copy /y "!T!" build\play\play.exe >nul
for %%f in (native\bin\*.dll) do copy /y "%%f" build\play\ >nul
echo Done.
echo.

rem ---- 3. What to try
echo  1. The friends' Arena ^(the room opens on its lobby; friends come in and out with F6, F7, F8^)
echo  2. A campaign room
echo  3. The friends' Arena, straight into the yard
echo.
choice /c 123 /n /m "Pick 1-3: "
set "pick=%errorlevel%"
set "ROOM=--arena"
set "YARD="
if "%pick%"=="2" set "ROOM="
if "%pick%"=="3" set "YARD=--yard"

rem ---- 4. Open the window: the host, you, with the friends' buttons top right ^(F6 +, F7 -, F8 cut off, F9 a poor line^).
echo.
echo Opening your window...
start "WRECKSMITH playtest (release)" "%CD%\build\play\play.exe" --position 40,60 --resolution 1280x720 -- --keep-window --host %ROOM% %YARD% --playtest --name You
echo.
echo Top right of the game: + brings a friend in, - sends the newest away, x cuts his line, ~ makes the next come over a poor line.
echo The friends close with the game. This is a release build: F3 and hitches.txt (in build\play) are what a player's game does. Close this window when done.
pause
endlocal
