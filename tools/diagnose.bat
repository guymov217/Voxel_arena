@echo off
rem WRECKSMITH: THE test. ONE double-click measures, on this computer, everything that decides why the game cannot hold a full room, and writes ONE file for me to read:
rem diagnose_report.txt, in the game's folder. It runs by itself, part after part, each in a game of its own: what a physics step costs (with the thread settings one by one, the
rem native core on and off), the same in a release build made from this project (what a player runs), a fight drawn for real (what each frame is made of; again with the shader
rem caches off as on a first launch, with Godot's render thread, on the other renderer, with physics interpolation off, full screen, at high priority), the picture's settings changed
rem one at a time, and the game's own room of eight with seven friend windows in the endless arena. About 25 minutes; a window shows the list and the time left.
rem   diagnose.bat                   the whole test
rem   diagnose.bat --quick           the same, shortened (a few minutes), for a look first
rem   diagnose.bat --size 1920x1080  the size of the windows the parts are drawn in (1280x720 by default, as the playtest)
rem   diagnose.bat --skip room       leave a part out (steps, release, fight, render, room, or an id from the report)
rem   diagnose.bat --all             every part there is, the ones the first report has answered too (threads, sound, caches, the other renderer, full screen, priority): 35 minutes
rem The second version (after the first report) asks what only this computer can say: how fast each of the processor's cores is and which of them Windows gives the game
rem (a part held to the fast ones, by Windows' own affinity setting of that one game, gone when it closes), the room in the release build, what a read-back costs on this card, and an experiment: the fighters' controls spread over all the processor's cores.
rem Close every other program first (browsers, recorders, other games) and leave the computer alone until the window says it is done.
rem Godot 4.7 is found by itself (put Godot_v4.7.2-stable_win64.exe in the game's folder). For the release build Godot's export templates must be installed
rem (Editor, Manage Export Templates, Download; or tools\package.bat --install-templates): without them that part says so and the rest runs.
setlocal EnableDelayedExpansion
cd /d "%~dp0\.."
title WRECKSMITH diagnostic test

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
echo.

rem ---- 2. Index the project (the engine must know the game's scripts before it can run them: the test's own are new, so this is done every time; a few seconds, a minute the first time).
echo Checking the project, please wait...
"!G!" --headless --path . --import >nul 2>&1
echo Done.
echo.

rem ---- 3. The test.
if exist diagnose_report.txt del diagnose_report.txt
echo WRECKSMITH diagnostic test. Close every other program now ^(browsers, recorders, other games^).
echo A window will show the list and the time left, and other windows of the game open and close by themselves. Leave the computer alone.
echo.
"!G!" --path . --position 60,60 --resolution 1000x560 -- --diag %*
echo.
if exist diagnose_report.txt (
	echo Done. Send me this one file: !CD!\diagnose_report.txt
) else (
	echo The report was not made. Run this again, and if it does not make it either, send the folder's hitches.txt and what this window says.
)
pause
endlocal
