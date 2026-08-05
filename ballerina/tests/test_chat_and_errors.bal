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

// Provider using the ReAct flow (model without native tool-call support) over Chat Completions.
final ModelProvider reactProvider = check new (API_KEY, CHATGPT_4O_LATEST, SERVICE_URL, apiType = CHAT_COMPLETIONS);
// Reasoning-capable provider over the Responses API.
final ModelProvider reasoningProvider = check new (API_KEY, GPT_5, SERVICE_URL,
        reasoningEffort = "low", apiType = RESPONSES);
// Provider with temperature disabled.
final ModelProvider noTempProvider = check new (API_KEY, GPT_4_TURBO, SERVICE_URL,
        temperature = (), apiType = CHAT_COMPLETIONS);
// Reasoning-capable provider over the Chat Completions API.
final ModelProvider chatReasoningProvider = check new (API_KEY, GPT_5, SERVICE_URL,
        reasoningEffort = "low", apiType = CHAT_COMPLETIONS);

final ai:ChatCompletionFunctions[] weatherTool = [
    {
        name: "get_weather",
        description: "Get the weather for a city",
        parameters: {
            "type": "object",
            "properties": {"city": {"type": "string"}},
            "required": ["city"]
        }
    }
];

// ===================================================================
// Chat Completions chat() tests
// ===================================================================

@test:Config
function testChatCompletionsChatWithTools() returns ai:Error? {
    ai:ChatUserMessage userMsg = {role: "user", content: "What is the weather in London?"};
    ai:ChatAssistantMessage result = check provider->chat(userMsg, weatherTool);
    ai:FunctionCall[]? toolCalls = result.toolCalls;
    test:assertTrue(toolCalls is ai:FunctionCall[]);
    if toolCalls is ai:FunctionCall[] {
        test:assertEquals(toolCalls[0].name, "get_weather");
        test:assertEquals(toolCalls[0].arguments, {"city": "London"});
    }
}

@test:Config
function testChatCompletionsChatWithAllMessageTypes() returns ai:Error? {
    ai:ChatMessage[] messages = [
        <ai:ChatSystemMessage>{role: "system", content: "You are a helpful assistant."},
        <ai:ChatUserMessage>{role: "user", content: "What is the weather?"},
        <ai:ChatAssistantMessage>{
            role: "assistant",
            content: "Checking the weather.",
            toolCalls: [{id: "call_1", name: "get_weather", arguments: {"city": "London"}}]
        },
        <ai:ChatFunctionMessage>{role: "function", name: "get_weather", id: "call_1", content: "sunny"}
    ];
    ai:ChatAssistantMessage result = check provider->chat(messages, weatherTool);
    ai:FunctionCall[]? toolCalls = result.toolCalls;
    test:assertTrue(toolCalls is ai:FunctionCall[]);
}

@test:Config
function testChatCompletionsChatWithStopSequence() returns ai:Error? {
    ai:ChatUserMessage userMsg = {role: "user", content: "Hello, how are you?"};
    ai:ChatAssistantMessage result = check provider->chat(userMsg, [], "STOP");
    test:assertEquals(result.content, "This is a mock response for: Hello, how are you?");
}

@test:Config
function testChatCompletionsChatWithNoTemperature() returns ai:Error? {
    ai:ChatUserMessage userMsg = {role: "user", content: "Hello, how are you?"};
    ai:ChatAssistantMessage result = check noTempProvider->chat(userMsg, []);
    test:assertEquals(result.content, "This is a mock response for: Hello, how are you?");
}

@test:Config
function testChatCompletionsChatConnectionError() {
    ai:ChatUserMessage userMsg = {role: "user", content: "TRIGGER_CONNECTION_ERROR now"};
    ai:ChatAssistantMessage|ai:Error result = provider->chat(userMsg, []);
    test:assertTrue(result is ai:Error);
    if result is ai:Error {
        test:assertTrue(result is ai:LlmConnectionError);
    }
}

@test:Config
function testChatCompletionsChatEmptyChoices() {
    ai:ChatUserMessage userMsg = {role: "user", content: "TRIGGER_EMPTY_CHOICES please"};
    ai:ChatAssistantMessage|ai:Error result = provider->chat(userMsg, []);
    test:assertTrue(result is ai:Error);
    if result is ai:Error {
        test:assertTrue(result.message().includes("Empty response from the model"));
    }
}

