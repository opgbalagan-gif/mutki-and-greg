$ErrorActionPreference = 'Stop'
$projectDirectory = Split-Path -Parent $PSScriptRoot
$godotExecutable = Join-Path $projectDirectory '.tools/godot-4.7.1/Godot_v4.7.1-stable_win64.exe'
if (-not (Test-Path -LiteralPath $godotExecutable)) {
    throw 'Godot не найден. Откройте project.godot в Godot 4.7.1 или новее.'
}
& $godotExecutable --path $projectDirectory --log-file (Join-Path $projectDirectory 'godot-play.log')
