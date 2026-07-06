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

import ballerina/ai;
import ballerina/test;
import ballerinax/openai.chat as chat;
import ballerinax/openai.responses as responses;

// ===================================================================
// react-utils.bal unit tests
// ===================================================================

final ai:ChatCompletionFunctions[] sampleTools = [
    {
        name: "get_weather",
        description: "Get the weather for a city",
        parameters: {
            "type": "object",
            "properties": {"city": {"type": "string"}},
            "required": ["city"]
        }
    },
    {
        name: "get_time",
        description: "Get the current time"
    }
];

@test:Config
function testIsToolCallSupported() {
    test:assertTrue(isToolCallSupported(GPT_4O));
    test:assertTrue(isToolCallSupported(GPT_4_TURBO));
    test:assertFalse(isToolCallSupported(CHATGPT_4O_LATEST));
}

@test:Config
function testExtractToolInfo() {
    ToolInfo info = extractToolInfo(sampleTools);
    test:assertEquals(info.toolList, "get_weather, get_time");
    test:assertTrue(info.toolIntro.includes("get_weather"));
    test:assertTrue(info.toolIntro.includes("get_time"));
}

@test:Config
function testConstructReActPrompt() {
    string prompt = constructReActPrompt(extractToolInfo(sampleTools), "Follow the rules.");
    test:assertTrue(prompt.includes("get_weather"));
    test:assertTrue(prompt.includes("Final Answer"));
    test:assertTrue(prompt.includes("Follow the rules."));
}

@test:Config
function testParseReActLlmResponseNil() {
    LlmChatResponse|ai:LlmToolResponse|ai:LlmInvalidGenerationError result = parseReActLlmResponse(());
    test:assertTrue(result is ai:LlmInvalidGenerationError);
}

@test:Config
function testParseReActLlmResponseFinalAnswer() {
    string resp = string `${BACKTICKS}
{
  "action": "Final Answer",
  "action_input": "The answer is 42"
}
${BACKTICKS}`;
    LlmChatResponse|ai:LlmToolResponse|ai:LlmInvalidGenerationError result = parseReActLlmResponse(resp);
    test:assertTrue(result is LlmChatResponse);
    if result is LlmChatResponse {
        test:assertEquals(result.content, "The answer is 42");
    }
}

@test:Config
function testParseReActLlmResponseToolCall() {
    string resp = string `${BACKTICKS}
{
  "action": "get_weather",
  "action_input": {"city": "London"}
}
${BACKTICKS}`;
    LlmChatResponse|ai:LlmToolResponse|ai:LlmInvalidGenerationError result = parseReActLlmResponse(resp);
    test:assertTrue(result is ai:LlmToolResponse);
    if result is ai:LlmToolResponse {
        test:assertEquals(result.name, "get_weather");
        test:assertEquals(result.arguments, {"city": "London"});
    }
}

@test:Config
function testParseReActLlmResponseInvalidJson() {
    string resp = string `${BACKTICKS}
this is not valid json
${BACKTICKS}`;
    LlmChatResponse|ai:LlmToolResponse|ai:LlmInvalidGenerationError result = parseReActLlmResponse(resp);
    test:assertTrue(result is ai:LlmInvalidGenerationError);
}

@test:Config
function testParseReActLlmResponseTooFewSegments() {
    LlmChatResponse|ai:LlmToolResponse|ai:LlmInvalidGenerationError result = parseReActLlmResponse("no braces here");
    test:assertTrue(result is ai:LlmInvalidGenerationError);
}

@test:Config
function testParseReActLlmResponseInvalidAction() {
    // A JSON blob missing the action name results in an invalid tool response.
    string resp = string `${BACKTICKS}
{
  "action_input": {"city": "London"}
}
${BACKTICKS}`;
    LlmChatResponse|ai:LlmToolResponse|ai:LlmInvalidGenerationError result = parseReActLlmResponse(resp);
    test:assertTrue(result is ai:LlmInvalidGenerationError);
}

