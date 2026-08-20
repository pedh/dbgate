# Installs a DbGate NSIS package unattended and verifies the result.
# Covers dbgate/dbgate#858: the installer must accept a custom target directory.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Installer,
    [Parameter(Mandatory = $true)][string] $TargetDir,
    [int] $TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Installer)) {
    throw "install: $Installer does not exist"
}

function Get-DbGateInstallations {
    $found = @()
    foreach ($key in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        $found += Get-ItemProperty -Path $key -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like '*DbGate*' } |
            Select-Object DisplayName, InstallLocation, UninstallString
    }
    return $found
}

function Remove-DbGateProcesses {
    $running = Get-Process -Name 'DbGate' -ErrorAction SilentlyContinue
    if ($running) {
        # the installer auto-cancels its "app is running" prompt when silent and then
        # exits 0 without installing anything
        Write-Host "install: stopping $($running.Count) leftover DbGate process(es)"
        $running | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
    }
}

Write-Host "install: $Installer -> $TargetDir"
Write-Host "install: running as $env:USERNAME, elevated=$(([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))"

Remove-DbGateProcesses

$expectedExe = Join-Path $TargetDir 'DbGate.exe'

# NSIS wants /D last and unquoted, but different launch mechanisms quote arguments
# differently, so try the documented spellings until the app appears in $TargetDir
$attempts = @(
    @{ Label = 'powershell single argument string'; Run = {
            Start-Process -FilePath $Installer -ArgumentList "/S /D=$TargetDir" -Wait -PassThru
        }
    },
    @{ Label = 'cmd.exe built command line'; Run = {
            & cmd.exe /c "`"$Installer`" /S /D=$TargetDir"
            [pscustomobject]@{ ExitCode = $LASTEXITCODE }
        }
    },
    @{ Label = 'per-user install mode'; Run = {
            Start-Process -FilePath $Installer -ArgumentList "/S /currentuser /D=$TargetDir" -Wait -PassThru
        }
    }
)

foreach ($attempt in $attempts) {
    Write-Host "install: attempt - $($attempt.Label)"
    $proc = & $attempt.Run
    Write-Host "install: exit code $($proc.ExitCode)"

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while (-not (Test-Path $expectedExe) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
    }

    if (Test-Path $expectedExe) {
        Write-Host "install: OK, installed into $TargetDir via '$($attempt.Label)'"
        Get-ChildItem -Path $TargetDir | Select-Object Name, Length | Out-Host
        exit 0
    }

    Write-Host "install: nothing in $TargetDir after this attempt"
    $installed = Get-DbGateInstallations
    if ($installed) {
        Write-Host 'install: but an installation was registered elsewhere:'
        $installed | Out-Host
    }
    Remove-DbGateProcesses
}

Write-Host 'install: no attempt installed into the requested directory'
Write-Host 'install: registered DbGate installations:'
Get-DbGateInstallations | Out-Host
foreach ($candidate in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\dbgate'),
        (Join-Path $env:LOCALAPPDATA 'Programs\DbGate'),
        (Join-Path ${env:ProgramFiles} 'DbGate'),
        'C:\DbGate')) {
    if (Test-Path $candidate) {
        Write-Host "install: found an installation in $candidate"
    }
}

throw "install: DbGate.exe never appeared in $TargetDir"
