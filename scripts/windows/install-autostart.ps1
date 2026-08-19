#!/usr/bin/env pwsh
param(
    [string]$TaskName = "TurboQuant llama-swap"
)
$ErrorActionPreference = "Stop"

$gateway = Join-Path $PSScriptRoot "start-gateway.ps1"
if (-not (Test-Path $gateway)) { throw "Gateway-Launcher fehlt: $gateway" }

$shell = Get-Command pwsh -ErrorAction SilentlyContinue
if (-not $shell) { $shell = Get-Command powershell -ErrorAction Stop }

$action = New-ScheduledTaskAction \
    -Execute $shell.Source \
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$gateway`""
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask \
    -TaskName $TaskName \
    -Action $action \
    -Trigger $trigger \
    -Settings $settings \
    -Description "Startet den lokalen llama-swap/TurboQuant Gateway beim Login; Modelle werden erst bei API-Anfrage geladen." \
    -Force | Out-Null

Write-Host "Autostart eingerichtet: $TaskName"
Write-Host "Gateway: $gateway"
