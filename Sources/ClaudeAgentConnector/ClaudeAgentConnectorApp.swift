import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct ClaudeAgentConnectorApp: App {
    @StateObject private var viewModel = AppViewModel()
    #if os(macOS)
    @State private var statusBarController: StatusBarController?
    #endif

    var body: some Scene {
        WindowGroup {
            MainView(viewModel: viewModel)
                .frame(minWidth: 1000, minHeight: 700)
                .onAppear {
                    #if os(macOS)
                    if statusBarController == nil {
                        statusBarController = StatusBarController {
                            NSApp.activate(ignoringOtherApps: true)
                            NSApp.windows.first?.makeKeyAndOrderFront(nil)
                        }
                    }
                    statusBarController?.updateConnectionState(isConnected: viewModel.isConnected)
                    #endif
                }
                .onChange(of: viewModel.isConnected) { _, connected in
                    #if os(macOS)
                    statusBarController?.updateConnectionState(isConnected: connected)
                    #endif
                }
        }
    }
}
