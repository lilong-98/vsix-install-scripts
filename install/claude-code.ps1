$ErrorActionPreference = "Stop"

$ClaudeBaseUrl = if ($env:VSIX_CLAUDE_BASE_URL) { $env:VSIX_CLAUDE_BASE_URL } else { "https://vsix.cc" }
$ClaudePackage = if ($env:VSIX_CLAUDE_PACKAGE) { $env:VSIX_CLAUDE_PACKAGE } else { "@anthropic-ai/claude-code" }
$DisableNonessentialTraffic = if ($env:VSIX_DISABLE_NONESSENTIAL_TRAFFIC) { $env:VSIX_DISABLE_NONESSENTIAL_TRAFFIC } else { "1" }

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

function Invoke-NpmInstall([string[]]$Arguments) {
  $npmCmd = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if ($npmCmd) {
    & npm.cmd @Arguments
    return
  }

  & npm @Arguments
}

function Get-ExecutableCommand([string]$Name) {
  $cmdCommand = Get-Command "$Name.cmd" -ErrorAction SilentlyContinue
  if ($cmdCommand) {
    return $cmdCommand.Source
  }

  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  return $null
}

function Ensure-ClaudeCodeCli {
  Ensure-NodeJs

  $claudeCommand = Get-ExecutableCommand "claude"
  if ($claudeCommand) {
    $version = try { & $claudeCommand --version 2>$null } catch { $claudeCommand }
    Say "Claude Code 已安装：$version"
    return
  }

  Say "未检测到 Claude Code。"
  if (-not (Confirm-Yes "是否使用 npm 安装 Claude Code？" $true)) {
    Say "已跳过安装。后续可手动运行：npm install -g $ClaudePackage"
    return
  }

  Invoke-NpmInstall @("install", "-g", $ClaudePackage)
}

function Launch-ClaudeCode {
  $claudeCommand = Get-ExecutableCommand "claude"
  if (-not $claudeCommand) {
    Say "未找到 claude 命令，请安装后手动运行：claude"
    return
  }

  if (Confirm-Yes "是否立即启动 Claude Code？" $false) {
    & $claudeCommand
  } else {
    Say "已跳过启动。请重开 PowerShell 后运行：claude"
  }
}

Say "VSIX Claude Code 交互式配置"
Say ""
Say "接口地址：$ClaudeBaseUrl"
Say "脚本会写入用户级环境变量 ANTHROPIC_BASE_URL、ANTHROPIC_AUTH_TOKEN。"
Say ""

$ApiKey = $env:VSIX_API_KEY
if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  $ApiKey = Read-Host "请输入 VSIX API Key"
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  throw "API Key 不能为空。"
}

[System.Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", $ClaudeBaseUrl, [System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable("ANTHROPIC_AUTH_TOKEN", $ApiKey, [System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", $DisableNonessentialTraffic, [System.EnvironmentVariableTarget]::User)

$env:ANTHROPIC_BASE_URL = $ClaudeBaseUrl
$env:ANTHROPIC_AUTH_TOKEN = $ApiKey
$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = $DisableNonessentialTraffic

Say ""
Say "Claude Code 配置已写入当前用户环境变量。"
Say "如果 Claude Code 已经打开，请重启 Claude Code 或重新打开 PowerShell 后再使用。"

Ensure-ClaudeCodeCli
Launch-ClaudeCode
