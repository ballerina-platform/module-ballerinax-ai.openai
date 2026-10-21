# Change Log

This file documents all significant changes made to the Ballerina ai.openai package across releases.

## [Un-released]

### Added
- [Add support for the OpenAI Responses API, selectable through the `apiType` configuration](https://github.com/wso2/product-ballerina-integrator/issues/2457)
- [Add the current OpenAI model families to `OPEN_AI_MODEL_NAMES`: `gpt-5.6`, `gpt-5.5`, `gpt-5.5-pro`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.4-nano`, `gpt-5.4-pro` and `gpt-5.3-codex`](https://github.com/wso2/product-ballerina-integrator/issues/2457)
- [Add a `reasoningEffort` initialization parameter for reasoning-capable models, applied on both the Chat Completions (`reasoning_effort`) and the Responses (`reasoning.effort`) APIs, matching `ai.azure`](https://github.com/wso2/product-ballerina-integrator/issues/2457)
- [Validate `reasoningEffort` against the selected model at initialization, so an unsupported effort fails fast instead of being rejected by OpenAI on the first call](https://github.com/wso2/product-ballerina-integrator/issues/2457)

### Removed
- [Remove the models OpenAI has already shut down from `OPEN_AI_MODEL_NAMES`: `gpt-4-0125-preview`, `gpt-4-turbo-preview`, `gpt-3.5-turbo-16k`, `gpt-3.5-turbo-1106`, `o1-mini`, `gpt-4o-audio-preview`, `chatgpt-4o-latest`, `computer-use-preview`, `codex-mini-latest`, `gpt-5-codex`, `gpt-5.1-codex`, `gpt-5.1-codex-mini`, `gpt-5.1-codex-max`, `gpt-5.2-codex`, the `gpt-5*-chat-latest` variants, and the models retired on 2026-10-23: `gpt-4o-2024-05-13`, `gpt-4-turbo`, `gpt-4-turbo-2024-04-09`, `gpt-4-1106-preview`, `gpt-4-0613`, `gpt-3.5-turbo`, `gpt-3.5-turbo-0125`, `o1`, `o1-2024-12-17`, `o1-pro`, `o1-pro-2025-03-19`, `o3-mini`, `o4-mini`, `gpt-4.1-nano` and `gpt-4.1-nano-2025-04-14`. Models with a later announced shutdown are kept](https://github.com/wso2/product-ballerina-integrator/issues/2457)

### Updated
- [Update batchEmbed to Validate Chunks at Element Level](https://github.com/ballerina-platform/ballerina-library/issues/8171)
- [`apiType` now defaults to `CHAT_COMPLETIONS`; the Responses API is opt-in](https://github.com/wso2/product-ballerina-integrator/issues/2457)
- [Passing `stop` with `apiType = RESPONSES` now returns an `ai:Error` instead of being silently dropped, as the Responses API has no stop-sequence parameter](https://github.com/wso2/product-ballerina-integrator/issues/2457)
- [`generate()` now applies `reasoningEffort` on both the Chat Completions and the Responses API, matching `chat()`](https://github.com/wso2/product-ballerina-integrator/issues/2457)

## [1.2.1] - 2025-07-27

### Added
- [Add `batchEmbed` API in `EmbeddingProvider`](https://github.com/ballerina-platform/ballerina-library/issues/8110)
- Bump AI module dependency version to 1.1.0

## [1.0.0] - 2025-07-09

### Added
- Add Implementations for ModelProvider and EmbeddingProvider
