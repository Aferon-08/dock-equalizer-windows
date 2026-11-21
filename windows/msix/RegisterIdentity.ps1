$ErrorActionPreference = 'Stop'

function Get-SoundbarRegistration {
    Get-AppxPackage -Name $env:SEKAI_IDENTITY_NAME | Where-Object Publisher -eq $env:SEKAI_IDENTITY_PUBLISHER
}

function Remove-SoundbarRegistration {
    Get-SoundbarRegistration | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName }
}

function Get-IdentityProbeExitCode {
    $program = Join-Path $env:SEKAI_PROGRAM_DIR 'SekaiSoundbar.exe'
    $probe = Start-Process -FilePath $program -WorkingDirectory $env:SEKAI_PROGRAM_DIR `
        -ArgumentList '--check-notification-identity' -Wait -PassThru
    return $probe.ExitCode
}

function Test-PackageInUse([System.Management.Automation.ErrorRecord]$Failure) {
    for ($exception = $Failure.Exception; $exception; $exception = $exception.InnerException) {
        if ($exception.HResult -eq 0x80073D02 -or $exception.Message -match '\b0x80073D02\b') {
            return $true
        }
    }
    return $Failure.ErrorDetails.Message -match '\b0x80073D02\b'
}

function Install-SoundbarRegistration([bool]$HasPrevious) {
    $delays = @(0, 500, 1000, 2000)
    for ($attempt = 0; $attempt -lt $delays.Count; $attempt++) {
        if ($delays[$attempt]) {
            Start-Sleep -Milliseconds $delays[$attempt]
        }
        try {
            Add-AppxPackage -Path $env:SEKAI_IDENTITY_PACKAGE -ExternalLocation $env:SEKAI_PROGRAM_DIR `
                -ForceTargetApplicationShutdown:($attempt -gt 0)
            return
        } catch {
            if (!(Test-PackageInUse $_)) {
                throw
            }
            if ($attempt -eq $delays.Count - 1) {
                # An older registration can still cover the new executable at the same external location.
                if ($HasPrevious -and (Get-IdentityProbeExitCode) -eq 0) {
                    return
                }
                throw
            }
        }
    }
}

try {
    if ($env:SEKAI_IDENTITY_ACTION -eq 'Remove') {
        Remove-SoundbarRegistration
        exit 0
    }

    $previous = @(Get-SoundbarRegistration)
    $version = [version]$env:SEKAI_IDENTITY_VERSION
    try {
        if (!($previous | Where-Object Version -ge $version)) {
            Install-SoundbarRegistration ($previous.Count -gt 0)
        }
        $probeExitCode = Get-IdentityProbeExitCode
        if ($probeExitCode -ne 0) {
            throw "Windows did not attach the registered identity to SekaiSoundbar.exe (exit $probeExitCode)."
        }
    } catch {
        if (!$previous) {
            try { Remove-SoundbarRegistration } catch { Write-Output $_.Exception.Message }
        }
        throw
    }
    exit 0
} catch {
    $message = $_.Exception.Message.Trim()
    $details = $_.ErrorDetails.Message
    if ($details -and !$message.Contains($details.Trim())) {
        $message += [Environment]::NewLine + $details.Trim()
    }
    Set-Content -LiteralPath $env:SEKAI_IDENTITY_ERROR -Value $message -Encoding Unicode
    exit 1
}