@test:Config
function testNormalizeLlmResponseWrapsBareJsonObject() {
    // Bare JSON object without fences: should be wrapped and parseable.
    string resp = "{\"action\": \"Final Answer\", \"action_input\": \"hi\"}";
    LlmChatResponse|ai:LlmToolResponse|ai:LlmInvalidGenerationError result = parseReActLlmResponse(resp);
    test:assertTrue(result is LlmChatResponse);
    if result is LlmChatResponse {
        test:assertEquals(result.content, "hi");
    }
}

@test:Config
function testNormalizeLlmResponseExtractsEmbeddedJson() {
    // JSON embedded within surrounding text and no fences.
    string resp = "Thought: I know the answer {\"action\": \"Final Answer\", \"action_input\": \"done\"} end";
    LlmChatResponse|ai:LlmToolResponse|ai:LlmInvalidGenerationError result = parseReActLlmResponse(resp);
    test:assertTrue(result is LlmChatResponse);
    if result is LlmChatResponse {
        test:assertEquals(result.content, "done");
    }
}

@test:Config
function testNormalizeLlmResponseStripsJsonFenceLabel() {
    string resp = string `${BACKTICKS}json
{"action": "Final Answer", "action_input": "labeled"}
${BACKTICKS}`;
    LlmChatResponse|ai:LlmToolResponse|ai:LlmInvalidGenerationError result = parseReActLlmResponse(resp);
    test:assertTrue(result is LlmChatResponse);
    if result is LlmChatResponse {
        test:assertEquals(result.content, "labeled");
    }
}

@test:Config
function testFormatFunctionCallToJsonWithFences() {
    ai:FunctionCall fc = {name: "get_weather", arguments: {"city": "Paris"}};
    string formatted = formatFunctionCallToJsonWithFences(fc);
    test:assertTrue(formatted.includes("get_weather"));
    test:assertTrue(formatted.includes("action_input"));
    test:assertTrue(formatted.includes("Paris"));
}

@test:Config
function testFormatFinalAnswerToJsonWithFences() {
    string formatted = formatFinalAnswerToJsonWithFences("this is the final answer");
    test:assertTrue(formatted.includes("Final Answer"));
    test:assertTrue(formatted.includes("this is the final answer"));
}

// ===================================================================
// model-provider.bal standalone function unit tests
// ===================================================================

@test:Config
function testSupportsReasoning() {
    test:assertFalse(supportsReasoning(O1_MINI));
    test:assertTrue(supportsReasoning(O1));
    test:assertTrue(supportsReasoning(O3));
    test:assertTrue(supportsReasoning(O3_MINI));
    test:assertTrue(supportsReasoning(O4_MINI));
    test:assertTrue(supportsReasoning(GPT_5));
    test:assertTrue(supportsReasoning(GPT_5_MINI));
    test:assertTrue(supportsReasoning(CODEX_MINI_LATEST));
    test:assertFalse(supportsReasoning(GPT_4O));
    test:assertFalse(supportsReasoning(GPT_3_5_TURBO));
}

@test:Config
function testGetChatMessageStringContentWithString() returns ai:Error? {
    string content = check getChatMessageStringContent("plain string");
    test:assertEquals(content, "plain string");
}

@test:Config
function testGetChatMessageStringContentWithTextDocument() returns ai:Error? {
    ai:TextDocument doc = {content: "document body"};
    string content = check getChatMessageStringContent(`Consider this: ${doc} end`);
    test:assertTrue(content.includes("document body"));
    test:assertTrue(content.includes("Consider this:"));
}

@test:Config
function testGetChatMessageStringContentWithTextChunk() returns ai:Error? {
    ai:TextChunk chunk = {content: "chunk body"};
    string content = check getChatMessageStringContent(`Chunk: ${chunk} end`);
    test:assertTrue(content.includes("chunk body"));
}

@test:Config
function testGetChatMessageStringContentWithTextDocumentArray() returns ai:Error? {
    ai:TextDocument[] docs = [{content: "doc one"}, {content: "doc two"}];
    string content = check getChatMessageStringContent(`Docs: ${docs} end`);
    test:assertTrue(content.includes("doc one"));
    test:assertTrue(content.includes("doc two"));
}

