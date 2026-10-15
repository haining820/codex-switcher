import AppKit
import SwiftUI

private let appSettings: [String: String] = {
    let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/codex-switcher/settings.json")
    guard let data = try? Data(contentsOf: path),
          let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
    return values
}()
private let desktopApp = appSettings["desktop_app"] ?? "/Applications/ChatGPT.app"
private let desktopBundleID = appSettings["desktop_bundle_id"] ?? "com.openai.codex"
private let companyCLIApp = appSettings["cli_app"] ?? "/Applications/codex-company.app"

struct DesktopStatus: Decodable {
    let mode: String
    let model: String
    let provider: String
}

struct CompanyModel: Decodable, Identifiable {
    let id: String
    let effort: String?
}

enum SwitcherError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let message) = self { return message }
        return nil
    }
}

@MainActor
final class SwitcherController: ObservableObject {
    @Published var status: DesktopStatus?
    @Published var models: [CompanyModel] = []
    @Published var selectedModel = ""
    @Published var loading = false
    @Published var switching = false
    @Published var message = ""
    @Published var isError = false
    @Published var updatedAt: Date?
    var isCompany: Bool { status?.mode == "company" }
    var canSwitch: Bool { status != nil && status?.mode != "custom" && !loading && !switching && (isCompany || !models.isEmpty) }

    func backend(_ arguments: [String]) async throws -> Data {
        guard let script = Bundle.main.resourceURL?.appendingPathComponent("switcher.py") else {
            throw SwitcherError.message("找不到配置组件，请重新安装应用。")
        }
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [script.path] + arguments
            let output = Pipe(), errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "操作失败，请重试。"
                throw SwitcherError.message(message)
            }
            return data
        }.value
    }

    func refreshStatus() async {
        do {
            status = try JSONDecoder().decode(DesktopStatus.self, from: await backend(["status-json"]))
        } catch { report(error) }
    }

    func refreshModels() async {
        guard !loading && !switching else { return }
        loading = true
        defer { loading = false }
        do {
            let newModels = try JSONDecoder().decode([CompanyModel].self, from: await backend(["models-json"]))
            models = newModels
            if !newModels.contains(where: { $0.id == selectedModel }) {
                selectedModel = newModels.contains(where: { $0.id == status?.model }) ? (status?.model ?? "") : (newModels.first?.id ?? "")
            }
            updatedAt = Date()
            if isError { message = ""; isError = false }
        } catch { report(error) }
    }

    func report(_ error: Error) {
        message = error.localizedDescription
        isError = true
    }

    func requestSwitch(to company: Bool) {
        guard !switching else { return }
        if company && selectedModel.isEmpty { report(SwitcherError.message("请先查询并选择公司模型。")); return }
        let alert = NSAlert()
        alert.messageText = company ? "切换到公司模式？" : "切换到个人模式？"
        alert.informativeText = "桌面应用将退出并重新打开，请先等待正在执行的任务结束。\n\n配置会自动备份；公司 CLI 不受影响。"
        alert.addButton(withTitle: "切换并重启")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .informational
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        switching = true
        message = "正在切换配置并重新打开桌面版…"
        isError = false
        Task {
            var closedDesktop = false
            do {
                let applications = NSRunningApplication.runningApplications(withBundleIdentifier: desktopBundleID)
                for application in applications {
                    guard application.terminate() else { throw SwitcherError.message("桌面应用暂时无法退出，请结束任务后重试。") }
                }
                for _ in 0..<150 {
                    if applications.allSatisfy({ $0.isTerminated }) { break }
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
                guard applications.allSatisfy({ $0.isTerminated }) else {
                    throw SwitcherError.message("桌面应用尚未退出，未修改配置。请结束任务后重试。")
                }
                closedDesktop = true
                var args = ["switch", "--mode", company ? "company" : "personal"]
                if company { args += ["--model", selectedModel] }
                _ = try await backend(args)
                await refreshStatus()
                try await openApplication(desktopApp)
                closedDesktop = false
                message = company ? "已切换到公司额度，桌面版已重新打开。" : "已切换到个人套餐，桌面版已重新打开。"
                isError = false
            } catch {
                if closedDesktop { try? await openApplication(desktopApp) }
                report(error)
            }
            switching = false
        }
    }

    func openApplication(_ path: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error = error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    func openCLI() {
        Task {
            do { try await openApplication(companyCLIApp) }
            catch { report(error) }
        }
    }
}

private let accent = Color(red: 0.02, green: 0.46, blue: 0.37)
private let secondary = Color(red: 0.38, green: 0.42, blue: 0.46)
private let primaryText = Color(red: 0.12, green: 0.16, blue: 0.19)

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.black.opacity(0.08), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.035), radius: 14, x: 0, y: 5)
    }
}

