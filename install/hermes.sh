#!/usr/bin/env bash
set -euo pipefail

HERMES_BASE_URL="${VSIX_HERMES_BASE_URL:-https://vsix.cc}"
HERMES_MODEL="${VSIX_HERMES_MODEL:-claude-sonnet-4-6}"
HERMES_PROVIDER_NAME="${VSIX_HERMES_PROVIDER_NAME:-custom-vsix}"
HERMES_API_MODE="${VSIX_HERMES_API_MODE:-anthropic_messages}"
HERMES_CONFIG_DIR="${HERMES_CONFIG_DIR:-$HOME/.hermes}"
HERMES_CONFIG_FILE="${HERMES_CONFIG_FILE:-$HERMES_CONFIG_DIR/config.yaml}"
FORCE_OVERWRITE="${VSIX_HERMES_FORCE_OVERWRITE:-0}"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE_OVERWRITE=1 ;;
    --help|-h)
      cat <<'EOF'
VSIX Hermes 一键配置脚本

用法：
  curl -fsSL https://vsix.cc/install/hermes.sh | bash

可选环境变量：
  VSIX_API_KEY=sk-xxxx                    跳过交互输入 API Key
  VSIX_HERMES_BASE_URL=https://...        覆盖 base_url，默认 https://vsix.cc
  VSIX_HERMES_MODEL=claude-sonnet-4-6     覆盖默认模型
  VSIX_HERMES_PROVIDER_NAME=custom-vsix   覆盖 provider 名称
  HERMES_CONFIG_FILE=/path/config.yaml    指定 Hermes 配置文件

可选参数：
  --dry-run                               只预览目标配置，不写入文件
  --force                                 无 PyYAML 且已有配置时，备份后覆盖写入
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
    local stamp backup_file
    stamp="$(date +%Y%m%d%H%M%S)"
    backup_file="$file.bak.$stamp"
    cp "$file" "$backup_file"
    say "已备份现有配置：$backup_file"
  fi
}

yaml_quote() {
  local value="$1"
  value="$(printf '%s' "$value" | sed "s/'/''/g")"
  printf "'%s'" "$value"
}

write_minimal_config() {
  local api_key="$1"
  local dir
  dir="$(dirname "$HERMES_CONFIG_FILE")"
  mkdir -p "$dir"
  cat > "$HERMES_CONFIG_FILE" <<EOF
model:
  default: $(yaml_quote "$HERMES_MODEL")
  provider: $(yaml_quote "$HERMES_PROVIDER_NAME")
  base_url: $(yaml_quote "$HERMES_BASE_URL")
  api_key: $(yaml_quote "$api_key")
  api_mode: $(yaml_quote "$HERMES_API_MODE")

custom_providers:
  - name: $(yaml_quote "$HERMES_PROVIDER_NAME")
    base_url: $(yaml_quote "$HERMES_BASE_URL")
    api_key: $(yaml_quote "$api_key")
    api_mode: $(yaml_quote "$HERMES_API_MODE")
    models:
      - $(yaml_quote "$HERMES_MODEL")

smart_model_routing:
  enabled: false
EOF
  chmod 600 "$HERMES_CONFIG_FILE" 2>/dev/null || true
}

