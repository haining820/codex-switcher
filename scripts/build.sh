#!/bin/zsh -f
set -euo pipefail
project_root="${0:A:h:h}"
build_dir="$project_root/build"
dist_dir="$project_root/dist"
switcher_app="$dist_dir/Codex 配置切换器.app"
launcher_app="$dist_dir/codex-company.app"
mkdir -p "$build_dir/swift-module-cache" "$dist_dir"

# 每次构建全新应用包，避免旧签名或旧可执行文件残留。
for app in "$switcher_app" "$launcher_app"; do
  if [[ -e "$app" ]]; then
    mv "$app" "$build_dir/$(basename "$app").previous.$(date +%Y%m%d%H%M%S).$$"
  fi
done
mkdir -p "$switcher_app/Contents/MacOS" "$switcher_app/Contents/Resources"
xcrun swiftc -swift-version 5 -parse-as-library -O \
  -module-cache-path "$build_dir/swift-module-cache" \
  -framework SwiftUI -framework AppKit \
  "$project_root/src/Switcher.swift" -o "$switcher_app/Contents/MacOS/CodexSwitcher"
cp "$project_root/assets/Info.plist" "$switcher_app/Contents/Info.plist"
cp "$project_root/assets/SwitcherIcon.icns" "$switcher_app/Contents/Resources/"
cp "$project_root/src/switcher.py" "$project_root/src/settings.py" "$switcher_app/Contents/Resources/"
ditto "$project_root/src/vendor" "$switcher_app/Contents/Resources/vendor"
printf 'APPL????' > "$switcher_app/Contents/PkgInfo"

osacompile -o "$launcher_app" "$project_root/launcher/launcher.applescript"
cp "$project_root/launcher/codex-company.command" "$project_root/launcher/company-models.mjs" "$launcher_app/Contents/Resources/"
chmod +x "$launcher_app/Contents/Resources/codex-company.command"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName codex-company' "$launcher_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.example.codex-company' "$launcher_app/Contents/Info.plist"
for app in "$switcher_app" "$launcher_app"; do
  codesign --force --sign - "$app"
  codesign --verify --strict "$app"
done
print "构建完成：$dist_dir"

