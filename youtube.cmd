@echo off
setlocal
cd /d "%~dp0"
set /p "URL=YouTube video or playlist URL: "
if not defined URL exit /b 1
if not exist "input" mkdir "input"
python -m yt_dlp --yes-playlist --no-overwrites -f bestaudio -o "input\%%(playlist_title|YouTube videos)s\%%(title).100B [%%(id)s].%%(ext)s" "%URL%"
if errorlevel 1 exit /b %errorlevel%
call "%~dp0transcribe.cmd"
exit /b %errorlevel%
