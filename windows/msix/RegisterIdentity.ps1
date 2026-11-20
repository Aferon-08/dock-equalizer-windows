$ErrorActionPreference = 'Stop'

function Get-SoundbarRegistration {
    Get-AppxPackage -Name $env:SEKAI_IDENTITY_NAME | Where-Object Publisher -eq $env:SEKAI_IDENTITY_PUBLISHER
}

function Remove-SoundbarRegistration {
    Get-SoundbarRegistration | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName }
}

try {
    if ($env:SEKAI_IDENTITY_ACTION -eq 'Remove') {
        Remove-SoundbarRegistration
        exit 0
    }

    $previous = Get-SoundbarRegistration
    $version = [version]$env:SEKAI_IDENTITY_VERSION
    try {
        if (!($previous | Where-Object Version -ge $version)) {
            Add-AppxPackage -Path $env:SEKAI_IDENTITY_PACKAGE -ExternalLocation $env:SEKAI_PROGRAM_DIR
        }
        $program = Join-Path $env:SEKAI_PROGRAM_DIR 'SekaiSoundbar.exe'
        $probe = Start-Process -FilePath $program -WorkingDirectory $env:SEKAI_PROGRAM_DIR `
            -ArgumentList '--check-notification-identity' -Wait -PassThru
        if ($probe.ExitCode -ne 0) {
            throw "Windows did not attach the registered identity to SekaiSoundbar.exe (exit $($probe.ExitCode))."
        }
    } catch {
        if (!$previous) {
            try { Remove-SoundbarRegistration } catch { Write-Output $_.Exception.Message }
        }
        throw
    }
    exit 0
} catch {
    $message = ($_.Exception.Message -split '\r?\n', 2)[0].Trim()
    Set-Content -LiteralPath $env:SEKAI_IDENTITY_ERROR -Value $message -Encoding Unicode
    exit 1
}
