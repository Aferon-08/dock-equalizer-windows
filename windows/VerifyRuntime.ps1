$ErrorActionPreference = 'Stop'

try {
    $manifest = [IO.File]::ReadAllLines($env:SEKAI_RUNTIME_MANIFEST)
    if ($manifest.Count -eq 0) { exit 1 }
    foreach ($line in $manifest) {
        if ($line -notmatch '\A([a-fA-F0-9]{64})  (.+)\z') { exit 1 }
        $expected = $Matches[1]
        $path = Join-Path $env:SEKAI_RUNTIME_DIR $Matches[2]
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected) { exit 1 }
    }
    exit 0
} catch {
    exit 1
}
