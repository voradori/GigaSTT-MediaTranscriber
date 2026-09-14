@echo off
setlocal
cd /d "%~dp0"
set "URL=%~1"
if not defined URL set /p "URL=YouTube video or playlist URL: "
if not defined URL exit /b 1
if not exist "%~dp0.venv\Scripts\python.exe" (
    echo Base tools are not installed. Run setup.cmd first.
    exit /b 2
)
"%~dp0.venv\Scripts\python.exe" "%~dp0scripts\youtube.py" --download-only "%URL%"
exit /b %errorlevel%
