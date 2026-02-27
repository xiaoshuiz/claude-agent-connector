#if os(macOS)
import AppKit

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let onOpenMainWindow: () -> Void

    private let statusMenuItem = NSMenuItem(title: "状态: 未连接", action: nil, keyEquivalent: "")
    private let openMenuItem = NSMenuItem(title: "打开主窗口", action: #selector(handleOpenMainWindow), keyEquivalent: "o")
    private let quitMenuItem = NSMenuItem(title: "退出", action: #selector(handleQuit), keyEquivalent: "q")

    init(onOpenMainWindow: @escaping () -> Void) {
        self.onOpenMainWindow = onOpenMainWindow
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.title = "CAC ○"
        }

        openMenuItem.target = self
        quitMenuItem.target = self

        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(openMenuItem)
        menu.addItem(quitMenuItem)
        statusItem.menu = menu
    }

    func updateConnectionState(isConnected: Bool) {
        statusMenuItem.title = "状态: \(isConnected ? "已连接" : "未连接")"
        statusItem.button?.title = isConnected ? "CAC ●" : "CAC ○"
    }

    @objc
    private func handleOpenMainWindow() {
        onOpenMainWindow()
    }

    @objc
    private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }
}
#endif
