param([Parameter(Mandatory)][string]$Dist)

$ErrorActionPreference = 'Stop'
$Dist = (Resolve-Path $Dist).Path
$stem = 'SekaiSoundbar-Windows11-x64'
$data = Join-Path $PSScriptRoot 'fixtures'
$argsForSmoke = '--smoke-test "{0}" "{1}"' -f (Join-Path $data lyrics.lrc), (Join-Path $data wordtime.json)
$installed = Join-Path $env:LOCALAPPDATA 'Programs\SekaiSoundbar'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\SekaiSoundbar'
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Sekai Soundbar\Sekai Soundbar.lnk'
$extract = Join-Path $env:RUNNER_TEMP 'SekaiSoundbarPortable'

function Invoke-Checked([string]$Exe, [string]$Arguments) {
    $process = Start-Process $Exe -ArgumentList $Arguments -WorkingDirectory (Split-Path $Exe) -PassThru -Wait
    if ($process.ExitCode -ne 0) { throw "$Exe exited with $($process.ExitCode)" }
}

# Reveal missing deployment files instead of picking them up from the build SDK.
$env:Path = "$env:SystemRoot\System32;$env:SystemRoot"
Remove-Item Env:QT_PLUGIN_PATH, Env:QML_IMPORT_PATH, Env:QML2_IMPORT_PATH -ErrorAction SilentlyContinue
Expand-Archive (Join-Path $Dist "$stem.zip") $extract
$portable = Join-Path $extract "$stem\SekaiSoundbar.exe"
Invoke-Checked $portable "--software-rendering $argsForSmoke"

$setup = Join-Path $Dist "$stem-Setup.exe"
if ((Test-Path $installed) -or (Test-Path $uninstallKey)) {
    throw 'Use a clean test account for the setup smoke test.'
}
Invoke-Checked $setup '/S'
$program = Join-Path $installed 'app\SekaiSoundbar.exe'
if (!(Test-Path $shortcut) -or !(Test-Path $uninstallKey)) {
    throw 'Setup did not register the app or create its shortcut.'
}
Invoke-Checked $program "--software-rendering $argsForSmoke"
Invoke-Checked $setup '/S'
if ((Get-FileHash $program).Hash -ne (Get-FileHash $portable).Hash) {
    throw 'Installed and portable executables differ after update.'
}
Invoke-Checked (Join-Path $installed 'Uninstall.exe') '/S'
if ((Test-Path $installed) -or (Test-Path $shortcut) -or (Test-Path $uninstallKey)) {
    throw 'Uninstall left the program, Start menu shortcut or uninstall entry behind.'
}
