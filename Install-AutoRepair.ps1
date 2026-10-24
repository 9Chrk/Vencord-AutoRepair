#requires -Version 5.1
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'VencordAutoRepair.psm1') -Force
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'config.json'))) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'config.example.json') -Destination (Join-Path $PSScriptRoot 'config.json')
}
$config = Get-AutoRepairConfig -ProjectPath $PSScriptRoot
if (-not (Get-DiscordSnapshot -DiscordPath $config.discordPath)) {
    throw 'Installation Discord Stable complete introuvable. Verifier discordPath dans config.json, puis relancer.'
}
foreach ($required in @('System32\wscript.exe', 'System32\WindowsPowerShell\v1.0\powershell.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $env:SystemRoot $required))) { throw ('Composant Windows manquant : ' + $required) }
}
$taskName = 'Vencord AutoRepair'
$legacyTaskName = 'Vencord AutoUpdate'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$service = New-Object -ComObject 'Schedule.Service'
$service.Connect()
$folder = $service.GetFolder('\')
$task = $service.NewTask(0)
$task.RegistrationInfo.Description = 'Reapplique Vencord apres les mises a jour de Discord, puis relance Discord si necessaire.'
$task.Principal.UserId = $identity.Name
$task.Principal.LogonType = 3 # InteractiveToken; no saved password.
$task.Principal.RunLevel = 0 # Current user; never highest privileges.
$task.Settings.Enabled = $true
$task.Settings.Hidden = $true
$task.Settings.StartWhenAvailable = $true
$task.Settings.DisallowStartIfOnBatteries = $false
$task.Settings.StopIfGoingOnBatteries = $false
$task.Settings.ExecutionTimeLimit = 'PT0S'
$task.Settings.MultipleInstances = 2 # IgnoreNew
$task.Settings.RestartInterval = 'PT1M'
$task.Settings.RestartCount = 3
$trigger = $task.Triggers.Create(9) # At logon.
$trigger.UserId = $identity.Name
$trigger.Delay = 'PT15S'
$action = $task.Actions.Create(0)
$action.Path = Join-Path $env:SystemRoot 'System32\wscript.exe'
$action.Arguments = '//B //NoLogo "' + (Join-Path $PSScriptRoot 'Launch-Watcher.vbs') + '"'
$action.WorkingDirectory = $PSScriptRoot
$existing = @($folder.GetTasks(1) | Where-Object { $_.Name -in @($taskName, $legacyTaskName) })
foreach ($previous in $existing) { $previous.Enabled = $false }
& (Join-Path $PSScriptRoot 'Stop-Watcher.ps1')
foreach ($previous in $existing) { $previous.Stop(0) }
$registered = $folder.RegisterTaskDefinition($taskName, $task, 6, $identity.Name, $null, 3, $null)
$null = $registered.Run($null)
foreach ($previous in $existing) {
    if ($previous.Name -eq $legacyTaskName) { $folder.DeleteTask($previous.Name, 0) }
}
Write-Output ('Automatisation active pour {0}. Tache : {1}.' -f $identity.Name, $taskName)
