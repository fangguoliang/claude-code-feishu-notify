# Feishu notification script for Claude Code hooks
# GitHub: https://github.com/your-username/claude-code-feishu-notify
param([Parameter(ValueFromPipeline=$true)]$InputObject)

# Set UTF-8 encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Function to check if Windows is locked (lock screen active)
# Only sends notifications when screen is locked to avoid frequent interruptions
function Test-LockScreen {
    # When Windows is locked, logonui.exe process runs
    $logonUI = Get-Process -Name "logonui" -ErrorAction SilentlyContinue
    return ($null -ne $logonUI)
}

# Get script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Load config
$configFile = Join-Path $scriptDir "config.json"
if (-not (Test-Path $configFile)) {
    Write-Error "Config file not found: $configFile"
    Write-Error "Please copy config.example.json to config.json and fill in your webhook URL"
    exit 1
}

$config = Get-Content -Path $configFile -Encoding UTF8 | ConvertFrom-Json
$WEBHOOK_URL = $config.webhook_url

if (-not $WEBHOOK_URL -or $WEBHOOK_URL -like "*YOUR_WEBHOOK_ID_HERE*") {
    Write-Error "Please configure your webhook URL in config.json"
    exit 1
}

$maxPromptLength = if ($config.max_prompt_length) { $config.max_prompt_length } else { 100 }

$tempFile = "$env:TEMP\feishu_notify.json"
$logFile = Join-Path $scriptDir "feishu-notify.log"

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Function to get recent prompt from transcript file
function Get-RecentPrompt {
    param([string]$transcriptPath, [int]$maxLength)

    if (-not $transcriptPath -or -not (Test-Path $transcriptPath)) {
        return $null
    }

    try {
        $lines = Get-Content -Path $transcriptPath -Encoding UTF8 -ErrorAction SilentlyContinue
        if (-not $lines) { return $null }

        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            $line = $lines[$i].Trim()
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            try {
                $entry = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($entry.type -eq "user" -and $entry.message -and $entry.message.role -eq "user") {
                    $content = $entry.message.content
                    if ($content) {
                        if ($content -is [array]) { continue }
                        if ([string]::IsNullOrWhiteSpace($content)) { continue }
                        if ($content.Length -gt $maxLength) {
                            $content = $content.Substring(0, $maxLength) + "..."
                        }
                        return $content
                    }
                }
            } catch { continue }
        }
    } catch {}
    return $null
}

# Read stdin for hook data
$stdinData = ""
if ($InputObject) { $stdinData = $InputObject | Out-String }
if ([string]::IsNullOrEmpty($stdinData)) {
    try { $stdinData = [Console]::In.ReadToEnd() } catch {}
}
if ([string]::IsNullOrEmpty($stdinData)) {
    try {
        $stdinData = [System.Console]::OpenStandardInput()
        $reader = New-Object System.IO.StreamReader($stdinData)
        $stdinData = $reader.ReadToEnd()
        $reader.Close()
    } catch {}
}

$hookType = if ($env:CLAUDE_HOOK_TYPE) { $env:CLAUDE_HOOK_TYPE } else { "unknown" }
$stopReason = ""
$content = ""

# Parse JSON - use ErrorAction Stop to catch parsing failures
$json = $null
$jsonParseSuccess = $false

try {
    $json = $stdinData | ConvertFrom-Json -ErrorAction Stop
    $jsonParseSuccess = $true
} catch {
    Add-Content -Path $logFile -Value "[$timestamp] JSON Parse Error: $($_.Exception.Message.Substring(0, [Math]::Min(200, $_.Exception.Message.Length)))" -Encoding UTF8
}

# Initialize projectPath for later use
$projectPath = "unknown"

