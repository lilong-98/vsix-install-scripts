#!/usr/bin/env bash
set -euo pipefail

ANTHROPIC_BASE_URL="${VSIX_OPENCLAW_ANTHROPIC_BASE_URL:-https://vsix.cc}"
OPENAI_BASE_URL="${VSIX_OPENCLAW_OPENAI_BASE_URL:-https://vsix.cc/v1}"
ANTHROPIC_MODEL="${VSIX_OPENCLAW_ANTHROPIC_MODEL:-claude-sonnet-4-6}"
OPENAI_MODEL="${VSIX_OPENCLAW_OPENAI_MODEL:-gpt-5.4}"
OPENCLAW_PACKAGE="${VSIX_OPENCLAW_PACKAGE:-@openclaw/cli}"
PROVIDER="${VSIX_OPENCLAW_PROVIDER:-}"
DRY_RUN=0
SKIP_INSTALL="${VSIX_OPENCLAW_SKIP_INSTALL:-0}"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --skip-install) SKIP_INSTALL=1 ;;
    --provider=anthropic) PROVIDER="anthropic" ;;
    --provider=openai) PROVIDER="openai" ;;
    --help|-h)
      cat <<'EOF'
VSIX OpenClaw 一键配置脚本

用法：
  curl -fsSL https://vsix.cc/install/openclaw.sh | sudo bash

如果已经安装 OpenClaw，也可以不用 sudo：
  curl -fsSL https://vsix.cc/install/openclaw.sh | bash

可选环境变量：
  VSIX_API_KEY=sk-xxxx                         跳过交互输入 API Key
  VSIX_OPENCLAW_PROVIDER=anthropic|openai      跳过通道选择
  VSIX_OPENCLAW_ANTHROPIC_MODEL=claude-...     覆盖 Claude 默认模型
  VSIX_OPENCLAW_OPENAI_MODEL=gpt-...           覆盖 OpenAI 默认模型
  VSIX_OPENCLAW_SKIP_INSTALL=1                 跳过 OpenClaw 安装检查

可选参数：
  --provider=anthropic                         使用 Anthropic（Claude）通道
  --provider=openai                            使用 OpenAI（Codex）通道
  --skip-install                               不自动安装 OpenClaw
  --dry-run                                    只预览将执行的配置命令
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

ask() {
  printf '%s\n' "$*" >&2
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

select_item() {
  local prompt="$1"
  shift
  local items=("$@")
  local choice

  ask "$prompt"
  local i
  for i in "${!items[@]}"; do
    printf '  %d) %s\n' "$((i + 1))" "${items[$i]}" >&2
  done

  while true; do
    read_input choice "请输入序号 [1-${#items[@]}]: "
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#items[@]}" ]; then
      printf '%s' "${items[$((choice - 1))]}"
      return
    fi
    ask "输入无效，请重新选择。"
  done
}

normalize_provider() {
  case "$PROVIDER" in
    anthropic|claude|Anthropic|Claude)
      PROVIDER="anthropic"
      ;;
    openai|codex|OpenAI|Codex)
      PROVIDER="openai"
      ;;
    "")
      local selected
      selected="$(select_item "请选择 OpenClaw 接入通道：" "Anthropic（Claude）" "OpenAI（Codex）")"
      case "$selected" in
        Anthropic*) PROVIDER="anthropic" ;;
        *) PROVIDER="openai" ;;
      esac
      ;;
    *)
      say "未知通道：$PROVIDER。请使用 anthropic 或 openai。"
      exit 1
      ;;
  esac
}

ensure_openclaw_cli() {
  if [ "$SKIP_INSTALL" = "1" ]; then
    return
  fi

  if command -v openclaw >/dev/null 2>&1; then
    say "OpenClaw 已安装：$(command -v openclaw)"
    return
  fi

  say "未检测到 OpenClaw。"
  if ! confirm_yes "是否使用 npm 安装 OpenClaw CLI？[Y/n]: " "yes"; then
    say "已跳过安装。后续可手动运行：npm install -g $OPENCLAW_PACKAGE"
    return
  fi

  if ! command -v npm >/dev/null 2>&1; then
    say "未找到 npm。请先安装 Node.js，再执行：npm install -g $OPENCLAW_PACKAGE"
    return
  fi

  npm install -g "$OPENCLAW_PACKAGE"
}