@test:Config
function testGetChatMessageStringContentWithTextChunkArray() returns ai:Error? {
    ai:TextChunk[] chunks = [{content: "chunk one"}, {content: "chunk two"}];
    string content = check getChatMessageStringContent(`Chunks: ${chunks} end`);
    test:assertTrue(content.includes("chunk one"));
    test:assertTrue(content.includes("chunk two"));
}

@test:Config
function testGetChatMessageStringContentWithNonTextDocumentFails() {
    ai:ImageDocument img = {content: "https://example.com/image.jpg"};
    string|ai:Error content = getChatMessageStringContent(`Image: ${img}`);
    test:assertTrue(content is ai:Error);
    if content is ai:Error {
        test:assertTrue(content.message().includes("Only Text Documents are currently supported."));
    }
}

@test:Config
function testGetChatMessageStringContentWithScalarInsertion() returns ai:Error? {
    int count = 5;
    string content = check getChatMessageStringContent(`Count is ${count} items`);
    test:assertEquals(content, "Count is 5 items");
}

@test:Config
function testConvertMessageToJsonArray() returns ai:Error? {
    ai:ChatMessage[] messages = [
        <ai:ChatSystemMessage>{role: "system", content: "sys"},
        <ai:ChatUserMessage>{role: "user", content: "hi"},
        <ai:ChatAssistantMessage>{role: "assistant", content: "hello"}
    ];
    json result = check convertMessageToJson(messages);
    test:assertTrue(result is json[]);
    json[] arr = <json[]>result;
    test:assertEquals(arr.length(), 3);
}

@test:Config
function testConvertMessageToJsonSingleUser() returns ai:Error? {
    ai:ChatUserMessage msg = {role: "user", content: "hi there"};
    json result = check convertMessageToJson(msg);
    map<json> obj = <map<json>>result;
    test:assertEquals(obj["role"], "user");
    test:assertEquals(obj["content"], "hi there");
}

@test:Config
function testConvertMessageToJsonSingleAssistant() returns ai:Error? {
    ai:ChatAssistantMessage msg = {role: "assistant", content: "hi"};
    json result = check convertMessageToJson(msg);
    // Assistant messages are returned as-is.
    test:assertEquals(result, msg.toJson());
}

// ===================================================================
// provider_utils.bal unit tests
// ===================================================================

@test:Config
function testGenerateJsonObjectSchemaAlreadyObject() {
    map<json> schema = {"type": "object", "properties": {"a": {"type": "string"}}};
    ResponseSchema result = generateJsonObjectSchema(schema);
    test:assertTrue(result.isOriginallyJsonObject);
    test:assertEquals(result.schema, schema);
}

@test:Config
function testGenerateJsonObjectSchemaWrapsNonObject() {
    map<json> schema = {"type": "integer", "title": "Rating"};
    ResponseSchema result = generateJsonObjectSchema(schema);
    test:assertFalse(result.isOriginallyJsonObject);
    test:assertEquals(result.schema["type"], "object");
    map<json> props = <map<json>>result.schema["properties"];
    test:assertTrue(props.hasKey("result"));
    // Metadata field is preserved at the top level.
    test:assertEquals(result.schema["title"], "Rating");
}

@test:Config
function testParseResponseAsTypeWrapped() returns error? {
    anydata result = check parseResponseAsType("{\"result\": 7}", int, false);
    test:assertEquals(result, 7);
}

@test:Config
function testParseResponseAsTypeDirect() returns error? {
    anydata result = check parseResponseAsType("7", int, true);
    test:assertEquals(result, 7);
}

@test:Config
function testParseResponseAsTypeConversionError() {
    anydata|error result = parseResponseAsType("not-json", int, true);
    test:assertTrue(result is error);
}

@test:Config
function testParseResponseAsTypeWrappedConversionError() {
    anydata|error result = parseResponseAsType("{\"result\": \"abc\"}", int, false);
    test:assertTrue(result is error);
}

@test:Config
function testHandleParseResponseErrorConversion() {
    error e = error("some ConversionError happened");
    error result = handleParseResponseError(e);
    test:assertTrue(result.message().includes(ERROR_MESSAGE));
}

