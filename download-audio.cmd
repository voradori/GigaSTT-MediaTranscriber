@echo off
setlocal
cd /d "%~dp0"
set "URL=%~1"
if not defined URL set /p "URL=YouTube video or playlist URL: "
if not defined URL exit /b 1
if not exist "input" mkdir "input"
if not exist ".venv\Scripts\python.exe" (
    echo Diarization tools are not installed. Run setup-diarization.cmd first.
    exit /b 2
)
".venv\Scripts\python.exe" -m yt_dlp --yes-playlist --no-overwrites ^
    -f "bestaudio[ext=webm]/bestaudio" ^
    -o "input\%%(playlist_title|YouTube videos)s\%%(title).100B [%%(id)s].%%(ext)s" "%URL%"
exit /b %errorlevel%
