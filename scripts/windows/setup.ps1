#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$conf = @{}
Get-Content (Join-Path $Root "scripts/common/profiles.conf") | Where-Object { $_ -match '^\s*[A-Za-z0-9_]+=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2; $conf[$k.Trim()] = $v.Trim()
}
$engine = Join-Path $Root $conf["ENGINE_DIR"]
$build  = Join-Path $Root $conf["BUILD_DIR"]

if (-not (Test-Path $engine)) {
    git clone --branch $conf["FORK_BRANCH"] $conf["FORK_URL"] $engine
    if ($LASTEXITCODE -ne 0) { throw "git clone fehlgeschlagen" }
} else {
    Write-Host "Engine vorhanden; aktualisiere $($conf['FORK_BRANCH']) ..."
    git -C $engine fetch origin $conf["FORK_BRANCH"]
    if ($LASTEXITCODE -ne 0) { throw "git fetch fehlgeschlagen" }
    git -C $engine checkout $conf["FORK_BRANCH"]
    if ($LASTEXITCODE -ne 0) { throw "git checkout fehlgeschlagen" }
    git -C $engine pull --ff-only origin $conf["FORK_BRANCH"]
    if ($LASTEXITCODE -ne 0) { throw "git pull fehlgeschlagen" }
}

cmake -S $engine -B $build -DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=89 -DCMAKE_BUILD_TYPE=Release
if ($LASTEXITCODE -ne 0) { throw "cmake configure fehlgeschlagen" }

cmake --build $build --config Release -j --target llama-server llama-cli llama-bench
if ($LASTEXITCODE -ne 0) { throw "cmake build fehlgeschlagen" }

$server = Join-Path $build "bin/Release/llama-server.exe"
if (-not (Test-Path $server)) { $server = Join-Path $build "bin/llama-server.exe" }
if (-not (Test-Path $server)) { throw "llama-server.exe nicht gefunden unter $build" }

Write-Host ""
Write-Host "Engine: $($conf['FORK_URL']) @ $($conf['FORK_BRANCH'])"
& $server --version
Write-Host "OK: TurboQuant-Setup abgeschlossen. Server: $server"