@test:Config
function testHandleParseResponseErrorPassthrough() {
    error e = error("some other unrelated error");
    error result = handleParseResponseError(e);
    test:assertEquals(result.message(), "some other unrelated error");
}

@test:Config
function testGetBase64EncodedString() returns ai:Error? {
    byte[] data = [72, 105];
    string encoded = check getBase64EncodedString(data);
    test:assertEquals(encoded, "SGk=");
}

@test:Config
function testBuildImageUrlWithValidUrl() returns ai:Error? {
    string url = check buildImageUrl("https://example.com/image.jpg", ());
    test:assertEquals(url, "https://example.com/image.jpg");
}

@test:Config
function testBuildImageUrlWithBytes() returns ai:Error? {
    byte[] data = [72, 105];
    string url = check buildImageUrl(data, "image/png");
    test:assertEquals(url, "data:image/png;base64,SGk=");
}

@test:Config
function testBuildImageUrlWithBytesDefaultMime() returns ai:Error? {
    byte[] data = [72, 105];
    string url = check buildImageUrl(data, ());
    test:assertEquals(url, "data:image/*;base64,SGk=");
}

@test:Config
function testBuildImageUrlWithInvalidUrl() {
    string|ai:Error url = buildImageUrl("not-a-valid-url", ());
    test:assertTrue(url is ai:Error);
    if url is ai:Error {
        test:assertTrue(url.message().includes("Must be a valid URL"));
    }
}

@test:Config
function testBuildTextContentPartEmpty() {
    TextContentPart? part = buildTextContentPart("");
    test:assertTrue(part is ());
}

@test:Config
function testBuildTextContentPartNonEmpty() {
    TextContentPart? part = buildTextContentPart("hello");
    test:assertTrue(part is TextContentPart);
    if part is TextContentPart {
        test:assertEquals(part.text, "hello");
    }
}

