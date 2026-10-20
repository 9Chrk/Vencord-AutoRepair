#requires -Version 5.1
# Cooperative shutdown: let a repair finish instead of killing it mid-write.
$ErrorActionPreference = 'Stop'
$runtime = Join-Path $PSScriptRoot 'runtime'
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
$request = Join-Path $runtime 'stop.request'
Set-Content -LiteralPath $request -Value 'stop' -Encoding ASCII
$deadline = [DateTime]::UtcNow.AddSeconds(480)
do {
    $lock = $null
    try { $lock = [IO.File]::Open((Join-Path $runtime 'watcher.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
    catch [IO.IOException] {
        if ([DateTime]::UtcNow -ge $deadline) { throw 'La surveillance ne s arrete pas. Reessayer apres la reparation en cours.' }
        Start-Sleep -Milliseconds 250
    }
} until ($lock)
$lock.Dispose()
Remove-Item -LiteralPath $request -Force
