$ErrorActionPreference = 'Stop'
$rootPath = Split-Path -Parent $PSScriptRoot
$venvPath = Join-Path $rootPath '.venv'
$pythonPath = Join-Path $venvPath 'Scripts\python.exe'
$hfPath = Join-Path $venvPath 'Scripts\hf.exe'
$modelPath = Join-Path $rootPath 'models\pyannote-speaker-diarization-community-1'

$env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' +
    [Environment]::GetEnvironmentVariable('Path', 'Machine')

function Find-FFmpegBin {
    $command = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if ($command) { return Split-Path -Parent $command.Source }
    $packages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path -LiteralPath $packages) {
        $executable = Get-ChildItem -LiteralPath $packages -Recurse -Filter ffmpeg.exe -File `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -like '*Gyan.FFmpeg.Shared_*' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($executable) { return $executable.DirectoryName }
    }
    return $null
}

$ffmpegBin = Find-FFmpegBin
if (-not $ffmpegBin) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw 'FFmpeg Shared is required. Install it and run setup-diarization.cmd again.'
    }
    winget install --exact --id Gyan.FFmpeg.Shared `
        --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) { throw 'Cannot install FFmpeg Shared' }
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' +
        [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $ffmpegBin = Find-FFmpegBin
    if (-not $ffmpegBin) { throw 'FFmpeg Shared was installed but cannot be found' }
}
$env:Path = $ffmpegBin + ';' + $env:Path

if (-not (Test-Path -LiteralPath $pythonPath)) {
    python -m venv $venvPath
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create .venv' }
}

& $pythonPath -m pip install --upgrade pip
if ($LASTEXITCODE -ne 0) { throw 'Cannot update pip' }
& $pythonPath -m pip install --index-url https://download.pytorch.org/whl/cu130 `
    'torch==2.14.0+cu130' 'torchaudio==2.11.0+cu130' 'torchcodec==0.16.0+cu130'
if ($LASTEXITCODE -ne 0) { throw 'Cannot install PyTorch with CUDA support' }
& $pythonPath -m pip install -r (Join-Path $rootPath 'requirements-diarization.txt')
if ($LASTEXITCODE -ne 0) { throw 'Cannot install diarization packages' }

if (-not (Test-Path -LiteralPath (Join-Path $modelPath 'config.yaml'))) {
    & $hfPath auth whoami *> $null
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Hugging Face login is required. Paste a read token when prompted.'
        & $hfPath auth login
        if ($LASTEXITCODE -ne 0) { throw 'Hugging Face login failed' }
    }
    & $hfPath download pyannote/speaker-diarization-community-1 --local-dir $modelPath
    if ($LASTEXITCODE -ne 0) { throw 'Cannot download Community-1' }
}

$env:PYANNOTE_METRICS_ENABLED = '0'
& $pythonPath -c "import torch, torchcodec, pyannote.audio; print('CUDA:', torch.cuda.is_available()); print('Pyannote:', pyannote.audio.__version__)"
if ($LASTEXITCODE -ne 0) { throw 'Diarization installation check failed' }
Write-Host 'Diarization is installed. Run diarize.cmd to process matching audio and transcripts.'
