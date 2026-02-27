import Foundation

enum ClaudeAgentRunnerError: LocalizedError {
    case executableNotFound(String)
    case executionFailed(String)
    case nonZeroExit(Int32, String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            return "未找到 Claude 可执行文件: \(path)"
        case .executionFailed(let reason):
            return "Claude 执行失败: \(reason)"
        case .nonZeroExit(let code, let message):
            return "Claude 退出码 \(code): \(message)"
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
}
