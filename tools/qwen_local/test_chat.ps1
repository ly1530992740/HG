param(
    [string]$BaseUrl = "http://127.0.0.1:8081",
    [switch]$Interactive
)

$ErrorActionPreference = "Stop"

function ConvertFrom-UnicodeEscape {
    param([string]$Text)
    return [Text.RegularExpressions.Regex]::Unescape($Text)
}

function Invoke-QwenChat {
    param(
        [array]$Messages,
        [int]$MaxTokens = 96
    )

    $body = @{
        model = "qwen3-0.6b"
        messages = $Messages
        max_tokens = $MaxTokens
        temperature = 0.2
        top_p = 0.8
        presence_penalty = 1.5
        stream = $false
    } | ConvertTo-Json -Depth 8

    $timer = [Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/v1/chat/completions" `
        -ContentType "application/json; charset=utf-8" `
        -Body $body `
        -TimeoutSec 30
    $timer.Stop()

    return [PSCustomObject]@{
        Text = $response.choices[0].message.content.Trim()
        ElapsedMs = $timer.ElapsedMilliseconds
        PromptTokens = $response.usage.prompt_tokens
        CompletionTokens = $response.usage.completion_tokens
    }
}

$health = Invoke-RestMethod -Uri "$BaseUrl/health" -TimeoutSec 3
if ($health.status -ne "ok") {
    throw "Qwen server is not ready at $BaseUrl"
}

$systemPrompt = ConvertFrom-UnicodeEscape "\u4f60\u662f\u4e00\u4e2a\u7b80\u6d01\u3001\u53ef\u9760\u7684\u4e2d\u6587\u6e38\u620fAI\u52a9\u624b\u3002\u4e0d\u8981\u5c55\u793a\u601d\u7ef4\u8fc7\u7a0b\uff0c\u53ea\u7ed9\u51fa\u6700\u7ec8\u7b54\u6848\u3002"
$firstPrompt = ConvertFrom-UnicodeEscape "\u8bf7\u7528\u4e00\u53e5\u4e2d\u6587\u4ecb\u7ecd\u4f60\u81ea\u5df1\uff0c\u5e76\u8bb0\u4f4f\u6211\u7684\u4ee3\u53f7\u662f\u84dd\u72d0\u3002 /no_think"
$secondPrompt = ConvertFrom-UnicodeEscape "\u6211\u521a\u624d\u8bf4\u7684\u4ee3\u53f7\u662f\u4ec0\u4e48\uff1f\u53ea\u56de\u7b54\u4ee3\u53f7\u3002 /no_think"
$expectedCodeName = ConvertFrom-UnicodeEscape "\u84dd\u72d0"

if ($Interactive) {
    $messages = @(@{ role = "system"; content = $systemPrompt })
    Write-Host "Interactive Qwen chat. Type /exit to quit."
    Write-Host "Add /think to a question when deeper reasoning is required.`n"

    while ($true) {
        $prompt = Read-Host "You"
        if ($prompt -eq "/exit") {
            break
        }
        if ([string]::IsNullOrWhiteSpace($prompt)) {
            continue
        }
        if ($prompt -notmatch "/(no_)?think") {
            $prompt += " /no_think"
        }

        $messages += @{ role = "user"; content = $prompt }
        $turn = Invoke-QwenChat -Messages $messages -MaxTokens 256
        Write-Host "Qwen ($($turn.ElapsedMs) ms):"
        Write-Host "$($turn.Text)`n"
        $messages += @{ role = "assistant"; content = $turn.Text }

        if ($messages.Count -gt 21) {
            $messages = @($messages[0]) + @($messages[($messages.Count - 20)..($messages.Count - 1)])
        }
    }

    exit 0
}

$messages = @(
    @{ role = "system"; content = $systemPrompt },
    @{ role = "user"; content = $firstPrompt }
)

$turn1 = Invoke-QwenChat -Messages $messages
Write-Host "Turn 1 ($($turn1.ElapsedMs) ms, $($turn1.CompletionTokens) output tokens):"
Write-Host $turn1.Text

$messages += @{ role = "assistant"; content = $turn1.Text }
$messages += @{ role = "user"; content = $secondPrompt }
$turn2 = Invoke-QwenChat -Messages $messages -MaxTokens 32
Write-Host "`nTurn 2 ($($turn2.ElapsedMs) ms, $($turn2.CompletionTokens) output tokens):"
Write-Host $turn2.Text

if ($turn2.Text -notmatch $expectedCodeName) {
    throw "Conversation memory test failed: expected the second response to contain the code name."
}

Write-Host "`nPASS: local Chinese multi-turn conversation is working."
