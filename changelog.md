# Change Log

This file documents all significant changes made to the Ballerina ai.openai package across releases.

## [Un-released]

### Added
- Add the current OpenAI model families to `OPEN_AI_MODEL_NAMES`: `gpt-5.6` (`sol`, `terra`, `luna`), `gpt-5.5`, `gpt-5.5-pro`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.4-nano`, `gpt-5.4-pro` and `gpt-5.3-codex`
- Validate the `reasoning` configuration against the selected model at initialization, so an unsupported effort fails fast instead of being rejected by OpenAI on the first call

### Updated
- [Update batchEmbed to Validate Chunks at Element Level](https://github.com/ballerina-platform/ballerina-library/issues/8171)
- `apiType` now defaults to `CHAT_COMPLETIONS`; the Responses API is opt-in
- Passing `stop` with `apiType = RESPONSES` now returns an `ai:Error` instead of being silently dropped, as the Responses API has no stop-sequence parameter
- `generate()` now applies the `reasoning` configuration on both the Chat Completions and the Responses API, matching `chat()`

## [1.2.1] - 2025-07-27

### Added
- [Add `batchEmbed` API in `EmbeddingProvider`](https://github.com/ballerina-platform/ballerina-library/issues/8110)
- Bump AI module dependency version to 1.1.0

## [1.0.0] - 2025-07-09

### Added
- Add Implementations for ModelProvider and EmbeddingProvider
