# Starts a packaged DbGate build in smoke test mode and verifies it came up.
#
# A packaged Windows Electron app is a GUI binary: it detaches from the console and
# writes nothing to stdout, so the result is passed through a JSON file instead.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Exe,
    [Parameter(Mandatory = $true)][string] $Label,
    [int] $TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Exe)) {
    throw "smoke test: $Exe does not exist"
}

$resultFile = Join-Path $env:RUNNER_TEMP "smoke-$Label.json"
$logFile = Join-Path $env:RUNNER_TEMP "smoke-$Label.log"
$workspaceDir = Join-Path $env:RUNNER_TEMP "dbgate-smoke-$Label"

Remove-Item -Path $resultFile -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $workspaceDir | Out-Null

$env:DBGATE_SMOKE_TEST = '1'
$env:DBGATE_SMOKE_TEST_RESULT = $resultFile
$env:DBGATE_SMOKE_TEST_TIMEOUT = ($TimeoutSeconds * 1000).ToString()
# keep the smoke run away from any real user data
$env:WORKSPACE_DIR = $workspaceDir

Write-Host "smoke test: starting $Exe"
$proc = Start-Process -FilePath $Exe -PassThru -RedirectStandardOutput $logFile -RedirectStandardError "$logFile.err"

if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    $proc.Kill()
    throw "smoke test: app did not exit within $TimeoutSeconds s"
}

foreach ($file in @($logFile, "$logFile.err")) {
    if ((Test-Path $file) -and (Get-Item $file).Length -gt 0) {
        Write-Host "--- $file ---"
        Get-Content $file | Out-Host
    }
}

# the API forks helper processes that can outlive the main process
$leftover = Get-Process -Name 'DbGate' -ErrorAction SilentlyContinue
if ($leftover) {
    Write-Host "smoke test: stopping $($leftover.Count) leftover process(es)"
    $leftover | Stop-Process -Force -ErrorAction SilentlyContinue
}

if (-not (Test-Path $resultFile)) {
    throw "smoke test: no result file written, app exited with $($proc.ExitCode)"
}

$result = Get-Content $resultFile -Raw | ConvertFrom-Json

if (-not $result.ok) {
    throw "smoke test: failed - $($result.error)"
}

if ($result.plugins.Count -lt 1) {
    throw 'smoke test: app started but loaded no plugin backend'
}

if ($proc.ExitCode -ne 0) {
    throw "smoke test: app exited with $($proc.ExitCode)"
}

Write-Host "smoke test: OK, app started and loaded $($result.plugins.Count) plugin backends"
Write-Host "smoke test: plugins - $($result.plugins -join ', ')"
