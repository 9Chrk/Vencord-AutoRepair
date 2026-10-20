Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AutoUpdateConfig {
    param([Parameter(Mandatory)][string]$ProjectPath)
    $configPath = Join-Path $ProjectPath 'config.json'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        $configPath = Join-Path $ProjectPath 'config.example.json'
    }
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($key in @('discordPath', 'pollSeconds', 'settleSeconds', 'retrySeconds', 'restartDiscord')) {
        if ($config.PSObject.Properties.Name -notcontains $key) { throw ('Parametre manquant : ' + $key) }
    }
    if ($config.discordPath -isnot [string] -or [string]::IsNullOrWhiteSpace($config.discordPath)) {
        throw 'discordPath doit contenir le chemin du dossier Discord.'
    }
    $discordPath = [Environment]::ExpandEnvironmentVariables($config.discordPath)
    if ($discordPath -match '%[^%]+%' -or $discordPath -notmatch '^[a-zA-Z]:[\\/]' -or
        $discordPath.IndexOfAny([IO.Path]::GetInvalidPathChars()) -ge 0 -or $discordPath.Contains('"')) {
        throw 'discordPath doit etre un chemin Windows local absolu, sans variable inconnue.'
    }
    $config.discordPath = [IO.Path]::GetFullPath($discordPath).TrimEnd('\')
    if ((Split-Path $config.discordPath -Leaf) -match '^app-') {
        throw 'discordPath doit viser le dossier Discord parent, sans app-<version>.'
    }
    $limits = @{ pollSeconds = @(1, 60); settleSeconds = @(5, 300); retrySeconds = @(10, 3600) }
    foreach ($key in $limits.Keys) {
        $value = $config.$key
        if (($value -isnot [int] -and $value -isnot [long]) -or
            $value -lt $limits[$key][0] -or $value -gt $limits[$key][1]) {
            throw ('{0} doit etre un entier entre {1} et {2}.' -f $key, $limits[$key][0], $limits[$key][1])
        }
    }
    if ($config.restartDiscord -isnot [bool]) { throw 'restartDiscord doit valoir true ou false, sans guillemets.' }
    return $config
}

function Get-DiscordSnapshot {
    param([Parameter(Mandatory)][string]$DiscordPath)
    if (-not (Test-Path -LiteralPath $DiscordPath -PathType Container)) { return $null }
    $versions = @(Get-ChildItem -LiteralPath $DiscordPath -Directory | Where-Object {
        $_.Name -match '^app-\d+\.\d+\.\d+(\.\d+)?$'
    })
    if ($versions.Count -eq 0) { return $null }
    $latest = $versions | Sort-Object { [version]$_.Name.Substring(4) } -Descending | Select-Object -First 1
    # The official installer currently selects its target lexicographically.
    $officialTarget = $versions | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.FullName 'resources') -PathType Container
    } | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $officialTarget -or $latest.Name -ne $officialTarget.Name) { return $null }
    $resources = Join-Path $latest.FullName 'resources'
    $exe = Join-Path $latest.FullName 'Discord.exe'
    $asar = Join-Path $resources 'app.asar'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf) -or
        -not (Test-Path -LiteralPath $asar -PathType Leaf)) { return $null }
    $parts = @($latest.Name)
    foreach ($file in @($exe, $asar, (Join-Path $resources '_app.asar'),
        (Join-Path $DiscordPath 'installer.db'), (Join-Path $DiscordPath 'SquirrelSetup.log'))) {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            $item = Get-Item -LiteralPath $file
            $parts += '{0}:{1}:{2}' -f $item.Name, $item.Length, $item.LastWriteTimeUtc.Ticks
        }
    }
    [pscustomobject]@{
        Version = $latest.Name.Substring(4)
        Directory = $latest.FullName
        Resources = $resources
        Signature = $parts -join '|'
    }
}