@test:Config
function testChatCompletionsChatDeprecatedFunctionCall() returns ai:Error? {
    ai:ChatUserMessage userMsg = {role: "user", content: "TRIGGER_DEPRECATED_FUNCTION_CALL now"};
    ai:ChatAssistantMessage result = check provider->chat(userMsg, []);
    ai:FunctionCall[]? toolCalls = result.toolCalls;
    test:assertTrue(toolCalls is ai:FunctionCall[]);
    if toolCalls is ai:FunctionCall[] {
        test:assertEquals(toolCalls[0].name, "get_weather");
        test:assertEquals(toolCalls[0].arguments, {"city": "Berlin"});
    }
}

@test:Config
function testChatCompletionsChatCustomToolUnsupported() {
    ai:ChatUserMessage userMsg = {role: "user", content: "TRIGGER_CUSTOM_TOOL now"};
    ai:ChatAssistantMessage|ai:Error result = provider->chat(userMsg, []);
    test:assertTrue(result is ai:Error);
}

@test:Config
function testChatCompletionsChatMalformedToolArgs() {
    ai:ChatUserMessage userMsg = {role: "user", content: "TRIGGER_MALFORMED_TOOL_ARGS now"};
    ai:ChatAssistantMessage|ai:Error result = provider->chat(userMsg, []);
    test:assertTrue(result is ai:Error);
}

// ===================================================================
// ReAct (Chat Completions) chat() tests
// ===================================================================

@test:Config
function testReActChatFinalAnswer() returns ai:Error? {
    ai:ChatMessage[] messages = [
        <ai:ChatSystemMessage>{role: "system", content: "Answer the question."},
        <ai:ChatUserMessage>{role: "user", content: "Summarize the plot."}
    ];
    ai:ChatAssistantMessage result = check reactProvider->chat(messages, weatherTool);
    test:assertEquals(result.content, "This is the final ReAct answer.");
}

@test:Config
function testReActChatToolCall() returns ai:Error? {
    ai:ChatMessage[] messages = [
        <ai:ChatSystemMessage>{role: "system", content: "Answer the question."},
        <ai:ChatUserMessage>{role: "user", content: "What is the weather in London?"}
    ];
    ai:ChatAssistantMessage result = check reactProvider->chat(messages, weatherTool);
    ai:FunctionCall[]? toolCalls = result.toolCalls;
    test:assertTrue(toolCalls is ai:FunctionCall[]);
    if toolCalls is ai:FunctionCall[] {
        test:assertEquals(toolCalls[0].name, "get_weather");
    }
}

@test:Config
function testReActChatWithAssistantHistory() returns ai:Error? {
    // Exercises the ReAct request-message builder for assistant messages carrying tool calls & content.
    ai:ChatMessage[] messages = [
        <ai:ChatSystemMessage>{role: "system", content: "Answer the question."},
        <ai:ChatUserMessage>{role: "user", content: "Summarize the report."},
        <ai:ChatAssistantMessage>{
            role: "assistant",
            content: "Prior reasoning.",
            toolCalls: [{id: "call_1", name: "get_weather", arguments: {"city": "London"}}]
        }
    ];
    ai:ChatAssistantMessage result = check reactProvider->chat(messages, weatherTool);
    test:assertEquals(result.content, "This is the final ReAct answer.");
}

// ===================================================================
// Responses API chat() error/status tests
// ===================================================================

@test:Config
function testResponsesChatConnectionError() {
    ai:ChatUserMessage userMsg = {role: "user", content: "TRIGGER_CONNECTION_ERROR now"};
    ai:ChatAssistantMessage|ai:Error result = responsesProvider->chat(userMsg, []);
    test:assertTrue(result is ai:LlmConnectionError);
}

@test:Config
function testResponsesChatStatusFailed() {
    ai:ChatUserMessage userMsg = {role: "user", content: "TRIGGER_STATUS_FAILED now"};
    ai:ChatAssistantMessage|ai:Error result = responsesProvider->chat(userMsg, []);
    test:assertTrue(result is ai:LlmConnectionError);
}

