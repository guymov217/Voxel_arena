@echo off
rem WRECKSMITH - the trailer of the game's features, one by one, made from the game itself: the
rem gate, the Emperor, every swing yours (the mouse drawn in the corner), steel that cuts where it
rem lands, armour knocked apart plate by plate, bones that break, beasts, giants, monsters, the pots,
rem the forge, the physician's blade, friends online, the hydra, then the logo. Every scene staged
rem and every blow scripted: nothing left to chance; the swings and a montage as they are played,
rem through the game's own camera with its HUD. Double-click this file.
rem Out: docs\store\trailer_features.mp4 (1920x1080, 30 fps, about 80 s; set TRAILER_FPS=60 for 60).
rem Needs what make_trailer.bat needs (it finds or fetches ffmpeg, Pillow and numpy itself).
rem See tools\TRAILERS.md for the scenes and the settings.
call "%~dp0make_trailer.bat" feature
