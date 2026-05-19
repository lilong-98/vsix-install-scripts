$ErrorActionPreference = "Stop"

$CodexBaseUrl = if ($env:VSIX_CODEX_BASE_URL) { $env:VSIX_CODEX_BASE_URL } else { "https://vsix.cc" }
$CodexModel = if ($env:VSIX_CODEX_MODEL) { $env:VSIX_CODEX_MODEL } else { "gpt-5.4" }
$CodexProvider = if ($env:VSIX_CODEX_PROVIDER) { $env:VSIX_CODEX_PROVIDER } else { "vsix" }
$CodexPackage = if ($env:VSIX_CODEX_PACKAGE) { $env:VSIX_CODEX_PACKAGE } else { "@openai/codex@latest" }
$CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
$ConfigFile = Join-Path $CodexHome "config.toml"
$AuthFile = Join-Path $CodexHome "auth.json"

function Say([string]$Message) {
  Write-Host $Message
}

function Confirm-Yes([string]$Prompt, [bool]$DefaultYes = $false) {
  $suffix = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
  $answer = Read-Host "$Prompt $suffix"

  if ([string]::IsNullOrWhiteSpace($answer)) {
    return $DefaultYes
  }

  return @("y", "yes") -contains $answer.Trim().ToLowerInvariant()
}

function Ensure-NodeJs {
  $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
  $npmCommand = Get-Command npm -ErrorAction SilentlyContinue
  if ($nodeCommand -and $npmCommand) {
    $nodeVersion = try { & node --version 2>$null } catch { $nodeCommand.Source }
    Say "Node.js 已安装：$nodeVersion"
    return
  }

  Say "未检测到 Node.js / npm，准备自动安装 Node.js LTS。"

  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "未找到 winget。请先手动安装 Node.js LTS：https://nodejs.org/"
  }

  Say "开始通过 winget 安装 Node.js LTS..."
  winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements

  if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw "Node.js 安装后仍未检测到 node。请重新打开 PowerShell 再试。"
  }

  if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "Node.js 安装后仍未检测到 npm。请重新打开 PowerShell 再试。"
  }

  Say "Node.js LTS 安装完成。"
}

function Backup-IfExists([string]$Path) {
  if (Test-Path -LiteralPath $Path) {
    $stamp = Get-Date -Format "yyyyMMddHHmmss"
    $backupPath = "$Path.bak.$stamp"
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    Say "已备份现有文件：$backupPath"
  }
}

function Write-CodexConfig {
  New-Item -ItemType Directory -Path $CodexHome -Force | Out-Null
  Backup-IfExists $ConfigFile

  $config = @"
model_provider = "$CodexProvider"
model = "$CodexModel"
model_reasoning_effort = "high"
disable_response_storage = true
preferred_auth_method = "apikey"

[model_providers.$CodexProvider]
name = "$CodexProvider"
base_url = "$CodexBaseUrl"
wire_api = "responses"
requires_openai_auth = true
"@

  Set-Content -LiteralPath $ConfigFile -Value $config -Encoding UTF8
}

function Write-CodexAuth([string]$ApiKey) {
  New-Item -ItemType Directory -Path $CodexHome -Force | Out-Null
  Backup-IfExists $AuthFile

  $auth = [ordered]@{
    OPENAI_API_KEY = $ApiKey
  } | ConvertTo-Json

  Set-Content -LiteralPath $AuthFile -Value $auth -Encoding UTF8
}

function Ensure-CodexCli {
  Ensure-NodeJs

  $codexCommand = Get-Command codex -ErrorAction SilentlyContinue
  if ($codexCommand) {
    $version = try { & codex --version 2>$null } catch { $codexCommand.Source }
    Say "Codex 已安装：$version"
    return
  }

  Say "未检测到 Codex CLI。"
  if (-not (Confirm-Yes "是否使用 npm 安装 Codex？" $true)) {
    Say "已跳过安装。后续可手动运行：npm install -g $CodexPackage"
    return
  }

  npm install -g $CodexPackage
}

function Launch-Codex {
  if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
    Say "未找到 codex 命令，请安装后手动运行：codex"
    return
  }

  if (Confirm-Yes "是否立即启动 Codex？" $false) {
    & codex
  } else {
    Say "已跳过启动。需要使用时运行：codex"
  }
}

Say "VSIX Codex 交互式配置"
Say ""
Say "接口地址：$CodexBaseUrl"
Say "默认模型：$CodexModel"
Say "脚本会写入："
Say "  - $ConfigFile"
Say "  - $AuthFile"
Say ""

$ApiKey = $env:VSIX_API_KEY
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  $ApiKey = Read-Host "请输入 VSIX API Key"
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  throw "API Key 不能为空。"
}

Write-CodexConfig
Write-CodexAuth $ApiKey

Say ""
Say "Codex 配置已写入："
Say "  - $ConfigFile"
Say "  - $AuthFile"
Say ""
Say "如果 Codex 已经打开，请重启 Codex 或重新打开 PowerShell 后再使用。"

Ensure-CodexCli
Launch-Codex