print_plan() {
  local base_url="$1"
  local env_key="$2"
  local compatibility="$3"
  local model="$4"

  say "将执行 OpenClaw 配置："
  say "  base_url: $base_url"
  say "  api_key_env: $env_key"
  say "  compatibility: $compatibility"
  say "  model: $model"
  say ""
  say "等价命令："
  say "  $env_key=*** openclaw onboard --auth-choice custom-api-key --custom-base-url $base_url --custom-api-key-env $env_key --custom-compatibility $compatibility --custom-model $model"
}

run_openclaw_onboard() {
  local base_url="$1"
  local env_key="$2"
  local compatibility="$3"
  local model="$4"
  local api_key="$5"
  local openclaw_bin=""

  if ! openclaw_bin="$(command -v openclaw 2>/dev/null)"; then
    say "未找到 openclaw 命令，无法自动写入配置。"
    say "请先安装后手动执行：npm install -g $OPENCLAW_PACKAGE"
    exit 1
  fi

  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] && command -v sudo >/dev/null 2>&1; then
    say "检测到 sudo 执行，配置将写入用户 $SUDO_USER 的 OpenClaw 环境。"
    sudo -H -u "$SUDO_USER" env "$env_key=$api_key" "$openclaw_bin" onboard \
      --auth-choice custom-api-key \
      --custom-base-url "$base_url" \
      --custom-api-key-env "$env_key" \
      --custom-compatibility "$compatibility" \
      --custom-model "$model"
    return
  fi

  env "$env_key=$api_key" "$openclaw_bin" onboard \
    --auth-choice custom-api-key \
    --custom-base-url "$base_url" \
    --custom-api-key-env "$env_key" \
    --custom-compatibility "$compatibility" \
    --custom-model "$model"
}

launch_openclaw() {
  if ! command -v openclaw >/dev/null 2>&1; then
    say "未找到 openclaw 命令。安装完成后可手动运行：openclaw"
    return
  fi

  if confirm_yes "是否立即启动 OpenClaw？[y/N]: "; then
    if [ -r /dev/tty ]; then
      exec </dev/tty
    fi
    exec openclaw
  fi

  say "已跳过启动。需要使用时运行：openclaw"
}

main() {
  say "VSIX OpenClaw 交互式配置"
  say ""

  normalize_provider

  local base_url env_key compatibility model api_key
  if [ "$PROVIDER" = "anthropic" ]; then
    base_url="$ANTHROPIC_BASE_URL"
    env_key="ANTHROPIC_API_KEY"
    compatibility="anthropic"
    model="$ANTHROPIC_MODEL"
    say "已选择：Anthropic（Claude）通道"
    say "提示：Claude / Anthropic 通道使用 ${base_url}，不要追加 /v1。"
  else
    base_url="$OPENAI_BASE_URL"
    env_key="OPENAI_API_KEY"
    compatibility="openai"
    model="$OPENAI_MODEL"
    say "已选择：OpenAI（Codex）通道"
    say "提示：OpenAI / Codex 通道使用 ${base_url}，必须带 /v1。"
  fi
  say ""

  api_key="${VSIX_API_KEY:-}"
  if [ -z "$api_key" ]; then
    read_input api_key "请输入 VSIX API Key: "
  fi

  if [ -z "$api_key" ]; then
    say "API Key 不能为空。"
    exit 1
  fi

  print_plan "$base_url" "$env_key" "$compatibility" "$model"

  if [ "$DRY_RUN" -eq 1 ]; then
    say "[dry-run] 已停止，未写入 OpenClaw 配置。"
    return
  fi

  ensure_openclaw_cli
  run_openclaw_onboard "$base_url" "$env_key" "$compatibility" "$model" "$api_key"

  say ""
  say "OpenClaw 配置已完成。"
  say "如果 OpenClaw 已经在运行，请重启 OpenClaw 后再使用。"
  launch_openclaw
}

main "$@"
