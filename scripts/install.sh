#!/bin/zsh -f
set -euo pipefail
project_root="${0:A:h:h}"
for name in 'Codex 配置切换器.app' 'codex-company.app'; do
  if [[ ! -d "$project_root/dist/$name" ]]; then
    print -u2 '请先执行 ./scripts/build.sh。'
    exit 1
  fi
done
if [[ ! -w /Applications ]]; then
  print -u2 '当前用户无法写入 /Applications，请通过 Finder 复制 dist 中的应用。'
  exit 1
fi
if pgrep -x CodexSwitcher >/dev/null; then
  print -u2 '请先退出 Codex 配置切换器，然后重新安装。'
  exit 1
fi
backup_dir="$HOME/Library/Application Support/codex-switcher/install-backups/$(date +%Y%m%d-%H%M%S)-$$"
for name in 'Codex 配置切换器.app' 'codex-company.app'; do
  if [[ -e "/Applications/$name" ]]; then
    mkdir -p "$backup_dir"
    mv "/Applications/$name" "$backup_dir/$name"
  fi
  ditto "$project_root/dist/$name" "/Applications/$name"
  codesign --verify --strict "/Applications/$name"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$name"
done
print '已安装到 /Applications，现有配置和钥匙串保持原样。'

