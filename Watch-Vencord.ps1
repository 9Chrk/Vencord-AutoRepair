#requires -Version 5.1
[CmdletBinding()]
param([switch]$Once, [switch]$CheckOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'VencordAutoUpdate.psm1') -Force
$config = Get-AutoUpdateConfig -ProjectPath $PSScriptRoot
$runtime = Join-Path $PSScriptRoot 'runtime'
$vencord = if ($env:VENCORD_USER_DATA_DIR) { $env:VENCORD_USER_DATA_DIR }
    elseif ($env:DISCORD_USER_DATA_DIR) { Join-Path (Split-Path $env:DISCORD_USER_DATA_DIR -Parent) 'VencordData' }
    else { Join-Path $env:APPDATA 'Vencord' }
if ($CheckOnly) {
    $snapshot = Get-DiscordSnapshot $config.discordPath
    if (-not $snapshot) { throw 'Aucune version complete de Discord detectee.' }
    [pscustomobject]@{ Version = $snapshot.Version; VencordPatched = Test-VencordPatch $snapshot $vencord
        UpdaterBusy = Test-DiscordUpdaterBusy $config.discordPath; DiscordPath = $config.discordPath }
    return
}
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
# FileShare.None gives a crash-safe lock, including across terminal/logon/task launches.
$lock = $null
try { $lock = [IO.File]::Open((Join-Path $runtime 'watcher.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
catch [IO.IOException] { return }
try {
    $stateFile = Join-Path $runtime 'state.json'
    $state = $null
    if (Test-Path -LiteralPath $stateFile) {
        try { $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json; $null = $state.version }
        catch { Write-AutoUpdateLog $runtime 'Etat illisible : verification des fichiers a nouveau.'; $state = $null }
    }
    $lastSignature = ''
    $stableSince = [DateTime]::UtcNow
    $retryAfter = [DateTime]::MinValue
    Write-AutoUpdateLog $runtime ('Surveillance demarree (verification toutes les {0} secondes).' -f $config.pollSeconds)
    do {
        if (Test-Path -LiteralPath (Join-Path $runtime 'stop.request')) {
            Write-AutoUpdateLog $runtime 'Arret de la surveillance demande.'
            break
        }
        try {
            $snapshot = Get-DiscordSnapshot $config.discordPath
            if (-not $snapshot -or (Test-DiscordUpdaterBusy $config.discordPath)) {
                $lastSignature = ''
            } else {
                if ($snapshot.Signature -ne $lastSignature) {
                    $lastSignature = $snapshot.Signature
                    $stableSince = [DateTime]::UtcNow
                }
                $reason = Get-RepairReason $snapshot $state (Test-VencordPatch $snapshot $vencord)
                $settled = ([DateTime]::UtcNow - $stableSince).TotalSeconds -ge $config.settleSeconds
                if ($reason -and $settled -and [DateTime]::UtcNow -ge $retryAfter) {
                    Write-AutoUpdateLog $runtime $reason
                    $snapshot = Invoke-VencordRepair -DiscordPath $config.discordPath -VencordPath $vencord `
                        -RuntimePath $runtime -Snapshot $snapshot -RestartDiscord $config.restartDiscord
                    $state = @{ version = $snapshot.Version; verifiedAt = [DateTime]::UtcNow.ToString('o') }
                    $state | ConvertTo-Json | Set-Content -LiteralPath ($stateFile + '.tmp') -Encoding UTF8
                    Move-Item -LiteralPath ($stateFile + '.tmp') -Destination $stateFile -Force
                    Write-AutoUpdateLog $runtime ('Vencord verifie sur Discord {0}.' -f $snapshot.Version)
                    if ($Once) { break }
                } elseif (-not $reason) {
                    if (-not $state) {
                        $state = @{ version = $snapshot.Version; verifiedAt = [DateTime]::UtcNow.ToString('o') }
                        $state | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding UTF8
                        Write-AutoUpdateLog $runtime ('Vencord deja present sur Discord {0}.' -f $snapshot.Version)
                    }
                    if ($Once) { break }
                }
            }
        } catch {
            Write-AutoUpdateLog $runtime ('ERREUR : ' + $_.Exception.Message)
            if ($Once) { throw }
            $retryAfter = [DateTime]::UtcNow.AddSeconds($config.retrySeconds)
            $lastSignature = ''
        }
        Start-Sleep -Seconds $config.pollSeconds
    } while ($true)
} finally {
    if ($lock) { $lock.Dispose() }
}
