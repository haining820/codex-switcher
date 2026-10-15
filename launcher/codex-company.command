#!/bin/zsh -f
set -eu
umask 077

company_settings="$HOME/.config/codex-switcher/cli.zsh"
if [[ -f "$company_settings" ]]; then
  source "$company_settings"
fi
company_root="${COMPANY_CODEX_ROOT:-$HOME/Documents/Codex/company-codex}"
company_default_project="${COMPANY_CODEX_PROJECT:-$HOME/IdeaProjects}"
company_state_dir="$company_root/home"
company_cli="${COMPANY_CODEX_CLI:-$(command -v codex || true)}"
if [[ -z "$company_cli" ]]; then
  company_candidates=("$HOME"/.nvm/versions/node/*/bin/codex(N))
  company_cli="${company_candidates[-1]:-}"
fi
company_node="${COMPANY_CODEX_NODE:-${company_cli:h}/node}"
if [[ ! -x "$company_node" ]]; then
  company_node="$(command -v node || true)"
fi
company_helper="${0:A:h}/company-models.mjs"

if [[ ! -x "$company_cli" ]]; then
  print -u2 '未找到原有 Codex CLI，请重新确认安装路径。'
  exit 1
fi
if [[ ! -f "$company_state_dir/config.toml" ]]; then
  print -u2 '未找到公司独立配置，请恢复配置后再启动。'
  exit 1
fi

# 只作用于此启动器及其子进程，不改变其他终端或桌面应用。
unset OPENAI_API_KEY OPENAI_BASE_URL CODEX_API_KEY ADA_API_KEY CODEX_SQLITE_HOME
export PATH="${company_cli:h}:$PATH"

if [[ "${1:-}" == '--check' ]]; then
  exec env CODEX_HOME="$company_state_dir" "$company_cli" features list
fi

if [[ -z "${COMPANY_CODEX_GATEWAY:-}" || "$COMPANY_CODEX_GATEWAY" == 'https://gateway.example.com/v1' ]]; then
  print -u2 '请先在 ~/.config/codex-switcher/cli.zsh 中填写 COMPANY_CODEX_GATEWAY。'
  exit 1
fi
export COMPANY_CODEX_GATEWAY
company_keychain_service="${COMPANY_CODEX_KEYCHAIN_SERVICE:-com.example.codex-switcher.gateway}"

print '公司 Codex：使用 公司网关 网关，配置与个人桌面版分开。'
print '请先连接公司网络或 VPN。默认 Token 从 macOS 钥匙串读取。'
print '启动时实时获取模型，输入编号选择；回车默认使用上次选择的模型。'
print 'Codex 内部 /model 菜单可能显示内置列表；切换公司模型请重新打开本应用。'
company_token=$(/usr/bin/security find-generic-password \
  -a "$(id -un)" -s "$company_keychain_service" -w 2>/dev/null) || company_token=''
if [[ -z "$company_token" ]]; then
  print '未能读取钥匙串，请解锁钥匙串或临时输入 Token。'
  read -rs 'company_token?公司 公司网关 Token（输入隐藏，仅本次使用）：'
  print
else
  print '已从系统钥匙串读取公司 Token。'
fi
if [[ -z "$company_token" ]]; then
  print -u2 'Token 不能为空。'
  exit 1
fi
export ADA_API_KEY="$company_token"
unset company_token

if [[ ! -x "$company_node" || ! -f "$company_helper" ]]; then
  print -u2 '缺少模型选择组件，请重新安装 codex-company。'
  exit 1
fi
company_model=$("$company_node" "$company_helper" "$company_state_dir") || exit 1
if [[ -z "$company_model" ]]; then
  print '已取消启动。'
  exit 0
fi
read -r "company_project?工作项目绝对路径（回车使用 $company_default_project）："
company_project="${company_project:-$company_default_project}"
if [[ "$company_project" != /* || ! -d "$company_project" ]]; then
  print -u2 '工作项目必须是存在的绝对目录路径。'
  exit 1
fi

exec env CODEX_HOME="$company_state_dir" "$company_cli" \
  --no-daemon --strict-config \
  --model "$company_model" \
  --cd "$company_project" \
  --sandbox workspace-write --ask-for-approval on-request
