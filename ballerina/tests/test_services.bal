// Copyright (c) 2025 WSO2 LLC. (http://www.wso2.org).
//
// WSO2 Inc. licenses this file to you under the Apache License,
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

import ballerina/http;
import ballerina/test;
import ballerinax/openai.chat as chat;
import ballerinax/openai.embeddings;
import ballerinax/openai.responses as responses;

service /llm on new http:Listener(8080) {
    // Chat Completions API mock endpoint
    // Change the payload type to JSON due to https://github.com/ballerina-platform/ballerina-library/issues/8048.
    resource function post openai/chat/completions(@http:Payload json payload)
                returns chat:CreateChatCompletionResponse|error {
        string model = check payload.model.ensureType();
        // The chat-completions path is exercised by both the GPT_4_TURBO provider and the
        // ReAct-based CHATGPT_4O_LATEST provider.
        test:assertTrue(model == GPT_4_TURBO || model == CHATGPT_4O_LATEST,
                string `Unexpected model in chat/completions request: ${model}`);
        chat:ChatCompletionRequestMessage[] messages = check (check payload.messages).fromJsonWithType();

        // Determine if this is a generate() call (has getResults tool) or a chat() call
        json|error toolsPayload = payload.tools;
        boolean isGenerateCall = false;
        boolean hasFunctionTools = false;
        if toolsPayload is json[] && toolsPayload.length() > 0 {
            map<json> firstToolJson = check toolsPayload[0].ensureType();
            json? fnJson = firstToolJson["function"];
            if fnJson is map<json> {
                string? toolName = check fnJson["name"].ensureType();
                if toolName == GET_RESULTS_TOOL {
                    isGenerateCall = true;
                } else {
                    hasFunctionTools = true;
                }
            }
        }

        if isGenerateCall {
            // Existing generate() path
            chat:ChatCompletionRequestMessage message = messages[0];
            chat:ChatCompletionRequestUserMessageContentPart[]? content = check message["content"].ensureType();
            if content is () {
                test:assertFail("Expected content in the payload");
            }

            chat:ChatCompletionRequestUserMessageContentPart initialContentPart = content[0];
            TextContentPart initialTextContent = check initialContentPart.ensureType();
            string initialText = initialTextContent.text;

            // Error/edge-case triggers for the generate() path, evaluated before schema validation.
            if initialText.startsWith("TRIGGER_GEN_CONNECTION_ERROR") {
                return error("Simulated upstream failure");
            }
            if initialText.startsWith("TRIGGER_GEN_EMPTY_CHOICES") {
                return getChatCompletionsEmptyChoicesResponse();
            }
            if initialText.startsWith("TRIGGER_GEN_NO_TOOLCALLS") {
                return getChatCompletionsSimpleChatResponse(initialText);
            }
            if initialText.startsWith("TRIGGER_GEN_CUSTOM_TOOL") {
                return getChatCompletionsCustomToolResponse();
            }
            if initialText.startsWith("TRIGGER_GEN_MALFORMED_ARGS") {
                return getGenerateResultToolResponse("this is not json");
            }
            test:assertEquals(content, getExpectedContentParts(initialText),
                    string `Test failed for prompt with initial content, ${initialText}`);
            test:assertEquals(message.role, "user");
            chat:ChatCompletionTool[]? tools = check (check payload.tools).fromJsonWithType();
            if tools is () || tools.length() == 0 {
                test:assertFail("No tools in the payload");
            }

            map<json>? parameters = check tools[0].'function?.parameters.toJson().cloneWithType();
            if parameters is () {
                test:assertFail("No parameters in the expected tool");
            }

            test:assertEquals(parameters, getExpectedParameterSchema(initialText),
                    string `Test failed for prompt with initial content, ${initialText}`);
            return getTestServiceResponse(initialText);
        }

        // Chat path: extract user message content
        string userContent = "";
        foreach chat:ChatCompletionRequestMessage msg in messages {
            if msg.role == "user" {
                anydata msgContent = msg["content"];
                if msgContent is string {
                    userContent = msgContent;
                }
            }
        }

        // Error/edge-case triggers keyed on the user content.
        if userContent.startsWith("TRIGGER_CONNECTION_ERROR") {
            return error("Simulated upstream failure");
        }
        if userContent.startsWith("TRIGGER_EMPTY_CHOICES") {
            return getChatCompletionsEmptyChoicesResponse();
        }
        if userContent.startsWith("TRIGGER_DEPRECATED_FUNCTION_CALL") {
            return getChatCompletionsFunctionCallResponse();
        }
        if userContent.startsWith("TRIGGER_CUSTOM_TOOL") {
            return getChatCompletionsCustomToolResponse();
        }
        if userContent.startsWith("TRIGGER_MALFORMED_TOOL_ARGS") {
            return getChatCompletionsMalformedToolArgsResponse();
        }
        // Parallel tool calling: a single assistant turn carrying more than one tool call.
        if userContent.startsWith("TRIGGER_PARALLEL_TOOL_CALLS") {
            chat:ChatCompletionTool[]? parallelTools = check (check payload.tools).fromJsonWithType();
            if parallelTools is () || parallelTools.length() == 0 {
                test:assertFail("No tools in the payload");
            }
            return getParallelToolCallResponse();
        }

        // ReAct models (no native tool-call support) receive a ReAct-formatted string.
        if model == CHATGPT_4O_LATEST {
            return getChatCompletionsReActResponse(userContent);
        }

        if hasFunctionTools {
            // Chat with function tools - return tool call response
            return getChatCompletionsToolCallResponse();
        }

        // Simple chat - return text response
        return getChatCompletionsSimpleChatResponse(userContent);
    }

    // Embeddings API mock endpoint
    resource function post openai/embeddings(@http:Payload embeddings:CreateEmbeddingRequest payload)
                returns embeddings:CreateEmbeddingResponse|error {
        string|string[]|int[]|embeddings:InputItemsArray[] input = payload.input;
        // Normalize the first textual input so triggers work for both embed() and batchEmbed().
        string firstInput = "";
        if input is string {
            firstInput = input;
        } else if input is string[] && input.length() > 0 {
            firstInput = input[0];
        }
        if firstInput.startsWith("TRIGGER_EMBEDDING_ERROR") {
            return error("Simulated embeddings failure");
        }
        if firstInput.startsWith("TRIGGER_EMPTY_EMBEDDING_DATA") {
            return {'object: "list", model: payload.model, data: [], usage: {prompt_tokens: 0, total_tokens: 0}};
        }
        // Determine how many inputs were provided to size the response.
        int count = 1;
        if input is string[] {
            count = input.length();
        }
        embeddings:CreateEmbeddingResponse_data[] data = [];
        foreach int i in 0 ..< count {
            data.push({index: i, 'object: "embedding", embedding: [0.1, 0.2, 0.3]});
        }
        return {
            'object: "list",
            model: payload.model,
            data,
            usage: {prompt_tokens: 5, total_tokens: 5}
        };
    }

    // Responses API mock endpoint
    resource function post openai/responses(@http:Payload json payload) returns responses:Response|error {
        // Extract the initial text content from the input items
        json[] inputItems = check (check payload.input).ensureType();
        if inputItems.length() == 0 {
            test:assertFail("Expected input items in the payload");
        }

        // Find the first user message's content to determine the test case
        string initialText = "";
        json firstItem = inputItems[0];
        string? role = check firstItem.role.ensureType();
        if role == "user" {
            json itemContent = check firstItem.content;
            if itemContent is string {
                initialText = itemContent;
            } else {
                // Content is an array of content parts (for generate() path)
                json[] contentParts = check itemContent.ensureType();
                if contentParts.length() > 0 {
                    json firstPart = contentParts[0];
                    string? partType = check firstPart.'type.ensureType();
                    if partType == "input_text" {
                        initialText = check firstPart.text.ensureType();
                    }
                }
            }
        }

        // Check if tools are provided and classify them
        json|error toolsJson = payload.tools;
        boolean hasGetResultsTool = false;
        if toolsJson is json[] && toolsJson.length() > 0 {
            foreach json tool in toolsJson {
                string? toolType = check tool.'type.ensureType();
                if toolType == "function" {
                    string? toolName = check tool.name.ensureType();
                    if toolName == GET_RESULTS_TOOL {
                        hasGetResultsTool = true;
                    }
                }
            }
        }

        if hasGetResultsTool {
            // Error/edge-case triggers for the generate() path, evaluated before schema validation.
            if initialText.startsWith("TRIGGER_GEN_CONNECTION_ERROR") {
                return error("Simulated upstream failure");
            }
            if initialText.startsWith("TRIGGER_GEN_NO_TOOLCALLS") {
                return getTestResponsesApiChatResponse(initialText);
            }
            if initialText.startsWith("TRIGGER_GEN_MALFORMED_ARGS") {
                return getResponsesGenerateResultResponse("this is not json");
            }
            if initialText.startsWith("TRIGGER_GEN_TYPE_MISMATCH") {
                // Valid JSON whose value cannot be coerced to the requested type.
                return getResponsesGenerateResultResponse("{\"result\": \"not-a-number\"}");
            }
            // Validate the parameter schema for generate() path
            json[] toolsArr = check toolsJson.ensureType();
            json firstTool = toolsArr[0];
            map<json>? parameters = check (check firstTool.parameters).cloneWithType();
            if parameters is () {
                test:assertFail("No parameters in the expected tool");
            }
            test:assertEquals(parameters, getExpectedParameterSchema(initialText),
                    string `Responses API: Test failed for prompt with initial content, ${initialText}`);
            // Return response with function_call output item (for generate() path)
            return getTestResponsesApiResponseWithToolCall(initialText);
        }

        // Error/status triggers keyed on the user content.
        if initialText.startsWith("TRIGGER_CONNECTION_ERROR") {
            return error("Simulated upstream failure");
        }
        if initialText.startsWith("TRIGGER_STATUS_FAILED") {
            return getTestResponsesApiStatusResponse("failed");
        }
        if initialText.startsWith("TRIGGER_STATUS_INCOMPLETE") {
            return getTestResponsesApiStatusResponse("incomplete");
        }
        if initialText.startsWith("TRIGGER_STATUS_CANCELLED") {
            return getTestResponsesApiStatusResponse("cancelled");
        }
        if initialText.startsWith("TRIGGER_STATUS_IN_PROGRESS") {
            return getTestResponsesApiStatusResponse("in_progress");
        }
        if initialText.startsWith("TRIGGER_EMPTY_OUTPUT") {
            // A completed response with no output items yields an "empty response" error.
            return buildEmptyResponse();
        }

        // If non-getResults tools are provided (chat with tools path), return tool call response
        if toolsJson is json[] && toolsJson.length() > 0 {
            return getTestResponsesApiToolCallChatResponse();
        }

        // Return a simple text message response (for chat() path)
        return getTestResponsesApiChatResponse(initialText);
    }
}

// Builds a Responses API getResults function_call response with the given raw arguments.
isolated function getResponsesGenerateResultResponse(string arguments) returns responses:Response => {
    id: "resp_test_id",
    'object: "response",
    created_at: 1234567890,
    model: "gpt-4o",
    status: "completed",
    'error: (),
    incomplete_details: (),
    instructions: (),
    output: [
        {
            id: "fc_test_id",
            'type: "function_call",
            name: GET_RESULTS_TOOL,
            arguments: arguments,
            call_id: "call_test_id",
            status: "completed"
        }
    ],
    output_text: "",
    usage: {
        input_tokens: 100,
        output_tokens: 50,
        total_tokens: 150,
        input_tokens_details: {cached_tokens: 0},
        output_tokens_details: {reasoning_tokens: 0}
    },
    tool_choice: "auto",
    metadata: (),
    tools: []
};

// Builds a Responses API response with a function_call output item (for generate() tests)
isolated function getTestResponsesApiResponseWithToolCall(string content) returns responses:Response {
    return {
        id: "resp_test_id",
        'object: "response",
        created_at: 1234567890,
        model: "gpt-4o",
        status: "completed",
        'error: (),
        incomplete_details: (),
        instructions: (),
        output: [
            {
                id: "fc_test_id",
                'type: "function_call",
                name: GET_RESULTS_TOOL,
                arguments: getTheMockLLMResult(content),
                call_id: "call_test_id",
                status: "completed"
            }
        ],
        output_text: "",
        usage: {
            input_tokens: 100,
            output_tokens: 50,
            total_tokens: 150,
            input_tokens_details: {cached_tokens: 0},
            output_tokens_details: {reasoning_tokens: 0}
        },
        tool_choice: "auto",
        metadata: (),
        tools: []
    };
}

// Builds a Responses API response with a text message output item (for chat() tests)
isolated function getTestResponsesApiChatResponse(string content) returns responses:Response {
    string responseText = "This is a mock response for: " + content;
    return {
        id: "resp_chat_test_id",
        'object: "response",
        created_at: 1234567890,
        model: "gpt-4o",
        status: "completed",
        'error: (),
        incomplete_details: (),
        instructions: (),
        output: [
            {
                id: "msg_test_id",
                'type: "message",
                role: "assistant",
                status: "completed",
                content: [
                    {
                        'type: "output_text",
                        text: responseText,
                        annotations: [],
                        logprobs: []
                    }
                ]
            }
        ],
        output_text: responseText,
        usage: {
            input_tokens: 50,
            output_tokens: 30,
            total_tokens: 80,
            input_tokens_details: {cached_tokens: 0},
            output_tokens_details: {reasoning_tokens: 0}
        },
        metadata: (), 
        tool_choice: "auto", 
        tools: []
    };
}

// Builds a Responses API response with function_call output items (for chat() with tools tests)
isolated function getTestResponsesApiToolCallChatResponse() returns responses:Response {
    return {
        id: "resp_tool_chat_test_id",
        'object: "response",
        created_at: 1234567890,
        model: "gpt-4o",
        status: "completed",
        'error: (),
        incomplete_details: (),
        instructions: (),
        output: [
            {
                id: "fc_chat_test_id",
                'type: "function_call",
                name: "get_weather",
                arguments: "{\"city\": \"London\"}",
                call_id: "call_weather_123",
                status: "completed"
            }
        ],
        output_text: "",
        usage: {
            input_tokens: 80,
            output_tokens: 20,
            total_tokens: 100,
            input_tokens_details: {cached_tokens: 0},
            output_tokens_details: {reasoning_tokens: 0}
        },
        tool_choice: "auto",
        metadata: (),
        tools: []
    };
}

// Builds a Chat Completions simple text response (for chat() without tools)
isolated function getChatCompletionsSimpleChatResponse(string content) returns chat:CreateChatCompletionResponse {
    string responseText = "This is a mock response for: " + content;
    return {
        id: "chatcmpl-simple-test",
        'object: "chat.completion",
        created: 1234567890,
        model: GPT_4_TURBO,
        choices: [
            {
                finish_reason: "stop",
                index: 0,
                logprobs: (),
                message: {
                    content: responseText,
                    refusal: (),
                    role: "assistant"
                }
            }
        ],
        usage: {prompt_tokens: 50, completion_tokens: 30, total_tokens: 80}
    };
}

// Builds a Chat Completions tool call response (for chat() with function tools)
isolated function getChatCompletionsToolCallResponse() returns chat:CreateChatCompletionResponse {
    return {
        id: "chatcmpl-tool-test",
        'object: "chat.completion",
        created: 1234567890,
        model: GPT_4_TURBO,
        choices: [
            {
                finish_reason: "tool_calls",
                index: 0,
                logprobs: (),
                message: {
                    role: "assistant",
                    refusal: (),
                    content: (),
                    tool_calls: [
                        {
                            id: "call_weather_456",
                            'type: "function",
                            'function: {
                                name: "get_weather",
                                arguments: "{\"city\": \"London\"}"
                            }
                        }
                    ]
                }
            }
        ],
        usage: {prompt_tokens: 80, completion_tokens: 20, total_tokens: 100}
    };
}

// Builds a Chat Completions response with an empty choices array.
isolated function getChatCompletionsEmptyChoicesResponse() returns chat:CreateChatCompletionResponse => {
    id: "chatcmpl-empty",
    'object: "chat.completion",
    created: 1234567890,
    model: GPT_4_TURBO,
    choices: [],
    usage: {prompt_tokens: 10, completion_tokens: 0, total_tokens: 10}
};

// Builds a Chat Completions response using the deprecated `function_call` field.
isolated function getChatCompletionsFunctionCallResponse() returns chat:CreateChatCompletionResponse => {
    id: "chatcmpl-fncall",
    'object: "chat.completion",
    created: 1234567890,
    model: GPT_4_TURBO,
    choices: [
        {
            finish_reason: "function_call",
            index: 0,
            logprobs: (),
            message: {
                role: "assistant",
                refusal: (),
                content: (),
                function_call: {
                    name: "get_weather",
                    arguments: "{\"city\": \"Berlin\"}"
                }
            }
        }
    ],
    usage: {prompt_tokens: 30, completion_tokens: 10, total_tokens: 40}
};

// Builds a Chat Completions response containing a custom (unsupported) tool call.
isolated function getChatCompletionsCustomToolResponse() returns chat:CreateChatCompletionResponse => {
    id: "chatcmpl-custom",
    'object: "chat.completion",
    created: 1234567890,
    model: GPT_4_TURBO,
    choices: [
        {
            finish_reason: "tool_calls",
            index: 0,
            logprobs: (),
            message: {
                role: "assistant",
                refusal: (),
                content: (),
                tool_calls: [
                    {
                        id: "call_custom_1",
                        'type: "custom",
                        custom: {name: "my_custom_tool", input: "raw input"}
                    }
                ]
            }
        }
    ],
    usage: {prompt_tokens: 30, completion_tokens: 10, total_tokens: 40}
};

// Builds a Chat Completions tool-call response with malformed (non-JSON) arguments.
isolated function getChatCompletionsMalformedToolArgsResponse() returns chat:CreateChatCompletionResponse => {
    id: "chatcmpl-malformed",
    'object: "chat.completion",
    created: 1234567890,
    model: GPT_4_TURBO,
    choices: [
        {
            finish_reason: "tool_calls",
            index: 0,
            logprobs: (),
            message: {
                role: "assistant",
                refusal: (),
                content: (),
                tool_calls: [
                    {
                        id: "call_bad_args",
                        'type: "function",
                        'function: {name: "get_weather", arguments: "this is not json"}
                    }
                ]
            }
        }
    ],
    usage: {prompt_tokens: 30, completion_tokens: 10, total_tokens: 40}
};

// Builds a Chat Completions response with ReAct-formatted content for the CHATGPT_4O_LATEST model.
isolated function getChatCompletionsReActResponse(string userContent) returns chat:CreateChatCompletionResponse {
    string reactContent;
    if userContent.includes("weather") {
        reactContent = string `${BACKTICKS}
{
  "action": "get_weather",
  "action_input": {"city": "London"}
}
${BACKTICKS}`;
    } else {
        reactContent = string `${BACKTICKS}
{
  "action": "Final Answer",
  "action_input": "This is the final ReAct answer."
}
${BACKTICKS}`;
    }
    return {
        id: "chatcmpl-react",
        'object: "chat.completion",
        created: 1234567890,
        model: CHATGPT_4O_LATEST,
        choices: [
            {
                finish_reason: "stop",
                index: 0,
                logprobs: (),
                message: {role: "assistant", refusal: (), content: reactContent}
            }
        ],
        usage: {prompt_tokens: 40, completion_tokens: 20, total_tokens: 60}
    };
}

// Builds a Responses API response with a non-completed status for error-path tests.
isolated function getTestResponsesApiStatusResponse(
        "completed"|"failed"|"in_progress"|"cancelled"|"queued"|"incomplete" status) returns responses:Response => {
    id: "resp_status_test",
    'object: "response",
    created_at: 1234567890,
    model: "gpt-4o",
    status: status,
    'error: status == "failed" ? {code: "server_error", message: "Something went wrong"} : (),
    incomplete_details: status == "incomplete" ? {reason: "max_output_tokens"} : (),
    instructions: (),
    output: [],
    output_text: "",
    usage: (),
    tool_choice: "auto",
    metadata: (),
    tools: []
};

// ===== Shared response builders used by unit tests =====

isolated function buildTextResponse(string text) returns responses:Response => {
    id: "resp_unit_text",
    'object: "response",
    created_at: 1234567890,
    model: "gpt-4o",
    status: "completed",
    'error: (),
    incomplete_details: (),
    instructions: (),
    output: [
        {
            id: "msg_unit",
            'type: "message",
            role: "assistant",
            status: "completed",
            content: [{'type: "output_text", text: text, annotations: [], logprobs: []}]
        }
    ],
    output_text: text,
    usage: (),
    tool_choice: "auto",
    metadata: (),
    tools: []
};

isolated function buildFunctionCallResponse(string name, string arguments, string callId) returns responses:Response => {
    id: "resp_unit_fc",
    'object: "response",
    created_at: 1234567890,
    model: "gpt-4o",
    status: "completed",
    'error: (),
    incomplete_details: (),
    instructions: (),
    output: [
        {
            id: "fc_unit",
            'type: "function_call",
            name: name,
            arguments: arguments,
            call_id: callId,
            status: "completed"
        }
    ],
    output_text: "",
    usage: (),
    tool_choice: "auto",
    metadata: (),
    tools: []
};

// A Responses API result carrying two function calls in one turn (parallel tool calling).
isolated function buildParallelFunctionCallResponse() returns responses:Response => {
    id: "resp_unit_parallel_fc",
    'object: "response",
    created_at: 1234567890,
    model: "gpt-4o",
    status: "completed",
    'error: (),
    incomplete_details: (),
    instructions: (),
    output: [
        {
            id: "fc_unit_1",
            'type: "function_call",
            name: "getWeather",
            arguments: "{\"city\": \"London\"}",
            call_id: "call_weather",
            status: "completed"
        },
        {
            id: "fc_unit_2",
            'type: "function_call",
            name: "getTime",
            arguments: "{\"city\": \"London\"}",
            call_id: "call_time",
            status: "completed"
        }
    ],
    output_text: "",
    usage: (),
    tool_choice: "auto",
    metadata: (),
    tools: []
};

isolated function buildEmptyResponse() returns responses:Response => {
    id: "resp_unit_empty",
    'object: "response",
    created_at: 1234567890,
    model: "gpt-4o",
    status: "completed",
    'error: (),
    incomplete_details: (),
    instructions: (),
    output: [],
    output_text: "",
    usage: (),
    tool_choice: "auto",
    metadata: (),
    tools: []
};
