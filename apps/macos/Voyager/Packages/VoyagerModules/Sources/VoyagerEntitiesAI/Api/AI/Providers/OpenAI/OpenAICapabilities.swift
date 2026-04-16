// Portions adapted from Conduit (MIT License).
// Original: Sources/Conduit/Providers/OpenAI/OpenAICapabilities.swift
// Commit: bd57239663e63c3ad28647a73ae761a7aa46e123

import Foundation

/// Capability presets for the direct OpenAI adapter.
///
/// Use these to configure ``OpenAIAdapter`` with the correct
/// feature set for the target OpenAI model.
public enum OpenAICapabilities {
    /// Full capabilities for modern OpenAI models (GPT-4o, o1, etc.).
    public static let full: AIProviderCapability = [
        .textGeneration,
        .streaming,
        .toolCalling,
        .structuredOutput,
        .parallelToolCalls,
        .usageReporting,
        .reasoning,
    ]

    /// Standard capabilities for most OpenAI models.
    public static let standard: AIProviderCapability = [
        .textGeneration,
        .streaming,
        .toolCalling,
        .structuredOutput,
        .parallelToolCalls,
        .usageReporting,
    ]

    /// Minimal capabilities for basic text-only generation.
    public static let minimal: AIProviderCapability = [
        .textGeneration,
        .usageReporting,
    ]
}
