@echo off
rem An online game on one machine: a host window and guest windows over ENet (no Steam needed).
rem Set GODOT to your Godot 4.7 exe, or put godot.exe on the PATH:
rem   set GODOT=D:\godot\Godot_v4.7.2-stable_win64.exe
rem   tools\mp_local.bat            (host + one guest, both played by you)
rem   tools\mp_local.bat 2          (host + two guests)
rem   set BOT=1                     (before running: the guests are played by bots)
rem   set LAG=120 & set LOSS=3      (pretend a 120 ms connection losing 3%% of packets)
rem In the host window: Start the co-op campaign (or Into the yard together).
setlocal
if "%GODOT%"=="" set GODOT=godot
set N=%1
if "%N%"=="" set N=1
set EXTRA=
if "%LOSS%"=="" set LOSS=0
if not "%LAG%"=="" set EXTRA=--lag %LAG% --loss %LOSS%
set BOTFLAG=
if not "%BOT%"=="" set BOTFLAG=--bot
cd /d "%~dp0\.."
start "WRECKSMITH host" "%GODOT%" --path . --position 40,60 --resolution 1100x650 -- --host --name Host %EXTRA%
timeout /t 3 /nobreak >nul
for /l %%i in (1,1,%N%) do (
	start "WRECKSMITH guest %%i" "%GODOT%" --path . --position 480,180 --resolution 1100x650 -- --join 127.0.0.1 --name "Guest %%i" %BOTFLAG% %EXTRA%
	timeout /t 1 /nobreak >nul
)
endlocal
