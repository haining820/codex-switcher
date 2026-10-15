# Codex 配置切换器

macOS 原生工具，在个人账号与自定义公司网关之间切换桌面配置，同时提供独立公司 CLI 启动入口。

## 功能

- 白色紧凑界面及小狗图标。
- 实时查询兼容网关的模型目录。
- 确认后退出桌面应用、备份并切换配置，再重新打开应用。
- 公司模式显示可配置的“查看用量”链接，使用系统默认浏览器打开。
- Token 存放在 macOS 钥匙串中。
- 公司 CLI 使用独立的 `CODEX_HOME`，可以与个人桌面版并行运行。

## 环境

macOS 13 或更高版本、Xcode Command Line Tools、`/usr/bin/python3`。目前在 Apple Silicon Mac 上验证。CLI 入口另需兼容的 Codex CLI 和 Node.js 22 或更高版本。

如果尚未安装开发工具：

```sh
xcode-select --install
```

## 构建与安装

```sh
./scripts/build.sh
./scripts/install.sh
```

安装前退出配置切换器。构建结果为 `dist/Codex 配置切换器.app` 和 `dist/codex-company.app`，使用本地签名并验证，不会自动切换运行中的桌面配置。已有应用备份到用户的 `Library/Application Support/codex-switcher/install-backups/`。

## 配置与启动

1. 按[配置说明](docs/configuration.md)在仓库外填写网关、桌面应用路径和可选的用量看板地址。
2. 将自己的 Token 保存到系统钥匙串。
3. 打开切换器，选择模型后拨动开关，确认重启桌面应用。
4. 如需独立 CLI，再配置并运行 `scripts/setup-cli.sh`。

仓库里的域名均为示例，不是可用服务。没有配置真实网关时，模型查询会提示先完成配置。网关需要支持所用 Codex 版本的 Responses 协议、Bearer 认证和 `/models` 目录；不同服务的兼容情况需自行验证。

## 源码结构

```text
src/Switcher.swift           原生界面、应用控制与默认浏览器入口
src/switcher.py             配置切换、备份、凭据读取及模型目录
src/settings.py             本机配置加载与网关地址校验
src/vendor/                 内置 tomlkit 0.13.3
config/                     不含真实服务地址的配置示例
launcher/                   公司 CLI 启动器及独立配置模板
assets/                     图标和 Info.plist
scripts/                    构建、安装及 CLI 初始化
tests/                      离线配置与模型菜单测试
```

修改配置示例不影响已经安装的应用或本机配置；修改源码后需重新构建、安装。

## 测试

```sh
/usr/bin/python3 tests/test_switcher.py
node --test tests/company-models.test.mjs
```

测试使用临时配置，不读取真实 Token、不连接网关、不修改桌面配置。

## 隔离范围

桌面开关修改主配置中的路由字段，同一桌面应用仍共用本地历史。CLI 使用独立配置及会话目录。两者处于同一个 macOS 用户下，仍能够访问相同文件。

普通 `codex` 命令默认跟随主配置，通过公司启动器启动时才使用独立目录。

## 对外分享

本仓库只保存通用源码及示例。真实服务地址、Token、个人配置、备份和会话应放在用户目录中。提交前检查 Git 暂存内容；`.gitignore` 只能防止部分误提交，不能清除已提交文件或历史。

许可证见仓库已有的 [LICENSE](LICENSE)，第三方声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
