<#
.SYNOPSIS
  Exportiert die installierte Minecraft-Bedrock-GDK-Version aus Windows, damit
  sie unter bedrock-mac (WineGDK + DXMT) laufen kann.

.DESCRIPTION
  Spiele aus der Xbox-App liegen verschlüsselt auf der Platte. Kopiert man sie
  aus dem Paketkontext heraus (Invoke-CommandInDesktopPackage), liefert Windows
  selbst die Klartextfassung. Das Skript entschlüsselt nichts selbst.

  Ablauf: Paket finden, Dateien im Paketkontext nach -Staging kopieren,
  exe prüfen (MZ-Header, x64), dann nach -Destination (z. B. den geteilten
  Mac-Ordner in Parallels) kopieren.

.EXAMPLE
  # In einer PowerShell als Administrator:
  Set-ExecutionPolicy -Scope Process Bypass
  .\export-minecraft.ps1
  .\export-minecraft.ps1 -Destination "\\Mac\Home\Downloads\minecraft-bedrock"
#>
#Requires -RunAsAdministrator
param(
    [string]$Destination = "\\Mac\Home\Downloads\minecraft-bedrock",
    [string]$Staging = "$env:USERPROFILE\minecraft-export",
    [int]$TimeoutMinutes = 30
)
$ErrorActionPreference = "Stop"
$Family = "Microsoft.MinecraftUWP_8wekyb3d8bbwe"

function Invoke-InPackage([string]$CmdLine) {
    Invoke-CommandInDesktopPackage -PackageFamilyName $Family -AppId "Game" `
        -Command "cmd.exe" -Args "/C $CmdLine"
}

function Wait-ForFile([string]$Path, [string]$What) {
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while (-not (Test-Path $Path)) {
        if ((Get-Date) -gt $deadline) { throw "Timeout beim Warten auf: $What" }
        Start-Sleep -Seconds 3
    }
}

function Get-PeMachine([string]$Path) {
    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $br = New-Object System.IO.BinaryReader($fs)
        if ($br.ReadUInt16() -ne 0x5A4D) { return $null }   # "MZ"
        $fs.Position = 0x3C
        $fs.Position = $br.ReadInt32() + 4                  # PE header + "PE\0\0"
        return $br.ReadUInt16()
    } finally { $fs.Close() }
}

Write-Host "== Minecraft Bedrock Export ==" -ForegroundColor Cyan

$pkg = Get-AppxPackage Microsoft.MinecraftUWP
if (-not $pkg) { throw "Minecraft Bedrock ist nicht installiert. In der Xbox-App installieren und einmal starten." }
$src = $pkg.InstallLocation
Write-Host "Paket:   $($pkg.PackageFullName)"
Write-Host "Ort:     $src"
if (-not (Test-Path (Join-Path $src "MicrosoftGame.Config"))) {
    throw "Keine GDK-Version (MicrosoftGame.Config fehlt). Ab 1.21.120 ist Bedrock auf Windows GDK."
}

if (Test-Path $Staging) { Remove-Item $Staging -Recurse -Force }
New-Item -ItemType Directory -Path $Staging -Force | Out-Null
$done = Join-Path $Staging ".robocopy-done"

Write-Host "[1/3] Kopiere Spieldateien im Paketkontext (dauert einige Minuten) ..."
# robocopy-Exitcodes < 8 bedeuten Erfolg; Marker-Datei zeigt das Ende an.
Invoke-InPackage "robocopy `"$src`" `"$Staging`" /E /R:1 /W:1 /NP /NFL /NDL & echo %ERRORLEVEL% > `"$done`""
Wait-ForFile $done "robocopy"
$rc = [int](Get-Content $done | Select-Object -First 1).Trim()
Remove-Item $done
if ($rc -ge 8) { throw "robocopy meldet Fehler (Exitcode $rc)." }

Write-Host "[2/3] Hole Minecraft.Windows.exe im Klartext ..."
$exe = Join-Path $Staging "Minecraft.Windows.exe"
$tmpExe = "$exe.plain"
Invoke-InPackage "copy /Y `"$src\Minecraft.Windows.exe`" `"$tmpExe`""
Wait-ForFile $tmpExe "exe-Kopie"
Start-Sleep -Seconds 5   # copy schreibt asynchron zu Ende
Move-Item $tmpExe $exe -Force

$machine = Get-PeMachine $exe
if ($null -eq $machine) { throw "Die exe hat keinen MZ-Header, ist also noch verschlüsselt. Minecraft einmal starten und erneut versuchen." }
if ($machine -ne 0x8664) { throw ("Die exe ist nicht x64 (PE-Machine 0x{0:X4}). bedrock-mac braucht die x64-Version." -f $machine) }
Write-Host "  exe ok: x64, $([math]::Round((Get-Item $exe).Length / 1MB, 1)) MB" -ForegroundColor Green

@"
package=$($pkg.PackageFullName)
version=$($pkg.Version)
architecture=$($pkg.Architecture)
exported=$(Get-Date -Format o)
"@ | Set-Content (Join-Path $Staging "BEDROCK-MAC-EXPORT.txt") -Encoding UTF8

Write-Host "[3/3] Kopiere nach $Destination ..."
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
robocopy $Staging $Destination /E /R:1 /W:1 /NP /NFL /NDL | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Kopieren nach $Destination fehlgeschlagen (Exitcode $LASTEXITCODE). Die Dateien liegen unter $Staging." }

$files = Get-ChildItem $Destination -Recurse -File
$mb = [math]::Round(($files | Measure-Object Length -Sum).Sum / 1MB)
Write-Host "Fertig: $($files.Count) Dateien, $mb MB in $Destination" -ForegroundColor Green
Write-Host "Version $($pkg.Version). Die VM wird danach nicht mehr gebraucht."
