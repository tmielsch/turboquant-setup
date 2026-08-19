#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$conf = @{}
Get-Content (Join-Path $Root "scripts/common/profiles.conf") | Where-Object { $_ -match '^\s*[A-Za-z_]+=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2; $conf[$k.Trim()] = $v.Trim()
}
$engine = Join-Path $Root $conf["ENGINE_DIR"]
$build  = Join-Path $Root $conf["BUILD_DIR"]

if (-not (Test-Path $engine)) {
    git clone --branch $conf["FORK_BRANCH"] $conf["FORK_URL"] $engine
    if ($LASTEXITCODE -ne 0) { throw "git clone fehlgeschlagen" }
} else {
    Write-Host "Engine vorhanden, überspringe Klonen: $engine"
}

if (-not (Test-Path (Join-Path $build "CMakeCache.txt"))) {
    cmake -S $engine -B $build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=89 -DCMAKE_BUILD_TYPE=Release
    if ($LASTEXITCODE -ne 0) { throw "cmake configure fehlgeschlagen" }
} else {
    Write-Host "Build-Cache vorhanden, überspringe configure"
}

cmake --build $build --config Release -j --target llama-server llama-cli llama-bench
if ($LASTEXITCODE -ne 0) { throw "cmake build fehlgeschlagen" }

$server = Join-Path $build "bin/Release/llama-server.exe"
if (-not (Test-Path $server)) { $server = Join-Path $build "bin/llama-server.exe" }
if (-not (Test-Path $server)) { throw "llama-server.exe nicht gefunden unter $build" }
& $server --version
Write-Host "OK: Setup abgeschlossen. Server: $server"
