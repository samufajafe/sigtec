# =====================================================================
# SIG-TEC - Builds dist\sigtec-<version>.zip for
# QGIS: Plugins > Manage and Install Plugins > Install from ZIP.
#
# The zip contains a single top folder "sigtec/" and uses "/" as path
# separator (Compress-Archive in Windows PowerShell 5.1 writes "\", which
# some unzip tools and QGIS versions do not handle well).
#
# Usage (from the repo root): powershell -ExecutionPolicy Bypass -File plugin\empaquetar_zip.ps1
# =====================================================================
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$origen = Join-Path $PSScriptRoot "sigtec"
$meta = Get-Content (Join-Path $origen "metadata.txt")
$version = (($meta | Where-Object { $_ -match '^version=' }) -replace '^version=', '').Trim()
$dist = Join-Path (Split-Path $PSScriptRoot -Parent) "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$zip = Join-Path $dist "sigtec-$version.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }

$archivo = [System.IO.Compression.ZipFile]::Open($zip, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    $base = (Resolve-Path $origen).Path.TrimEnd('\') + '\'
    Get-ChildItem $origen -Recurse -File |
        Where-Object { $_.FullName -notmatch '\\__pycache__\\' -and $_.Extension -ne '.pyc' } |
        ForEach-Object {
            $relativo = $_.FullName.Substring($base.Length).Replace('\', '/')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archivo, $_.FullName, "sigtec/$relativo",
                [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
        }
} finally {
    $archivo.Dispose()
}
Write-Host "Created $zip"
