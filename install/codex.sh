#!/usr/bin/env bash
set -euo pipefail

CODEX_BASE_URL="${VSIX_CODEX_BASE_URL:-https://vsix.cc}"
CODEX_MODEL="${VSIX_CODEX_MODEL:-gpt-5.4}"
CODEX_PROVIDER="${VSIX_CODEX_PROVIDER:-vsix}"
CODEX_PACKAGE="${VSIX_CODEX_PACKAGE:-@openai/codex@latest}"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
CONFIG_FILE="$CODEX_HOME_DIR/config.toml"
AUTH_FILE="$CODEX_HOME_DIR/auth.json"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --help|-h)
      cat <<'EOF'
VSIX Codex 一键配置脚本

用法：
  curl -fsSL https://vsix.cc/install/codex.sh | bash

可选环境变量：
  VSIX_API_KEY=sk-xxxx              跳过交互输入 API Key
  VSIX_CODEX_BASE_URL=https://...   覆盖 base_url，默认 https://vsix.cc
  VSIX_CODEX_MODEL=gpt-5.4          覆盖模型名
  CODEX_HOME=/path/to/.codex        覆盖 Codex 配置目录

可选参数：
  --dry-run                         只预览目标路径，不写入文件
EOF
      exit 0
      ;;
    *)
      printf '未知参数：%s\n' "$arg" >&2
      exit 1
      ;;
  esac
done

if ! { exec 3</dev/tty; } 2>/dev/null; then
  exec 3<&0
fi

say() {
  printf '%s\n' "$*"
}

read_input() {
  local var_name="$1"
  local prompt="$2"
  read -r -u 3 -p "$prompt" "$var_name"
}

confirm_yes() {
  local prompt="$1"
  local default_yes="${2:-no}"
  local answer
  read_input answer "$prompt"
  if [ -z "$answer" ]; then
    [ "$default_yes" = "yes" ]
    return
  fi
  case "$answer" in
    y|Y|yes|YES|Yes) return 0 ;;
    *) return 1 ;;
  esac
}

backup_if_exists() {
  local file="$1"
  if [ -f "$file" ]; then
    local stamp
    stamp="$(date +%Y%m%d%H%M%S)"
    cp "$file" "$file.bak.$stamp"
    say "已备份现有文件：$file.bak.$stamp"
  fi
}

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

write_config() {
  mkdir -p "$CODEX_HOME_DIR"
  backup_if_exists "$CONFIG_FILE"
  cat > "$CONFIG_FILE" <<EOF
model_provider = "$CODEX_PROVIDER"
model = "$CODEX_MODEL"
model_reasoning_effort = "high"
disable_response_storage = true
preferred_auth_method = "apikey"

[model_providers.$CODEX_PROVIDER]
name = "$CODEX_PROVIDER"
base_url = "$CODEX_BASE_URL"
wire_api = "responses"
requires_openai_auth = true
EOF
}

write_auth() {
  local api_key="$1"
  local escaped_key
  escaped_key="$(json_escape "$api_key")"
  mkdir -p "$CODEX_HOME_DIR"
  backup_if_exists "$AUTH_FILE"
  cat > "$AUTH_FILE" <<EOF
{
  "OPENAI_API_KEY": "$escaped_key"
}
EOF
  chmod 600 "$AUTH_FILE" 2>/dev/null || true
}

ensure_codex_cli() {
  if command -v codex >/dev/null 2>&1; then
    say "Codex 已安装：$(codex --version 2>/dev/null || command -v codex)"
    return
  fi

  say "未检测到 Codex CLI。"
  if ! confirm_yes "是否使用 npm 安装 Codex？[Y/n]: " "yes"; then
    say "已跳过安装。后续可手动运行：npm install -g $CODEX_PACKAGE"
    return
  fi

  if ! command -v npm >/dev/null 2>&1; then
    say "未找到 npm。请先安装 Node.js，再执行：npm install -g $CODEX_PACKAGE"
    return
  fi

  npm install -g "$CODEX_PACKAGE"
}

launch_codex() {
  if ! command -v codex >/dev/null 2>&1; then
    say "未找到 codex 命令，请安装后手动运行：codex"
    return
  fi

  if confirm_yes "是否立即启动 Codex？[y/N]: "; then
    if [ -r /dev/tty ]; then
      exec </dev/tty
    fi
    exec codex
  fi

  say "已跳过启动。需要使用时运行：codex"
}

main() {
  say "VSIX Codex 交互式配置"
  say ""
  say "接口地址：$CODEX_BASE_URL"
  say "默认模型：$CODEX_MODEL"
  say "脚本会写入："
  say "  - $CONFIG_FILE"
  say "  - $AUTH_FILE"
  say ""

  local api_key="${VSIX_API_KEY:-}"
  if [ -z "$api_key" ]; then
    read_input api_key "请输入 VSIX API Key: "
  fi

  if [ -z "$api_key" ]; then
    say "API Key 不能为空。"
    exit 1
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] 将写入配置目录：$CODEX_HOME_DIR"
    say "[dry-run] base_url：$CODEX_BASE_URL"
    say "[dry-run] model：$CODEX_MODEL"
    return
  fi

  write_config
  write_auth "$api_key"

  say ""
  say "Codex 配置已写入："
  say "  - $CONFIG_FILE"
  say "  - $AUTH_FILE"
  say ""
  say "如果 Codex 已经打开，请重启 Codex 或重新打开终端后再使用。"

  ensure_codex_cli
  launch_codex
}

main "$@"
