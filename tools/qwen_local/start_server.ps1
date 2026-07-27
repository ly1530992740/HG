param(
    [int]$Port = 8081,
    [int]$ContextSize = 4096,
    [int]$GpuLayers = 99,
    [int]$StartupTimeoutSeconds = 60
)

$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$runtimeDir = Join-Path $PSScriptRoot "runtime"
$serverExe = Join-Path $runtimeDir "llama-server.exe"
$modelPath = Join-Path $projectRoot "addons\Qwen3-0.6B-GGUF\Qwen3-0.6B-Q8_0.gguf"
$pidPath = Join-Path $PSScriptRoot "server.pid"
$stdoutPath = Join-Path $PSScriptRoot "server.stdout.log"
$stderrPath = Join-Path $PSScriptRoot "server.stderr.log"
$healthUrl = "http://127.0.0.1:$Port/health"

if (-not (Test-Path -LiteralPath $serverExe)) {
    throw "llama-server.exe not found: $serverExe"
}
if (-not (Test-Path -LiteralPath $modelPath)) {
    throw "GGUF model not found: $modelPath"
}

try {
    $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
    if ($health.status -eq "ok") {
        Write-Output "Qwen server is already ready at http://127.0.0.1:$Port"
        exit 0
    }
} catch {
    # No healthy server is listening yet.
}

$arguments = @(
    "--model", $modelPath,
    "--alias", "qwen3-0.6b",
    "--host", "127.0.0.1",
    "--port", $Port,
    "--ctx-size", $ContextSize,
    "--gpu-layers", $GpuLayers,
    "--flash-attn", "on",
    "--parallel", "1",
    "--jinja",
    "--reasoning", "off",
    "--no-webui"
)

$process = Start-Process `
    -FilePath $serverExe `
    -ArgumentList $arguments `
    -WorkingDirectory $runtimeDir `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath `
    -PassThru

Set-Content -LiteralPath $pidPath -Value $process.Id -Encoding ASCII

$deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
while ((Get-Date) -lt $deadline) {
    if ($process.HasExited) {
        $details = if (Test-Path -LiteralPath $stderrPath) {
            (Get-Content -LiteralPath $stderrPath -Tail 30) -join [Environment]::NewLine
        } else {
            "No error log was created."
        }
        throw "llama-server exited with code $($process.ExitCode).`n$details"
    }

    try {
        $health = Invoke-RestMethod -Uri $healthUrl -TimeoutSec 2
        if ($health.status -eq "ok") {
            $warmupBody = @{
                model = "qwen3-0.6b"
                messages = @(@{ role = "user"; content = "Reply with OK. /no_think" })
                max_tokens = 4
                temperature = 0.2
                stream = $false
            } | ConvertTo-Json -Depth 5
            Invoke-RestMethod `
                -Method Post `
                -Uri "http://127.0.0.1:$Port/v1/chat/completions" `
                -ContentType "application/json; charset=utf-8" `
                -Body $warmupBody `
                -TimeoutSec 30 | Out-Null
            Write-Output "Qwen3-0.6B is ready at http://127.0.0.1:$Port"
            Write-Output "OpenAI-compatible endpoint: http://127.0.0.1:$Port/v1/chat/completions"
            Write-Output "PID: $($process.Id)"
            exit 0
        }
    } catch {
        Start-Sleep -Milliseconds 250
    }
}

Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
throw "Qwen server did not become ready within $StartupTimeoutSeconds seconds. See $stderrPath"
