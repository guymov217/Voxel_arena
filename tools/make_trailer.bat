@echo off
rem The launch trailer, rendered from the game on this PC: docs\store\trailer.mp4 (1920x1080, 30 fps).
rem With "rise" (make_rise_trailer.bat) the second one instead: docs\store\trailer_rise.mp4, over the shoulder.
rem Double-click this file. It needs Godot 4.7 and Python 3; ffmpeg and Pillow it finds or fetches itself:
rem   ffmpeg: the FFMPEG variable (the ffmpeg.exe, its bin folder or the folder it was unzipped to),
rem           the PATH (read fresh, so a PATH just edited counts), the usual install folders, or,
rem           if it is nowhere, downloaded once (about 100 MB) into ..\trailer_work\ffmpeg.
rem   Godot:  the GODOT variable, else D:\godot\Godot_v4.7.2-stable_win64(_console).exe, else godot on the PATH.
rem 20-40 minutes with a graphics card; shots already made are kept, so a run that was stopped
rem carries on. Work files go to ..\trailer_work beside the project.
setlocal
cd /d "%~dp0\.."

rem The PATH as it is saved now (a window opened before PATH was edited still has the old one).
set "UPATH="
set "SPATH="
for /f "tokens=2,*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul ^| find /i "REG_"') do set "UPATH=%%B"
for /f "tokens=2,*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul ^| find /i "REG_"') do set "SPATH=%%B"
call set "PATH=%PATH%;%SPATH%;%UPATH%"

rem ---------- Python ----------
set "PY="
where python >nul 2>nul && set "PY=python"
if not defined PY where py >nul 2>nul && set "PY=py -3"
if not defined PY (
	echo Python 3 not found: install it from python.org and tick "Add python.exe to PATH", then run this again.
	pause
	exit /b 1
)

rem ---------- ffmpeg ----------
set "FF="
if defined FFMPEG call :tryff "%FFMPEG%"
if not defined FF for /f "delims=" %%F in ('where ffmpeg.exe 2^>nul') do if not defined FF set "FF=%%~dpF"
if not defined FF for %%D in ("%CD%\..\trailer_work\ffmpeg" "%~dp0ffmpeg" "C:\ffmpeg" "D:\ffmpeg" "%ProgramFiles%\ffmpeg" "%ProgramFiles(x86)%\ffmpeg" "%USERPROFILE%\ffmpeg" "%USERPROFILE%\Downloads" "%LOCALAPPDATA%\Microsoft\WinGet\Links" "%USERPROFILE%\scoop\shims" "%ProgramData%\chocolatey\bin") do if not defined FF call :tryff "%%~D"
if not defined FF for /d %%P in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\*FFmpeg*") do for /f "delims=" %%F in ('dir /b /s "%%~P\ffmpeg.exe" 2^>nul') do if not defined FF set "FF=%%~dpF"
if not defined FF call :getff
if not defined FF (
	echo.
	echo ffmpeg could not be found or downloaded.
	echo Download "ffmpeg-release-essentials.zip" from https://www.gyan.dev/ffmpeg/builds/ , unzip it, and set
	echo FFMPEG to the folder that has ffmpeg.exe in it, e.g.  setx FFMPEG "C:\ffmpeg\bin"
	echo then run this again.
	pause
	exit /b 1
)
if not exist "%FF%ffprobe.exe" (
	echo Found ffmpeg in %FF% but no ffprobe.exe beside it: use the "essentials" or "full" build, which has both.
	pause
	exit /b 1
)
set "PATH=%FF%;%PATH%"
echo ffmpeg: %FF%

rem ---------- Pillow ----------
%PY% -c "import PIL" >nul 2>nul || (
	echo Installing Pillow for Python...
	%PY% -m pip install --user pillow || (echo Could not install Pillow: run  pip install pillow  yourself. & pause & exit /b 1)
)
rem (The second trailer, "make_trailer.bat rise", makes its war drums with numpy.)
set "SCRIPT=tools\make_trailer.py"
if /i "%~1"=="rise" set "SCRIPT=tools\make_rise_trailer.py"
if /i not "%~1"=="rise" goto :deps_ok
%PY% -c "import numpy" >nul 2>nul && goto :deps_ok
echo Installing numpy for Python...
%PY% -m pip install --user numpy || (echo Could not install numpy: run  pip install numpy  yourself. & pause & exit /b 1)
:deps_ok

rem ---------- Godot ----------
if "%GODOT%"=="" if exist "D:\godot\Godot_v4.7.2-stable_win64_console.exe" set "GODOT=D:\godot\Godot_v4.7.2-stable_win64_console.exe"
if "%GODOT%"=="" if exist "D:\godot\Godot_v4.7.2-stable_win64.exe" set "GODOT=D:\godot\Godot_v4.7.2-stable_win64.exe"
if "%GODOT%"=="" set "GODOT=D:\godot\Godot_v4.7.2-stable_win64.exe"
if exist "%GODOT%" goto :godot_ok
where godot >nul 2>nul && set "GODOT=godot" && goto :godot_ok
echo Godot not found at "%GODOT%": set GODOT to your Godot 4.7 *_console.exe, e.g.
echo   setx GODOT "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
pause
exit /b 1
:godot_ok
echo Godot: %GODOT%

%PY% %SCRIPT%
echo.
pause
endlocal
exit /b 0

rem %1: an ffmpeg.exe, the bin folder it is in, or a folder ffmpeg was unzipped into.
:tryff
if exist "%~1\ffmpeg.exe" (set "FF=%~f1\" & goto :eof)
if exist "%~1\bin\ffmpeg.exe" (set "FF=%~f1\bin\" & goto :eof)
if /i "%~nx1"=="ffmpeg.exe" if exist "%~1" (set "FF=%~dp1" & goto :eof)
for /d %%S in ("%~1\ffmpeg*") do if not defined FF if exist "%%~S\bin\ffmpeg.exe" set "FF=%%~fS\bin\"
goto :eof

rem No ffmpeg anywhere: fetch the essentials build (has ffprobe) with Windows' own curl and tar.
:getff
set "FD=%CD%\..\trailer_work\ffmpeg"
echo ffmpeg was not found on this PC: downloading it once (about 100 MB) into %FD% ...
if not exist "%FD%" mkdir "%FD%"
curl -L --fail --progress-bar -o "%FD%\ffmpeg.zip" "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" || goto :eof
tar -xf "%FD%\ffmpeg.zip" -C "%FD%" || goto :eof
del "%FD%\ffmpeg.zip" >nul 2>nul
call :tryff "%FD%"
goto :eof
