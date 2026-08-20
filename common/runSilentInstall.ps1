# Installs a DbGate NSIS package unattended into a given directory and verifies the
# result. Covers dbgate/dbgate#858: the installer must accept a custom target directory.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Installer,
    [Parameter(Mandatory = $true)][string] $TargetDir,
    [int] $TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Installer)) {
    throw "install: $Installer does not exist"
}

Write-Host "install: $Installer -> $TargetDir"

# NSIS requires /D to be the last argument and to be passed *unquoted* even when the path
# contains spaces. Passing a single pre-built string to -ArgumentList hands the command
# line over verbatim, whereas separate arguments would be quoted and /D silently ignored.
$proc = Start-Process -FilePath $Installer -ArgumentList "/S /D=$TargetDir" -Wait -PassThru
Write-Host "install: installer exit code $($proc.ExitCode)"

$expectedExe = Join-Path $TargetDir 'DbGate.exe'
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

# the installer can relaunch itself and the first process then returns early
while (-not (Test-Path $expectedExe) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
}

if (-not (Test-Path $expectedExe)) {
    Write-Host "install: content of $TargetDir :"
    if (Test-Path $TargetDir) {
        Get-ChildItem -Path $TargetDir -Recurse -Depth 1 | Select-Object FullName | Out-Host
    }
    else {
        Write-Host 'install: target directory was not created'
    }

    Write-Host 'install: searching for an installation elsewhere, to see whether /D was ignored:'
    foreach ($root in @($env:LOCALAPPDATA, $env:APPDATA, ${env:ProgramFiles}, ${env:ProgramFiles(x86)}, 'C:\')) {
        if (-not $root) { continue }
        Get-ChildItem -Path $root -Filter 'DbGate.exe' -Recurse -Depth 4 -ErrorAction SilentlyContinue |
            Select-Object -First 5 FullName | Out-Host
    }

    Write-Host 'install: uninstall registry entries mentioning DbGate:'
    foreach ($key in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        Get-ItemProperty -Path $key -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like '*DbGate*' } |
            Select-Object DisplayName, InstallLocation | Out-Host
    }

    throw "install: DbGate.exe did not appear in $TargetDir within $TimeoutSeconds s"
}

if ($proc.ExitCode -ne 0) {
    throw "install: installer exited with $($proc.ExitCode)"
}

Write-Host "install: OK, installed into $TargetDir"
Get-ChildItem -Path $TargetDir | Select-Object Name, Length | Out-Host
