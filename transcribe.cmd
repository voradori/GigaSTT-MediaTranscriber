@echo off
setlocal
cd /d "%~dp0"
python "%~dp0scripts\transcribe.py" %*
exit /b %errorlevel%
