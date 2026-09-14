$ErrorActionPreference = 'Stop'
$rootPath = Split-Path -Parent $PSScriptRoot
$toolsPath = Join-Path $rootPath 'tools'
$modelsPath = Join-Path $rootPath 'models'
$venvPath = Join-Path $rootPath '.venv'
$pythonPath = Join-Path $venvPath 'Scripts\python.exe'
if (-not (Test-Path -LiteralPath $pythonPath)) {
    python -m venv $venvPath
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create .venv' }
}
& $pythonPath -m pip install -r (Join-Path $rootPath 'requirements-youtube.txt')
if ($LASTEXITCODE -ne 0) { throw 'Cannot install YouTube tools in .venv' }
New-Item -ItemType Directory -Force -Path $toolsPath, $modelsPath | Out-Null
$enginePath = Join-Path $toolsPath 'gigastt.exe'
if (-not (Test-Path -LiteralPath $enginePath)) {
    $release = Invoke-RestMethod 'https://api.github.com/repos/ekhodzitsky/gigastt/releases/latest'
    $name = "gigastt-$($release.tag_name.TrimStart('v'))-x86_64-pc-windows-msvc.tar.gz"
    $asset = $release.assets | Where-Object name -eq $name | Select-Object -First 1
    $checksum = $release.assets | Where-Object name -eq "$name.sha256" | Select-Object -First 1
    if (-not $asset -or -not $checksum) { throw "Windows release asset missing: $name" }
    $archivePath = Join-Path $toolsPath $name
    Invoke-WebRequest $asset.browser_download_url -OutFile $archivePath
    $checksumPath = "$archivePath.sha256"
    Invoke-WebRequest $checksum.browser_download_url -OutFile $checksumPath
    $expected = ((Get-Content -LiteralPath $checksumPath -Raw).Trim() -split '\s+')[0]
    $actual = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    if ($expected -ine $actual) { throw 'GigaSTT archive checksum mismatch' }
    tar -xzf $archivePath -C $toolsPath
    if ($LASTEXITCODE -ne 0) { throw 'Cannot extract GigaSTT archive' }
}
& (Join-Path $toolsPath 'gigastt.exe') download --model-dir $modelsPath
if ($LASTEXITCODE -ne 0) { throw 'Cannot download GigaSTT models' }
$warmupPath = Join-Path $toolsPath 'setup-warmup.wav'
$warmupJson = Join-Path $toolsPath 'setup-warmup.json'
try {
    & $pythonPath -c "import sys,wave; w=wave.open(sys.argv[1],'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000); w.writeframes(bytes(32000)); w.close()" $warmupPath
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create punctuation warmup audio' }
    & (Join-Path $toolsPath 'gigastt.exe') transcribe --model-dir $modelsPath --punctuation on --punct-model-dir (Join-Path $modelsPath 'punct') --itn off -f json -o $warmupJson $warmupPath
    if ($LASTEXITCODE -ne 0) { throw 'Cannot download punctuation model' }
} finally {
    Remove-Item -LiteralPath $warmupPath, $warmupJson -ErrorAction SilentlyContinue
}
Write-Host 'Base tools are installed in .venv. Future transcribe.cmd runs use offline mode.'
