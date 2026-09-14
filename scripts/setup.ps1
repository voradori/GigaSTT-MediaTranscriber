$ErrorActionPreference = 'Stop'
function Get-Sha256 {
    param([string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { return [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '') }
        finally { $hasher.Dispose() }
    } finally { $stream.Dispose() }
}
$rootPath = Split-Path -Parent $PSScriptRoot
$toolsPath = Join-Path $rootPath 'tools'
$modelsPath = Join-Path $rootPath 'models'
$venvPath = Join-Path $rootPath '.venv'
$pythonPath = Join-Path $venvPath 'Scripts\python.exe'
if (-not (Test-Path -LiteralPath $pythonPath)) {
    $pythonCommand = $null
    $pythonArgs = @()
    foreach ($candidate in @('python', 'py')) {
        if (-not (Get-Command $candidate -ErrorAction SilentlyContinue)) { continue }
        $candidateArgs = @()
        if ($candidate -eq 'py') { $candidateArgs = @('-3') }
        $works = $false
        try {
            & $candidate @candidateArgs -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>$null
            $works = ($LASTEXITCODE -eq 0)
        } catch { $works = $false }
        if ($works) {
            $pythonCommand = $candidate
            $pythonArgs = $candidateArgs
            break
        }
    }
    while (-not $pythonCommand) {
        Write-Host 'A working Python 3.10+ was not found through python or py. It may still be installed.'
        $choice = (Read-Host 'Enter full path to python.exe, I to install with WinGet, or Q to exit').Trim()
        if ($choice -eq 'Q' -or -not $choice) {
            throw 'Setup stopped. You can install Python from https://www.python.org/downloads/windows/ and run setup.cmd again.'
        }
        if ($choice -eq 'I') {
            if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
                Write-Host 'WinGet is unavailable. Install Python from https://www.python.org/downloads/windows/ or enter its existing path.'
                continue
            }
            winget install --exact --id Python.Python.3.11 `
                --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -ne 0) { throw 'Python installation through WinGet failed' }
            throw 'Python was installed. Open a new terminal and run setup.cmd again.'
        }
        $candidatePath = $choice.Trim('"')
        if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
            Write-Host 'The file does not exist. Enter the full path to python.exe.'
            continue
        }
        try {
            & $candidatePath -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>$null
            if ($LASTEXITCODE -eq 0) { $pythonCommand = $candidatePath }
        } catch { }
        if (-not $pythonCommand) { Write-Host 'This interpreter is unavailable or older than Python 3.10.' }
    }
    & $pythonCommand @pythonArgs -m venv $venvPath
    if ($LASTEXITCODE -ne 0) { throw 'Cannot create .venv with the selected Python' }
}
& $pythonPath -m pip install -r (Join-Path $rootPath 'requirements-youtube.txt')
if ($LASTEXITCODE -ne 0) { throw 'Cannot install YouTube tools in .venv' }
New-Item -ItemType Directory -Force -Path $toolsPath, $modelsPath | Out-Null

$ffmpegRoot = Join-Path $toolsPath 'ffmpeg'
$ffmpegBin = Get-ChildItem -LiteralPath $ffmpegRoot -Recurse -Filter ffmpeg.exe -File `
    -ErrorAction SilentlyContinue | Where-Object {
        (Test-Path -LiteralPath (Join-Path $_.DirectoryName 'ffprobe.exe')) -and
        (Get-ChildItem -LiteralPath $_.DirectoryName -Filter 'avcodec*.dll' -File)
    } | Select-Object -First 1
if (-not $ffmpegBin) {
    $release = Invoke-RestMethod 'https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest'
    $name = 'ffmpeg-n9.0-latest-win64-lgpl-shared-9.0.zip'
    $asset = $release.assets | Where-Object name -eq $name | Select-Object -First 1
    if (-not $asset -or $asset.digest -notmatch '^sha256:[a-fA-F0-9]{64}$') {
        throw "FFmpeg release asset or SHA256 digest missing: $name"
    }
    $archivePath = Join-Path $toolsPath $name
    $stagingPath = Join-Path $toolsPath 'ffmpeg-installing'
    if (Test-Path -LiteralPath $stagingPath) {
        throw "Remove incomplete FFmpeg installation before retrying: $stagingPath"
    }
    try {
        Invoke-WebRequest $asset.browser_download_url -OutFile $archivePath
        $actual = Get-Sha256 $archivePath
        if ($actual -ine $asset.digest.Substring(7)) { throw 'FFmpeg archive checksum mismatch' }
        Expand-Archive -LiteralPath $archivePath -DestinationPath $stagingPath
        $ffmpegBin = Get-ChildItem -LiteralPath $stagingPath -Recurse -Filter ffmpeg.exe -File |
            Where-Object {
                (Test-Path -LiteralPath (Join-Path $_.DirectoryName 'ffprobe.exe')) -and
                (Get-ChildItem -LiteralPath $_.DirectoryName -Filter 'avcodec*.dll' -File)
            } | Select-Object -First 1
        if (-not $ffmpegBin) { throw 'FFmpeg archive has no usable shared build' }
        $packagePath = Split-Path -Parent $ffmpegBin.DirectoryName
        $destination = Join-Path $ffmpegRoot (Split-Path -Leaf $packagePath)
        if (Test-Path -LiteralPath $destination) { throw "FFmpeg destination already exists: $destination" }
        New-Item -ItemType Directory -Force -Path $ffmpegRoot | Out-Null
        Move-Item -LiteralPath $packagePath -Destination $destination
    } finally {
        Remove-Item -LiteralPath $archivePath -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$nodeRoot = Join-Path $toolsPath 'node'
$nodeExecutable = Get-ChildItem -LiteralPath $nodeRoot -Recurse -Filter node.exe -File `
    -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $nodeExecutable) {
    $versions = Invoke-RestMethod 'https://nodejs.org/dist/index.json'
    $version = ($versions | Where-Object { $_.version -like 'v24.*' -and $_.lts } |
        Select-Object -First 1).version
    if (-not $version) { throw 'Node.js 24 LTS release not found' }
    $name = "node-$version-win-x64.zip"
    $checksumText = Invoke-RestMethod "https://nodejs.org/dist/$version/SHASUMS256.txt"
    $checksumLine = $checksumText -split "`n" | Where-Object { $_ -match "^[a-fA-F0-9]{64}\s+$([regex]::Escape($name))\s*$" } |
        Select-Object -First 1
    if (-not $checksumLine) { throw "Node.js checksum not found: $name" }
    $archivePath = Join-Path $toolsPath $name
    $stagingPath = Join-Path $toolsPath 'node-installing'
    if (Test-Path -LiteralPath $stagingPath) {
        throw "Remove incomplete Node.js installation before retrying: $stagingPath"
    }
    try {
        Invoke-WebRequest "https://nodejs.org/dist/$version/$name" -OutFile $archivePath
        $actual = Get-Sha256 $archivePath
        if ($actual -ine ($checksumLine -split '\s+')[0]) { throw 'Node.js archive checksum mismatch' }
        Expand-Archive -LiteralPath $archivePath -DestinationPath $stagingPath
        $nodeExecutable = Get-ChildItem -LiteralPath $stagingPath -Recurse -Filter node.exe -File |
            Select-Object -First 1
        if (-not $nodeExecutable) { throw 'Node.js archive has no node.exe' }
        $destination = Join-Path $nodeRoot $nodeExecutable.Directory.Name
        if (Test-Path -LiteralPath $destination) { throw "Node.js destination already exists: $destination" }
        New-Item -ItemType Directory -Force -Path $nodeRoot | Out-Null
        Move-Item -LiteralPath $nodeExecutable.DirectoryName -Destination $destination
    } finally {
        Remove-Item -LiteralPath $archivePath -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $stagingPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
$enginePath = Join-Path $toolsPath 'gigastt.exe'
if (-not (Test-Path -LiteralPath $enginePath)) {
    $release = Invoke-RestMethod 'https://api.github.com/repos/ekhodzitsky/gigastt/releases/latest'
    $name = "gigastt-$($release.tag_name.TrimStart('v'))-x86_64-pc-windows-msvc.tar.gz"
    $asset = $release.assets | Where-Object name -eq $name | Select-Object -First 1
    $checksum = $release.assets | Where-Object name -eq "$name.sha256" | Select-Object -First 1
    if (-not $asset -or -not $checksum) { throw "Windows release asset missing: $name" }
    if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
        throw 'Windows tar.exe is required to unpack GigaSTT. Update Windows and run setup.cmd again.'
    }
    $archivePath = Join-Path $toolsPath $name
    Invoke-WebRequest $asset.browser_download_url -OutFile $archivePath
    $checksumPath = "$archivePath.sha256"
    Invoke-WebRequest $checksum.browser_download_url -OutFile $checksumPath
    $expected = ((Get-Content -LiteralPath $checksumPath -Raw).Trim() -split '\s+')[0]
    $actual = Get-Sha256 $archivePath
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
