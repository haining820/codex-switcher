# 配置方式

## 桌面设置

先用个人账号打开桌面应用，完成初始设置，确保主配置存在。

```sh
mkdir -p "$HOME/.config/codex-switcher"
cp config/settings.example.json "$HOME/.config/codex-switcher/settings.json"
chmod 600 "$HOME/.config/codex-switcher/settings.json"
```

编辑这份本机文件，填写自己的实际地址。不要把填好的配置复制回仓库。

- `gateway_url`：公司网关的基础地址，支持 HTTP 或 HTTPS，不包含 `/models`、认证信息、查询参数或片段。示例域名不可直接使用。
- `dashboard_url`：可选，用量看板地址；删除此项即可隐藏“查看用量”。使用系统默认浏览器打开，不附加 Token。
- `keychain_service`：Token 所在的钥匙串服务名，默认 `com.example.codex-switcher.gateway`。
- `desktop_app`：桌面应用绝对路径，示例 `/Applications/ChatGPT.app`，按自己的安装位置调整。
- `desktop_bundle_id`：桌面应用的 bundle 标识，示例 `com.openai.codex`，需与实际应用匹配。
- `cli_app`：公司 CLI 应用路径，默认 `/Applications/codex-company.app`。
- `config_path`：可选，默认 `~/.codex/config.toml`。
- `state_dir`：可选，默认 `~/Library/Application Support/codex-switcher`。

所有配置值均为字符串。修改后重新打开切换器。应用路径、标识及网关认证需要与本机安装版本兼容。

## 钥匙串 Token

默认服务名使用下面的命令；自定义了服务名时同步替换 `-s` 的参数。将 `-w` 保留在最后，终端会提示输入密码，此时输入自己的 Token：

```sh
/usr/bin/security add-generic-password -U \
  -a "$(id -un)" \
  -s 'com.example.codex-switcher.gateway' \
  -T /usr/bin/security \
  -w
```

账户使用当前 macOS 用户短名称。更新 Token 时执行同一命令；也可以在“钥匙串访问”中按服务名查找。Token 不应写进源码、配置示例、Git 或普通文档。

## 桌面切换原理

公司模式写入 `company_gateway` provider，基础地址从本机设置读取，认证使用 `/usr/bin/security` 命令从钥匙串获取 Token。此 provider 不再叠加 `env_key` 或 `requires_openai_auth`。

切换前保存个人路由快照及整份配置备份；校验非路由字段没有变化后原子写入。插件、MCP、hooks 等其他字段保留，个人登录凭据文件不被替换。切回个人模式时恢复路由快照并删除切换器自己的 provider。

状态目录包含 `personal-routing.json`、`company-model.json`、`models.json`、`switch.lock` 和 `backups/`。目录权限为 `700`，写入文件为 `600`。完整备份可能含原配置的敏感信息，只保存在本机。

切换器要求所选模型在最近一小时内读取的目录中。实时目录读取成功不代表模型调用和计费已验证。

## 独立 CLI

先生成启动选项示例：

```sh
./scripts/setup-cli.sh
```

第一次运行会创建 `~/.config/codex-switcher/cli.zsh` 并退出。编辑此文件，至少将 `COMPANY_CODEX_GATEWAY` 改为真实地址，再运行一次初始化脚本。

可选字段示例：

```sh
COMPANY_CODEX_GATEWAY='https://gateway.example.com/v1'
COMPANY_CODEX_KEYCHAIN_SERVICE='com.example.codex-switcher.gateway'
COMPANY_CODEX_CLI='/opt/homebrew/bin/codex'
COMPANY_CODEX_NODE='/opt/homebrew/bin/node'
COMPANY_CODEX_PROJECT="$HOME/IdeaProjects"
COMPANY_CODEX_ROOT="$HOME/Documents/Codex/company-codex"
```

上述域名只是占位符，必须替换。CLI 与桌面分别读取本机选项，二者网关和钥匙串服务名应保持一致。CLI 使用 `ADA_API_KEY` 环境变量传入进程中的临时凭据；这个变量名是客户端约定，不包含实际密钥。

默认独立配置为 `$HOME/Documents/Codex/company-codex/home/config.toml`。初始化脚本只在文件不存在时创建配置，不会覆盖已有内容。修改网关后，需同步调整已有独立配置中的 `base_url`。

启动器自动查找 PATH 中的 Codex CLI，随后尝试 nvm 路径。存在多套安装时建议显式指定 CLI 和 Node.js 路径。默认工作目录为 `~/IdeaProjects`，运行时可输入其他绝对路径。

使用切换器的“打开终端”按钮，或直接运行：

```sh
'/Applications/codex-company.app/Contents/Resources/codex-company.command'
```

如需终端快捷命令：

```sh
mkdir -p "$HOME/.local/bin"
ln -s '/Applications/codex-company.app/Contents/Resources/codex-company.command' "$HOME/.local/bin/codex-company"
```

将 `~/.local/bin` 加入 PATH。已有同名链接时先核对目标，不要直接覆盖。

## 恢复和卸载

- 切换失败时先检查网络、凭据、本机设置和版本兼容性。其他自定义 provider 不会被自动覆盖。
- 桌面应用无法退出时，先结束任务后重试。切换器不会强制结束正在运行的任务。
- 恢复个人模式需要原有状态目录。若快照丢失，退出桌面应用并另存当前主配置，再从 `backups/` 选择切换前的个人配置恢复。整份备份也会恢复当时的插件等设置。
- 卸载前先切回个人模式，再删除应用和快捷链接。是否删除会话、备份及钥匙串条目由自己决定。

## 从其他本机版本迁移

此通用版本不会自动安装，也不会接管旧版状态。若旧版本当前处于公司模式，先用旧切换器恢复个人模式，再使用新版本。按上文填写自己的服务地址及钥匙串服务名后构建安装。可以选择继续使用原钥匙串条目，但真实条目名称和网关地址只放在本机配置中。
