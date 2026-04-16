// Portions adapted from Conduit (MIT License).
// Original: Sources/Conduit/Core/Tools/ToolExecutor.swift
// Commit: bd57239663e63c3ad28647a73ae761a7aa46e123

import Foundation

/// Protocol for AI tools that can be executed by ``AIToolExecutor``.
public protocol AITool: Sendable {
    var name: String { get }
    var description: String { get }
    var inputSchema: [String: Any]? { get }
    func execute(arguments: String) async throws -> String
}

/// Handles tool execution errors.
public enum AIToolExecutionError: Error, Sendable, Equatable {
    case toolNotFound(String)
    case invalidArguments(String)
    case executionFailed(String)
}

/// Manages tool registration and execution.
///
/// Trimmed from Conduit's ToolExecutor to match Voyager patterns:
/// - No actor isolation (Voyager uses TCA for concurrency)
/// - Uses Voyager-owned ``AIToolCall`` type
/// - Simplified retry/error handling
public final class AIToolExecutor: Sendable {
    private var tools: [String: any AITool] = [:]

    public init() {}

    /// Registers a tool.
    public func register(_ tool: any AITool) {
        tools[tool.name] = tool
    }

    /// Unregisters a tool.
    @discardableResult
    public func unregister(name: String) -> Bool {
        tools.removeValue(forKey: name) != nil
    }

    /// Returns all registered tool names.
    public var registeredToolNames: [String] {
        Array(tools.keys)
    }

    /// Executes a tool call.
    public func execute(toolCall: AIToolCall) async throws -> AIToolResult {
        guard let tool = tools[toolCall.name] else {
            throw AIToolExecutionError.toolNotFound(toolCall.name)
        }

        do {
            let result = try await tool.execute(arguments: toolCall.arguments)
            return AIToolResult(id: toolCall.id, content: result, isSuccess: true)
        } catch {
            return AIToolResult(id: toolCall.id, content: error.localizedDescription, isSuccess: false)
        }
    }

    /// Executes multiple tool calls concurrently.
    public func execute(toolCalls: [AIToolCall]) async throws -> [AIToolResult] {
        try await withThrowingTaskGroup(of: (Int, AIToolResult).self) { group in
            for (index, call) in toolCalls.enumerated() {
                group.addTask { [weak self] in
                    guard let self else { throw CancellationError() }
                    let result = try await execute(toolCall: call)
                    return (index, result)
                }
            }

            var results: [(Int, AIToolResult)] = []
            for try await result in group {
                results.append(result)
            }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
