@echo off
setlocal
cd /d "%~dp0"
set /p "URL=YouTube video or playlist URL: "
if not defined URL exit /b 1
python "%~dp0scripts\youtube.py" "%URL%"
exit /b %errorlevel%
