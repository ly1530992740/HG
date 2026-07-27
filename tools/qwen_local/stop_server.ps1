param(
    [int]$Port = 8081
)

$ErrorActionPreference = "Stop"
$pidPath = Join-Path $PSScriptRoot "server.pid"

if (-not (Test-Path -LiteralPath $pidPath)) {
    Write-Host "No Qwen server PID file was found."
    exit 0
}

$serverPid = [int](Get-Content -LiteralPath $pidPath -Raw).Trim()
$process = Get-Process -Id $serverPid -ErrorAction SilentlyContinue
if ($null -eq $process) {
    Remove-Item -LiteralPath $pidPath -Force
    Write-Host "The recorded Qwen server process is no longer running."
    exit 0
}

if ($process.ProcessName -ne "llama-server") {
    throw "PID $serverPid belongs to $($process.ProcessName), not llama-server."
}

Stop-Process -Id $serverPid
$process.WaitForExit(5000) | Out-Null
Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
Write-Host "Stopped Qwen server on port $Port (PID $serverPid)."
