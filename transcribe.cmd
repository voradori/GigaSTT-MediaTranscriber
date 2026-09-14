@echo off
setlocal
cd /d "%~dp0"
python "%~dp0scripts\transcribe.py" %*
if errorlevel 1 exit /b %errorlevel%
if exist "%~dp0models\pyannote-speaker-diarization-community-1\config.yaml" (
    if not exist "%~dp0.venv\Scripts\python.exe" (
        echo Diarization model exists but .venv is missing.
        exit /b 2
    )
    call "%~dp0diarize.cmd" %*
)
exit /b %errorlevel%
