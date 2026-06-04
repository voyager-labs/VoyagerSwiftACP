func codexModelsWithThinkingJSON() -> String {
    """
    {
      "models": [
        {
          "slug": "gpt-5.5",
          "display_name": "GPT-5.5",
          "supported_reasoning_levels": [
            { "effort": "low", "description": "Low" },
            { "effort": "medium", "description": "Medium" },
            { "effort": "high", "description": "High" }
          ],
          "default_reasoning_level": "medium",
          "hidden": false
        },
        {
          "slug": "gpt-5.3-codex-spark",
          "display_name": "GPT-5.3 Codex Spark",
          "hidden": false
        },
        {
          "slug": "gpt-5.4",
          "display_name": "GPT-5.4",
          "hidden": true
        }
      ]
    }
    """
}

func codexAppServerModelsJSON() -> String {
    """
    {
      "data": [
        {
          "id": "preset-gpt-5.5",
          "model": "gpt-5.5",
          "displayName": "GPT-5.5",
          "hidden": true,
          "supportedReasoningEfforts": [
            { "reasoningEffort": "minimal", "description": "Minimal" },
            { "reasoningEffort": "xhigh", "description": "Extra high" }
          ],
          "defaultReasoningEffort": "xhigh"
        },
        {
          "id": "internal-disabled",
          "model": "internal-disabled",
          "displayName": "Internal Disabled",
          "visibility": "none"
        },
        {
          "model": "gpt-5.4-mini",
          "display_name": "GPT-5.4 mini",
          "supported_reasoning_efforts": ["low", "medium", "high"],
          "default_reasoning_effort": "medium"
        }
      ]
    }
    """
}

func codexSingleModelJSON() -> String {
    """
    {
      "models": [
        {
          "slug": "gpt-5.2",
          "display_name": "gpt-5.2"
        }
      ]
    }
    """
}

func openAIModelsJSON() -> String {
    """
    {
      "data": [
        { "id": "gpt-4.1" },
        { "id": "gpt-5.1" },
        { "id": "gpt-5-pro" },
        { "id": "gpt-5.5" },
        { "id": "o4-mini" },
        { "id": "custom-openai-model" }
      ]
    }
    """
}

func openAIModelsWithReasoningMetadataJSON() -> String {
    """
    {
      "data": [
        {
          "id": "gpt-5.5",
          "supported_reasoning_efforts": ["none", "low", "high"],
          "default_reasoning_effort": "high"
        },
        {
          "id": "custom-reasoning-model",
          "supportedReasoningEfforts": [
            { "reasoningEffort": "minimal" },
            { "reasoningEffort": "medium" }
          ],
          "defaultReasoningEffort": "xhigh"
        }
      ]
    }
    """
}

func anthropicModelsJSON() -> String {
    """
    {
      "data": [
        {
          "id": "claude-sonnet-4-5",
          "display_name": "Claude Sonnet 4.5",
          "capabilities": {
            "thinking": {
              "supported": true,
              "types": {
                "enabled": { "supported": true }
              }
            },
            "effort": {
              "supported": true,
              "low": { "supported": true },
              "medium": { "supported": true },
              "high": { "supported": true },
              "xhigh": { "supported": false },
              "max": { "supported": true }
            }
          }
        },
        {
          "id": "claude-adaptive",
          "display_name": "Claude Adaptive",
          "capabilities": {
            "thinking": {
              "supported": true,
              "types": {
                "adaptive": { "supported": true }
              }
            },
            "effort": {
              "supported": false,
              "low": { "supported": true },
              "high": { "supported": true }
            }
          }
        },
        { "id": "claude-custom" }
      ]
    }
    """
}
