# Voyager AI Neutral Contracts — Attribution

This directory contains Voyager-owned neutral AI contract types that serve as the
runtime inference layer for AI providers. These types are **not** direct copies of
any upstream library but are informed by the design of two open-source projects.

## Upstream Sources

### Swift AI SDK (Apache-2.0)

- Repository: https://github.com/teunlao/swift-ai-sdk
- Pinned commit: `88225c3fa3544e30fe361ca4aa03c4a60c7444ec`
- License: Apache-2.0
- Classification: S1 (Rewrite-light)
- Influenced types: `AIStreamEvent` (from `LanguageModelV3StreamPart`),
  `AIFinishReason` (from `LanguageModelV3FinishReason`),
  `AIProviderCapability` (from provider capability patterns)

### Conduit (MIT)

- Repository: https://github.com/christopherkarani/Conduit
- Pinned commit: `bd57239663e63c3ad28647a73ae761a7aa46e123`
- License: MIT
- Classification: C1 (Copy/Trim)
- Influenced types: `AIMessage` (from `Message`),
  `AIContentPart` (from `Message.ContentPart`),
  `AIGenerationResult` (from `GenerationResult`),
  `AIUsage` (from `UsageStats`),
  `AIToolCall` (from `Transcript.ToolCall`)

## Design Principles

- All types are Voyager-owned with no upstream type name leakage in public surfaces.
- Types are provider-agnostic: OpenAI, Anthropic, and OpenRouter deltas can all be
  represented without vendor-specific DTO fields.
- Foundation types (`AIProvider`, `ProviderAuthMethod`, etc.) are not duplicated here;
  this layer is the **runtime inference** layer, not the connection-management layer.

## License Compliance

- Apache-2.0: Copyright notice and license text retained in project NOTICE.
- MIT: Copyright notice and license text retained in project NOTICE.
- No source files are verbatim copies; all types are rewritten in Voyager style.
