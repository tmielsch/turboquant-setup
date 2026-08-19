#!/usr/bin/env pwsh
param(
    [string]$Listen = "127.0.0.1:9292"
)
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$conf = @{}
Get-Content (Join-Path $Root "scripts/common/profiles.conf") |
    Where-Object { $_ -match '^\s*[A-Za-z0-9_]+=' } |
    ForEach-Object {
        $k, $v = $_ -split '=', 2
        $conf[$k.Trim()] = $v.Trim()
    }

$swap = Get-Command llama-swap -ErrorAction SilentlyContinue
if (-not $swap) {
    throw "llama-swap fehlt. Einmalig installieren (Windows: winget install llama-swap), dann erneut starten."
}

$build = Join-Path $Root $conf["BUILD_DIR"]
$engine = Join-Path $build "bin/Release/llama-server.exe"
if (-not (Test-Path $engine)) { $engine = Join-Path $build "bin/llama-server.exe" }
if (-not (Test-Path $engine)) {
    throw "TurboQuant llama-server fehlt. Erst scripts/windows/setup.ps1 ausführen."
}

$model9b = Join-Path $Root $conf["MODEL_9B"]
$model27b = Join-Path $Root $conf["MODEL_27B"]
$mtp27b = Join-Path $Root $conf["MTP_DRAFT_27B"]

if (-not (Test-Path $model27b)) { throw "27B-Modell fehlt: $model27b" }
if (-not (Test-Path $model9b)) { Write-Warning "9B-Modell fehlt; qwen3.5-9b-32k kann nicht geladen werden: $model9b" }
if (-not (Test-Path $mtp27b)) { Write-Warning "MTP-Draft fehlt; *-mtp Varianten können nicht geladen werden: $mtp27b" }

# llama-swap config stays machine-independent. Absolute paths are injected at runtime.
$env:TQ_ENGINE = (Resolve-Path $engine).Path
$env:TQ_MODEL_27B = (Resolve-Path $model27b).Path
$env:TQ_MODEL_9B = if (Test-Path $model9b) { (Resolve-Path $model9b).Path } else { $model9b }
$env:TQ_MTP_DRAFT_27B = if (Test-Path $mtp27b) { (Resolve-Path $mtp27b).Path } else { $mtp27b }

$config = Join-Path $Root "llama-swap/config.yaml"
if (-not (Test-Path $config)) { throw "llama-swap config fehlt: $config" }

Write-Host "TurboQuant Gateway"
Write-Host "  API:      http://$Listen/v1"
Write-Host "  Web UI:   http://$Listen/ui"
Write-Host "  Engine:   $engine"
Write-Host "  Models:   qwen3.8-27b-200k, qwen3.8-27b-250k, *-mtp"
Write-Host ""
Write-Host "Kein Modell wird beim Start geladen. llama-swap startet die angeforderte Variante on demand."

& $swap.Source --config $config --listen $Listen --watch-config
