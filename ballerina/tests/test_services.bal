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
import ballerinax/openai.responses as responses;

service /llm on new http:Listener(8080) {
    // Chat Completions API mock endpoint
    // Change the payload type to JSON due to https://github.com/ballerina-platform/ballerina-library/issues/8048.
    resource function post openai/chat/completions(@http:Payload json payload)
                returns chat:CreateChatCompletionResponse|error {
        test:assertEquals(payload.model, GPT_4_TURBO);
        chat:ChatCompletionRequestMessage[] messages = check (check payload.messages).fromJsonWithType();
        chat:ChatCompletionRequestMessage message = messages[0];

        chat:ChatCompletionRequestUserMessageContentPart[]? content = check message["content"].ensureType();
        if content is () {
            test:assertFail("Expected content in the payload");
        }

        chat:ChatCompletionRequestUserMessageContentPart initialContentPart = content[0];
        TextContentPart initialTextContent = check initialContentPart.ensureType();
        string initialText = initialTextContent.text;
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

        // Check if tools are provided (generate() path uses getResults tool)
        json|error toolsJson = payload.tools;
        boolean hasGetResultsTool = false;
        if toolsJson is json[] && toolsJson.length() > 0 {
            json firstTool = toolsJson[0];
            string? toolName = check firstTool.name.ensureType();
            if toolName == GET_RESULTS_TOOL {
                hasGetResultsTool = true;

                // Validate the parameter schema matches expectations
                map<json>? parameters = check (check firstTool.parameters).cloneWithType();
                if parameters is () {
                    test:assertFail("No parameters in the expected tool");
                }
                test:assertEquals(parameters, getExpectedParameterSchema(initialText),
                        string `Responses API: Test failed for prompt with initial content, ${initialText}`);
            }
        }

        if hasGetResultsTool {
            // Return response with function_call output item (for generate() path)
            return getTestResponsesApiResponseWithToolCall(initialText);
        }

        // If non-getResults tools are provided (chat with tools path), return tool call response
        if toolsJson is json[] && toolsJson.length() > 0 {
            return getTestResponsesApiToolCallChatResponse();
        }

        // Return a simple text message response (for chat() path)
        return getTestResponsesApiChatResponse(initialText);
    }
}

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
