import Foundation

enum ClaudeAgentRunnerError: LocalizedError {
    case executableNotFound(String)
    case executionFailed(String)
    case nonZeroExit(Int32, String)
    case authenticationRequired(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            return "未找到 Claude 可执行文件: \(path)"
        case .executionFailed(let reason):
            return "Claude 执行失败: \(reason)"
        case .nonZeroExit(let code, let message):
            return "Claude 退出码 \(code): \(message)"
        case .authenticationRequired(let message):
            return message
        }
    }
}

struct ClaudeRunResult {
    let output: String
    let errorOutput: String
    let exitCode: Int32
}

final class ClaudeAgentRunner {
    func run(prompt: String, executablePath: String) async throws -> ClaudeRunResult {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw ClaudeAgentRunnerError.executableNotFound(executablePath)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["-p", prompt]

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { _ in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
                let code = process.terminationStatus
                let combinedOutput = [output, errorOutput]
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")

                if let authMessage = self.authenticationErrorMessage(from: combinedOutput) {
                    continuation.resume(throwing: ClaudeAgentRunnerError.authenticationRequired(authMessage))
                    return
                }

                if code == 0 {
                    continuation.resume(returning: ClaudeRunResult(output: output, errorOutput: errorOutput, exitCode: code))
                } else {
                    continuation.resume(throwing: ClaudeAgentRunnerError.nonZeroExit(code, errorOutput.isEmpty ? output : errorOutput))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: ClaudeAgentRunnerError.executionFailed(error.localizedDescription))
            }
        }
    }

    private func authenticationErrorMessage(from output: String) -> String? {
        let normalized = output
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        let lowercased = normalized.lowercased()
        let isAuthPrompt =
            lowercased.contains("connect your account to continue") ||
            lowercased.contains("please run claude login") ||
            lowercased.contains("please run `claude login`") ||
            lowercased.contains("authentication required")
        guard isAuthPrompt else {
            return nil
        }

        let snippetLimit = 200
        let snippet = normalized.count > snippetLimit
            ? String(normalized.prefix(snippetLimit)) + "…"
            : normalized
        return "Claude CLI 尚未完成登录，请先在终端执行 `claude login` 后重试。CLI 输出：\(snippet)"
    }
}
