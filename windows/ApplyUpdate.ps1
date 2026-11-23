$ErrorActionPreference = 'Stop'
$setup = $env:SEKAI_UPDATE_SETUP
$root = $env:SEKAI_UPDATE_ROOT
$staging = Split-Path -LiteralPath $setup
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\SekaiSoundbar'
$restart = $true

try {
    $old = Get-Process -Id ([int]$env:SEKAI_UPDATE_PROCESS) -ErrorAction SilentlyContinue
    if ($old) {
        try { $started = $old.StartTime.ToUniversalTime().ToFileTimeUtc() }
        catch { if (!$old.HasExited) { throw }; $started = 0 }
        if ($started -eq [long]$env:SEKAI_UPDATE_STARTED -and !$old.WaitForExit(20000)) {
            $restart = $false
            throw 'Sekai Soundbar did not finish shutting down.'
        }
    }
    if ((Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash -ne $env:SEKAI_UPDATE_SHA256) {
        throw 'The installer changed after verification.'
    }
    # NSIS requires /D= to be the last argument and uses the rest of the line as the path.
    $installation = Start-Process -FilePath $setup -ArgumentList "/S /D=$root" -WorkingDirectory $staging -Wait -PassThru
    if ($installation.ExitCode -ne 0) {
        throw "Setup exited with code $($installation.ExitCode)."
    }
} finally {
    Remove-Item -LiteralPath $setup -ErrorAction SilentlyContinue
    try { [IO.Directory]::Delete($staging) } catch { }

    # The setup keeps the previous runtime registered if an update rolls back.
    $registration = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
    if ($restart -and $registration.InstallLocation -eq $root -and $registration.RuntimeFolder -in @('app', 'app-update')) {
        $program = Join-Path $root "$($registration.RuntimeFolder)\SekaiSoundbar.exe"
        if (Test-Path -LiteralPath $program -PathType Leaf) {
            Start-Process -FilePath $program -WorkingDirectory (Split-Path -LiteralPath $program)
        }
    }
}
