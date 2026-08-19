#!/usr/bin/env pwsh
param([Parameter(Mandatory=$true)][ValidateSet("9b","27b")][string]$Profile)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$conf = @{}
Get-Content (Join-Path $Root "scripts/common/profiles.conf") | Where-Object { $_ -match '^\s*[A-Za-z0-9_]+=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2; $conf[$k.Trim()] = $v.Trim()
}
$build = Join-Path $Root $conf["BUILD_DIR"]
$server = Join-Path $build "bin/Release/llama-server.exe"
if (-not (Test-Path $server)) { $server = Join-Path $build "bin/llama-server.exe" }
$model = Join-Path $Root $conf["MODEL_9B"]
if ($Profile -eq "27b") { $model = Join-Path $Root $conf["MODEL_27B"] }
if (-not (Test-Path $model)) { throw "Modell fehlt: $model" }

$args = @(
    "-m", $model,
    "-ngl", $conf["GPU_LAYERS"],
    "-c", $conf["CTX"],
    "-ctk", $conf["KV_K"],
    "-ctv", $conf["KV_V"],
    "--flash-attn", "on",
    "--jinja",
    "-np", "1",
    "--host", $conf["HOST"],
    "--port", $conf["PORT"]
)
if ($Profile -eq "27b" -and (Test-Path (Join-Path $Root $conf["MTP_DRAFT_27B"]))) {
    $args += "--spec-type", "draft-mtp", "--spec-draft-model", (Join-Path $Root $conf["MTP_DRAFT_27B"]), "--spec-draft-n-max", "3"
}
Write-Host "Starte llama-server (Profil $Profile):"
Write-Host "  $server $($args -join ' ')"
& $server @args