@test:Config
function testResponsesChatStatusIncomplete() {
    ai:ChatUserMessage userMsg = {role: "user", content: "TRIGGER_STATUS_INCOMPLETE now"};
    ai:ChatAssistantMessage|ai:Error result = responsesProvider->chat(userMsg, []);
    test:assertTrue(result is ai:LlmInvalidResponseError);
}

@test:Config
function testResponsesChatStatusCancelled() {
    ai:ChatUserMessage userMsg = {role: "user", content: "TRIGGER_STATUS_CANCELLED now"};
    ai:ChatAssistantMessage|ai:Error result = responsesProvider->chat(userMsg, []);
    test:assertTrue(result is ai:LlmConnectionError);
    if result is ai:Error {
        test:assertTrue(result.message().includes("cancelled"));
    }
}

@test:Config
function testResponsesChatStatusInProgress() {
    ai:ChatUserMessage userMsg = {role: "user", content: "TRIGGER_STATUS_IN_PROGRESS now"};
    ai:ChatAssistantMessage|ai:Error result = responsesProvider->chat(userMsg, []);
    test:assertTrue(result is ai:LlmConnectionError);
    if result is ai:Error {
        test:assertTrue(result.message().includes("in_progress"));
    }
}

@test:Config
function testResponsesChatWithStopReturnsError() {
    // The Responses API has no stop-sequence parameter, so the value cannot be honored and
    // the call must fail instead of silently dropping it.
    ai:ChatUserMessage userMsg = {role: "user", content: "Hello there"};
    ai:ChatAssistantMessage|ai:Error result = responsesProvider->chat(userMsg, [], "STOPSEQ");
    if result !is ai:Error {
        test:assertFail("Expected an error when 'stop' is used with the Responses API");
    }
    test:assertTrue(result.message().includes("'stop' parameter is not supported"), result.message());
}

@test:Config
function testDefaultApiTypeIsChatCompletions() returns ai:Error? {
    // A provider created without an explicit `apiType` must use the Chat Completions API. `stop` is
    // honored there and rejected on the Responses API, so a successful call proves the routing.
    ModelProvider defaultProvider = check new (API_KEY, GPT_4_TURBO, SERVICE_URL);
    ai:ChatUserMessage userMsg = {role: "user", content: "Hello, how are you?"};
    ai:ChatAssistantMessage result = check defaultProvider->chat(userMsg, [], "STOPSEQ");
    test:assertEquals(result.content, "This is a mock response for: Hello, how are you?");
}

@test:Config
function testResponsesGenerateForwardsReasoningAndDisablesStore() returns ai:Error? {
    int result = check reasoningProvider->generate(`TRIGGER_GEN_ASSERT_REQUEST rate this out of 10`);
    test:assertEquals(result, 7);
}

@test:Config
function testChatCompletionsGenerateForwardsReasoning() returns ai:Error? {
    int result = check chatReasoningProvider->generate(`TRIGGER_GEN_ASSERT_REASONING rate this out of 10`);
    test:assertEquals(result, 7);
}

@test:Config
function testResponsesChatWithReasoning() returns ai:Error? {
    ai:ChatUserMessage userMsg = {role: "user", content: "Explain quantum entanglement"};
    ai:ChatAssistantMessage result = check reasoningProvider->chat(userMsg, []);
    test:assertEquals(result.content, "This is a mock response for: Explain quantum entanglement");
}

@test:Config
function testResponsesChatWithAllMessageTypes() returns ai:Error? {
    ai:ChatMessage[] messages = [
        <ai:ChatSystemMessage>{role: "system", content: "You are helpful."},
        <ai:ChatUserMessage>{role: "user", content: "What is the weather?"},
        <ai:ChatAssistantMessage>{
            role: "assistant",
            content: "Checking.",
            toolCalls: [{id: "call_1", name: "get_weather", arguments: {"city": "London"}}]
        },
        <ai:ChatFunctionMessage>{role: "function", name: "get_weather", id: "call_1", content: "sunny"}
    ];
    ai:ChatAssistantMessage result = check responsesProvider->chat(messages, weatherTool);
    ai:FunctionCall[]? toolCalls = result.toolCalls;
    test:assertTrue(toolCalls is ai:FunctionCall[]);
}
