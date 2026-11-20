@echo off
rem Put the two Steam extensions in the project: GodotSteam and the Steam multiplayer peer. Download their two zip
rem files (docs\RELEASE_HE.md says where), then DRAG THE TWO ZIPS ONTO THIS FILE. It copies them into addons\, imports the
rem project and says whether the game loads them. Close the Godot editor first. Needs Python 3 and Godot 4.7, which
rem it finds by itself (the same way package.bat does).
setlocal
cd /d "%~dp0"
if "%~1"=="" (
	echo Drag the two downloaded zip files ^(GodotSteam, and the Steam multiplayer peer^) onto this file.
	echo docs\RELEASE_HE.md says where to download them.
	echo.
	pause
	exit /b 1
)
call tools\package.bat --addons-only --godotsteam %*
exit /b %ERRORLEVEL%
