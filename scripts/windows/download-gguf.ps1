#!/usr/bin/env pwsh
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$models = Join-Path $Root "models"
New-Item -ItemType Directory -Force -Path $models | Out-Null
$urls = @(
    "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/main/Qwen3.5-9B-Q4_K_M.gguf"
)
foreach ($u in $urls) {
    $f = Join-Path $models ([IO.Path]::GetFileName($u))
    if (Test-Path $f) {
        $remote = (curl.exe -sIL $u | Select-String "content-length" | Select-Object -Last 1) -replace ".*:\s*", ""
        if ($remote -and ([int64]$remote -le (Get-Item $f).Length)) { Write-Host "Vollständig: $f"; continue }
        Write-Host "Unvollständig ($([math]::Round((Get-Item $f).Length/1MB,1))MB), setze Download fort: $f"
    }
    Write-Host "Downloade $u"
    curl.exe -L --fail -C - $u -o $f
    if ($LASTEXITCODE -ne 0) { throw "Download fehlgeschlagen: $u" }
}
Write-Host "OK: Modelle in $models"