@test:Config
function testConvertFunctionsToCompletionTools() {
    chat:ChatCompletionTool[] tools = convertFunctionsToCompletionTools(sampleTools);
    test:assertEquals(tools.length(), 2);
    test:assertEquals(tools[0].'function.name, "get_weather");
    // Tool without parameters gets an empty parameter map.
    test:assertEquals(tools[1].'function.name, "get_time");
}

@test:Config
function testGetExpectedResponseSchema() returns ai:Error? {
    ResponseSchema schema = check getExpectedResponseSchema(int);
    test:assertFalse(schema.isOriginallyJsonObject);
    test:assertEquals(schema.schema["type"], "object");
}

@test:Config
function testGetGetResultsTool() returns ai:Error? {
    chat:ChatCompletionTool[] tools = check getGetResultsTool({"type": "object", "properties": {}});
    test:assertEquals(tools.length(), 1);
    test:assertEquals(tools[0].'function.name, GET_RESULTS_TOOL);
}

@test:Config
function testGetGetResultsToolChoice() {
    chat:ChatCompletionNamedToolChoice choice = getGetResultsToolChoice();
    test:assertEquals(choice.'function.name, GET_RESULTS_TOOL);
}

// ===================================================================
// responses_utils.bal unit tests
// ===================================================================

@test:Config
function testConvertToResponsesInputSingleUserMessage() returns ai:Error? {
    ai:ChatUserMessage msg = {role: "user", content: "hello"};
    [responses:InputParam, string?] [items, instructions] =
        check convertToResponsesInput(msg, [], GPT_4O);
    test:assertTrue(instructions is ());
    responses:InputItem[] itemArr = <responses:InputItem[]>items;
    test:assertEquals(itemArr.length(), 1);
}

@test:Config
function testConvertToResponsesInputWithSystemUserAssistantFunction() returns ai:Error? {
    ai:ChatMessage[] messages = [
        <ai:ChatSystemMessage>{role: "system", content: "You are helpful."},
        <ai:ChatUserMessage>{role: "user", content: "Weather?"},
        <ai:ChatAssistantMessage>{
            role: "assistant",
            content: "Let me check.",
            toolCalls: [{id: "call_1", name: "get_weather", arguments: {"city": "London"}}]
        },
        <ai:ChatFunctionMessage>{role: "function", name: "get_weather", id: "call_1", content: "sunny"}
    ];
    [responses:InputParam, string?] [items, instructions] =
        check convertToResponsesInput(messages, sampleTools, GPT_4O);
    test:assertEquals(instructions, "You are helpful.");
    responses:InputItem[] itemArr = <responses:InputItem[]>items;
    // user + assistant-content + function_call + function_call_output = 4
    test:assertEquals(itemArr.length(), 4);
}

@test:Config
function testConvertToResponsesInputAssistantWithoutToolCalls() returns ai:Error? {
    ai:ChatMessage[] messages = [
        <ai:ChatAssistantMessage>{role: "assistant", content: "just text"}
    ];
    [responses:InputParam, string?] [items, _] =
        check convertToResponsesInput(messages, [], GPT_4O);
    responses:InputItem[] itemArr = <responses:InputItem[]>items;
    test:assertEquals(itemArr.length(), 1);
}

@test:Config
function testConvertToResponsesInputReActInstructions() returns ai:Error? {
    // For models without tool-call support, tools are folded into a ReAct prompt.
    ai:ChatMessage[] messages = [
        <ai:ChatSystemMessage>{role: "system", content: "Base instructions."}
    ];
    [responses:InputParam, string?] [_, instructions] =
        check convertToResponsesInput(messages, sampleTools, CHATGPT_4O_LATEST);
    test:assertTrue(instructions is string);
    if instructions is string {
        test:assertTrue(instructions.includes("get_weather"));
        test:assertTrue(instructions.includes("Base instructions."));
    }
}

@test:Config
function testConvertToResponsesTools() {
    responses:FunctionTool[] tools = convertToResponsesTools(sampleTools);
    test:assertEquals(tools.length(), 2);
    test:assertEquals(tools[0].name, "get_weather");
    test:assertEquals(tools[0].strict, false);
}

@test:Config
function testConvertResponsesOutputToAssistantMessageText() returns ai:Error? {
    responses:Response response = buildTextResponse("Hello there");
    ai:ChatAssistantMessage msg = check convertResponsesOutputToAssistantMessage(response);
    test:assertEquals(msg.content, "Hello there");
}

@test:Config
function testConvertResponsesOutputToAssistantMessageToolCall() returns ai:Error? {
    responses:Response response = buildFunctionCallResponse("get_weather", "{\"city\": \"Paris\"}", "call_9");
    ai:ChatAssistantMessage msg = check convertResponsesOutputToAssistantMessage(response);
    ai:FunctionCall[]? toolCalls = msg.toolCalls;
    test:assertTrue(toolCalls is ai:FunctionCall[]);
    if toolCalls is ai:FunctionCall[] {
        test:assertEquals(toolCalls[0].name, "get_weather");
        test:assertEquals(toolCalls[0].arguments, {"city": "Paris"});
    }
}

@test:Config
function testConvertResponsesOutputToAssistantMessageEmpty() {
    responses:Response response = buildEmptyResponse();
    ai:ChatAssistantMessage|ai:Error msg = convertResponsesOutputToAssistantMessage(response);
    test:assertTrue(msg is ai:Error);
    if msg is ai:Error {
        test:assertTrue(msg.message().includes("Empty response from the model"));
    }
}

@test:Config
function testConvertResponsesOutputToAssistantMessageMalformedArgs() {
    responses:Response response = buildFunctionCallResponse("get_weather", "not valid json", "call_x");
    ai:ChatAssistantMessage|ai:Error msg = convertResponsesOutputToAssistantMessage(response);
    test:assertTrue(msg is ai:Error);
}

@test:Config
function testConvertContentPartsForResponses() {
    DocumentContentPart[] parts = [
        {'type: "text", text: "some text"},
        {'type: "image_url", image_url: {url: "https://example.com/i.jpg"}}
    ];
    responses:InputContent[] result = convertContentPartsForResponses(parts);
    test:assertEquals(result.length(), 2);
    responses:InputContent first = result[0];
    test:assertTrue(first is responses:InputTextContent);
    responses:InputContent second = result[1];
    test:assertTrue(second is responses:InputImageContent);
}