python_with_yaml() {
  local candidate
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import yaml' >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

merge_config_with_python() {
  local python_bin="$1"
  local api_key="$2"

  "$python_bin" - "$HERMES_CONFIG_FILE" "$HERMES_PROVIDER_NAME" "$HERMES_API_MODE" "$HERMES_BASE_URL" "$api_key" "$HERMES_MODEL" <<'PY'
import sys
from pathlib import Path

import yaml

config_path = Path(sys.argv[1]).expanduser()
provider_name, api_mode, base_url, api_key, model_id = sys.argv[2:]

data = {}
if config_path.exists() and config_path.stat().st_size > 0:
    with config_path.open("r", encoding="utf-8") as fh:
        loaded = yaml.safe_load(fh)
    if loaded is None:
        data = {}
    elif isinstance(loaded, dict):
        data = loaded
    else:
        raise SystemExit("现有 Hermes config.yaml 不是 YAML 对象，已停止写入以避免破坏配置。")

model = data.get("model")
if not isinstance(model, dict):
    model = {}
data["model"] = model
model.update({
    "default": model_id,
    "provider": provider_name,
    "base_url": base_url,
    "api_key": api_key,
    "api_mode": api_mode,
})

custom_providers = data.get("custom_providers")
if not isinstance(custom_providers, list):
    custom_providers = []

next_providers = []
updated = False
for item in custom_providers:
    if isinstance(item, dict) and item.get("name") == provider_name:
        item = dict(item)
        item.update({
            "name": provider_name,
            "base_url": base_url,
            "api_key": api_key,
            "api_mode": api_mode,
            "models": [model_id],
        })
        updated = True
    next_providers.append(item)

if not updated:
    next_providers.append({
        "name": provider_name,
        "base_url": base_url,
        "api_key": api_key,
        "api_mode": api_mode,
        "models": [model_id],
    })

data["custom_providers"] = next_providers

routing = data.get("smart_model_routing")
if not isinstance(routing, dict):
    routing = {}
data["smart_model_routing"] = routing
routing["enabled"] = False

config_path.parent.mkdir(parents=True, exist_ok=True)
with config_path.open("w", encoding="utf-8") as fh:
    yaml.safe_dump(data, fh, allow_unicode=True, sort_keys=False)
PY
  chmod 600 "$HERMES_CONFIG_FILE" 2>/dev/null || true
}

write_config() {
  local api_key="$1"
  local python_bin=""

  backup_if_exists "$HERMES_CONFIG_FILE"

  if python_bin="$(python_with_yaml 2>/dev/null)"; then
    merge_config_with_python "$python_bin" "$api_key"
    say "已使用 $python_bin 安全合并 Hermes 配置。"
    return
  fi

  if [ -s "$HERMES_CONFIG_FILE" ] && [ "$FORCE_OVERWRITE" != "1" ]; then
    say "检测到已有 Hermes 配置，但当前环境没有 PyYAML，无法安全合并。"
    say "建议执行：python3 -m pip install PyYAML"
    if ! confirm_yes "是否改为备份后覆盖写入 VSIX 最小配置？[y/N]: "; then
      say "已取消写入。"
      exit 1
    fi
  fi

  write_minimal_config "$api_key"
}

detect_hermes() {
  if command -v hermes >/dev/null 2>&1; then
    say "Hermes 已安装：$(command -v hermes)"
    return 0
  fi

  say "未检测到 hermes 命令。本脚本只写入配置，不会自动安装或重装 Hermes。"
  return 1
}

launch_hermes() {
  if ! command -v hermes >/dev/null 2>&1; then
    say "配置完成后，请在安装 Hermes 的环境中重启 Hermes。"
    return
  fi

  if confirm_yes "是否立即启动 Hermes？[y/N]: "; then
    if [ -r /dev/tty ]; then
      exec </dev/tty
    fi
    exec hermes
  fi

  say "已跳过启动。需要使用时运行：hermes"
}

main() {
  say "VSIX Hermes 交互式配置"
  say ""
  say "接口地址：$HERMES_BASE_URL"
  say "默认模型：$HERMES_MODEL"
  say "Provider：$HERMES_PROVIDER_NAME"
  say "配置文件：$HERMES_CONFIG_FILE"
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
    say "[dry-run] 将写入：$HERMES_CONFIG_FILE"
    say "[dry-run] base_url：$HERMES_BASE_URL"
    say "[dry-run] model：$HERMES_MODEL"
    say "[dry-run] provider：$HERMES_PROVIDER_NAME"
    return
  fi

  write_config "$api_key"

  say ""
  say "Hermes 配置已写入：$HERMES_CONFIG_FILE"
  say "如果 Hermes 已经在运行，请重启 Hermes 后再使用。"
  say ""
  say "你也可以先直接测试 VSIX Anthropic 端点："
  say "  curl -X POST \"$HERMES_BASE_URL/v1/messages\" -H \"Content-Type: application/json\" -H \"x-api-key: ***\" -H \"anthropic-version: 2023-06-01\" -d '{\"model\":\"$HERMES_MODEL\",\"max_tokens\":50,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}'"
  say ""

  detect_hermes || true
  launch_hermes
}

main "$@"