function Test-VencordPatch {
    param([Parameter(Mandatory)]$Snapshot, [Parameter(Mandatory)][string]$VencordPath)
    $asar = Join-Path $Snapshot.Resources 'app.asar'
    if (-not (Test-Path -LiteralPath (Join-Path $Snapshot.Resources '_app.asar') -PathType Leaf)) { return $false }
    if (-not (Test-Path -LiteralPath $asar -PathType Leaf)) { return $false }
    # An official Vencord loader is a tiny ASAR containing the path to patcher.js.
    $size = (Get-Item -LiteralPath $asar).Length
    if ($size -eq 0 -or $size -gt 65536) { return $false }
    $loader = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($asar))
    $patcher = Join-Path $VencordPath 'dist\patcher.js'
    if ($loader -notmatch 'require\(("(?:\\.|[^"\\])*")\)') { return $false }
    try { $referencedPatcher = ConvertFrom-Json -InputObject $Matches[1] }
    catch { return $false }
    # Compare decoded paths: Go and PowerShell can escape apostrophes differently.
    if ($referencedPatcher -ine $patcher) { return $false }
    foreach ($name in @('patcher.js', 'preload.js', 'renderer.js', 'renderer.css')) {
        $file = Join-Path $VencordPath ('dist\' + $name)
        if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Length -eq 0) {
            return $false
        }
    }
    return $true
}

