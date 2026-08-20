# Installs a DbGate NSIS package unattended into a given directory and verifies the
# result. Covers dbgate/dbgate#858: the installer must accept a custom target directory.
#
# The NSIS installer can relaunch itself (eg. to elevate) and the first process then
# returns before the installation finished, so waiting for the exit code alone is not
# enough - the expected files are polled instead.

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

# NSIS requires /D to be the last argument and to be passed unquoted, even when the path
# contains spaces, so let cmd.exe assemble the command line
& cmd.exe /c "`"$Installer`" /S /D=$TargetDir"
$installerExitCode = $LASTEXITCODE

$expectedExe = Join-Path $TargetDir 'DbGate.exe'
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

while (-not (Test-Path $expectedExe) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
}

if (-not (Test-Path $expectedExe)) {
    Write-Host "install: installer exit code $installerExitCode"
    Write-Host 'install: still running installer processes:'
    Get-Process | Where-Object { $_.ProcessName -like '*dbgate*' } | Select-Object Id, ProcessName | Out-Host
    Write-Host "install: content of $TargetDir :"
    if (Test-Path $TargetDir) {
        Get-ChildItem -Path $TargetDir | Select-Object Name | Out-Host
    }
    else {
        Write-Host 'install: target directory was not created'
    }
    Write-Host 'install: default install locations, to see whether /D was ignored:'
    foreach ($candidate in @(
            (Join-Path $env:LOCALAPPDATA 'Programs\dbgate'),
            (Join-Path $env:LOCALAPPDATA 'Programs\DbGate'),
            (Join-Path ${env:ProgramFiles} 'DbGate'))) {
        if (Test-Path $candidate) {
            Write-Host "install: found an installation in $candidate"
        }
    }
    throw "install: DbGate.exe did not appear in $TargetDir within $TimeoutSeconds s"
}

# wait until the installer released the files it is still writing
while ((Get-Process | Where-Object { $_.ProcessName -like '*dbgate*' -and $_.ProcessName -like '*setup*' }) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
}

Write-Host "install: OK, installed into $TargetDir"
Get-ChildItem -Path $TargetDir | Select-Object Name, Length | Out-Host
