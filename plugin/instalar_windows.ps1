# =====================================================================
# SIG-TEC - Installs the plugin into the QGIS user profile (Windows).
#
#   QGIS 3.x : %APPDATA%\QGIS\QGIS3\profiles\<profile>\python\plugins\sigtec
#   QGIS 4.x : %APPDATA%\QGIS\QGIS4\profiles\<profile>\python\plugins\sigtec
#
# By default it installs into every QGIS3/QGIS4 profile folder that exists
# (or QGIS3 if none exists yet). Existing config.json is kept.
#
# Usage (from the repo root, in PowerShell):
#   powershell -ExecutionPolicy Bypass -File plugin\instalar_windows.ps1
#   powershell -ExecutionPolicy Bypass -File plugin\instalar_windows.ps1 -Perfil default -Version QGIS4
#   powershell -ExecutionPolicy Bypass -File plugin\instalar_windows.ps1 -Destino C:\tmp\plugins
# Then in QGIS: Plugins > Manage and Install Plugins > Installed > enable "SIG-TEC".
# =====================================================================
param(
    [string]$Perfil = "default",
    [ValidateSet("", "QGIS3", "QGIS4")][string]$Version = "",
    [string]$Destino = ""     # plugins folder to use instead of the QGIS profile
)
$ErrorActionPreference = "Stop"
$origen = Join-Path $PSScriptRoot "sigtec"
if (-not (Test-Path (Join-Path $origen "metadata.txt"))) { throw "Plugin not found in $origen" }

$carpetas = @()
if ($Destino) {
    $carpetas += $Destino
} else {
    $versiones = if ($Version) { @($Version) } else { @("QGIS3", "QGIS4") }
    foreach ($v in $versiones) {
        $perfil = Join-Path $env:APPDATA "QGIS\$v\profiles\$Perfil"
        if ($Version -or (Test-Path $perfil)) { $carpetas += Join-Path $perfil "python\plugins" }
    }
    if ($carpetas.Count -eq 0) {
        $carpetas += Join-Path $env:APPDATA "QGIS\QGIS3\profiles\$Perfil\python\plugins"
    }
}

foreach ($plugins in $carpetas) {
    $dest = Join-Path $plugins "sigtec"
    $configPrevia = $null
    if (Test-Path (Join-Path $dest "config.json")) {
        $configPrevia = Get-Content (Join-Path $dest "config.json") -Raw -Encoding UTF8
    }
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -Path (Join-Path $origen "*") -Destination $dest -Recurse -Force
    Get-ChildItem $dest -Recurse -Directory -Filter "__pycache__" | Remove-Item -Recurse -Force
    if ($configPrevia) {
        [System.IO.File]::WriteAllText((Join-Path $dest "config.json"), $configPrevia, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "   (kept existing config.json)"
    }
    Write-Host "Installed in $dest"
}
Write-Host "Restart QGIS (or use Plugin Reloader) and enable 'SIG-TEC' in the Plugins manager."
