param([Parameter(Mandatory)][string]$Dist, [switch]$ExpectNotificationIdentity)

$ErrorActionPreference = 'Stop'
$Dist = (Resolve-Path $Dist).Path
$stem = 'SekaiSoundbar-Windows11-x64'
$data = Join-Path $PSScriptRoot 'fixtures'
$argsForSmoke = '--smoke-test "{0}" "{1}"' -f (Join-Path $data lyrics.lrc), (Join-Path $data wordtime.json)
$installed = Join-Path $env:LOCALAPPDATA 'Programs\SekaiSoundbar'
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\SekaiSoundbar'
$shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Sekai Soundbar\Sekai Soundbar.lnk'
$extract = Join-Path $env:RUNNER_TEMP 'SekaiSoundbarPortable'
if ($ExpectNotificationIdentity -and [Environment]::OSVersion.Version.Build -lt 22000) {
    throw 'Testing the notification identity requires Windows 11.'
}

function Invoke-Checked([string]$Exe, [string]$Arguments) {
    $process = Start-Process $Exe -ArgumentList $Arguments -WorkingDirectory (Split-Path $Exe) -PassThru -Wait
    if ($process.ExitCode -ne 0) { throw "$Exe exited with $($process.ExitCode)" }
}

# Reveal missing deployment files instead of picking them up from the build SDK.
$env:Path = "$env:SystemRoot\System32;$env:SystemRoot"
Remove-Item Env:QT_PLUGIN_PATH, Env:QML_IMPORT_PATH, Env:QML2_IMPORT_PATH -ErrorAction SilentlyContinue
if (!$ExpectNotificationIdentity) {
    Expand-Archive (Join-Path $Dist "$stem.zip") $extract
    $portable = Join-Path $extract "$stem\SekaiSoundbar.exe"
    Invoke-Checked $portable "--software-rendering $argsForSmoke"
}

$setup = Join-Path $Dist "$stem-Setup.exe"
if ((Test-Path $installed) -or (Test-Path $uninstallKey)) {
    throw 'Use a clean test account for the setup smoke test.'
}
# An interrupted installation can leave an app directory with no executable.
New-Item -Path (Join-Path $installed 'app') -ItemType Directory -Force | Out-Null
Invoke-Checked $setup '/S'
$program = Join-Path $installed 'app\SekaiSoundbar.exe'
if (!(Test-Path $shortcut) -or !(Test-Path $uninstallKey)) {
    throw 'Setup did not register the app or create its shortcut.'
}
if ($ExpectNotificationIdentity) {
    Invoke-Checked $program '--check-notification-identity'
}
Invoke-Checked $program "--software-rendering $argsForSmoke"
$marker = Join-Path $installed 'app\reuse-marker.txt'
Set-Content $marker 'The installer must reuse the verified runtime directory.'
$locked = [IO.File]::Open($program, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
try {
    Invoke-Checked $setup '/S'
} finally {
    $locked.Dispose()
}
if (!(Test-Path $marker)) { throw 'Setup replaced the verified runtime during reinstall.' }
# A changed file must force the ordinary replacement path.
Set-Content (Join-Path $installed 'app\VERSION.txt') 'modified'
Invoke-Checked $setup '/S'
if (Test-Path $marker) { throw 'Setup reused a runtime with a modified file.' }
Move-Item (Join-Path $installed 'app') (Join-Path $installed 'previous')
New-Item -Path (Join-Path $installed 'app') -ItemType Directory | Out-Null
Invoke-Checked $setup '/S'
if ($ExpectNotificationIdentity) {
    Invoke-Checked $program '--check-notification-identity'
}
if (!$ExpectNotificationIdentity -and (Get-FileHash $program).Hash -ne (Get-FileHash $portable).Hash) {
    throw 'Installed and portable executables differ after update.'
}
Invoke-Checked (Join-Path $installed 'Uninstall.exe') '/S'
if ((Test-Path $installed) -or (Test-Path $shortcut) -or (Test-Path $uninstallKey)) {
    throw 'Uninstall left the program, Start menu shortcut or uninstall entry behind.'
}
if ($ExpectNotificationIdentity -and (Get-AppxPackage -Name 'Aferon08.SekaiSoundbar.Desktop')) {
    throw 'Uninstall left the notification identity registered.'
}
