#!/usr/bin/env bash
set -euo pipefail

CLAUDE_BASE_URL="${VSIX_CLAUDE_BASE_URL:-https://vsix.cc}"
CLAUDE_PACKAGE="${VSIX_CLAUDE_PACKAGE:-@anthropic-ai/claude-code}"
DISABLE_NONESSENTIAL_TRAFFIC="${VSIX_DISABLE_NONESSENTIAL_TRAFFIC:-1}"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --help|-h)
      cat <<'EOF'
VSIX Claude Code 一键配置脚本

用法：
  curl -fsSL https://vsix.cc/install/claude-code.sh | bash

可选环境变量：
  VSIX_API_KEY=sk-xxxx                    跳过交互输入 API Key
  VSIX_CLAUDE_BASE_URL=https://...        覆盖 ANTHROPIC_BASE_URL，默认 https://vsix.cc
  VSIX_CLAUDE_PACKAGE=@anthropic-ai/...   覆盖 Claude Code npm 包名

可选参数：
  --dry-run                               只预览目标配置，不写入文件
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

detect_shell_rc() {
  case "${SHELL##*/}" in
    zsh)
      printf '%s/.zshrc' "$HOME"
      return
      ;;
    bash)
      printf '%s/.bashrc' "$HOME"
      return
      ;;
  esac

  case "$(uname -s 2>/dev/null || true)" in
    Darwin) printf '%s/.zshrc' "$HOME" ;;
    *) printf '%s/.profile' "$HOME" ;;
  esac
}

remove_existing_export() {
  local rc_file="$1"
  local key="$2"

  touch "$rc_file"
  if [ "$(uname -s 2>/dev/null || true)" = "Darwin" ]; then
    sed -i '' "/^[[:space:]]*export[[:space:]]\\{1,\\}${key}=/d" "$rc_file" 2>/dev/null || true
  else
    sed -i "/^[[:space:]]*export[[:space:]]\\{1,\\}${key}=/d" "$rc_file" 2>/dev/null || true
  fi
}

persist_export() {
  local rc_file="$1"
  local key="$2"
  local value="$3"
  local escaped_value

  remove_existing_export "$rc_file" "$key"
  escaped_value="$(printf '%s' "$value" | sed "s/'/'\\\\''/g")"
  printf "\n# VSIX Claude Code\nexport %s='%s'\n" "$key" "$escaped_value" >> "$rc_file"
}

ensure_claude_code_cli() {
  if command -v claude >/dev/null 2>&1; then
    say "Claude Code 已安装：$(claude --version 2>/dev/null || command -v claude)"
    return
  fi

  say "未检测到 Claude Code。"
  if ! confirm_yes "是否使用 npm 安装 Claude Code？[Y/n]: " "yes"; then
    say "已跳过安装。后续可手动运行：npm install -g $CLAUDE_PACKAGE"
    return
  fi

  if ! command -v npm >/dev/null 2>&1; then
    say "未找到 npm。请先安装 Node.js，再执行：npm install -g $CLAUDE_PACKAGE"
    return
  fi

  npm install -g "$CLAUDE_PACKAGE"
}

launch_claude() {
  if ! command -v claude >/dev/null 2>&1; then
    say "未找到 claude 命令，请安装后手动运行：claude"
    return
  fi

  if confirm_yes "是否立即启动 Claude Code？[y/N]: "; then
    if [ -r /dev/tty ]; then
      exec </dev/tty
    fi
    exec claude
  fi

  say "已跳过启动。请重开终端或执行 source 后运行：claude"
}

main() {
  say "VSIX Claude Code 交互式配置"
  say ""
  say "接口地址：$CLAUDE_BASE_URL"
  say "脚本会写入 ANTHROPIC_BASE_URL、ANTHROPIC_AUTH_TOKEN。"
  say ""

  local api_key="${VSIX_API_KEY:-}"
  if [ -z "$api_key" ]; then
    read_input api_key "请输入 VSIX API Key: "
  fi

  if [ -z "$api_key" ]; then
    say "API Key 不能为空。"
    exit 1
  fi

  local rc_file
  rc_file="$(detect_shell_rc)"

  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] 将写入：$rc_file"
    say "[dry-run] ANTHROPIC_BASE_URL=$CLAUDE_BASE_URL"
    say "[dry-run] ANTHROPIC_AUTH_TOKEN=***"
    return
  fi

  export ANTHROPIC_BASE_URL="$CLAUDE_BASE_URL"
  export ANTHROPIC_AUTH_TOKEN="$api_key"
  export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="$DISABLE_NONESSENTIAL_TRAFFIC"

  persist_export "$rc_file" "ANTHROPIC_BASE_URL" "$CLAUDE_BASE_URL"
  persist_export "$rc_file" "ANTHROPIC_AUTH_TOKEN" "$api_key"
  persist_export "$rc_file" "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" "$DISABLE_NONESSENTIAL_TRAFFIC"

  say ""
  say "Claude Code 配置已写入：$rc_file"
  say "如果 Claude Code 已经打开，请重启 Claude Code 或重新打开终端后再使用。"

  ensure_claude_code_cli
  launch_claude
}

main "$@"
