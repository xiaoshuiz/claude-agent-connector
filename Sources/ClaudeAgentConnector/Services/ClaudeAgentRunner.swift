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

            let outputHandle = outputPipe.fileHandleForReading
            let errorHandle = errorPipe.fileHandleForReading
            let outputLock = NSLock()
            let errorLock = NSLock()
            var outputData = Data()
            var errorData = Data()
            let streamCompletionGroup = DispatchGroup()
            streamCompletionGroup.enter()
            streamCompletionGroup.enter()

            outputHandle.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    streamCompletionGroup.leave()
                    return
                }
                outputLock.lock()
                outputData.append(chunk)
                outputLock.unlock()
            }

            errorHandle.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    streamCompletionGroup.leave()
                    return
                }
                errorLock.lock()
                errorData.append(chunk)
                errorLock.unlock()
            }

            process.terminationHandler = { _ in
                DispatchQueue.global(qos: .utility).async {
                    streamCompletionGroup.wait()

                    outputLock.lock()
                    let outputSnapshot = outputData
                    outputLock.unlock()

                    errorLock.lock()
                    let errorSnapshot = errorData
                    errorLock.unlock()

                    let output = String(data: outputSnapshot, encoding: .utf8) ?? ""
                    let errorOutput = String(data: errorSnapshot, encoding: .utf8) ?? ""
                    let code = process.terminationStatus

                    if code == 0 {
                        continuation.resume(returning: ClaudeRunResult(output: output, errorOutput: errorOutput, exitCode: code))
                    } else {
                        continuation.resume(throwing: ClaudeAgentRunnerError.nonZeroExit(code, errorOutput.isEmpty ? output : errorOutput))
                    }
                }
            }

            do {
                try process.run()
            } catch {
                outputHandle.readabilityHandler = nil
                errorHandle.readabilityHandler = nil
                continuation.resume(throwing: ClaudeAgentRunnerError.executionFailed(error.localizedDescription))
            }
        }
    }
}
