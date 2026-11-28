@echo off
rem WRECKSMITH: the experiments that answer what is still open, in one double-click: the men's controls on the worker threads and Godot's own render thread, each beside the
rem same without it, on this computer: the step, a fight drawn for real, and the game's room of eight with seven friend windows. About 16 minutes.
rem It is diagnose.bat with --all --only (same rules: close every other program first, leave the computer alone), and makes the same one file, diagnose_report.txt: send it.
call "%~dp0diagnose.bat" --all --only steps_auto,steps_threads,fight_base,fight_threads,fight_render_thread,room_eight,room_threads %*
