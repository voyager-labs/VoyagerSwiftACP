// Portions adapted from Conduit (MIT License).
// Original: Sources/Conduit/Providers/Anthropic/AnthropicProvider.swift
// Commit: bd57239663e63c3ad28647a73ae761a7aa46e123

import Foundation

/// Capability presets for the direct Anthropic adapter.
public enum AnthropicCapabilities {
    /// Full capabilities for modern Claude models.
    public static let full: AIProviderCapability = [
        .textGeneration,
        .streaming,
        .toolCalling,
        .structuredOutput,
        .parallelToolCalls,
        .usageReporting,
        .reasoning,
    ]

    /// Standard capabilities for Claude models.
    public static let standard: AIProviderCapability = [
        .textGeneration,
        .streaming,
        .toolCalling,
        .parallelToolCalls,
        .usageReporting,
    ]

    /// Minimal text-only capabilities.
    public static let minimal: AIProviderCapability = [
        .textGeneration,
        .usageReporting,
    ]
}
