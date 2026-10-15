#!/bin/zsh -f
set -euo pipefail
umask 077
project_root="${0:A:h:h}"
company_settings="$HOME/.config/codex-switcher/cli.zsh"
mkdir -p "$HOME/.config/codex-switcher"
if [[ ! -e "$company_settings" ]]; then
  cp "$project_root/launcher/cli.example.zsh" "$company_settings"
  print "已创建示例，请填写实际网关后重新执行：$company_settings"
  exit 0
fi
source "$company_settings"
company_root="${COMPANY_CODEX_ROOT:-$HOME/Documents/Codex/company-codex}"
company_gateway="${COMPANY_CODEX_GATEWAY:-}"
/usr/bin/python3 - "$company_root/home/config.toml" "$company_gateway" "$project_root/launcher/config.example.toml" <<'PY'
import json
from pathlib import Path
import sys
from urllib.parse import urlsplit
path = Path(sys.argv[1])
url = sys.argv[2].rstrip('/')
try:
    parsed = urlsplit(url)
    valid = (parsed.scheme in ('http', 'https') and parsed.hostname
             and parsed.hostname != 'gateway.example.com'
             and not (parsed.username or parsed.password or parsed.query or parsed.fragment))
except ValueError:
    valid = False
if not valid:
    sys.exit('请先在 cli.zsh 中填写有效的 COMPANY_CODEX_GATEWAY。')
if path.exists():
    print('已有公司 CLI 配置，保留现有内容。')
else:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    content = Path(sys.argv[3]).read_text().replace('"https://gateway.example.com/v1"', json.dumps(url))
    with path.open('x', encoding='utf-8') as stream:
        stream.write(content)
    path.chmod(0o600)
    print('已创建公司 CLI 独立配置。')
PY
