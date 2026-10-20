#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$service = New-Object -ComObject 'Schedule.Service'
$service.Connect()
$folder = $service.GetFolder('\')
$tasks = @($folder.GetTasks(1) | Where-Object Name -eq 'Vencord AutoUpdate')
foreach ($task in $tasks) { $task.Enabled = $false }
& (Join-Path $PSScriptRoot 'Stop-Watcher.ps1')
foreach ($task in $tasks) { $task.Stop(0); $folder.DeleteTask($task.Name, 0) }
Write-Output 'Surveillance supprimee. Les fichiers Discord et Vencord sont conserves.'
