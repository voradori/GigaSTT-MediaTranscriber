@echo off
setlocal
cd /d "%~dp0"
set "URL=%~1"
if not defined URL set /p "URL=YouTube video or playlist URL: "
if not defined URL exit /b 1
python "%~dp0scripts\youtube.py" --download-only "%URL%"
exit /b %errorlevel%
