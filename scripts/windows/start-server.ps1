#!/usr/bin/env pwsh
param(
    [Parameter(Mandatory=$true)][ValidateSet("9b","27b","27b-200k","27b-250k")][string]$Profile,
    [ValidateRange(1024,262144)][int]$Context = 0,
    [ValidateSet("default","balanced","max")][string]$KvPreset = "default",
    [switch]$Mtp
)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$conf = @{}
Get-Content (Join-Path $Root "scripts/common/profiles.conf") | Where-Object { $_ -match '^\s*[A-Za-z0-9_]+=' } | ForEach-Object {
    $k, $v = $_ -split '=', 2; $conf[$k.Trim()] = $v.Trim()
}

$build = Join-Path $Root $conf["BUILD_DIR"]
$server = Join-Path $build "bin/Release/llama-server.exe"
if (-not (Test-Path $server)) { $server = Join-Path $build "bin/llama-server.exe" }
if (-not (Test-Path $server)) { throw "llama-server fehlt. Erst scripts/windows/setup.ps1 ausführen." }

$is27b = $Profile -like "27b*"
if ($is27b) {
    $model = Join-Path $Root $conf["MODEL_27B"]
    if ($Context -gt 0) {
        $ctx = $Context
    } elseif ($Profile -eq "27b-250k") {
        $ctx = [int]$conf["CTX_27B_MAX"]
    } else {
        $ctx = [int]$conf["CTX_27B"]
    }
} else {
    $model = Join-Path $Root $conf["MODEL_9B"]
    $ctx = if ($Context -gt 0) { $Context } else { [int]$conf["CTX_9B"] }
}
if (-not (Test-Path $model)) { throw "Modell fehlt: $model" }

if ($is27b) {
    switch ($KvPreset) {
        "balanced" { $kvK = "q8_0"; $kvV = "turbo3" }
        "max"      { $kvK = "q8_0"; $kvV = "turbo2" }
        default    { $kvK = $conf["KV_K_27B"]; $kvV = $conf["KV_V_27B"] }
    }
} else {
    $kvK = $conf["KV_K_9B"]
    $kvV = $conf["KV_V_9B"]
}

# IMPORTANT: do not pass -ngl when using --fit. Explicit -ngl disables automatic
# layer fitting in current llama.cpp. The requested context remains fixed; fit
# adjusts the weight offload around that context instead of shrinking it.
$args = @(
    "-m", $model,
    "-fit", $conf["FIT"],
    "-fitt", $conf["FIT_TARGET_MIB"],
    "-c", "$ctx",
    "-ctk", $kvK,
    "-ctv", $kvV,
    "--flash-attn", "on",
    "--jinja",
    "-np", "1",
    "--host", $conf["HOST"],
    "--port", $conf["PORT"]
)

if ($is27b -and $Mtp) {
    $draft = Join-Path $Root $conf["MTP_DRAFT_27B"]
    if (-not (Test-Path $draft)) { throw "MTP-Draft fehlt: $draft" }
    $args += @(
        "--spec-type", "draft-mtp",
        "--spec-draft-model", $draft,
        "--spec-draft-n-max", $conf["MTP_DRAFT_N_MAX"],
        "--spec-chain", $conf["MTP_CHAIN"]
    )
}

Write-Host "Starte llama-server"
Write-Host "  Profil:   $Profile"
Write-Host "  Context:  $ctx"
Write-Host "  KV:       K=$kvK / V=$kvV"
Write-Host "  MTP:      $($Mtp.IsPresent)"
Write-Host "  VRAM fit: auto (target margin $($conf['FIT_TARGET_MIB']) MiB)"
Write-Host ""
Write-Host "  $server $($args -join ' ')"
& $server @args
