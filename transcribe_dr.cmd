@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0.venv\Scripts\python.exe" (
    echo Diarization is not installed. Run setup-diarization.cmd first.
    exit /b 2
)
if not exist "%~dp0models\pyannote-speaker-diarization-community-1\config.yaml" (
    echo Community-1 model is not installed. Run setup-diarization.cmd first.
    exit /b 2
)
call "%~dp0transcribe.cmd" %*
if errorlevel 1 exit /b %errorlevel%
call "%~dp0diarize.cmd" %*
exit /b %errorlevel%
