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
import ballerina/ai.observe;
import ballerina/log;
import ballerinax/openai.responses as responses;

# Converts ai:ChatMessage array to Responses API input items and instructions.
#
# System messages are extracted to the `instructions` parameter.
# User, assistant, and function messages are converted to typed input items.
#
# + messages - List of chat messages or a single user message
# + tools - Tool definitions (used for ReAct prompt construction on unsupported models)
# + modelType - The model type (used to determine tool call support)
# + return - A tuple of [input items, optional instructions] or an error
isolated function convertToResponsesInput(ai:ChatMessage[]|ai:ChatUserMessage messages,
        ai:ChatCompletionFunctions[] tools, OPEN_AI_MODEL_NAMES modelType)
        returns [responses:InputParam, string?]|ai:Error {
    if messages is ai:ChatUserMessage {
        responses:InputItem item = <responses:EasyInputMessage>{
            role: ai:USER,
            content: check getChatMessageStringContent(messages.content)
        };
        return [[item], ()];
    }

    responses:InputItem[] inputItems = [];
    string[] instructionParts = [];
    boolean supportsToolCalls = isToolCallSupported(modelType);

    foreach ai:ChatMessage message in messages {
        if message is ai:ChatSystemMessage {
            string content = check getChatMessageStringContent(message.content);
            if !supportsToolCalls && tools.length() > 0 {
                content = constructReActPrompt(extractToolInfo(tools), content);
            }
            instructionParts.push(content);
        } else if message is ai:ChatUserMessage {
            inputItems.push(<responses:EasyInputMessage>{
                role: ai:USER,
                content: check getChatMessageStringContent(message.content)
            });
        } else if message is ai:ChatAssistantMessage {
            ai:FunctionCall[]? toolCalls = message.toolCalls;
            if toolCalls is ai:FunctionCall[] && toolCalls.length() > 0 {
                // If the assistant message also has text content, emit it first
                string? content = message?.content;
                if content is string {
                    inputItems.push(<responses:EasyInputMessage>{role: ai:ASSISTANT, content});
                }
                // Emit each function call as a separate input item
                foreach ai:FunctionCall tc in toolCalls {
                    inputItems.push({
                        'type: "function_call",
                        name: tc.name,
                        arguments: tc?.arguments.toJsonString(),
                        call_id: tc.id ?: string `call_${tc.name}`,
                        status: "completed"
                    });
                }
            } else {
                inputItems.push(<responses:EasyInputMessage>{
                    role: ai:ASSISTANT,
                    content: message?.content ?: ""
                });
            }
        } else if message is ai:ChatFunctionMessage {
            inputItems.push({
                'type: "function_call_output",
                call_id: message.id ?: string `call_${message.name}`,
                output: message?.content ?: ""
            });
        }
    }

    string? instructions = instructionParts.length() > 0
        ? string:'join("\n\n", ...instructionParts)
        : ();
    return [inputItems, instructions];
}

# Converts ai:ChatCompletionFunctions to Responses API flat function tool format.
#
# + tools - The tool definitions to convert
# + return - Array of function tool objects in Responses API flat format
isolated function convertToResponsesTools(ai:ChatCompletionFunctions[] tools) returns responses:FunctionTool[] {
    return from ai:ChatCompletionFunctions tool in tools
        select <responses:FunctionTool>{
            'type: "function",
            name: tool.name,
            description: tool.description,
            parameters: tool.parameters ?: {},
            strict: false
        };
}

