@echo off
rem WRECKSMITH - RISE, the Steam trailer: one gladiator's rise from a slave with a stick to the
rem champion of Rome, seen through the camera on his helmet and a film camera on the kills, every
rem kill in slow motion, cut on the beat of its own score. Double-click this file.
rem Out: docs\store\trailer_rise.mp4 (1920x1080, 30 fps, about 80 s; set TRAILER_FPS=60 for 60).
rem Needs what make_trailer.bat needs (it finds or fetches ffmpeg, Pillow and numpy itself).
rem See tools\TRAILERS.md for the shot list and the settings.
call "%~dp0make_trailer.bat" rise