function Get-DiscordProcesses {
    param([Parameter(Mandatory)][string]$DiscordPath)
    $prefix = [IO.Path]::GetFullPath($DiscordPath).TrimEnd('\') + '\'
    foreach ($process in @(Get-Process -Name Discord -ErrorAction SilentlyContinue)) {
        if ($process.HasExited) { continue }
        $exe = $process.Path
        if (-not $exe) {
            # Chromium children can exit between enumeration and reading their path.
            $process.Refresh()
            if ($process.HasExited) { continue }
            throw ('Impossible de verifier le chemin du processus Discord {0}. Nouvelle tentative plus tard.' -f $process.Id)
        }
        if ($exe.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { $process }
    }
}

function Test-DiscordUpdaterBusy {
    param([Parameter(Mandatory)][string]$DiscordPath)
    $prefix = [IO.Path]::GetFullPath($DiscordPath).TrimEnd('\') + '\'
    foreach ($process in @(Get-Process -Name Update, updater_launcher -ErrorAction SilentlyContinue)) {
        if (-not $process.Path -or $process.Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Write-AutoUpdateLog {
    param([Parameter(Mandatory)][string]$RuntimePath, [Parameter(Mandatory)][string]$Message)
    $log = Join-Path $RuntimePath 'watcher.log'
    if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 2097152) {
        Move-Item -LiteralPath $log -Destination ($log + '.previous') -Force
    }
    Add-Content -LiteralPath $log -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
}

function Get-OfficialInstaller {
    param([Parameter(Mandatory)][string]$RuntimePath)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/Vencord/Installer/releases/latest' `
        -Headers @{ 'User-Agent' = 'VencordAutoUpdate' } -TimeoutSec 30
    $assets = @($release.assets | Where-Object name -eq 'VencordInstallerCli.exe')
    if ($assets.Count -ne 1) { throw 'Installateur CLI officiel introuvable.' }
    $asset = $assets[0]
    if ($asset.digest -notmatch '^sha256:([a-fA-F0-9]{64})$') { throw 'Empreinte SHA256 officielle absente.' }
    $expectedHash = $Matches[1]
    if (-not $asset.browser_download_url.StartsWith('https://github.com/Vencord/Installer/releases/download/', [StringComparison]::Ordinal)) {
        throw 'URL inattendue pour l installateur officiel.'
    }
    $installer = Join-Path $RuntimePath 'VencordInstallerCli.exe'
    if ((Test-Path -LiteralPath $installer) -and (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash -eq $expectedHash) {
        return $installer
    }
    $download = $installer + '.download'
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $download -TimeoutSec 120
        if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne $expectedHash) { throw 'Empreinte SHA256 incorrecte.' }
        Move-Item -LiteralPath $download -Destination $installer -Force
    } finally {
        if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -Force }
    }
    return $installer
}

function Invoke-VencordRepair {
    param([Parameter(Mandatory)][string]$DiscordPath, [Parameter(Mandatory)][string]$VencordPath,
        [Parameter(Mandatory)][string]$RuntimePath, [Parameter(Mandatory)]$Snapshot,
        [bool]$RestartDiscord = $true)
    # Fetch/verify the installer BEFORE closing Discord. Offline failures leave it running.
    $installer = Get-OfficialInstaller -RuntimePath $RuntimePath
    $current = Get-DiscordSnapshot -DiscordPath $DiscordPath
    if (-not $current -or $current.Signature -ne $Snapshot.Signature -or (Test-DiscordUpdaterBusy $DiscordPath)) {
        throw 'Discord est encore en cours de mise a jour. Reparation differee.'
    }
    $running = @(Get-DiscordProcesses -DiscordPath $DiscordPath)
    if ($running.Count -gt 0 -and -not $RestartDiscord) { throw 'Discord est ouvert. Reparation reportee a sa fermeture.' }
    $wasRunning = $running.Count -gt 0
    $success = $false
    $process = $null
    $stdout = Join-Path $RuntimePath 'installer.stdout.log'
    $stderr = Join-Path $RuntimePath 'installer.stderr.log'
    Write-AutoUpdateLog $RuntimePath ('Reparation de Discord {0}; relance={1}.' -f $Snapshot.Version, $wasRunning)
    try {
        # Only stop processes belonging to this Discord installation.
        foreach ($discord in $running) { Stop-Process -Id $discord.Id -Force -ErrorAction SilentlyContinue }
        $deadline = [DateTime]::UtcNow.AddSeconds(20)
        while (@(Get-DiscordProcesses $DiscordPath).Count -gt 0) {
            if ([DateTime]::UtcNow -ge $deadline) { throw 'Discord ne se ferme pas.' }
            Start-Sleep -Milliseconds 500
        }
        # Do not patch if an updater appeared while Discord was closing.
        $current = Get-DiscordSnapshot $DiscordPath
        if (-not $current -or $current.Signature -ne $Snapshot.Signature -or (Test-DiscordUpdaterBusy $DiscordPath)) {
            throw 'Mise a jour de Discord detectee pendant sa fermeture.'
        }
        $process = Start-Process -FilePath $installer -ArgumentList ('--repair --location "{0}"' -f $DiscordPath) `
            -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        # Windows PowerShell needs a retained handle to expose ExitCode reliably.
        $null = $process.Handle
        if (-not $process.WaitForExit(180000)) { throw 'Delai de reparation depasse (3 minutes).' }
        $output = (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue) +
            (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)
        if ($process.ExitCode -ne 0 -or $output -notmatch 'Successfully patched') {
            throw ('Echec de l installateur (code {0}); voir installer.stdout.log et installer.stderr.log.' -f $process.ExitCode)
        }
        $after = Get-DiscordSnapshot $DiscordPath
        if (-not $after -or $after.Version -ne $Snapshot.Version -or -not (Test-VencordPatch $after $VencordPath)) {
            throw 'La verification des fichiers Vencord apres reparation a echoue.'
        }
        $success = $true
        return $after
    } finally {
        if ($process -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        # On failure, restart only if the resulting install still passes verification.
        if ($wasRunning -and $RestartDiscord) {
            $restartTarget = Get-DiscordSnapshot $DiscordPath
            if ($restartTarget -and ($success -or -not $process -or (Test-VencordPatch $restartTarget $VencordPath))) {
                Start-Process -FilePath (Join-Path $restartTarget.Directory 'Discord.exe') `
                    -WorkingDirectory $restartTarget.Directory -WindowStyle Normal | Out-Null
                Write-AutoUpdateLog $RuntimePath 'Discord relance.'
            } else {
                Write-AutoUpdateLog $RuntimePath 'Reparation incomplete : Discord reste ferme; consulter les journaux.'
            }
        }
    }
}

function Get-RepairReason {
    param([Parameter(Mandatory)]$Snapshot, [AllowNull()]$State, [bool]$Patched)
    if (-not $Patched) { return 'Vencord absent ou incomplet' }
    if ($State -and $State.version -ne $Snapshot.Version) { return 'Nouvelle version de Discord' }
    return $null
}

Export-ModuleMember -Function Get-AutoUpdateConfig, Get-DiscordSnapshot, Test-VencordPatch, Get-DiscordProcesses,
    Test-DiscordUpdaterBusy, Write-AutoUpdateLog, Get-OfficialInstaller, Invoke-VencordRepair, Get-RepairReason
