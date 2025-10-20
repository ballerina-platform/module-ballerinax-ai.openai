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
import ballerina/constraint;
import ballerina/lang.array;
import ballerinax/openai.chat;

type ResponseSchema record {|
    map<json> schema;
    boolean isOriginallyJsonObject = true;
|};

type DocumentContentPart TextContentPart|ImageContentPart;

type TextContentPart chat:ChatCompletionRequestMessageContentPartText;

type ImageContentPart chat:ChatCompletionRequestMessageContentPartImage;

const JSON_CONVERSION_ERROR = "FromJsonStringError";
const CONVERSION_ERROR = "ConversionError";
const ERROR_MESSAGE = "Error occurred while attempting to parse the response from the " +
    "LLM as the expected type. Retrying and/or validating the prompt could fix the response.";
const RESULT = "result";
const GET_RESULTS_TOOL = "getResults";
const FUNCTION = "function";
const NO_RELEVANT_RESPONSE_FROM_THE_LLM = "No relevant response from the LLM";

isolated function generateJsonObjectSchema(map<json> schema) returns ResponseSchema {
    string[] supportedMetaDataFields = ["$schema", "$id", "$anchor", "$comment", "title", "description"];

    if schema["type"] == "object" {
        return {schema};
    }

    map<json> updatedSchema = map from var [key, value] in schema.entries()
        where supportedMetaDataFields.indexOf(key) is int
        select [key, value];

    updatedSchema["type"] = "object";
    map<json> content = map from var [key, value] in schema.entries()
        where supportedMetaDataFields.indexOf(key) !is int
        select [key, value];

    updatedSchema["properties"] = {[RESULT]: content};

    return {schema: updatedSchema, isOriginallyJsonObject: false};
}

isolated function parseResponseAsType(string resp,
        typedesc<anydata> expectedResponseTypedesc, boolean isOriginallyJsonObject) returns anydata|error {
    if !isOriginallyJsonObject {
        map<json> respContent = check resp.fromJsonStringWithType();
        anydata|error result = trap respContent[RESULT].fromJsonWithType(expectedResponseTypedesc);
        if result is error {
            return handleParseResponseError(result);
        }
        return result;
    }

    anydata|error result = resp.fromJsonStringWithType(expectedResponseTypedesc);
    if result is error {
        return handleParseResponseError(result);
    }
    return result;
}

isolated function getExpectedResponseSchema(typedesc<anydata> expectedResponseTypedesc) returns ResponseSchema|ai:Error {
    // Restricted at compile-time for now.
    typedesc<json> td = checkpanic expectedResponseTypedesc.ensureType();
    return generateJsonObjectSchema(check generateJsonSchemaForTypedescAsJson(td));
}

isolated function getGetResultsToolChoice() returns chat:ChatCompletionNamedToolChoice => {
    'type: FUNCTION,
    'function: {
        name: GET_RESULTS_TOOL
    }
};

isolated function getGetResultsTool(map<json> parameters) returns chat:ChatCompletionTool[]|ai:Error {
    chat:FunctionParameters|error toolParams = parameters.cloneWithType();
    if toolParams is error {
        return error("Error in generated schema: " + toolParams.message());
    }
    return [
        {
            'type: FUNCTION,
            'function: {
                name: GET_RESULTS_TOOL,
                parameters: toolParams,
                description: "Tool to call with the response from a large language model (LLM) for a user prompt."
            }
        }
    ];
}

isolated function generateChatCreationContent(ai:Prompt prompt)
                        returns DocumentContentPart[]|ai:Error {
    string[] & readonly strings = prompt.strings;
    anydata[] insertions = prompt.insertions;
    DocumentContentPart[] contentParts = [];
    string accumulatedTextContent = "";

    if strings.length() > 0 {
        accumulatedTextContent += strings[0];
    }

    foreach int i in 0 ..< insertions.length() {
        anydata insertion = insertions[i];
        string str = strings[i + 1];

        if insertion is ai:Document {
            addTextContentPart(buildTextContentPart(accumulatedTextContent), contentParts);
            accumulatedTextContent = "";
            check addDocumentContentPart(insertion, contentParts);
        } else if insertion is ai:Document[] {
            addTextContentPart(buildTextContentPart(accumulatedTextContent), contentParts);
            accumulatedTextContent = "";
            foreach ai:Document doc in insertion {
                check addDocumentContentPart(doc, contentParts);
            }
        } else {
            accumulatedTextContent += insertion.toString();
        }
        accumulatedTextContent += str;
    }

    addTextContentPart(buildTextContentPart(accumulatedTextContent), contentParts);
    return contentParts;
}

isolated function addDocumentContentPart(ai:Document doc, DocumentContentPart[] contentParts) returns ai:Error? {
    if doc is ai:TextDocument {
        return addTextContentPart(buildTextContentPart(doc.content), contentParts);
    } else if doc is ai:ImageDocument {
        return contentParts.push(check buildImageContentPart(doc));
    }

    return error ai:Error("Only text and image documents are supported.");
}

