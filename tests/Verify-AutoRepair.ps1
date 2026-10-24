#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $root 'VencordAutoRepair.psm1') -Force
$fixture = Join-Path $PSScriptRoot ('.tmp\' + [guid]::NewGuid().ToString('N'))
$discordRoot = Join-Path $fixture 'Discord'
$vencordRoot = Join-Path $fixture "Vencord test user's"
$runtime = Join-Path $fixture 'runtime'
$script:passed = 0
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw ('ECHEC : ' + $Message) }
    $script:passed++
    Write-Output ('OK : ' + $Message)
}
function Add-FixtureVersion([string]$Version, [switch]$Incomplete) {
    $dir = Join-Path $discordRoot ('app-' + $Version)
    New-Item -ItemType Directory -Path (Join-Path $dir 'resources') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'Discord.exe'), 'fixture')
    if (-not $Incomplete) { [IO.File]::WriteAllText((Join-Path $dir 'resources\app.asar'), 'original Discord') }
}
function Add-FixturePatch($Snapshot) {
    [IO.File]::WriteAllText((Join-Path $Snapshot.Resources '_app.asar'), 'original Discord')
    $loader = 'require(' + (ConvertTo-Json -InputObject (Join-Path $vencordRoot 'dist\patcher.js') -Compress) + ')'
    [IO.File]::WriteAllText((Join-Path $Snapshot.Resources 'app.asar'), $loader)
}
try {
    New-Item -ItemType Directory -Path $runtime, (Join-Path $vencordRoot 'dist') -Force | Out-Null
    foreach ($file in @('patcher.js', 'preload.js', 'renderer.js', 'renderer.css')) {
        [IO.File]::WriteAllText((Join-Path $vencordRoot ('dist\' + $file)), 'fixture')
    }
    $configRoot = Join-Path $fixture 'Configuration'
    New-Item -ItemType Directory -Path $configRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $root 'config.example.json') -Destination (Join-Path $configRoot 'config.example.json')
    $config = Get-AutoRepairConfig $configRoot
    Assert-True ($config.discordPath -eq (Join-Path $env:LOCALAPPDATA 'Discord')) 'Configuration generique : chemin de la session Windows'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $configRoot 'config.json'))) 'Lecture des valeurs par defaut sans creer de configuration locale'
    $config.discordPath = Join-Path $fixture 'Discord custom'
    $config.restartDiscord = $false
    $config | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $configRoot 'config.json') -Encoding UTF8
    $loaded = Get-AutoRepairConfig $configRoot
    Assert-True ($loaded.discordPath -eq $config.discordPath -and -not $loaded.restartDiscord) 'La configuration locale et le choix sans redemarrage sont respectes'
    $badConfigs = @(
        @{ Key = 'pollSeconds'; Value = 0 },
        @{ Key = 'pollSeconds'; Value = 61 },
        @{ Key = 'pollSeconds'; Value = '15' },
        @{ Key = 'settleSeconds'; Value = 0 },
        @{ Key = 'retrySeconds'; Value = -1 },
        @{ Key = 'restartDiscord'; Value = 'false' },
        @{ Key = 'discordPath'; Value = '' },
        @{ Key = 'discordPath'; Value = '.\Discord' },
        @{ Key = 'discordPath'; Value = '%VENCORD_TEST_UNKNOWN_ENV_VARIABLE%\Discord' },
        @{ Key = 'discordPath'; Value = 'C:\Discord\app-1.0.1' },
        @{ Key = 'discordPath'; Value = 'C:\Discord" --uninstall' }
    )
    foreach ($invalid in $badConfigs) {
        $copy = $config | ConvertTo-Json | ConvertFrom-Json
        $copy.($invalid.Key) = $invalid.Value
        $copy | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $configRoot 'config.json') -Encoding UTF8
        $rejected = $false
        try { $null = Get-AutoRepairConfig $configRoot } catch { $rejected = $true }
        Assert-True $rejected ('Configuration invalide refusee : ' + $invalid.Key + '=' + $invalid.Value)
    }
    [IO.File]::WriteAllText((Join-Path $configRoot 'config.json'), '{}')
    $rejected = $false
    try { $null = Get-AutoRepairConfig $configRoot } catch { $rejected = $true }
    Assert-True $rejected 'Configuration incomplete refusee'
    Assert-True ($null -eq (Get-DiscordSnapshot $discordRoot)) 'Discord absent : aucune action'
    Add-FixtureVersion '1.0.9'
    Add-FixtureVersion '1.0.10'
    Assert-True ($null -eq (Get-DiscordSnapshot $discordRoot)) 'Desaccord de tri avec le CLI : aucun mauvais ciblage'
    # Remove only the small, known fixture file/directory; never a user installation.
    Remove-Item -LiteralPath (Join-Path $discordRoot 'app-1.0.9\resources\app.asar')
    Remove-Item -LiteralPath (Join-Path $discordRoot 'app-1.0.9\resources')
    Remove-Item -LiteralPath (Join-Path $discordRoot 'app-1.0.9\Discord.exe')
    Remove-Item -LiteralPath (Join-Path $discordRoot 'app-1.0.9')
    $snapshot = Get-DiscordSnapshot $discordRoot
    Assert-True ($snapshot.Version -eq '1.0.10') 'Selection de la derniere version complete'
    Assert-True (-not (Test-VencordPatch $snapshot $vencordRoot)) 'Installation non patchee detectee'
    Add-FixturePatch $snapshot
    Assert-True (Test-VencordPatch $snapshot $vencordRoot) 'Chargeur Vencord et fichiers verifies'
    $loaderPath = (ConvertTo-Json -InputObject (Join-Path $vencordRoot 'dist\patcher.js') -Compress).Replace('\u0027', "'")
    [IO.File]::WriteAllText((Join-Path $snapshot.Resources 'app.asar'), ('require(' + $loaderPath + ')'))
    Assert-True (Test-VencordPatch $snapshot $vencordRoot) 'Chemin avec espaces et apostrophe : echappement du CLI accepte'
    [IO.File]::WriteAllText((Join-Path $snapshot.Resources 'app.asar'), 'require("C:\\other\\patcher.js")')
    Assert-True (-not (Test-VencordPatch $snapshot $vencordRoot)) 'Chargeur pointant vers un autre Vencord refuse'
    [IO.File]::WriteAllText((Join-Path $snapshot.Resources 'app.asar'), 'another loader')
    Assert-True (-not (Test-VencordPatch $snapshot $vencordRoot)) 'Une sauvegarde seule ne prouve pas le patch'
    Add-FixturePatch $snapshot
    [IO.File]::WriteAllText((Join-Path $vencordRoot 'dist\renderer.js'), '')
    Assert-True (-not (Test-VencordPatch $snapshot $vencordRoot)) 'Telechargement Vencord incomplet detecte'
    [IO.File]::WriteAllText((Join-Path $vencordRoot 'dist\renderer.js'), 'fixture')
    Assert-True ($null -eq (Get-RepairReason $snapshot $null $true)) 'Premier lancement deja patche : pas de redemarrage inutile'
    Assert-True ($null -ne (Get-RepairReason $snapshot @{ version = '1.0.8' } $true)) 'Changement de version : reparation demandee'
    Assert-True ($null -ne (Get-RepairReason $snapshot @{ version = '1.0.10' } $false)) 'Patch ecrase a version identique : reparation demandee'
    Assert-True ($null -eq (Get-RepairReason $snapshot @{ version = '1.0.10' } $true)) 'Version inchangee et saine : aucune action'
    $before = (Get-DiscordSnapshot $discordRoot).Signature
    [IO.File]::WriteAllText((Join-Path $discordRoot 'installer.db'), 'updating')
    Assert-True ($before -ne (Get-DiscordSnapshot $discordRoot).Signature) 'Activite de mise a jour invalide la stabilite'
    Add-FixtureVersion '1.0.11' -Incomplete
    Assert-True ($null -eq (Get-DiscordSnapshot $discordRoot)) 'Version recente incomplete : ne pas reparer la precedente'
    [IO.File]::WriteAllText((Join-Path $discordRoot 'app-1.0.11\resources\app.asar'), 'original Discord')
    $snapshot = Get-DiscordSnapshot $discordRoot

    $module = Get-Module VencordAutoRepair
    $exitedCount = & $module {
        function script:Get-Process {
            param($Name, $ErrorAction)
            [pscustomobject]@{ HasExited = $true; Path = $null; Id = 123 }
        }
        @(Get-DiscordProcesses 'C:\fixture\Discord').Count
    }
    Assert-True ($exitedCount -eq 0) 'Processus deja termine : ignore sans erreur de chemin'
    $exitedCount = & $module {
        function script:Get-Process {
            param($Name, $ErrorAction)
            $fake = [pscustomobject]@{ HasExited = $false; Path = $null; Id = 123 }
            $fake | Add-Member ScriptMethod Refresh { $this.HasExited = $true }
            return $fake
        }
        @(Get-DiscordProcesses 'C:\fixture\Discord').Count
    }
    Assert-True ($exitedCount -eq 0) 'Processus termine pendant la detection : ignore apres rafraichissement'
    Remove-Module VencordAutoRepair
    Import-Module (Join-Path $root 'VencordAutoRepair.psm1') -Force

    # Exercise repair verification without ever launching an installer or stopping Discord.
    $module = Get-Module VencordAutoRepair
    & $module {
        function script:Get-OfficialInstaller { param($RuntimePath); return 'FAKE-NOT-EXECUTED.exe' }
        function script:Get-DiscordProcesses { param($DiscordPath); return @() }
        function script:Test-DiscordUpdaterBusy { param($DiscordPath); return $false }
        function script:Start-Process {
            param($FilePath, $ArgumentList, $WindowStyle, [switch]$PassThru, $RedirectStandardOutput, $RedirectStandardError)
            [IO.File]::WriteAllText($RedirectStandardOutput, 'Success!')
            $fake = [pscustomobject]@{ ExitCode = 0; HasExited = $true; Handle = 1 }
            $fake | Add-Member ScriptMethod WaitForExit { param($Timeout); return $true }
            $fake | Add-Member ScriptMethod Refresh { }
            return $fake
        }
    }
    $rejected = $false
    try { $null = Invoke-VencordRepair $discordRoot $vencordRoot $runtime $snapshot }
    catch { if ($_.Exception.Message -notlike 'Echec de l installateur*') { throw }; $rejected = $true }
    Assert-True $rejected 'Un code retour zero sans patch effectif est rejete'
    & $module {
        function script:Start-Process {
            param($FilePath, $ArgumentList, $WindowStyle, [switch]$PassThru, $RedirectStandardOutput, $RedirectStandardError)
            [IO.File]::WriteAllText($RedirectStandardOutput, 'Success!')
            [IO.File]::WriteAllText($RedirectStandardError, 'INFO Successfully patched')
            $fake = [pscustomobject]@{ ExitCode = 0; HasExited = $true; Handle = 1 }
            $fake | Add-Member ScriptMethod WaitForExit { param($Timeout); return $true }
            $fake | Add-Member ScriptMethod Refresh { }
            return $fake
        }
    }
    $rejected = $false
    try { $null = Invoke-VencordRepair $discordRoot $vencordRoot $runtime $snapshot }
    catch { if ($_.Exception.Message -notlike 'La verification des fichiers*') { throw }; $rejected = $true }
    Assert-True $rejected 'Un message de succes sans fichiers valides est rejete'
    Add-FixturePatch $snapshot
    $snapshot = Get-DiscordSnapshot $discordRoot
    $verified = Invoke-VencordRepair $discordRoot $vencordRoot $runtime $snapshot
    Assert-True ($verified.Version -eq '1.0.11') 'Reparation valide reconnue sans toucher au vrai Discord'
    [IO.File]::AppendAllText((Join-Path $discordRoot 'installer.db'), '-busy')
    $rejected = $false
    try { $null = Invoke-VencordRepair $discordRoot $vencordRoot $runtime $snapshot }
    catch { $rejected = $_.Exception.Message -like 'Discord est encore*' }
    Assert-True $rejected 'Mise a jour apparue pendant le telechargement : reparation differee'
    $snapshot = Get-DiscordSnapshot $discordRoot
    & $module { function script:Test-DiscordUpdaterBusy { param($DiscordPath); return $true } }
    $rejected = $false
    try { $null = Invoke-VencordRepair $discordRoot $vencordRoot $runtime $snapshot }
    catch { $rejected = $_.Exception.Message -like 'Discord est encore*' }
    Assert-True $rejected 'Processus de mise a jour actif : aucune reparation'
    Write-Output ('{0} controles reussis.' -f $script:passed)
} finally {
    Remove-Module VencordAutoRepair -ErrorAction SilentlyContinue
    # Resolve and constrain the target before recursive cleanup, in this PowerShell only.
    $allowed = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.tmp')).TrimEnd('\') + '\'
    $target = [IO.Path]::GetFullPath($fixture)
    if ($target.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $target)) {
        Remove-Item -LiteralPath $target -Recurse -Force
    }
}