# Converts ai:BuiltInTool array to Responses API tool format.
#
# Each built-in tool's `name` maps to the `type` field in the API, and its
# `configurations` are spread as top-level properties of the tool object.
#
# + tools - The built-in tool definitions to convert
# + return - Array of chat:Tool objects or an error
isolated function convertBuiltInToolsToResponsesFormat(ai:BuiltInTool[] tools) returns responses:Tool[]|ai:Error {
    responses:Tool[] result = [];
    foreach ai:BuiltInTool tool in tools {
        map<anydata> toolMap = {'type: tool.name};
        map<anydata>? configs = tool.configurations;
        if configs is map<anydata> {
            foreach string key in configs.keys() {
                anydata value = configs[key];
                toolMap[key] = value;
            }
        }
        responses:Tool|error converted = toolMap.cloneWithType();
        if converted is error {
            return error ai:Error("Failed to convert built-in tool '" + tool.name + "' to Responses API format." + "Found " + toolMap.toJsonString() , converted);
        }
        result.push(converted);
    }
    return result;
}

# Converts a Responses API response to an ai:ChatAssistantMessage.
#
# Extracts text content from output_text and function calls from function_call output items.
#
# + response - The Responses API response
# + return - A ChatAssistantMessage or an error
isolated function convertResponsesOutputToAssistantMessage(responses:Response response)
        returns ai:ChatAssistantMessage|ai:Error {
    ai:ChatAssistantMessage result = {role: ai:ASSISTANT};
    ai:FunctionCall[] functionCalls = [];

    // Commented out the old output_text extraction logic since we're now scanning output items for content parts
    // anydata outputText = response?.output_text;
    // if outputText is string && outputText.length() > 0 {
    //     result.content = outputText;
    // }

    // Scan output items for message and function_call items using type-safe pattern matching
    foreach responses:OutputItem item in response.output {
        if item is responses:OutputMessage {
            // Extract text content from message output items
            foreach responses:OutputMessageContent contentPart in item.content {
                if contentPart is responses:OutputTextContent {
                    if contentPart.text.length() > 0 {
                        result.content = (result.content ?: "") + contentPart.text;
                    }
                }
            }
        } else if item is responses:FunctionToolCall {
            json|error parsedArgs = item.arguments.fromJsonString();
            if parsedArgs is error {
                return error ai:LlmInvalidResponseError(
                    "Failed to parse function call arguments as JSON", parsedArgs);
            }
            map<json>|error argsMap = parsedArgs.cloneWithType();
            if argsMap is error {
                return error ai:LlmInvalidResponseError(
                    "Failed to convert parsed arguments to expected type", argsMap);
            }
            functionCalls.push({
                name: item.name,
                arguments: argsMap,
                id: item.call_id
            });
        }
    }

    if functionCalls.length() > 0 {
        result.toolCalls = functionCalls;
    }

    if result.content is () && functionCalls.length() == 0 {
        return error ai:LlmInvalidResponseError("Empty response from the model");
    }

    return result;
}

# Converts DocumentContentPart array from Chat Completions format to Responses API format.
#
# Chat Completions uses {type: "text", text} and {type: "image_url", image_url: {url}}.
# Responses API uses {type: "input_text", text} and {type: "input_image", image_url: url}.
#
# + parts - The content parts in Chat Completions format
# + return - The content parts in Responses API format
isolated function convertContentPartsForResponses(DocumentContentPart[] parts) returns responses:InputContent[] {
    responses:InputContent[] result = [];
    foreach DocumentContentPart part in parts {
        if part is TextContentPart {
            result.push(<responses:InputTextContent>{
                'type: "input_text",
                text: part.text
            });
        } else if part is ImageContentPart {
            result.push(<responses:InputImageContent>{
                'type: "input_image",
                image_url: part.image_url.url
            });
        }
    }
    return result;
}

# Generates a structured response from the LLM via the Responses API.
#
# This mirrors the Chat Completions `generateLlmResponse` but uses the Responses API.
# Uses the same getResults tool-forcing pattern with flat tool definitions.
#
# + responsesClient - The chat client for the Responses API
# + modelType - The model to use
# + prompt - The user prompt
# + expectedResponseTypedesc - The expected response type descriptor
# + return - The parsed response or an error
isolated function generateLlmResponseViaResponses(responses:Client responsesClient, OPEN_AI_MODEL_NAMES modelType,
        ai:Prompt prompt, typedesc<json> expectedResponseTypedesc, string? reasoningEffort = ())
        returns anydata|ai:Error {
    log:printInfo("Generating LLM response via Responses API for model: " + modelType.toString());
    observe:GenerateContentSpan span = observe:createGenerateContentSpan(modelType);
    span.addProvider("openai");

    DocumentContentPart[] content;
    ResponseSchema responseSchema;
    do {
        content = check generateChatCreationContent(prompt);
        responseSchema = check getExpectedResponseSchema(expectedResponseTypedesc);
    } on fail ai:Error err {
        span.close(err);
        return err;
    }

    // Build the getResults tool as a typed FunctionTool
    responses:FunctionTool getResultsTool = {
        'type: "function",
        name: GET_RESULTS_TOOL,
        parameters: responseSchema.schema,
        description: "Tool to call with the response from a large language model (LLM) for a user prompt.",
        strict: false
    };

    // Build tool_choice for Responses API
    responses:ToolChoiceFunction toolChoice = {
        'type: "function",
        name: GET_RESULTS_TOOL
    };

    // Convert content parts to Responses API format
    responses:InputContent[] responsesContent = convertContentPartsForResponses(content);

    // Build input - a single user message with content parts
    responses:InputParam inputMessage = [
        <responses:Item>{
            role: ai:USER,
            content: responsesContent
        }
    ];

    responses:CreateResponse request = {
        model: modelType,
        input: inputMessage,
        tools: [getResultsTool],
        tool_choice: toolChoice
    };

    span.addInputMessages([inputMessage].toJson());

    responses:Response|error response = responsesClient->/responses.post(request);
    if response is error {
        ai:Error err = error("LLM call failed: " + response.message(), detail = response.detail(), cause = response.cause());
        span.close(err);
        return err;
    }

    // Record observability
    span.addResponseId(response.id);
    responses:ResponseUsage? usage = response.usage;
    if usage is responses:ResponseUsage {
        span.addInputTokenCount(usage.input_tokens);
        span.addOutputTokenCount(usage.output_tokens);
    }

    // Find the function_call output item for getResults
    string? toolArguments = ();
    foreach responses:OutputItem item in response.output {
        if item is responses:FunctionToolCall && item.name == GET_RESULTS_TOOL {
            toolArguments = item.arguments;
            break;
        }
    }

    if toolArguments is () {
        ai:Error err = error(NO_RELEVANT_RESPONSE_FROM_THE_LLM);
        span.close(err);
        return err;
    }

    map<json>|error arguments = toolArguments.fromJsonStringWithType();
    if arguments is error {
        ai:Error err = error(NO_RELEVANT_RESPONSE_FROM_THE_LLM);
        span.close(err);
        return err;
    }

    anydata|error res = parseResponseAsType(arguments.toJsonString(), expectedResponseTypedesc,
            responseSchema.isOriginallyJsonObject);
    if res is error {
        log:printError("Error occured to convert Types", res);
        ai:Error err = error ai:LlmInvalidGenerationError(string `Invalid value returned from the LLM Client, expected: '${
            expectedResponseTypedesc.toBalString()}', found '${res.toBalString()}'`);
        span.close(err);
        return err;
    }

    anydata|error result = res.ensureType(expectedResponseTypedesc);
    if result is error {
        log:printError("Error occured to convert Types", result);
        ai:Error err = error ai:LlmInvalidGenerationError(string `Invalid value returned from the LLM Client, expected: '${
            expectedResponseTypedesc.toBalString()}', found '${(typeof response).toBalString()}'`);
        span.close(err);
        return err;
    }

    span.addOutputMessages(result.toJson());
    span.addOutputType(observe:JSON);
    span.close();
    return result;
}