isolated function addTextContentPart(TextContentPart? contentPart, DocumentContentPart[] contentParts) {
    if contentPart is TextContentPart {
        return contentParts.push(contentPart);
    }
}

isolated function buildTextContentPart(string content) returns TextContentPart? {
    if content.length() == 0 {
        return;
    }

    return {
        'type: "text",
        text: content
    };
}

isolated function buildImageContentPart(ai:ImageDocument doc) returns ImageContentPart|ai:Error =>
    {
    'type: "image_url",
    image_url: {
        url: check buildImageUrl(doc.content, doc.metadata?.mimeType)
    }
};

isolated function buildImageUrl(ai:Url|byte[] content, string? mimeType) returns string|ai:Error {
    if content is ai:Url {
        ai:Url|constraint:Error validationRes = constraint:validate(content);
        if validationRes is error {
            return error(validationRes.message(), validationRes.cause());
        }
        return content;
    }

    return string `data:${mimeType ?: "image/*"};base64,${check getBase64EncodedString(content)}`;
}

isolated function getBase64EncodedString(byte[] content) returns string|ai:Error {
    string|error binaryContent = array:toBase64(content);
    if binaryContent is error {
        return error("Failed to convert byte array to string: " + binaryContent.message() + ", " +
                        binaryContent.detail().toBalString());
    }
    return binaryContent;
}

isolated function handleParseResponseError(error chatResponseError) returns error {
    string msg = chatResponseError.message();
    if msg.includes(JSON_CONVERSION_ERROR) || msg.includes(CONVERSION_ERROR) {
        return error(string `${ERROR_MESSAGE}`, chatResponseError);
    }
    return chatResponseError;
}

isolated function generateLlmResponse(chat:Client llmClient, OPEN_AI_MODEL_NAMES modelType,
        ai:Prompt prompt, typedesc<json> expectedResponseTypedesc) returns anydata|ai:Error {
    observe:GenerateContentSpan span = observe:createGenerateContentSpan(modelType);
    span.addProvider("openai");

    DocumentContentPart[] content;
    ResponseSchema responseSchema;
    chat:ChatCompletionTool[] tools;
    do {
        content = check generateChatCreationContent(prompt);
        responseSchema = check getExpectedResponseSchema(expectedResponseTypedesc);
        tools = check getGetResultsTool(responseSchema.schema);
    } on fail ai:Error err {
        span.close(err);
        return err;
    }

    chat:CreateChatCompletionRequest request = {
        messages: [
            {
                role: ai:USER,
                content
            }
        ],
        model: modelType,
        tools,
        tool_choice: getGetResultsToolChoice()
    };
    span.addInputMessages(request.messages.toJson());
    chat:CreateChatCompletionResponse|error response = llmClient->/chat/completions.post(request);
    if response is error {
        ai:Error err = error("LLM call failed: " + response.message(), detail = response.detail(), cause = response.cause());
        span.close(err);
        return err;
    }

    string? responseId = response.id;
    if responseId is string {
        span.addResponseId(responseId);
    }
    int? inputTokens = response.usage?.prompt_tokens;
    if inputTokens is int {
        span.addInputTokenCount(inputTokens);
    }
    int? outputTokens = response.usage?.completion_tokens;
    if outputTokens is int {
        span.addOutputTokenCount(outputTokens);
    }

    chat:CreateChatCompletionResponse_choices[] choices = response.choices;
    if choices.length() == 0 {
        ai:Error err = error("No completion choices");
        span.close(err);
        return err;
    }

    chat:ChatCompletionResponseMessage? message = choices[0].message;
    chat:ChatCompletionMessageToolCall[]? toolCalls = message?.tool_calls;
    if toolCalls is () || toolCalls.length() == 0 {
        ai:Error err = error(NO_RELEVANT_RESPONSE_FROM_THE_LLM);
        span.close(err);
        return err;
    }

    chat:ChatCompletionMessageToolCall tool = toolCalls[0];
    map<json>|error arguments = tool.'function.arguments.fromJsonStringWithType();
    if arguments is error {
        ai:Error err = error(NO_RELEVANT_RESPONSE_FROM_THE_LLM);
        span.close(err);
        return err;
    }

    anydata|error res = parseResponseAsType(arguments.toJsonString(), expectedResponseTypedesc,
            responseSchema.isOriginallyJsonObject);
    if res is error {
        ai:Error err = error ai:LlmInvalidGenerationError(string `Invalid value returned from the LLM Client, expected: '${
            expectedResponseTypedesc.toBalString()}', found '${res.toBalString()}'`);
        span.close(err);
        return err;
    }

    anydata|error result = res.ensureType(expectedResponseTypedesc);
    if result is error {
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