# Extract values from parsed JSON or use regex fallback
if ($jsonParseSuccess -and $json) {
    if ($json.hook_event_name) { $hookType = $json.hook_event_name }
    if ($json.message) { $content = $json.message }
    if ($json.reason) { $stopReason = $json.reason }
    if ($json.cwd) { $projectPath = $json.cwd }

    if ($json.tool_input) {
        $ti = $json.tool_input
        if ($ti.questions -and $ti.questions.Count -gt 0) {
            $q = $ti.questions[0]
            if (-not $content) { $content = $q.question }
            if ($q.options -and $q.options.Count -gt 0) {
                $optionLabels = $q.options | ForEach-Object { $_.label }
                $content += "`nOptions: " + ($optionLabels -join ", ")
            }
            $answers = if ($ti.answers) { $ti.answers } elseif ($json.tool_response -and $json.tool_response.answers) { $json.tool_response.answers } else { $null }
            if ($answers) {
                $answer = $answers | Select-Object -ExpandProperty $q.question -ErrorAction SilentlyContinue
                if ($answer) { $content += "`nAnswer: " + $answer }
            }
        } elseif ($ti.question) { if (-not $content) { $content = $ti.question } }
        elseif ($ti.prompt) { if (-not $content) { $content = $ti.prompt } }
        elseif ($ti.command) { if (-not $content) { $content = $ti.command } }
    }
    if ($json.tool_name -and !$content) { $content = "Tool: " + $json.tool_name }
    if ($json.notification_type -and !$content) { $content = $json.notification_type }
} else {
    # Fallback: extract values using regex when JSON parsing fails
    Add-Content -Path $logFile -Value "[$timestamp] Using regex fallback for parsing" -Encoding UTF8

    if ($stdinData -match '"hook_event_name"\s*:\s*"([^"]+)"') { $hookType = $matches[1] }
    if ($stdinData -match '"reason"\s*:\s*"([^"]+)"') { $stopReason = $matches[1] }
    if ($stdinData -match '"message"\s*:\s*"([^"]+)"') { $content = $matches[1] }
    if ($stdinData -match '"cwd"\s*:\s*"([^"]+)"') { $projectPath = $matches[1] -replace '\\\\', '\' }
    if ($stdinData -match '"notification_type"\s*:\s*"([^"]+)"') { if (-not $content) { $content = $matches[1] } }
}

# Get transcript_path for prompt extraction
$transcriptPath = $null
if ($jsonParseSuccess -and $json -and $json.transcript_path) {
    $transcriptPath = $json.transcript_path
} elseif ($stdinData -match '"transcript_path"\s*:\s*"([^"]+)"') {
    $transcriptPath = $matches[1] -replace '\\\\', '\'
}

$recentPrompt = ""
if ($transcriptPath) {
    $recentPrompt = Get-RecentPrompt -transcriptPath $transcriptPath -maxLength $maxPromptLength
}

$taskStatus = ""
if ($content) { $taskStatus = $content }
elseif ($stopReason) { $taskStatus = $stopReason }
else {
    $hookDisplay = switch ($hookType) {
        "Stop" { "Task Done" }
        "Notification" { "Notification" }
        "PermissionRequest" { "Waiting Confirm" }
        "SessionEnd" { "Session End" }
        default { $hookType }
    }
    $taskStatus = $hookDisplay
}

# Build message with labels
$message = "【项目路径】`n" + $projectPath
if ($recentPrompt) { $message += "`n【提示词】`n" + $recentPrompt }
$message += "`n【CC任务进展】`n" + $taskStatus
$message += "`n" + $timestamp

# Log
Add-Content -Path $logFile -Value "[$timestamp] Hook: $hookType, Content: $taskStatus" -Encoding UTF8

# Check lock screen status - only send notification when screen is locked
# This prevents frequent notifications while you're actively using the computer
if (-not (Test-LockScreen)) {
    Add-Content -Path $logFile -Value "[$timestamp] Skipped: Screen not locked (press Win+L to lock)" -Encoding UTF8
    exit 0
}

Add-Content -Path $logFile -Value "[$timestamp] Screen locked, sending notification..." -Encoding UTF8

# Send to Feishu
$body = @{msg_type="text"; content=@{text=$message}} | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText($tempFile, $body, [System.Text.UTF8Encoding]::new($false))

try {
    $result = Invoke-RestMethod -Uri $WEBHOOK_URL -Method Post -ContentType "application/json; charset=utf-8" -Body ([System.IO.File]::ReadAllBytes($tempFile))
    Add-Content -Path $logFile -Value "[$timestamp] Sent: code=$($result.code)" -Encoding UTF8
} catch {
    Add-Content -Path $logFile -Value "[$timestamp] Error: $_" -Encoding UTF8
}

Remove-Item $tempFile -ErrorAction SilentlyContinue
exit 0