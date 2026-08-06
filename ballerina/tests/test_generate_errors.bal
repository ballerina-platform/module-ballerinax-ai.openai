// Copyright (c) 2025 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/ai;
import ballerina/test;
import ballerinax/openai.responses;

// ===================================================================
// generate() error paths - Chat Completions
// ===================================================================

@test:Config
function testGenerateConnectionError() {
    int|ai:Error result = provider->generate(`TRIGGER_GEN_CONNECTION_ERROR`);
    test:assertTrue(result is ai:Error);
}

@test:Config
function testGenerateEmptyChoices() {
    int|ai:Error result = provider->generate(`TRIGGER_GEN_EMPTY_CHOICES`);
    test:assertTrue(result is ai:Error);
    if result is ai:Error {
        test:assertTrue(result.message().includes("No completion choices"));
    }
}

@test:Config
function testGenerateNoToolCalls() {
    int|ai:Error result = provider->generate(`TRIGGER_GEN_NO_TOOLCALLS`);
    test:assertTrue(result is ai:Error);
    if result is ai:Error {
        test:assertTrue(result.message().includes(NO_RELEVANT_RESPONSE_FROM_THE_LLM));
    }
}

@test:Config
function testGenerateCustomToolUnsupported() {
    int|ai:Error result = provider->generate(`TRIGGER_GEN_CUSTOM_TOOL`);
    test:assertTrue(result is ai:Error);
    if result is ai:Error {
        test:assertTrue(result.message().includes("Custom tools are not supported"));
    }
}

@test:Config
function testGenerateMalformedArgs() {
    int|ai:Error result = provider->generate(`TRIGGER_GEN_MALFORMED_ARGS`);
    test:assertTrue(result is ai:Error);
    if result is ai:Error {
        test:assertTrue(result.message().includes(NO_RELEVANT_RESPONSE_FROM_THE_LLM));
    }
}

// ===================================================================
// generate() error paths - Responses API
// ===================================================================

@test:Config
function testResponsesGenerateConnectionError() {
    int|ai:Error result = responsesProvider->generate(`TRIGGER_GEN_CONNECTION_ERROR`);
    test:assertTrue(result is ai:Error);
}

@test:Config
function testResponsesGenerateNoToolCalls() {
    int|ai:Error result = responsesProvider->generate(`TRIGGER_GEN_NO_TOOLCALLS`);
    test:assertTrue(result is ai:Error);
    if result is ai:Error {
        test:assertTrue(result.message().includes(NO_RELEVANT_RESPONSE_FROM_THE_LLM));
    }
}

@test:Config
function testResponsesGenerateMalformedArgs() {
    int|ai:Error result = responsesProvider->generate(`TRIGGER_GEN_MALFORMED_ARGS`);
    test:assertTrue(result is ai:Error);
    if result is ai:Error {
        test:assertTrue(result.message().includes(NO_RELEVANT_RESPONSE_FROM_THE_LLM));
    }
}

@test:Config
function testResponsesGenerateTypeMismatch() {
    int|ai:Error result = responsesProvider->generate(`TRIGGER_GEN_TYPE_MISMATCH`);
    test:assertTrue(result is ai:Error);
    if result is ai:Error {
        test:assertTrue(result is ai:LlmInvalidGenerationError);
    }
}

// ===================================================================
// Audio content edge cases
// ===================================================================

@test:Config
function testGenerateAudioWithInvalidFormat() {
    ai:AudioDocument aud = {
        content: sampleBinaryData,
        metadata: {"format": "ogg"}
    };
    string|ai:Error result = provider->generate(`Please describe the audio content. ${aud}.`);
    test:assertTrue(result is ai:Error);
    if result is ai:Error {
        test:assertTrue(result.message().includes("specify the audio format"));
    }
}

@test:Config
function testGenerateAudioWithUrlContentUnsupported() {
    ai:AudioDocument aud = {
        content: "https://example.com/audio.mp3",
        metadata: {"format": "mp3"}
    };
    string|ai:Error result = provider->generate(`Please describe the audio content. ${aud}.`);
    test:assertTrue(result is ai:Error);
    if result is ai:Error {
        test:assertTrue(result.message().includes("URL-based audio content is not supported"));
    }
}

@test:Config
function testResponsesGenerateAudioContentGenerationError() {
    // A bad audio format surfaces during content generation (before the HTTP call).
    ai:AudioDocument aud = {
        content: sampleBinaryData,
        metadata: {"format": "ogg"}
    };
    string|ai:Error result = responsesProvider->generate(`Please describe the audio content. ${aud}.`);
    test:assertTrue(result is ai:Error);
}

@test:Config
function testResponsesGenerateAudioNotSupported() {
    // Valid audio passes content generation but is rejected by the Responses API path.
    ai:AudioDocument aud = {
        content: sampleBinaryData,
        metadata: {"format": "mp3"}
    };
    string|ai:Error result = responsesProvider->generate(`Please describe the audio content. ${aud}.`);
    test:assertTrue(result is ai:Error);
    if result is ai:Error {
        test:assertTrue(result.message().includes("Audio input is not supported in the Responses API"));
    }
}

// ===================================================================
// Responses chat() empty-output handling
// ===================================================================

@test:Config
function testResponsesChatEmptyOutput() {
    ai:ChatUserMessage userMsg = {role: "user", content: "TRIGGER_EMPTY_OUTPUT now"};
    ai:ChatAssistantMessage|ai:Error result = responsesProvider->chat(userMsg, []);
    test:assertTrue(result is ai:Error);
    if result is ai:Error {
        test:assertTrue(result.message().includes("Empty response from the model"));
    }
}

// ===================================================================
// Provider initialization - defaults and error paths
// ===================================================================

@test:Config
function testInitWithDefaultServiceUrlAndApiType() returns ai:Error? {
    // Omitting serviceUrl and apiType exercises their default values.
    ModelProvider _ = check new (API_KEY, GPT_4O);
}

@test:Config
function testInitChatCompletionsWithInvalidUrl() {
    ModelProvider|ai:Error result = new (API_KEY, GPT_4_TURBO, "ht tp://invalid url", apiType = CHAT_COMPLETIONS);
    test:assertTrue(result is ai:Error);
}

@test:Config
function testInitResponsesWithInvalidUrl() {
    ModelProvider|ai:Error result = new (API_KEY, GPT_4O, "ht tp://invalid url", apiType = RESPONSES);
    test:assertTrue(result is ai:Error);
}

@test:Config
function testEmbeddingInitWithDefaultServiceUrl() returns ai:Error? {
    EmbeddingProvider _ = check new (API_KEY, TEXT_EMBEDDING_3_SMALL);
}

@test:Config
function testEmbeddingInitWithInvalidUrl() {
    EmbeddingProvider|ai:Error result = new (API_KEY, TEXT_EMBEDDING_3_SMALL, "ht tp://invalid url");
    test:assertTrue(result is ai:Error);
}

// ===================================================================
// convertResponsesOutputToAssistantMessage: args parse-but-not-a-map
// ===================================================================

@test:Config
function testConvertResponsesOutputArgsNotAMap() {
    // Arguments parse as valid JSON (a number) but not as a map<json>.
    responses:Response response = buildFunctionCallResponse("get_weather", "42", "call_num");
    ai:ChatAssistantMessage|ai:Error msg = convertResponsesOutputToAssistantMessage(response);
    test:assertTrue(msg is ai:Error);
}
