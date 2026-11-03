@echo off
rem WRECKSMITH - THE CROWD WANTS BLOOD: the trailer that worked, its lines and its order kept, made
rem again as a film from the game itself. A crane from the sky into the arena, every fight through a
rem film camera, every kill in slow motion, the forge, the cheese, the chaos, friends online, the
rem hydra, then the logo over the champion alone, cut on the beat of its own score. Double-click this file.
rem Out: docs\store\trailer_blood.mp4 (1920x1080, 30 fps, about 75 s; set TRAILER_FPS=60 for 60).
rem Needs what make_trailer.bat needs (it finds or fetches ffmpeg, Pillow and numpy itself).
rem See tools\TRAILERS.md for the shot list and the settings.
call "%~dp0make_trailer.bat" blood
