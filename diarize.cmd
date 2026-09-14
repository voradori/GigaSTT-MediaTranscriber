@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0.venv\Scripts\python.exe" (
    echo Pyannote is not installed in .venv.
    exit /b 2
)
set "PYANNOTE_METRICS_ENABLED=0"
"%~dp0.venv\Scripts\python.exe" "%~dp0scripts\diarize.py" %*
exit /b %errorlevel%
