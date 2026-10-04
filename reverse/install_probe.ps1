# Installe (ou met à jour) le mod CockroachProbe dans l'installation UE4SS du jeu.
# Usage : powershell -ExecutionPolicy Bypass -File reverse\install_probe.ps1 [-Win64 <chemin>]
param(
    [string]$Win64 = "C:\Program Files (x86)\Steam\steamapps\common\Empire of the Ants\Empire\Binaries\Win64"
)
$ErrorActionPreference = "Stop"
$mods = Join-Path $Win64 "ue4ss\Mods"
if (-not (Test-Path $mods)) { throw "UE4SS introuvable: $mods" }

$src = Join-Path $PSScriptRoot "ue4ss\CockroachProbe"
$dst = Join-Path $mods "CockroachProbe"
New-Item -ItemType Directory -Force (Join-Path $dst "Scripts") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $dst "out") | Out-Null
Copy-Item (Join-Path $src "Scripts\main.lua") (Join-Path $dst "Scripts\main.lua") -Force

$utf8 = New-Object System.Text.UTF8Encoding($false)  # sans BOM

# mods.txt : la ligne doit être avant "Keybinds" (UE4SS le demande).
$txt = Join-Path $mods "mods.txt"
$lines = [IO.File]::ReadAllLines($txt) | Where-Object { $_ -notmatch '^\s*CockroachProbe\s*:' }
$out = New-Object System.Collections.Generic.List[string]
$added = $false
foreach ($l in $lines) {
    if (-not $added -and $l -match 'Built-in keybinds') { $out.Add("CockroachProbe : 1"); $added = $true }
    $out.Add($l)
}
if (-not $added) { $out.Insert(0, "CockroachProbe : 1") }
[IO.File]::WriteAllLines($txt, $out, $utf8)

# mods.json (versions récentes d'UE4SS).
$json = Join-Path $mods "mods.json"
if (Test-Path $json) {
    $arr = @([IO.File]::ReadAllText($json) | ConvertFrom-Json) | Where-Object { $_.mod_name -ne "CockroachProbe" }
    $entry = [pscustomobject]@{ mod_name = "CockroachProbe"; mod_enabled = $true }
    $kb = [array]::IndexOf(@($arr | ForEach-Object { $_.mod_name }), "Keybinds")
    if ($kb -lt 0) { $arr = @($arr) + $entry } else { $arr = @($arr[0..($kb - 1)]) + $entry + @($arr[$kb..($arr.Count - 1)]) }
    [IO.File]::WriteAllText($json, (ConvertTo-Json @($arr) -Depth 3), $utf8)
}
Write-Host "CockroachProbe installe dans $dst"
