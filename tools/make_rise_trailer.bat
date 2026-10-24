@echo off
rem The second trailer: one gladiator's rise through the arena, all from just over his right
rem shoulder, the camera shaking with his run and his blows, under war drums made for it.
rem Out: docs\store\trailer_rise.mp4 (1920x1080, 30 fps, about a minute). Double-click this file.
rem Needs what make_trailer.bat needs (it finds or fetches ffmpeg, Pillow and numpy itself).
call "%~dp0make_trailer.bat" rise
