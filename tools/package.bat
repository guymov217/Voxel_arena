@echo off
rem WRECKSMITH - package the game: ready for Steam (SteamPipe depots + scripts) and as downloads for people who
rem do not have Steam (a zip and an installer). Double-click this file. It needs Python 3 and Godot 4.7 with its export
rem templates; it finds Godot by itself (the GODOT variable, the folders Godot is usually unzipped to, the PATH),
rem and `package.bat --install-templates` fetches the export templates it is missing.
rem Results: dist\steam\ (what to upload), dist\standalone\ (what to hand out), dist\PACKAGE_REPORT.md.
rem Arguments go on to tools\package.py, for example:
rem   package.bat --channel standalone        only the downloads for people without Steam
rem   package.bat --skip-export               pack again what build\ holds (after filling in Steam's ids)
rem Close the Godot editor first. docs\PACKAGING.md has the whole story.
setlocal
cd /d "%~dp0\.."

rem The PATH as it is saved now (a window opened before PATH was edited still has the old one).
set "UPATH="
set "SPATH="
for /f "tokens=2,*" %%A in ('reg query "HKCU\Environment" /v Path 2^>nul ^| find /i "REG_"') do set "UPATH=%%B"
for /f "tokens=2,*" %%A in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul ^| find /i "REG_"') do set "SPATH=%%B"
call set "PATH=%PATH%;%SPATH%;%UPATH%"

set "PY="
where python >nul 2>nul && set "PY=python"
if not defined PY where py >nul 2>nul && set "PY=py -3"
if not defined PY (
	echo Python 3 not found: install it from python.org and tick "Add python.exe to PATH", then run this again.
	pause
	exit /b 1
)
%PY% tools\package.py %*
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" echo Packaging stopped ^(exit %RC%^): read the lines above.
pause
exit /b %RC%
