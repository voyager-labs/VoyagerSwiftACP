// Portions adapted from Swift AI SDK (Apache-2.0).
// Original: Sources/OpenAICompatibleProvider/OpenAICompatibleProvider.swift
// Commit: 88225c3fa3544e30fe361ca4aa03c4a60c7444ec

import Foundation

/// Capability presets for OpenAI-compatible providers.
///
/// Use these to configure ``OpenAICompatibleAdapter`` with the correct
/// feature set for the target provider.
public enum OpenAICompatibleCapabilities {
    /// Capabilities assumed for all OpenAI-compatible providers.
    public static let `default`: AIProviderCapability = [
        .textGeneration,
        .streaming,
        .usageReporting,
    ]

    /// Full capabilities for providers that support all features.
    public static let full: AIProviderCapability = [
        .textGeneration,
        .streaming,
        .toolCalling,
        .structuredOutput,
        .parallelToolCalls,
        .usageReporting,
    ]

    /// Minimal capabilities for basic providers (no streaming, no tools).
    public static let minimal: AIProviderCapability = [
        .textGeneration,
        .usageReporting,
    ]
}