struct SwitcherView: View {
    @ObservedObject var controller: SwitcherController
    private var usageDashboardURL: URL? {
        guard let dashboard = appSettings["dashboard_url"],
              let url = URL(string: dashboard),
              ["http", "https"].contains(url.scheme ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
    var body: some View {
        ZStack {
            Color.white
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    if let iconURL = Bundle.main.url(forResource: "SwitcherIcon", withExtension: "icns"),
                       let icon = NSImage(contentsOf: iconURL) {
                        Image(nsImage: icon)
                            .resizable().interpolation(.high).scaledToFit()
                            .frame(width: 100, height: 100)
                            .accessibilityLabel("应用图标")
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        Text("CODEX / CONTROL").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(2.5).foregroundStyle(accent)
                        Text("桌面模式集中管理，公司 CLI 独立运行。")
                            .font(.system(size: 13)).foregroundStyle(secondary)
                    }
                }.padding(.bottom, -16)
                Panel {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Label("桌面版配置", systemImage: "macwindow").font(.system(size: 15, weight: .semibold))
                            Spacer()
                            HStack(spacing: 6) {
                                Circle().fill(controller.status == nil ? Color.gray : accent).frame(width: 6, height: 6)
                                Text(controller.switching ? "切换中" : controller.status == nil ? "读取中" : controller.isCompany ? "公司模式" : controller.status?.mode == "custom" ? "自定义模式" : "个人模式")
                                    .font(.system(size: 11, weight: .medium))
                            }.foregroundStyle(accent).padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(accent.opacity(0.09)))
                        }
                        HStack(spacing: 18) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(controller.isCompany ? "公司额度" : "个人套餐").font(.system(size: 23, weight: .semibold))
                                    if controller.isCompany, let dashboardURL = usageDashboardURL {
                                        Button {
                                            NSWorkspace.shared.open(dashboardURL)
                                        } label: {
                                            Text("查看用量").underline().font(.system(size: 12))
                                        }
                                        .buttonStyle(.plain).foregroundStyle(accent)
                                        .help("使用默认浏览器打开公司额度看板")
                                    }
                                }
                                Text(controller.isCompany ? "通过公司网关处理工作任务" : "使用自己的 ChatGPT 套餐")
                                    .font(.system(size: 12)).foregroundStyle(secondary)
                            }
                            Spacer()
                            VStack(spacing: 6) {
                                Toggle("公司模式", isOn: Binding(get: { controller.isCompany }, set: { controller.requestSwitch(to: $0) }))
                                    .toggleStyle(.switch).tint(accent).labelsHidden()
                                    .disabled(!controller.canSwitch)
                                    .accessibilityLabel("切换公司桌面模式")
                                Text("公司模式").font(.system(size: 10)).foregroundStyle(secondary)
                            }
                        }
                        Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("公司模型").font(.system(size: 12, weight: .medium)).foregroundStyle(primaryText)
                                Spacer()
                                if controller.loading { ProgressView().controlSize(.small).scaleEffect(0.7) }
                                Button { Task { await controller.refreshModels() } } label: {
                                    Label("刷新", systemImage: "arrow.clockwise").font(.system(size: 11))
                                }.buttonStyle(.plain).foregroundStyle(accent).disabled(controller.loading || controller.switching)
                            }
                            if controller.models.isEmpty {
                                HStack {
                                    Text(controller.loading ? "正在实时查询公司模型…" : "模型列表暂未就绪，请点击刷新")
                                        .font(.system(size: 12)).foregroundStyle(secondary)
                                    Spacer()
                                }.frame(height: 30)
                            } else {
                                Picker("公司模型", selection: $controller.selectedModel) {
                                    ForEach(controller.models) { model in Text(model.id).tag(model.id) }
                                }.labelsHidden().pickerStyle(.menu).controlSize(.large)
                                    .frame(maxWidth: .infinity).disabled(controller.switching)
                            }
                            HStack {
                                Text(controller.updatedAt.map { "实时目录 · \(controller.models.count) 个模型 · \($0.formatted(date: .omitted, time: .shortened))" } ?? "连接公司网络后可获取最新模型")
                                    .font(.system(size: 10)).foregroundStyle(secondary)
                                Spacer()
                                if controller.isCompany && controller.selectedModel != controller.status?.model && !controller.selectedModel.isEmpty {
                                    Button("应用模型") { controller.requestSwitch(to: true) }
                                        .font(.system(size: 11)).tint(accent).disabled(controller.switching)
                                }
                            }
                        }
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                            Text("拨动开关后确认重启，桌面版配置才会生效。")
                        }.font(.system(size: 11)).foregroundStyle(secondary)
                    }
                }
                Panel {
                    HStack(spacing: 16) {
                        Image(systemName: "terminal.fill").font(.system(size: 25)).foregroundStyle(accent)
                            .frame(width: 48, height: 48)
                            .background(RoundedRectangle(cornerRadius: 13).fill(accent.opacity(0.08)))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("codex-company").font(.system(size: 16, weight: .semibold, design: .monospaced))
                            Text("公司 CLI · 独立配置，与桌面版并行使用")
                                .font(.system(size: 11)).foregroundStyle(secondary)
                        }
                        Spacer(minLength: 12)
                        Button { controller.openCLI() } label: {
                            HStack(spacing: 7) { Text("打开终端"); Image(systemName: "arrow.up.right") }
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 14).padding(.vertical, 11)
                                .background(RoundedRectangle(cornerRadius: 11).fill(accent))
                                .foregroundStyle(Color.white)
                        }.buttonStyle(.plain).disabled(controller.switching)
                    }
                }
                if !controller.message.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: controller.isError ? "exclamationmark.circle" : "checkmark.circle")
                        Text(controller.message).fixedSize(horizontal: false, vertical: true)
                    }.font(.system(size: 11)).foregroundStyle(controller.isError ? Color(red: 0.75, green: 0.18, blue: 0.12) : accent)
                        .frame(maxHeight: 40, alignment: .topLeading)
                }
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                    Text("自动备份配置 · 凭据安全保存在系统钥匙串")
                    Spacer()
                    Text("SWITCHER 2.0").font(.system(size: 9, design: .monospaced)).tracking(1)
                }.font(.system(size: 10)).foregroundStyle(secondary)
            }.padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 18)
                .frame(maxHeight: .infinity, alignment: .top)
        }.ignoresSafeArea().clipped().foregroundStyle(primaryText).preferredColorScheme(.light)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let controller = SwitcherController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = NSSize(width: 640, height: 550)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Codex 配置切换器"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .white
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: SwitcherView(controller: controller))
        window.contentView = host
        window.center()
        let arguments = CommandLine.arguments
        let rendering = arguments.count == 3 && arguments[1] == "--render-preview"
        if !rendering {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        Task {
            await controller.refreshStatus()
            await controller.refreshModels()
            if rendering {
                try? await Task.sleep(nanoseconds: 500_000_000)
                host.layoutSubtreeIfNeeded()
                guard let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
                host.cacheDisplay(in: host.bounds, to: image)
                guard let png = image.representation(using: .png, properties: [:]) else { exit(1) }
                do { try png.write(to: URL(fileURLWithPath: arguments[2])); exit(0) }
                catch { exit(1) }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }
}

@main
struct SwitcherMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        application.setActivationPolicy(CommandLine.arguments.contains("--render-preview") ? .accessory : .regular)
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}
