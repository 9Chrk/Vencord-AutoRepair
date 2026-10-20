Option Explicit
Dim shell, fso, folder, command, result
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
folder = fso.GetParentFolderName(WScript.ScriptFullName)
command = """" & shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"" -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & folder & "\Watch-Vencord.ps1"""
' Wait so Task Scheduler can track completion and restart on failure.
result = shell.Run(command, 0, True)
WScript.Quit result
