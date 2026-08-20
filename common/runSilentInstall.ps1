# Installs a DbGate NSIS package unattended and verifies the result.
# Covers dbgate/dbgate#858: the installer must accept a custom target directory,
# including one whose path contains spaces.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Installer,
    [Parameter(Mandatory = $true)][string] $TargetDir,
    [int] $TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Installer)) {
    throw "install: $Installer does not exist"
}

Write-Host "install: $Installer -> $TargetDir"

# The installer auto-cancels its "app is running" prompt when silent and then exits 0
# without installing anything, so no leftover process may be around.
$running = Get-Process -Name 'DbGate' -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "install: stopping $($running.Count) leftover DbGate process(es)"
    $running | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
}

# NSIS requires /D to be last and unquoted; passing the whole command line as one string
# keeps it that way even when the path contains spaces
$proc = Start-Process -FilePath $Installer -ArgumentList "/S /D=$TargetDir" -Wait -PassThru
Write-Host "install: installer exit code $($proc.ExitCode)"

$nsisLog = Join-Path $env:TEMP 'dbgate-nsis-init.log'
if (Test-Path $nsisLog) {
    Write-Host "--- $nsisLog ---"
    Get-Content $nsisLog | Out-Host
}
else {
    Write-Host "install: $nsisLog was not written, the custom NSIS include did not run"
}

$expectedExe = Join-Path $TargetDir 'DbGate.exe'
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)

# the installer can relaunch itself, so the first process may return before it finished
while (-not (Test-Path $expectedExe) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
}

if (-not (Test-Path $expectedExe)) {
    Write-Host 'install: registered DbGate installations:'
    foreach ($key in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        Get-ItemProperty -Path $key -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like '*DbGate*' } |
            Select-Object DisplayName, InstallLocation | Out-Host
    }
    # a truncated target directory means /D lost everything after the first space
    foreach ($candidate in @($TargetDir.Split(' ')[0], (Join-Path $env:LOCALAPPDATA 'Programs\dbgate'))) {
        if (Test-Path $candidate) {
            Write-Host "install: found an installation in $candidate"
        }
    }
    throw "install: DbGate.exe did not appear in $TargetDir within $TimeoutSeconds s"
}

if ($proc.ExitCode -ne 0) {
    throw "install: installer exited with $($proc.ExitCode)"
}

Write-Host "install: OK, installed into $TargetDir"
Get-ChildItem -Path $TargetDir | Select-Object Name, Length | Out-Host
